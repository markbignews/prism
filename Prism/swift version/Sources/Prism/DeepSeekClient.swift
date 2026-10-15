import Foundation

struct DeepSeekBalanceInfo: Codable, Identifiable, Sendable {
    let currency: String
    let totalBalance: String
    let grantedBalance: String
    let toppedUpBalance: String

    var id: String { currency }

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
        case grantedBalance = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
    }
}

struct DeepSeekBalanceResponse: Codable, Sendable {
    let isAvailable: Bool
    let balanceInfos: [DeepSeekBalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

private enum InstallationIdentity {
    private static let storageKey = "deepseek.userID"

    static let userID: String = {
        if let saved = UserDefaults.standard.string(forKey: storageKey),
           !saved.isEmpty,
           saved.count <= 512,
           saved.unicodeScalars.allSatisfy({
               CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
           }) {
            return saved
        }
        let generated = "prism_swift_\(UUID().uuidString.lowercased())"
        UserDefaults.standard.set(generated, forKey: storageKey)
        return generated
    }()
}

enum DeepSeekModels {
    static let flash = "deepseek-flash"
    static let pro = "deepseek-v4-pro"

    static func canonical(_ model: String, baseURL: String) -> String {
        guard URL(string: baseURL)?.host?.lowercased() == "api.deepseek.com" else { return model }
        switch model {
        case "deepseek-v4-flash", "deepseek-v4-flash-vision-exp": return flash
        default: return model
        }
    }

    /// Preserve discovered and manually entered model IDs across restarts.
    static func supportedConversationModel(_ model: String) -> String {
        let cleaned = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? flash : cleaned
    }
}

struct DeepSeekClient {
    var apiKey: String
    var baseURL: String
    var model: String
    var parameters: ModelParameters
    var language: AppLanguage
    var mode: ConversationMode = .balanced
    var responseLength: ResponseLength = .standard
    var session: URLSession = .shared

    private func contentValue(for message: ChatMessage, text: String, includeAttachments: Bool) -> APIMessageContent {
        guard includeAttachments, message.role == .user, !message.attachments.isEmpty else {
            return .text(text)
        }

        var blocks: [APIContentBlock] = [.text(text)]
        for attachment in message.attachments {
            switch attachment.kind {
            case .image:
                let encoded = attachment.data.base64EncodedString()
                blocks.append(.image("data:\(attachment.mediaType);base64,\(encoded)"))
            case .text:
                let label = "\n\n[附件：\(attachment.fileName)]\n"
                blocks.append(.text(label + (attachment.textContent ?? "")))
            }
        }
        return .blocks(blocks)
    }

    func makeStreamRequest(
        messages: [ChatMessage],
        memoryContext: String?,
        supervisorHint: String? = nil,
        tools: [ToolDef]? = nil,
        toolResults: [ToolResult] = [],
        toolExchanges: [ToolExchange] = []
    ) throws -> URLRequest {
        let key = try APICredentials.normalized(apiKey)
        let modelName = DeepSeekModels.canonical(model.trimmingCharacters(in: .whitespacesAndNewlines), baseURL: baseURL)
        guard !modelName.isEmpty else {
            throw DeepSeekError.invalidModel
        }
        let latestUserMessage = messages.last(where: { $0.role == .user })
        if modelName == DeepSeekModels.pro,
           latestUserMessage?.attachments.contains(where: { $0.kind == .image }) == true {
            throw DeepSeekError.api("DeepSeek V4 Pro 不支持图片输入，请切换到 DeepSeek V4.1 Flash 后重试。")
        }
        let url = try ModelCatalogClient.endpoint(baseURL: baseURL, suffix: "chat/completions")

        // Keep the system prefix stable for DeepSeek's prefix cache. Dynamic
        // memory/supervisor context belongs on the current user turn; putting
        // it in a system message before the transcript would invalidate the
        // cache prefix on every request.
        let systemPrompt = AgentPrompt.system(language: language, mode: mode, responseLength: responseLength)
        var requestMessages = [APIMessage(role: "system", content: .text(systemPrompt))]
        // Only the last assistant message may carry toolCalls, and only when we have
        // pending tool results that correspond to them.  Stale toolCalls from previous
        // turns (where tool messages were never persisted) must be stripped so the API
        // never sees a tool_calls message without matching tool messages after it.
        // `buildWindowedMessages` already makes the token-aware context choice.
        // A second, message-count cap silently discarded early dialogue first.
        let tail = messages
        let lastAssistantInTail = tail.lastIndex(where: { $0.role == .assistant })
        let lastUserInTail = tail.lastIndex(where: { $0.role == .user })
        requestMessages += tail.enumerated().map { i, msg in
            let keepToolCalls = !toolResults.isEmpty && i == lastAssistantInTail
            // Tool-enabled thinking requires reasoning from every assistant turn,
            // including final answers. Legacy records may have no saved reasoning.
            let reasoning: String? = parameters.thinkingEnabled && (tools?.isEmpty == false || !toolExchanges.isEmpty || !toolResults.isEmpty) && msg.role == .assistant
                ? (msg.reasoning ?? "") : nil
            var content = msg.role == .user
                ? "[sentAt=\(AgentPrompt.transcriptTimestamp(msg.createdAt))]\n\(msg.content)"
                : msg.content
            if msg.role == .user, i == lastUserInTail {
                var dynamicContext = ""
                if let hint = supervisorHint, !hint.isEmpty {
                    dynamicContext += "\n\n[监督者方向]\n\(hint)"
                }
                if let memoryContext, !memoryContext.isEmpty {
                    dynamicContext += "\n\n\(memoryContext)"
                }
                content += dynamicContext
            }
            return APIMessage(role: msg.role.rawValue, content: contentValue(for: msg, text: content, includeAttachments: i == lastUserInTail),
                              reasoningContent: reasoning,
                              toolCalls: keepToolCalls ? msg.toolCalls : nil)
        }
        // Inject tool results from previous round as role:"tool" messages
        for tr in toolResults {
            requestMessages.append(APIMessage(role: "tool", content: .text(tr.content), toolCallID: tr.toolCallID, name: tr.name))
        }

        // Replay each subturn separately. Combining all reasoning/tool calls into
        // one assistant message loses earlier tool results on the next request.
        for exchange in toolExchanges {
            requestMessages.append(APIMessage(role: "assistant", content: .text(exchange.response.content),
                reasoningContent: parameters.thinkingEnabled ? (exchange.response.reasoning ?? "") : nil,
                toolCalls: exchange.response.toolCalls))
            for result in exchange.results {
                requestMessages.append(APIMessage(role: "tool", content: .text(result.content),
                    toolCallID: result.toolCallID, name: result.name))
            }
        }

        // Response style must never change the model's sampling distribution.
        // A single conservative configuration reduces divergence when a user
        // asks the same question in Rational, Balanced, or Warm.
        let stableTemperature = 0.2
        let stableTopP = 0.95

        let body = ChatRequest(
            model: modelName,
            userID: InstallationIdentity.userID,
            messages: requestMessages,
            temperature: parameters.thinkingEnabled ? nil : stableTemperature,
            topP: stableTopP,
            maxTokens: responseLength.maxTokens,
            presencePenalty: nil,
            frequencyPenalty: nil,
            thinking: ThinkingConfig(type: parameters.thinkingEnabled ? "enabled" : "disabled"),
            reasoningEffort: parameters.thinkingEnabled ? parameters.reasoningEffort : nil,
            stream: true,
            streamOptions: StreamOptions(includeUsage: true),
            tools: tools
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        return request
    }

    func stream(
        messages: [ChatMessage], memoryContext: String?, supervisorHint: String? = nil,
        tools: [ToolDef]? = nil, toolResults: [ToolResult] = [], toolExchanges: [ToolExchange] = [],
        onDelta: @MainActor @Sendable @escaping (DeepSeekStreamDelta) -> Void
    ) async throws -> DeepSeekResult {
        let request = try makeStreamRequest(messages: messages, memoryContext: memoryContext,
            supervisorHint: supervisorHint, tools: tools, toolResults: toolResults, toolExchanges: toolExchanges)
        try Task.checkCancellation()

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }

        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DeepSeekError.http(http.statusCode)
        }

        var content = ""
        var reasoning = ""
        var toolCallsByIndex: [Int: ToolCall] = [:]
        var finalUsage: TokenUsage?

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8) else { continue }
            let chunk = try JSONDecoder().decode(StreamResponse.self, from: data)
            if let usage = chunk.usage { finalUsage = usage }
            guard let delta = chunk.choices.first?.delta else { continue }

            if let token = delta.reasoningContent, !token.isEmpty {
                reasoning += token
                await onDelta(.reasoning(token))
            }
            if let token = delta.content, !token.isEmpty {
                content += token
                await onDelta(.content(token))
            }
            if let toolCalls = delta.toolCalls {
                for tc in toolCalls {
                    await onDelta(.toolCall(tc))
                    // Accumulate tool_call fragments by index
                    let idx = tc.index ?? 0
                    var existing = toolCallsByIndex[idx] ?? ToolCall(id: "", name: "", arguments: "")
                    if let id = tc.id { existing.id = id }
                    if let name = tc.function?.name { existing.name = name }
                    if let args = tc.function?.arguments { existing.arguments += args }
                    toolCallsByIndex[idx] = existing
                }
            }
        }

        let allToolCalls = toolCallsByIndex.keys.sorted().compactMap { idx -> ToolCall? in
            let tc = toolCallsByIndex[idx]!
            guard !tc.name.isEmpty else { return nil }
            return tc
        }

        let hasContent = !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasReasoning = !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasToolCalls = !allToolCalls.isEmpty

        if let finalUsage {
            await UsageStatsStore.shared.record(finalUsage)
        }

        guard hasContent || hasReasoning || hasToolCalls else {
            throw DeepSeekError.emptyResponse
        }
        return DeepSeekResult(
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            reasoning: hasReasoning ? reasoning : nil,
            toolCalls: allToolCalls
        )
    }

    /// Non-streaming call for full re-summarization (higher output tokens)
    func fullSummarize(systemPrompt: String, userContent: String) async throws -> String {
        return try await summarizeRequest(systemPrompt: systemPrompt, userContent: userContent, maxTokens: 8192, timeout: 180)
    }

    /// Non-streaming call for incremental summarization (lightweight, no thinking)
    func summarize(systemPrompt: String, userContent: String) async throws -> String {
        return try await summarizeRequest(systemPrompt: systemPrompt, userContent: userContent, maxTokens: 1024, timeout: 120)
    }

    /// Validate an API key against the provider's `/models` endpoint
    /// Returns normally on success,
    /// throws on invalid key, network failure, or provider error.
    func validateAPIKey(apiKey: String, baseURL: String) async throws {
        _ = try await ModelCatalogClient().fetch(apiKey: apiKey, baseURL: baseURL)
    }

    /// Read the provider balance without invoking a model or consuming model
    /// tokens. DeepSeek returns one entry per currency.
    func fetchBalance() async throws -> DeepSeekBalanceResponse {
        let key = try APICredentials.normalized(apiKey)
        let url = try ModelCatalogClient.endpoint(baseURL: baseURL, suffix: "user/balance")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch { throw error }
        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DeepSeekError.http(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
        } catch {
            throw DeepSeekError.invalidResponse
        }
    }

    private func summarizeRequest(systemPrompt: String, userContent: String, maxTokens: Int, timeout: Double) async throws -> String {
        let key = try APICredentials.normalized(apiKey)
        let modelName = DeepSeekModels.canonical(model.trimmingCharacters(in: .whitespacesAndNewlines), baseURL: baseURL)
        guard !modelName.isEmpty else {
            throw DeepSeekError.invalidModel
        }
        let url = try ModelCatalogClient.endpoint(baseURL: baseURL, suffix: "chat/completions")

        let messages = [
            APIMessage(role: "system", content: .text(systemPrompt)),
            APIMessage(role: "user", content: .text(userContent))
        ]

        let body = ChatRequest(
            model: modelName,
            userID: InstallationIdentity.userID,
            messages: messages,
            temperature: 0.3,
            topP: 1.0,
            maxTokens: maxTokens,
            presencePenalty: nil,
            frequencyPenalty: nil,
            thinking: ThinkingConfig(type: "disabled"),
            reasoningEffort: nil,
            stream: false,
            streamOptions: nil
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        try Task.checkCancellation()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }
        try Task.checkCancellation()

        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DeepSeekError.http(http.statusCode)
        }

        let result = try JSONDecoder().decode(ChatResponse.self, from: data)
        if let usage = result.usage {
            await UsageStatsStore.shared.record(usage)
        }
        return result.choices.first?.message.content ?? ""
    }
}

enum DeepSeekStreamDelta: Sendable {
    case reasoning(String)
    case content(String)
    case toolCall(ToolCallDelta)
}

struct ToolExchange: Sendable {
    var response: DeepSeekResult
    var results: [ToolResult]
}

struct DeepSeekResult: Sendable {
    var content: String
    var reasoning: String?
    var toolCalls: [ToolCall] = []
}

enum DeepSeekError: LocalizedError {
    case missingAPIKey
    case malformedAPIKey
    case http(Int)
    case invalidModel
    case invalidBaseURL
    case invalidResponse
    case emptyResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "请先在设置中填写 API Key。"
        case .malformedAPIKey: "API Key 格式不正确。请只粘贴密钥本身，不要包含空格、引号或 Bearer 前缀。"
        case .http(let status): ProviderFailure.httpMessage(status, language: .simplifiedChinese)
        case .invalidModel:
            "DeepSeek model name is missing."
        case .invalidBaseURL:
            "DeepSeek base URL is invalid."
        case .invalidResponse:
            "The server response was invalid."
        case .emptyResponse:
            "The model returned an empty response."
        case .api(let detail):
            detail
        }
    }
}

private struct ChatRequest: Encodable {
    var model: String
    var userID: String
    var messages: [APIMessage]
    var temperature: Double?
    var topP: Double
    var maxTokens: Int
    var presencePenalty: Double?
    var frequencyPenalty: Double?
    var thinking: ThinkingConfig?
    var reasoningEffort: String?
    var stream: Bool
    var streamOptions: StreamOptions?
    var tools: [ToolDef]?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case userID = "user_id"
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case presencePenalty = "presence_penalty"
        case frequencyPenalty = "frequency_penalty"
        case thinking
        case reasoningEffort = "reasoning_effort"
        case stream
        case streamOptions = "stream_options"
        case tools
    }
}

/// DeepSeek's vision endpoint follows the OpenAI-compatible multimodal
/// message shape: text-only messages remain strings, while user messages
/// containing images use an array of text/image_url blocks.
private enum APIMessageContent: Encodable {
    case text(String)
    case blocks([APIContentBlock])

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .blocks(let blocks):
            var container = encoder.unkeyedContainer()
            for block in blocks {
                try container.encode(block)
            }
        }
    }
}

private enum APIContentBlock: Encodable {
    case text(String)
    case image(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .text)
        case .image(let dataURL):
            try container.encode("image_url", forKey: .type)
            try container.encode(APIImageURL(url: dataURL, detail: "auto"), forKey: .imageURL)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, text
        case imageURL = "image_url"
    }
}

private struct APIImageURL: Encodable {
    let url: String
    let detail: String
}

private struct StreamOptions: Encodable {
    var includeUsage: Bool

    enum CodingKeys: String, CodingKey {
        case includeUsage = "include_usage"
    }
}

private struct ThinkingConfig: Encodable {
    var type: String
}

private struct APIMessage: Encodable {
    var role: String
    var content: APIMessageContent?
    var reasoningContent: String?
    var toolCalls: [ToolCall]?
    var toolCallID: String?
    var name: String?

    enum CodingKeys: String, CodingKey {
        case role, content, name
        case reasoningContent = "reasoning_content"
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }
}

private struct ChatResponse: Decodable {
    var choices: [Choice]
    var usage: TokenUsage?
}

private struct Choice: Decodable {
    var message: ResponseMessage
}

private struct ResponseMessage: Decodable {
    var content: String
    var reasoningContent: String?

    enum CodingKeys: String, CodingKey {
        case content
        case reasoningContent = "reasoning_content"
    }
}

private struct StreamResponse: Decodable {
    var choices: [StreamChoice]
    var usage: TokenUsage?
}

private struct StreamChoice: Decodable {
    var delta: StreamDelta?
}

private struct StreamDelta: Decodable {
    var content: String?
    var reasoningContent: String?
    var toolCalls: [ToolCallDelta]?

    enum CodingKeys: String, CodingKey {
        case content
        case reasoningContent = "reasoning_content"
        case toolCalls = "tool_calls"
    }
}
