import Foundation

struct DeepSeekClient {
    var apiKey: String
    var baseURL: String
    var model: String
    var parameters: ModelParameters
    var language: AppLanguage
    var mode: ConversationMode = .balanced
    var responseLength: ResponseLength = .standard

    func stream(
        messages: [ChatMessage],
        memoryContext: String?,
        supervisorHint: String? = nil,
        tools: [ToolDef]? = nil,
        toolResults: [ToolResult] = [],
        onDelta: @MainActor @Sendable @escaping (DeepSeekStreamDelta) -> Void
    ) async throws -> DeepSeekResult {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeepSeekError.missingAPIKey
        }
        let modelName = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelName.isEmpty else {
            throw DeepSeekError.invalidModel
        }
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions") else {
            throw DeepSeekError.invalidBaseURL
        }

        var requestMessages = [APIMessage(role: "system", content: AgentPrompt.system(language: language, mode: mode, responseLength: responseLength))]
        if let hint = supervisorHint, !hint.isEmpty {
            requestMessages.append(APIMessage(role: "system", content: "[监督者方向]\n\(hint)"))
        }
        if let memoryContext, !memoryContext.isEmpty {
            requestMessages.append(APIMessage(role: "system", content: memoryContext))
        }
        // Only the last assistant message may carry toolCalls, and only when we have
        // pending tool results that correspond to them.  Stale toolCalls from previous
        // turns (where tool messages were never persisted) must be stripped so the API
        // never sees a tool_calls message without matching tool messages after it.
        let tail = messages.suffix(500)
        let lastAssistantInTail = tail.lastIndex(where: { $0.role == .assistant })
        requestMessages += tail.enumerated().map { i, msg in
            let keepToolCalls = !toolResults.isEmpty && i == lastAssistantInTail
            return APIMessage(role: msg.role.rawValue, content: msg.content,
                              toolCalls: keepToolCalls ? msg.toolCalls : nil)
        }
        // Inject tool results from previous round as role:"tool" messages
        for tr in toolResults {
            requestMessages.append(APIMessage(role: "tool", content: tr.content, toolCallID: tr.toolCallID, name: tr.name))
        }

        let modeTemp = switch mode {
        case .rational: 0.1
        case .balanced: 0.35
        case .warm: 0.6
        }
        let modeTopP = switch mode {
        case .rational: 0.8
        case .balanced: 0.9
        case .warm: 0.95
        }

        let body = ChatRequest(
            model: modelName,
            messages: requestMessages,
            temperature: modeTemp,
            topP: modeTopP,
            maxTokens: 8192,
            presencePenalty: 0,
            frequencyPenalty: 0,
            thinking: ThinkingConfig(type: parameters.thinkingEnabled ? "enabled" : "disabled"),
            reasoningEffort: parameters.thinkingEnabled ? parameters.reasoningEffort : nil,
            stream: true,
            tools: tools
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        try Task.checkCancellation()

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }

        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            var detail = ""
            for try await line in bytes.lines {
                detail += line
            }
            if detail.isEmpty {
                detail = "HTTP \(http.statusCode)"
            }
            throw DeepSeekError.api(detail)
        }

        var content = ""
        var reasoning = ""
        var toolCallsByIndex: [Int: ToolCall] = [:]

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8) else { continue }
            let chunk = try JSONDecoder().decode(StreamResponse.self, from: data)
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

        guard hasContent || hasReasoning || hasToolCalls else {
            throw DeepSeekError.emptyResponse
        }
        return DeepSeekResult(
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            reasoning: reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : reasoning.trimmingCharacters(in: .whitespacesAndNewlines),
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

    private func summarizeRequest(systemPrompt: String, userContent: String, maxTokens: Int, timeout: Double) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeepSeekError.missingAPIKey
        }
        let modelName = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelName.isEmpty else {
            throw DeepSeekError.invalidModel
        }
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions") else {
            throw DeepSeekError.invalidBaseURL
        }

        let messages = [
            APIMessage(role: "system", content: systemPrompt),
            APIMessage(role: "user", content: userContent)
        ]

        let body = ChatRequest(
            model: modelName,
            messages: messages,
            temperature: 0.3,
            topP: 0.9,
            maxTokens: maxTokens,
            presencePenalty: 0,
            frequencyPenalty: 0,
            thinking: ThinkingConfig(type: "disabled"),
            reasoningEffort: nil,
            stream: false
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        try Task.checkCancellation()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }
        try Task.checkCancellation()

        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw DeepSeekError.api(detail)
        }

        let result = try JSONDecoder().decode(ChatResponse.self, from: data)
        return result.choices.first?.message.content ?? ""
    }
}

enum DeepSeekStreamDelta: Sendable {
    case reasoning(String)
    case content(String)
    case toolCall(ToolCallDelta)
}

struct DeepSeekResult {
    var content: String
    var reasoning: String?
    var toolCalls: [ToolCall] = []
}

enum DeepSeekError: LocalizedError {
    case missingAPIKey
    case invalidModel
    case invalidBaseURL
    case invalidResponse
    case emptyResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "DeepSeek API Key is missing."
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
    var messages: [APIMessage]
    var temperature: Double
    var topP: Double
    var maxTokens: Int
    var presencePenalty: Double
    var frequencyPenalty: Double
    var thinking: ThinkingConfig?
    var reasoningEffort: String?
    var stream: Bool
    var tools: [ToolDef]?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case presencePenalty = "presence_penalty"
        case frequencyPenalty = "frequency_penalty"
        case thinking
        case reasoningEffort = "reasoning_effort"
        case stream
        case tools
    }
}

private struct ThinkingConfig: Encodable {
    var type: String
}

private struct APIMessage: Codable {
    var role: String
    var content: String?
    var toolCalls: [ToolCall]?
    var toolCallID: String?
    var name: String?

    enum CodingKeys: String, CodingKey {
        case role, content, name
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }
}

private struct ChatResponse: Decodable {
    var choices: [Choice]
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
