import Foundation
import Testing
import Synchronization
@testable import Prism

@Suite @MainActor struct ContextOptimizationTests {
    private func client(window: Int = 65_536) -> DeepSeekClient {
        DeepSeekClient(apiKey: "placeholder", baseURL: "https://api.deepseek.com", model: DeepSeekModels.flash,
            parameters: ModelParameters(thinkingEnabled: true, reasoningEffort: "high", contextWindowTokens: window),
            language: .simplifiedChinese)
    }
    private func conversation(turns: Int = 6, length: Int = 10_000) -> Conversation {
        var value = Conversation(title: "合成上下文")
        for i in 0..<turns {
            value.messages.append(ChatMessage(role: .user, content: "我说的是朋友，不是恋人。第\(i)件事。" + String(repeating: "原话", count: length / 2)))
            value.messages.append(ChatMessage(role: .assistant, content: "这只是未验证的解释。" + String(repeating: "分析", count: length / 2), reasoning: "待核对"))
        }
        value.messages.append(ChatMessage(role: .user, content: "现在我补充一个明确纠正，请保留这段原话。"))
        return value
    }
    private func summary(source: ChatMessage) -> String {
        let object: [String: Any] = ["items": [["kind": "user_fact", "text": "用户明确说是朋友，不是恋人；不应擅自改成恋爱关系。", "sourceMessageID": source.id.uuidString, "quote": "我说的是朋友，不是恋人"]]]
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
    private func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func pressurePrunesDurablyAndRemeasuresWithoutASummaryCall() async throws {
        let value = conversation(turns: 0)
        var committed: [ToolExchange] = []
        var calls = 0
        let turn = OptimizedTurn(conversation: value, assistantID: UUID(), client: client(), memory: "context", hint: "hint", chapterIndex: nil,
            tools: ToolRegistry.definitions, commit: { _, exchanges, _, _, _, _ in committed = exchanges; return true },
            summarize: { _, _ in calls += 1; throw URLError(.notConnectedToInternet) })
        let original = String(repeating: "数据", count: 60_000) + "必须保留末尾"
        let call = ToolCall(id: "oversized", name: "search_memory", arguments: "{}")
        try turn.record(ToolExchange(response: .init(content: "", reasoning: "完整推理", toolCalls: [call]),
            results: [.init(toolCallID: call.id, name: call.name, content: original)]))
        try await turn.prepare(allowTools: true, round: 1)
        #expect(calls == 0 && turn.report.prunedResults == 1)
        #expect(turn.report.afterTokens < turn.report.beforeTokens)
        #expect(committed[0].results[0].content == original)
        let projected = try #require(committed[0].results[0].projectedContent)
        #expect(projected.count < 8192 && projected.contains("fetch_context") && projected.hasSuffix("必须保留末尾"))
        #expect(committed[0].response.reasoning == "完整推理")
        let before = projected
        try await turn.prepare(allowTools: true, round: 1)
        #expect(committed[0].results[0].projectedContent == before)
    }

    @Test func noPressureLeavesToolEvidenceExactAndUnmodified() async throws {
        let value = conversation(turns: 0)
        let turn = OptimizedTurn(conversation: value, assistantID: UUID(), client: client(window: 1_000_000), memory: nil, hint: nil, chapterIndex: nil,
            tools: [], commit: { _, _, _, _, _, _ in true }, summarize: { _, _ in Issue.record("Unexpected summary"); return "" })
        let content = String(repeating: "🧑🏽‍🤝‍🧑🏻完整证据", count: 1000)
        try turn.record(.init(response: .init(content: "", reasoning: nil, toolCalls: [.init(id: "a", name: "lookup", arguments: "{}")]),
                             results: [.init(toolCallID: "a", name: "lookup", content: content)]))
        try await turn.prepare(allowTools: true, round: 0)
        #expect(turn.exchanges[0].results[0].projectedContent == nil)
        #expect(turn.exchanges[0].results[0].content == content)
    }

    @Test func validatedSummaryKeepsRecentOriginalsAndCheckpointSurvivesRestart() async throws {
        let value = conversation()
        var stored: CompactionCheckpoint?
        var calls = 0
        let turn = OptimizedTurn(conversation: value, assistantID: UUID(), client: client(), memory: nil, hint: nil, chapterIndex: nil,
            tools: [], commit: { _, _, checkpoint, _, _, _ in stored = checkpoint; return true },
            summarize: { prompt, input in
                calls += 1
                #expect(prompt.contains("否定") && prompt.contains("纠正"))
                #expect(ContextMeter.text(input) + 12_000 < 65_536)
                return summary(source: value.messages[0])
            })
        try await turn.prepare(allowTools: true, round: 0)
        let checkpoint = try #require(stored)
        #expect(calls >= 1 && calls <= 2)
        #expect(turn.projectedMessages.last == turn.messages.last)
        #expect(turn.projectedMessages.first?.content.contains("不是恋人") == true)
        #expect(turn.messages.map(\.content) == value.messages.map(\.content))
        let decoded = try JSONDecoder().decode(CompactionCheckpoint.self, from: JSONEncoder().encode(checkpoint))
        #expect(ContextMeter.checkpoint(decoded, matches: turn.messages))
        var edited = turn.messages
        edited[0].content = "我更正了这个故事。"
        #expect(!ContextMeter.checkpoint(decoded, matches: edited))
        #expect(!ContextMeter.checkpoint(decoded, matches: Array(turn.messages.dropFirst())))
        #expect(!ContextMeter.checkpoint(decoded, matches: Array(turn.messages.reversed())))
    }

    @Test func inventedOrAssistantOnlyFactsAndNonShrinkingSummariesAreRejected() async throws {
        let value = conversation(turns: 2, length: 20_000)
        let wrong = summary(source: value.messages[0]).replacingOccurrences(of: "我说的是朋友，不是恋人", with: "原话里从来没有说过")
        #expect(throws: (any Error).self) { try OptimizedTurn.validateSummary(wrong, sources: value.messages, conversationID: value.id) }
        let assistant = summary(source: value.messages[1]).replacingOccurrences(of: "我说的是朋友，不是恋人", with: "这只是未验证的解释")
        #expect(throws: (any Error).self) { try OptimizedTurn.validateSummary(assistant, sources: value.messages, conversationID: value.id) }
        var committed: CompactionCheckpoint?
        let turn = OptimizedTurn(conversation: value, assistantID: UUID(), client: client(), memory: nil, hint: nil, chapterIndex: nil, tools: [],
            commit: { _, _, checkpoint, _, _, _ in committed = checkpoint; return true }, summarize: { _, _ in wrong })
        do { try await turn.prepare(allowTools: true, round: 0, force: true); Issue.record("Invalid summary accepted") } catch {}
        #expect(committed == nil && turn.checkpoint == nil && turn.messages.count == value.messages.count)
    }

    @Test func failedStorageCannotPublishAProjectedSummary() async throws {
        let value = conversation(turns: 3)
        let turn = OptimizedTurn(conversation: value, assistantID: UUID(), client: client(), memory: nil, hint: nil, chapterIndex: nil, tools: [],
            commit: { _, _, checkpoint, _, _, _ in checkpoint == nil }, summarize: { _, _ in summary(source: value.messages[0]) })
        do { try await turn.prepare(allowTools: true, round: 0, force: true); Issue.record("Storage failure ignored") } catch {}
        #expect(turn.checkpoint == nil)
        #expect(turn.projectedMessages.map(\.id) == turn.messages.map(\.id))
    }

    @Test func snapshotsReplayExactPrefixAcrossNewTurnsAndToolsStayStableAtTheCap() throws {
        var value = conversation(turns: 1, length: 5)
        value.messages[0].requestContext = "当时的记忆与时间"
        value.messages[0].requestHint = "当时的提示"
        value.messages[1].toolTranscript = [.init(response: .init(content: "中间", reasoning: "工具前推理", toolCalls: [.init(id: "a", name: "lookup", arguments: "{}")]),
            results: [.init(toolCallID: "a", name: "lookup", content: "完整工具结果")])]
        value.messages[1].wireReasoning = "最终推理"
        let turn = OptimizedTurn(conversation: value, assistantID: UUID(), client: client(), memory: "新的记忆", hint: "新的提示", chapterIndex: "新索引", tools: ToolRegistry.definitions,
                                 commit: { _, _, _, _, _, _ in true })
        let first = try body(turn.request(allowTools: true, round: 0))
        let final = try body(turn.request(allowTools: false, round: 2))
        #expect(first["reasoning_effort"] as? String == "low")
        #expect(final["reasoning_effort"] as? String == "high")
        #expect(final["tool_choice"] as? String == "none")
        let a = try JSONSerialization.data(withJSONObject: #require(first["tools"]), options: [.sortedKeys])
        let b = try JSONSerialization.data(withJSONObject: #require(final["tools"]), options: [.sortedKeys])
        #expect(a == b)
        let wire = try #require(first["messages"] as? [[String: Any]])
        #expect((wire[1]["content"] as? String)?.contains("当时的记忆与时间") == true)
        #expect((wire.last?["content"] as? String)?.contains("新的记忆") == true)
        #expect(wire.filter { $0["role"] as? String == "tool" }.count == 1)
        #expect(wire.first { $0["content"] as? String == "完整工具结果" }?["tool_call_id"] as? String == "a")
        #expect(wire.filter { $0["role"] as? String == "assistant" }.last?["reasoning_content"] as? String == "最终推理")
        let loaded = try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(value))
        #expect(loaded == value)
    }

    @Test func customRoutesRetainUserEffortAndAnExplicitWindowIsHonored() throws {
        var custom = client(window: 32_768)
        custom.baseURL = "https://provider.test/v1"
        let turn = OptimizedTurn(conversation: conversation(turns: 0), assistantID: UUID(), client: custom, memory: nil, hint: nil, chapterIndex: nil, tools: [], commit: { _, _, _, _, _, _ in true })
        #expect(try body(turn.request(allowTools: true, round: 0))["reasoning_effort"] as? String == "high")
        #expect(turn.policy.window == 32_768 && turn.policy.trigger + turn.policy.output < 32_768)
        var explicit = client()
        explicit.parameters.adaptiveThinking = false
        let fixed = OptimizedTurn(conversation: conversation(turns: 0), assistantID: UUID(), client: explicit, memory: nil, hint: nil, chapterIndex: nil, tools: [], commit: { _, _, _, _, _, _ in true })
        #expect(try body(fixed.request(allowTools: true, round: 0))["reasoning_effort"] as? String == "high")
    }

    @Test func fullToolResultsCanBeRereadAfterRestartAndDeletionInvalidatesCopies() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let agent = ChatAgent(storagePath: root.path)
        agent.createConversation()
        var value = try #require(agent.selectedConversation)
        let user = ChatMessage(role: .user, content: "这是原始消息")
        let assistant = ChatMessage(role: .assistant, content: "回答")
        value.messages = [user, assistant]
        agent.selectedConversation = value
        let turn = agent.makeOptimizedTurn(conversation: value, assistantID: assistant.id, client: client(), memory: "保存的时间", hint: nil)
        let original = String(repeating: "中间必须能读到", count: 10_000)
        try turn.record(.init(response: .init(content: "", reasoning: "r", toolCalls: [.init(id: "source", name: "lookup", arguments: "{}")]),
                             results: [.init(toolCallID: "source", name: "lookup", content: original)]))
        try await turn.prepare(allowTools: true, round: 1)
        let loaded = ChatAgent(storagePath: root.path)
        let args: [String: Any] = ["conversation_id": value.id.uuidString, "message_id": assistant.id.uuidString, "tool_call_id": "source", "offset": 6000, "count": 1000]
        let raw = await ToolRegistry.execute(name: "fetch_context", arguments: String(decoding: try JSONSerialization.data(withJSONObject: args), as: UTF8.self), store: loaded)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        #expect(object["content"] as? String == String(original.dropFirst(6000).prefix(1000)))
        #expect(object["nextOffset"] as? Int == 7000)
        loaded.deleteMessage(in: value.id, messageID: user.id)
        let missing = await ToolRegistry.execute(name: "fetch_context", arguments: String(decoding: try JSONSerialization.data(withJSONObject: args), as: UTF8.self), store: loaded)
        #expect(missing.contains("source missing"))
    }

    @Test func usageSeparatesReportedReasoningAndCompactionWithoutInventingMissingNumbers() throws {
        let raw = Data(#"{"prompt_tokens":100,"completion_tokens":50,"prompt_cache_hit_tokens":80,"completion_tokens_details":{"reasoning_tokens":30,"other":null}}"#.utf8)
        let usage = try JSONDecoder().decode(TokenUsage.self, from: raw)
        #expect(usage.reasoningTokens == 30)
        var stats = UsageStats()
        stats.add(usage, purpose: "compaction")
        #expect(stats.outputTokens == 50 && stats.reportedReasoningTokens == 30)
        #expect(stats.compactionRequests == 1 && stats.backgroundRequests == 1)
        let unknown = try JSONDecoder().decode(TokenUsage.self, from: Data(#"{"prompt_tokens":1}"#.utf8))
        #expect(unknown.reasoningTokens == nil)
        #expect(try JSONDecoder().decode(TokenUsage.self, from: JSONEncoder().encode(usage)) == usage)
        let legacy = try JSONDecoder().decode(UsageStats.self, from: Data(#"{"inputTokens":1,"outputTokens":1,"cacheHitTokens":0,"cacheMissTokens":1,"requestCount":1}"#.utf8))
        #expect(legacy.reportedReasoningTokens == nil)
    }
}

private final class OptimizationURLProtocol: URLProtocol, @unchecked Sendable {
    static let handler = Mutex<(@Sendable (URLRequest) throws -> (Int, String))?>(nil)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let handle = try #require(Self.handler.withLock { $0 })
            let (status, text) = try handle(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(text.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite(.serialized) @MainActor struct ContextRecoveryTransportTests {
    private func fixture() -> (DeepSeekClient, URLSession, Conversation) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OptimizationURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = DeepSeekClient(apiKey: "placeholder", baseURL: "https://api.deepseek.com", model: DeepSeekModels.flash,
                                   parameters: ModelParameters(contextWindowTokens: 65_536), language: .simplifiedChinese, session: session)
        let user = ChatMessage(role: .user, content: "用户明确说不是恋人。" + String(repeating: "原始依据", count: 300))
        let conversation = Conversation(title: "原始来源", messages: [user, .init(role: .assistant, content: "待核对"), .init(role: .user, content: "请继续")])
        return (client, session, conversation)
    }
    private var success: String {
        "data: {\"choices\":[{\"delta\":{\"content\":\"保留否定的回答\"}}]}\n\ndata: [DONE]\n\n"
    }
    private func validSummary(_ conversation: Conversation) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: ["items": [["kind": "user_fact", "text": "用户说不是恋人。", "sourceMessageID": conversation.messages[0].id.uuidString, "quote": "不是恋人"]]]), as: UTF8.self)
    }

    @Test func recognizedOverflowCompactsAndRetriesExactlyOnce() async throws {
        let (client, session, conversation) = fixture()
        defer { session.invalidateAndCancel() }
        let requests = Mutex(0)
        let second = success
        OptimizationURLProtocol.handler.withLock { $0 = { _ in
            let attempt = requests.withLock { $0 += 1; return $0 }
            return attempt == 1 ? (400, #"{"error":{"code":"context_length_exceeded"}}"#) : (200, second)
        } }
        var summaries = 0
        let turn = OptimizedTurn(conversation: conversation, assistantID: UUID(), client: client, memory: nil, hint: nil, chapterIndex: nil, tools: [],
            commit: { _, _, _, _, _, _ in true }, summarize: { _, _ in summaries += 1; return try validSummary(conversation) })
        let result = try await turn.stream(round: 0, allowTools: true) { _ in }
        #expect(result.content == "保留否定的回答")
        #expect(requests.withLock { $0 } == 2 && summaries == 1 && turn.report.overflowRetries == 1)
    }

    @Test func genericErrorsAndErrorsAfterVisibleOutputDoNotRetry() async throws {
        for partial in [false, true] {
            let (client, session, conversation) = fixture()
            defer { session.invalidateAndCancel() }
            let requests = Mutex(0)
            OptimizationURLProtocol.handler.withLock { $0 = { _ in
                requests.withLock { $0 += 1 }
                return partial
                    ? (200, "data: {\"choices\":[{\"delta\":{\"content\":\"已经输出\"}}]}\n\ndata: {\"error\":{\"code\":\"context_length_exceeded\"}}\n\n")
                    : (400, #"{"error":{"code":"invalid_request_error"}}"#)
            } }
            var summaries = 0
            let turn = OptimizedTurn(conversation: conversation, assistantID: UUID(), client: client, memory: nil, hint: nil, chapterIndex: nil, tools: [],
                commit: { _, _, _, _, _, _ in true }, summarize: { _, _ in summaries += 1; return "" })
            do { _ = try await turn.stream(round: 0, allowTools: true) { _ in }; Issue.record("Provider failure was lost") } catch {}
            #expect(requests.withLock { $0 } == 1 && summaries == 0)
        }
    }

    @Test func repeatedOverflowStopsAfterTheRecoveryRequest() async throws {
        let (client, session, conversation) = fixture()
        defer { session.invalidateAndCancel() }
        let requests = Mutex(0)
        OptimizationURLProtocol.handler.withLock { $0 = { _ in
            requests.withLock { $0 += 1 }
            return (400, #"{"error":{"code":"context_window_exceeded"}}"#)
        } }
        let turn = OptimizedTurn(conversation: conversation, assistantID: UUID(), client: client, memory: nil, hint: nil, chapterIndex: nil, tools: [],
            commit: { _, _, _, _, _, _ in true }, summarize: { _, _ in try validSummary(conversation) })
        do { _ = try await turn.stream(round: 0, allowTools: true) { _ in }; Issue.record("Repeated overflow was lost") } catch {}
        #expect(requests.withLock { $0 } == 2 && turn.report.overflowRetries == 1)
    }
}

@Suite @MainActor struct ContextPersistenceBoundaryTests {
    @Test func staleSourceCannotCommitOrActivateASummaryAndSuccessfulCheckpointLoads() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let agent = ChatAgent(storagePath: root.path)
        agent.createConversation()
        var conversation = try #require(agent.selectedConversation)
        let user = ChatMessage(role: .user, content: "用户说的是朋友，不是恋人。" + String(repeating: "事实", count: 1000))
        let reply = ChatMessage(role: .assistant, content: "等待")
        conversation.messages = [user, .init(role: .assistant, content: "已知回答"), .init(role: .user, content: "再补充一个事实"), reply]
        agent.selectedConversation = conversation
        let client = DeepSeekClient(apiKey: "placeholder", baseURL: "https://api.deepseek.com", model: DeepSeekModels.flash,
                                    parameters: ModelParameters(), language: .simplifiedChinese)
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: ["items": [["kind": "user_fact", "text": "用户说是朋友而非恋人。", "sourceMessageID": user.id.uuidString, "quote": "朋友，不是恋人"]]]), as: UTF8.self)
        let turn = agent.makeOptimizedTurn(conversation: conversation, assistantID: reply.id, client: client, memory: nil, hint: nil,
            summarize: { _, _ in raw })
        try await turn.prepare(allowTools: true, round: 0, force: true)
        let loaded = ChatAgent(storagePath: root.path)
        let saved = try #require(loaded.conversations.first { $0.id == conversation.id })
        #expect(ContextMeter.checkpoint(saved.compactionCheckpoint, matches: saved.messages))
        #expect(saved.messages[0].content == user.content)
        var value = try #require(agent.selectedConversation)
        value.compactionCheckpoint = nil
        agent.selectedConversation = value
        let stale = agent.makeOptimizedTurn(conversation: value, assistantID: reply.id, client: client, memory: nil, hint: nil,
            summarize: { _, _ in
                var changed = agent.selectedConversation!
                changed.messages[0].content = "用户修改了原话。"
                agent.selectedConversation = changed
                return raw
            })
        do { try await stale.prepare(allowTools: true, round: 0, force: true); Issue.record("Stale summary accepted") } catch {}
        #expect(agent.selectedConversation?.compactionCheckpoint == nil)
        #expect(agent.selectedConversation?.messages[0].content == "用户修改了原话。")
    }

    @Test func profileFingerprintTracksSourceChangesAndIgnoresRequestSnapshots() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = AppSettings(storagePath: root.path)
        let user = ChatMessage(role: .user, content: "我希望简短回答。")
        var conversation = Conversation(title: "偏好", messages: [user])
        let chapter = StoryChapter(title: "偏好", summary: "偏好简短回答", keywords: ["简短"], messageIDs: [user.id])
        let before = ChatAgent.profileFingerprint(chapter: chapter, conversation: conversation, settings: settings)
        conversation.messages[0].requestContext = "新的时间信息"
        #expect(before == ChatAgent.profileFingerprint(chapter: chapter, conversation: conversation, settings: settings))
        conversation.messages[0].content = "我更希望详细回答。"
        #expect(before != ChatAgent.profileFingerprint(chapter: chapter, conversation: conversation, settings: settings))
        #expect(before.count == 64)
    }

    @Test func imagePayloadUsesAVisualReserveRatherThanPricingBase64AsOrdinaryText() throws {
        let data = try JSONSerialization.data(withJSONObject: ["messages": [["image_url": ["url": "data:image/png;base64," + String(repeating: "A", count: 200_000)]]]])
        var request = URLRequest(url: URL(string: "https://provider.test")!)
        request.httpBody = data
        #expect(try ContextMeter.request(request) < 20_000)
        #expect(try ContextMeter.request(request) >= 16_384)
    }

    @Test func messagesApiUsageAddsCacheReadsWithoutDoubleCountingOutput() throws {
        let data = Data(#"{"usage":{"input_tokens":50,"output_tokens":20,"cache_read_input_tokens":100,"cache_creation_input_tokens":10}}"#.utf8)
        let usage = try #require(DeepSeekWebSearchClient.responseUsage(data))
        #expect(usage.promptTokens == 160 && usage.promptCacheHitTokens == 100 && usage.promptCacheMissTokens == 60)
        #expect(usage.completionTokens == 20)
        #expect(DeepSeekWebSearchClient.responseUsage(Data(#"{"usage":{}}"#.utf8)) == nil)
    }
}

@Suite @MainActor struct ContextStorageConflictTests {
    @Test func externalWriteRejectsCheckpointWithoutOverwritingEitherSourcesOrTheOtherWindow() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let agent = ChatAgent(storagePath: root.path)
        agent.createConversation()
        var value = try #require(agent.selectedConversation)
        let user = ChatMessage(role: .user, content: "明确说不是恋人。" + String(repeating: "依据", count: 2000))
        let assistant = ChatMessage(role: .assistant, content: "placeholder")
        value.messages = [user, .init(role: .assistant, content: "历史答复"), .init(role: .user, content: "当前提问"), assistant]
        agent.selectedConversation = value
        #expect(agent.flushStorage())
        let client = DeepSeekClient(apiKey: "placeholder", baseURL: "https://api.deepseek.com", model: DeepSeekModels.flash,
                                    parameters: ModelParameters(), language: .simplifiedChinese)
        let turn = agent.makeOptimizedTurn(conversation: value, assistantID: assistant.id, client: client, memory: nil, hint: nil,
            summarize: { _, _ in
                let external = try SQLiteStore(root: root)
                _ = try external.read("conversations.json", legacy: root)
                var other = agent.conversations
                other[0].title = "来自另一个窗口"
                try external.write("conversations.json", data: SQLiteStore.encoder().encode(other))
                let object: [String: Any] = ["items": [["kind": "user_fact", "text": "用户否认恋爱关系。", "sourceMessageID": user.id.uuidString, "quote": "不是恋人"]]]
                return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            })
        do { try await turn.prepare(allowTools: true, round: 0, force: true); Issue.record("Conflict was ignored") } catch {}
        #expect(agent.hasStorageFailure && agent.selectedConversation?.compactionCheckpoint == nil)
        let loaded = ChatAgent(storagePath: root.path)
        #expect(loaded.conversations[0].title == "来自另一个窗口")
        #expect(loaded.conversations[0].messages[0].content == user.content)
        #expect(loaded.conversations[0].compactionCheckpoint == nil)
    }
}

@Suite @MainActor struct ContextCalibrationAndCancellationTests {
    @Test func reportedUsageCanCorrectUnderestimationOnlyOnTheSameRoute() async throws {
        let client = DeepSeekClient(apiKey: "placeholder", baseURL: "https://api.deepseek.com", model: DeepSeekModels.flash,
                                    parameters: ModelParameters(), language: .simplifiedChinese)
        var conversation = Conversation(title: "用量", messages: [.init(role: .user, content: "本轮提问")])
        let turn = OptimizedTurn(conversation: conversation, assistantID: UUID(), client: client, memory: nil, hint: nil,
            chapterIndex: nil, tools: [], commit: { _, _, _, _, _, _ in true })
        try await turn.prepare(allowTools: true, round: 0)
        let estimate = try turn.measured(allowTools: true, round: 0)
        try turn.finish(.init(content: "答复", reasoning: nil, usage: .init(promptTokens: Int64(estimate * 2))))
        #expect(turn.report.calibrationFactor == 2 && turn.report.observedInputTokens == Int64(estimate * 2))
        conversation.optimizationReport = turn.report
        let next = OptimizedTurn(conversation: conversation, assistantID: UUID(), client: client, memory: nil, hint: nil,
            chapterIndex: nil, tools: [], commit: { _, _, _, _, _, _ in true })
        #expect(try next.measured(allowTools: true, round: 0) == estimate * 2)
        var different = client
        different.baseURL = "https://another-provider.test/v1"
        let changed = OptimizedTurn(conversation: conversation, assistantID: UUID(), client: different, memory: nil, hint: nil,
            chapterIndex: nil, tools: [], commit: { _, _, _, _, _, _ in true })
        #expect(changed.report.calibrationFactor == 1)
    }

    @Test func cancellationWhileSummarizingLeavesOriginalsAndCheckpointIntact() async throws {
        let client = DeepSeekClient(apiKey: "placeholder", baseURL: "https://api.deepseek.com", model: DeepSeekModels.flash,
                                    parameters: ModelParameters(), language: .simplifiedChinese)
        let conversation = Conversation(title: "取消", messages: [
            .init(role: .user, content: String(repeating: "原始依据，不是推测。", count: 1000)),
            .init(role: .assistant, content: "已知回答"), .init(role: .user, content: "当前问题")])
        var began = false
        var stored: CompactionCheckpoint?
        let turn = OptimizedTurn(conversation: conversation, assistantID: UUID(), client: client, memory: nil, hint: nil,
            chapterIndex: nil, tools: [], commit: { _, _, checkpoint, _, _, _ in stored = checkpoint; return true },
            summarize: { _, _ in
                began = true
                try await Task.sleep(for: .seconds(3))
                return "{}"
            })
        let work = Task { try await turn.prepare(allowTools: true, round: 0, force: true) }
        for _ in 0..<1000 { if began { break }; await Task.yield() }
        #expect(began)
        work.cancel()
        do { try await work.value; Issue.record("Cancellation ignored") } catch is CancellationError {} catch { Issue.record("Unexpected cancellation failure: \(error)") }
        #expect(stored == nil && turn.checkpoint == nil)
        #expect(turn.messages.map(\.content) == conversation.messages.map(\.content))
    }
}
