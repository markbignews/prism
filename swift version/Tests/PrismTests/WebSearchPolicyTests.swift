import Foundation
import Synchronization
import Testing
@testable import Prism

@Suite struct SearchAndScopeContractTests {
    @Test func firstTurnProvidesWebAndCrossConversationRetrieval() throws {
        let tools = ToolRegistry.availableDefinitions(baseURL: "https://api.deepseek.com", includeHistory: false)
        #expect(Set(tools.map(\.function.name)) == ["track_person", "emotion_timeline", "search_web", "search_memory", "search_chapters", "fetch_chapter_messages", "manage_narrative_timeline", "request_user_input", "fetch_context", "request_deeper_analysis"])
        let client = DeepSeekClient(apiKey: "placeholder", baseURL: "https://api.deepseek.com", model: "deepseek-flash",
            parameters: ModelParameters(), language: .simplifiedChinese)
        let request = try client.makeStreamRequest(messages: [.init(role: .user, content: "这个心理学说法有依据吗？")],
                                                   memoryContext: nil, tools: tools)
        let bodyData = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])
        let system = try #require(messages.first?["content"] as? String)
        #expect(system.contains(AgentPrompt.webSearchRules))
        #expect(system.contains(AgentPrompt.productScopeRules))
        #expect(body["tool_choice"] as? String == "auto")
        let advertised = try #require(body["tools"] as? [[String: Any]])
        #expect(advertised.contains { ($0["function"] as? [String: Any])?["name"] as? String == "search_web" })
    }

    @Test func customProvidersDoNotAdvertiseOfficialOnlySearchInAnyTurn() {
        for includeHistory in [true, false] {
            let names = ToolRegistry.availableDefinitions(baseURL: "https://provider.test/v1", includeHistory: includeHistory).map(\.function.name)
            #expect(!names.contains("search_web"))
            #expect(!names.contains("search_psychology"))
            #expect(names.contains("request_user_input"))
        }
    }

    @Test(arguments: ConversationMode.allCases, AppLanguage.allCases)
    func everyStyleKeepsSearchAutonomousAndWorkScope(mode: ConversationMode, language: AppLanguage) {
        let prompt = AgentPrompt.system(language: language, mode: mode)
        #expect(prompt.contains(AgentPrompt.webSearchRules))
        #expect(prompt.hasSuffix(AgentPrompt.productScopeRules))
        #expect(prompt.contains("是否调用 search_web 由你根据完整上下文自主决定"))
        #expect(!prompt.contains("先查再答"))
        #expect(!prompt.contains("就主动检索"))
        #expect(!prompt.contains("只有用户明确要求研究依据"))
        #expect(!prompt.contains("普通的关系理解、情绪陪伴和基于当前对话的事实梳理不自动搜索"))
    }
}

private func searchRequestBody(_ request: URLRequest) throws -> Data {
    if let data = request.httpBody { return data }
    let stream = try #require(request.httpBodyStream)
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
        if count == 0 { break }
        data.append(contentsOf: buffer.prefix(count))
    }
    return data
}

private final class SearchURLProtocol: URLProtocol, @unchecked Sendable {
    static let handler = Mutex<(@Sendable (URLRequest) throws -> Data)?>(nil)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let action = try #require(Self.handler.withLock { $0 })
            let data = try action(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite(.serialized) @MainActor struct OfficialSearchTransportTests {
    @Test func broaderSearchUsesOfficialEndpointAndRedactsQueryBeforeSending() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = AppSettings(storagePath: folder.path, credentialStore: TestCredentials())
        settings.apiKey = "placeholder"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SearchURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let expectedInstructions = DeepSeekWebSearchClient.searchInstructions
        SearchURLProtocol.handler.withLock { $0 = { request in
            #expect(request.url?.absoluteString == "https://api.deepseek.com/anthropic/v1/messages")
            let bodyData = try searchRequestBody(request)
            let body = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            let system = try #require(body["system"] as? String)
            #expect(system.contains(expectedInstructions))
            #expect(system.contains(AgentPrompt.productScopeRules))
            let messages = try #require(body["messages"] as? [[String: Any]])
            #expect(messages.count == 1)
            let content = try #require(messages.first?["content"] as? [[String: Any]])
            let sent = try #require(content.first?["text"] as? String)
            #expect(sent.contains("当前社交平台公开消息隐私设置"))
            #expect(!sent.contains("test@example.com"))
            #expect(!sent.contains("13912345678"))
            #expect(!sent.contains("https://private.test"))
            let choice = try #require(body["tool_choice"] as? [String: String])
            #expect(choice["type"] == "auto")
            let tools = try #require(body["tools"] as? [[String: Any]])
            #expect(tools.first?["type"] as? String == "web_search_20250305")
            return Data(#"{"content":[{"type":"text","text":"模拟核查结论 [官方说明](https://example.com/rules)"}]}"#.utf8)
        } }
        let result = await DeepSeekWebSearchClient.search(
            query: "当前社交平台公开消息隐私设置 test@example.com 13912345678 https://private.test/path",
            settings: settings, session: session)
        #expect(result.contains("模拟核查结论"))
        #expect(!result.contains("test@example.com"))
    }
}
