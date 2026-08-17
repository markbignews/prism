import Foundation
import Combine

@MainActor
final class ChatStore: ObservableObject, ChatAgentDelegate {
    private let agent = ChatAgent()
    @Published private(set) var conversations: [Conversation] = []
    @Published var selectedConversationID: Conversation.ID? {
        didSet { agent.selectedConversationID = selectedConversationID }
    }
    /// Monotonic UI revision.  The agent owns the value types, so a published
    /// revision makes mutations such as deletion visible immediately even
    /// when a computed collection (rather than an @Published property) is
    /// read by SwiftUI.
    @Published private(set) var stateRevision: UInt = 0

    var isSending: Bool { agent.isSending }
    var errorMessage: String? { agent.errorMessage }
    var isSummarizing: Bool { agent.isSummarizing }
    var lastSummaryStatus: String { agent.lastSummaryStatus }
    var selectedConversation: Conversation? {
        guard let id = selectedConversationID else { return nil }
        return conversations.first(where: { $0.id == id })
    }
    var allChapters: [StoryChapter] { agent.allChapters }
    var personArchive: [PersonRecord] { agent.personArchive }
    var emotionTimeline: [EmotionEntry] { agent.emotionTimeline }
    var blindspots: [BlindspotRecord] { agent.blindspots }
    var memoryStore: [MemoryEntry] { agent.memoryStore }
    var narrativeTimeline: [NarrativeEvent] { agent.narrativeTimeline }
    var currentSendTask: Task<Void, Never>? {
        get { agent.currentSendTask }
        set { agent.currentSendTask = newValue }
    }

    init() {
        agent.delegate = self
        syncFromAgent()
    }

    private func syncFromAgent() {
        conversations = agent.conversations
        selectedConversationID = agent.selectedConversationID
    }

    private func refreshAfterMutation() {
        syncFromAgent()
        stateRevision &+= 1
    }

    func agentStateDidChange() { refreshAfterMutation() }

    func bootstrapIfNeeded(language: AppLanguage = .simplifiedChinese) {
        agent.bootstrapIfNeeded(language: language)
        refreshAfterMutation()
    }

    func createConversation(language: AppLanguage = .simplifiedChinese) {
        agent.createConversation(language: language)
        refreshAfterMutation()
    }

    func deleteSelectedConversation() {
        agent.deleteSelectedConversation()
        refreshAfterMutation()
    }

    func deleteConversation(id: UUID) {
        agent.deleteConversation(id: id)
        refreshAfterMutation()
    }

    func resetAll() {
        agent.resetAll()
        refreshAfterMutation()
    }

    func reloadStorage(from s: AppSettings? = nil) {
        agent.reloadStorage(from: s)
        refreshAfterMutation()
    }

    func renameConversation(id: UUID, newTitle: String) {
        agent.renameConversation(id: id, newTitle: newTitle)
        refreshAfterMutation()
    }

    func setMode(_ mode: ConversationMode, for conversationID: UUID) {
        agent.setMode(mode, for: conversationID)
        refreshAfterMutation()
    }

    func deleteMessage(in cid: UUID, messageID: UUID) {
        agent.deleteMessage(in: cid, messageID: messageID)
        refreshAfterMutation()
    }

    func cancelSend() {
        agent.cancelSend()
        refreshAfterMutation()
    }

    /// Delete confirmations are presented with SwiftUI `.confirmationDialog`
    /// in the view layer (see ContentView's `PendingDelete`), so the store
    /// only exposes the plain mutation.
    func searchMemory(query: String, limit: Int = 10) -> [MemoryEntry] { agent.searchMemory(query: query, limit: limit) }
    func hasActiveSafetyCrisis(for id: UUID) -> Bool { agent.hasActiveSafetyCrisis(for: id) }
    func contextUsage(settings: AppSettings) -> ContextUsageSnapshot {
        agent.contextUsage(for: selectedConversationID, settings: settings)
    }

    func send(_ text: String, settings: AppSettings) async { await agent.send(text, settings: settings) }
    func regenerateAssistantMessage(in cid: UUID, messageID: UUID, settings: AppSettings) async { await agent.regenerateAssistantMessage(in: cid, messageID: messageID, settings: settings) }
    func editAndResend(userMessageID: UUID, newText: String, settings: AppSettings) async { await agent.editAndResend(userMessageID: userMessageID, newText: newText, settings: settings) }
    func summarizeOnDeselect(conversationID: UUID, settings: AppSettings) async { await agent.summarizeOnDeselect(conversationID: conversationID, settings: settings) }
    func fullReSummarize(conversationID: UUID, settings: AppSettings) async { await agent.fullReSummarize(conversationID: conversationID, settings: settings) }
    func fullReSummarize(settings: AppSettings) async { await agent.fullReSummarize(settings: settings) }
}
