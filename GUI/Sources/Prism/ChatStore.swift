import Foundation
import Combine

@MainActor
final class ChatStore: ObservableObject, ChatAgentDelegate {
    private let agent = ChatAgent()

    var conversations: [Conversation] { agent.conversations }
    var selectedConversationID: Conversation.ID? {
        get { agent.selectedConversationID }
        set { agent.selectedConversationID = newValue }
    }
    var isSending: Bool { agent.isSending }
    var errorMessage: String? { agent.errorMessage }
    var isSummarizing: Bool { agent.isSummarizing }
    var lastSummaryStatus: String { agent.lastSummaryStatus }
    var selectedConversation: Conversation? { agent.selectedConversation }
    var allChapters: [StoryChapter] { agent.allChapters }
    var personArchive: [PersonRecord] { agent.personArchive }
    var emotionTimeline: [EmotionEntry] { agent.emotionTimeline }
    var blindspots: [BlindspotRecord] { agent.blindspots }
    var memoryStore: [MemoryEntry] { agent.memoryStore }
    var currentSendTask: Task<Void, Never>? {
        get { agent.currentSendTask }
        set { agent.currentSendTask = newValue }
    }

    init() { agent.delegate = self }

    func agentStateDidChange() { objectWillChange.send() }

    func bootstrapIfNeeded(language: AppLanguage = .simplifiedChinese) { agent.bootstrapIfNeeded(language: language) }
    func createConversation(language: AppLanguage = .simplifiedChinese) { agent.createConversation(language: language) }
    func deleteSelectedConversation() { agent.deleteSelectedConversation() }
    func deleteConversation(id: UUID) { agent.deleteConversation(id: id) }
    func resetAll() { agent.resetAll() }
    func reloadStorage(from s: AppSettings? = nil) { agent.reloadStorage(from: s) }
    func renameConversation(id: UUID, newTitle: String) { agent.renameConversation(id: id, newTitle: newTitle) }
    func deleteMessage(in cid: UUID, messageID: UUID) { agent.deleteMessage(in: cid, messageID: messageID) }
    func cancelSend() { agent.cancelSend() }
    func searchMemory(query: String, limit: Int = 10) -> [MemoryEntry] { agent.searchMemory(query: query, limit: limit) }
    func hasActiveSafetyCrisis(for id: UUID) -> Bool { agent.hasActiveSafetyCrisis(for: id) }

    func send(_ text: String, settings: AppSettings) async { await agent.send(text, settings: settings) }
    func regenerateAssistantMessage(in cid: UUID, messageID: UUID, settings: AppSettings) async { await agent.regenerateAssistantMessage(in: cid, messageID: messageID, settings: settings) }
    func editAndResend(userMessageID: UUID, newText: String, settings: AppSettings) async { await agent.editAndResend(userMessageID: userMessageID, newText: newText, settings: settings) }
    func summarizeOnDeselect(conversationID: UUID, settings: AppSettings) async { await agent.summarizeOnDeselect(conversationID: conversationID, settings: settings) }
    func fullReSummarize(conversationID: UUID, settings: AppSettings) async { await agent.fullReSummarize(conversationID: conversationID, settings: settings) }
    func fullReSummarize(settings: AppSettings) async { await agent.fullReSummarize(settings: settings) }
}
