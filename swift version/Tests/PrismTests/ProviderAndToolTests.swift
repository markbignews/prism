import AppKit
import Foundation
import Testing
@testable import Prism

@Suite struct ToolTranscriptTests {
    @Test func finalToolFreeRequestReplaysBothToolRoundsWithExactReasoning() throws {
        let client = DeepSeekClient(apiKey: " placeholder ", baseURL: "https://provider.test/v1", model: "model",
            parameters: ModelParameters(thinkingEnabled: true, reasoningEffort: "high"), language: .simplifiedChinese)
        let original = ChatMessage(role: .assistant, content: "历史答复", reasoning: "历史推理")
        let exchanges = [
            ToolExchange(response: DeepSeekResult(content: "", reasoning: "  第一轮\n全文  ", toolCalls: [.init(id: "a", name: "lookup", arguments: "{}")]), results: [.init(toolCallID: "a", name: "lookup", content: "证据 A")]),
            ToolExchange(response: DeepSeekResult(content: "中间正文", reasoning: "第二轮全文", toolCalls: [.init(id: "b", name: "lookup", arguments: "{}")]), results: [.init(toolCallID: "b", name: "lookup", content: "证据 B")])
        ]
        let request = try client.makeStreamRequest(messages: [original, .init(role: .user, content: "本轮问题")], memoryContext: nil,
            tools: nil, toolExchanges: exchanges)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer placeholder")
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["system", "assistant", "user", "assistant", "tool", "assistant", "tool"])
        #expect(messages[1]["reasoning_content"] as? String == "历史推理")
        #expect(messages[3]["reasoning_content"] as? String == "  第一轮\n全文  ")
        #expect(messages[4]["tool_call_id"] as? String == "a")
        #expect(messages[5]["reasoning_content"] as? String == "第二轮全文")
        #expect(messages[6]["tool_call_id"] as? String == "b")
    }
}

@Suite struct ProviderMessageTests {
    @Test(arguments: ["Bearer secret", "key with space", "sk-test\nextra", "\"sk-test\"", "中文密钥"])
    func malformedKeysFailBeforeAnyRequest(key: String) {
        #expect(throws: (any Error).self) { try APICredentials.normalized(key) }
        let client = DeepSeekClient(apiKey: key, baseURL: "https://provider.test", model: "model", parameters: ModelParameters(), language: .simplifiedChinese)
        #expect(throws: (any Error).self) { try client.makeStreamRequest(messages: [], memoryContext: nil) }
    }
    @Test func edgeWhitespaceIsRemovedAndErrorMessagesExplainActions() throws {
        #expect(try APICredentials.normalized(" \nsk-placeholder\t") == "sk-placeholder")
        #expect(ProviderFailure.message(DeepSeekError.http(401), language: .simplifiedChinese).contains("密钥验证失败"))
        #expect(ProviderFailure.message(DeepSeekError.http(402), language: .simplifiedChinese).contains("余额不足"))
        #expect(ProviderFailure.message(DeepSeekError.http(429), language: .simplifiedChinese).contains("稍等"))
        #expect(ProviderFailure.message(URLError(.timedOut), language: .simplifiedChinese).contains("超时"))
        #expect(!ProviderFailure.message(URLError(.cannotFindHost, userInfo: [NSLocalizedDescriptionKey: "secret"]), language: .english).contains("secret"))
    }
}

@Suite @MainActor struct NativeInputTests {
    @Test func composerCapsHeightAndDocumentRemainsScrollable() {
        let scroll = ComposerScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 110))
        let editor = ComposerTextView(frame: .zero)
        editor.font = .systemFont(ofSize: 13)
        editor.isVerticallyResizable = true
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.heightTracksTextView = false
        scroll.documentView = editor
        editor.string = "一行"
        let frameBefore = editor.frame
        let containerBefore = editor.textContainer?.containerSize
        let short = scroll.measuredHeight(width: 400)
        _ = scroll.measuredHeight(width: 800)
        #expect(editor.frame == frameBefore)
        #expect(editor.textContainer?.containerSize == containerBefore)
        editor.string = (1...100).map { "第\($0)行：内容与事实" }.joined(separator: "\n")
        let long = scroll.measuredHeight(width: 400)
        scroll.resizeDocument()
        #expect(short == 28)
        #expect(long > short && long < 160)
        #expect(editor.frame.height > scroll.contentSize.height * 5)
        editor.scrollRangeToVisible(NSRange(location: (editor.string as NSString).length, length: 0))
        #expect(scroll.contentView.bounds.origin.y > 0)
        editor.scrollRangeToVisible(NSRange(location: 0, length: 0))
        #expect(scroll.contentView.bounds.origin.y < 30)
    }
}

@Suite struct ConfirmationSizingTests {
    @Test(arguments: [CGFloat(420), 560, 616, 680, 900, 1600], [1, 2])
    func stackedReviewsLeaveRoomForComposer(height: CGFloat, count: Int) {
        let body = ConfirmationLayout.bodyHeight(availableHeight: height, cardCount: count)
        #expect(body >= 36 && body <= 160)
        // 64 pt per card reserves padding, spacing and the horizontal actions.
        #expect((body + 64) * CGFloat(count) + 160 <= height)
    }
    @Test func invalidOrTransitionalGeometryRemainsFinite() {
        for height: CGFloat in [0, -1, .infinity, .nan] {
            let body = ConfirmationLayout.bodyHeight(availableHeight: height, cardCount: 0)
            #expect(body.isFinite && body >= 36 && body <= 160)
        }
    }
}
