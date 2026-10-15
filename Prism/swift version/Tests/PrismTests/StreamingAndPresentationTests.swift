import Foundation
import Combine
import Testing
@testable import Prism

@MainActor
private final class StreamRecorder: ChatAgentDelegate {
    var globalFrames = 0
    var streamedMessages: [ChatMessage] = []
    weak var agent: ChatAgent?
    var contentAtGlobalPublish: String?
    func agentStateDidChange() {
        globalFrames += 1
        contentAtGlobalPublish = agent?.selectedConversation?.messages.last?.content
    }
    func agentDidStream(_ message: ChatMessage, in conversationID: UUID) {
        streamedMessages.append(message)
    }
}

@MainActor
private func streamingFixture(historyCount: Int = 0) throws -> (folder: URL, agent: ChatAgent, conversationID: UUID, replyID: UUID) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var conversation = Conversation(title: "界面与流式回归")
    for i in 0..<historyCount {
        conversation.messages.append(ChatMessage(role: i.isMultiple(of: 2) ? .user : .assistant,
            content: String(repeating: "可观察事实与尚未确定的解释。", count: 100)))
    }
    conversation.messages.append(ChatMessage(role: .user, content: "请帮我理解这件事。"))
    let reply = ChatMessage(role: .assistant, content: "")
    try JSONEncoder().encode([conversation]).write(to: folder.appendingPathComponent("conversations.json"))
    let agent = ChatAgent(storagePath: folder.path)
    // A real send appends its placeholder after recovery. Persisted empty
    // trailing assistant messages are intentionally removed during load.
    conversation.messages.append(reply)
    agent.selectedConversation = conversation
    // Fixture setup schedules a 500ms persistence write. Complete it before
    // attaching stream observers: a save-completion notification is legitimate
    // global state, unrelated to token delivery, and may arrive on a busy runner.
    try #require(agent.flushStorage())
    return (folder, agent, conversation.id, reply.id)
}

@Suite(.serialized) @MainActor struct StreamingDeliveryTests {
    @Test func tenThousandDeltasAreBatchedWithoutGlobalRefreshOrLostText() async throws {
        let fixture = try streamingFixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let recorder = StreamRecorder()
        recorder.agent = fixture.agent
        fixture.agent.delegate = recorder
        fixture.agent.isSending = true
        fixture.agent.beginStreamingMessage(fixture.replyID)
        for _ in 0..<10_000 { fixture.agent.append(.content("字"), to: fixture.replyID, in: fixture.conversationID) }
        #expect(recorder.streamedMessages.count == 1) // First token is immediate.
        #expect(recorder.globalFrames == 0)
        // Allow other main-actor test suites to finish their work before the
        // scheduled frame runs; do not assume an exact scheduler deadline.
        for _ in 0..<50 {
            if recorder.streamedMessages.count >= 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(recorder.streamedMessages.count == 2)
        #expect(recorder.streamedMessages.last?.content == String(repeating: "字", count: 10_000))
        #expect(recorder.globalFrames == 0)
        fixture.agent.finishStreamingMessage(fixture.replyID, in: fixture.conversationID,
            content: "完整最终回复", reasoning: "最终依据")
        #expect(recorder.globalFrames == 1)
        #expect(recorder.contentAtGlobalPublish == "完整最终回复")
        #expect(fixture.agent.streamingMessageID == nil)
    }

    @Test func finishingFlushesPendingFramesAndLateTokensCannotOverwriteResult() async throws {
        let fixture = try streamingFixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let recorder = StreamRecorder()
        fixture.agent.delegate = recorder
        fixture.agent.isSending = true
        fixture.agent.beginStreamingMessage(fixture.replyID)
        fixture.agent.append(.reasoning("先核对"), to: fixture.replyID, in: fixture.conversationID)
        fixture.agent.append(.content("尚未发布的片段"), to: fixture.replyID, in: fixture.conversationID)
        fixture.agent.finishStreamingMessage(fixture.replyID, in: fixture.conversationID, content: "[已取消生成]", reasoning: "")
        fixture.agent.append(.content("迟到片段"), to: fixture.replyID, in: fixture.conversationID)
        try await Task.sleep(for: .milliseconds(90))
        #expect(recorder.streamedMessages.count == 2)
        #expect(fixture.agent.selectedConversation?.messages.last?.content == "[已取消生成]")
        #expect(fixture.agent.selectedConversation?.messages.last?.reasoning == "先核对")
    }

    @Test func toolRoundReasoningSurvivesFinalShortReasoningAndReload() throws {
        let fixture = try streamingFixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        fixture.agent.isSending = true
        fixture.agent.beginStreamingMessage(fixture.replyID)
        let original = "第一轮：核对事实。\n保留原文。\n\n第二轮：检查工具证据。\n\nWrite the reply now."
        for part in ["第一轮：核对事实。\n保留原文。", "\n\n", "第二轮：检查工具证据。", "\n\n", "Write the reply now."] {
            fixture.agent.append(.reasoning(part), to: fixture.replyID, in: fixture.conversationID)
        }
        // Reproduce the original overwrite: only the final subrequest is supplied.
        fixture.agent.finishStreamingMessage(fixture.replyID, in: fixture.conversationID,
            content: "最终答复", reasoning: "Write the reply now.")
        #expect(fixture.agent.selectedConversation?.messages.last?.reasoning == original)
        fixture.agent.save()
        #expect(fixture.agent.flushStorage())
        let restored = ChatAgent(storagePath: fixture.folder.path)
        #expect(restored.selectedConversation?.messages.last?.reasoning == original)
    }

    @Test func toolPlaceholderBoundaryRefreshesTheActiveMessage() throws {
        let fixture = try streamingFixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let store = ChatStore(agent: fixture.agent)
        fixture.agent.isSending = true
        fixture.agent.beginStreamingMessage(fixture.replyID)
        fixture.agent.append(.reasoning("需要检索原文"), to: fixture.replyID, in: fixture.conversationID)
        var conversation = try #require(fixture.agent.selectedConversation)
        conversation.messages[conversation.messages.count - 1].isToolPlaceholder = true
        fixture.agent.selectedConversation = conversation
        fixture.agent.delegate?.agentStateDidChange()
        #expect(store.stream.message?.isToolPlaceholder == true)
        #expect(store.stream.message?.reasoning == "需要检索原文")
        fixture.agent.finishStreamingMessage(fixture.replyID, in: fixture.conversationID, content: "已核对原文", reasoning: "依据")
        #expect(store.stream.message == nil)
    }

    @Test func streamChangesOnlyTheReplyObservableAndFinalFrameSynchronizesHistory() throws {
        let fixture = try streamingFixture(historyCount: 80)
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let store = ChatStore(agent: fixture.agent)
        let settings = AppSettings(storagePath: fixture.folder.path, credentialStore: TestCredentials.shared)
        let before = store.contextUsage(settings: settings)
        var notifications = 0
        let subscription = store.objectWillChange.sink { notifications += 1 }
        defer { subscription.cancel() }
        fixture.agent.isSending = true
        fixture.agent.beginStreamingMessage(fixture.replyID)
        fixture.agent.append(.content("流式正文"), to: fixture.replyID, in: fixture.conversationID)
        #expect(notifications == 0)
        #expect(store.stream.message?.content == "流式正文")
        #expect(store.selectedConversation?.messages.last?.content == "")
        for _ in 0..<100 { #expect(store.contextUsage(settings: settings) == before) }
        fixture.agent.finishStreamingMessage(fixture.replyID, in: fixture.conversationID,
            content: String(repeating: "最终事实", count: 100), reasoning: "")
        #expect(notifications > 0)
        #expect(store.selectedConversation?.messages.last?.content == String(repeating: "最终事实", count: 100))
        #expect(store.contextUsage(settings: settings).estimatedTokens > before.estimatedTokens)
        #expect(store.stream.message == nil)
        settings.responseLength = .brief
        #expect(store.contextUsage(settings: settings).reservedOutputTokens == ResponseLength.brief.maxTokens)
    }
}

@Suite struct SharedStanceTests {
    @Test(arguments: ConversationMode.allCases, AppLanguage.allCases)
    func everyModeAndLanguageSharesEvidenceBoundedOptimism(mode: ConversationMode, language: AppLanguage) {
        let prompt = AgentPrompt.system(language: language, mode: mode)
        #expect(prompt.contains(AgentPrompt.cautiousOptimismPrinciple))
        #expect(prompt.contains("不盲目乐观、不淡化风险、不许诺结果"))
        #expect(prompt.contains("尊重事实与对方边界"))
    }

    @Test(arguments: AppLanguage.allCases)
    func titlebarDisclaimerIsLocalizedAndBrief(language: AppLanguage) {
        let subtitle = L10n.text(.aiGeneratedSubtitle, language)
        #expect(subtitle.contains("AI"))
        #expect(subtitle.count < 70)
        #expect(subtitle != "aiGeneratedSubtitle")
    }
}
