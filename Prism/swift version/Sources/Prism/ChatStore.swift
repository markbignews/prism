import Foundation
import Combine

@MainActor
final class ChatStore: ObservableObject, ChatAgentDelegate {
    private let agent: ChatAgent
    let stream = StreamingMessageState()
    var streamingMessageID: UUID? { agent.streamingMessageID }
    private var contextCache: (key: ContextCacheKey, value: ContextUsageSnapshot)?

    private struct ContextCacheKey: Equatable {
        var conversationID: UUID?
        var revision: UInt
        var model: String
        var usesFlashParameters: Bool
        var language: AppLanguage
        var mode: ConversationMode
        var length: ResponseLength
        var parameters: ModelParameters
        var flashParameters: ModelParameters
        var summaryInterval: Int
    }
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
    var hasStorageFailure: Bool { agent.hasStorageFailure }
    var canRetryStorage: Bool { agent.canRetryStorage }
    func retryStorage() { agent.retryStorage(); refreshAfterMutation() }
    @discardableResult func flushStorage() -> Bool { agent.flushStorage() }
    func exportWindowSnapshot(to url: URL) throws { try agent.exportWindowSnapshot(to: url) }
    func importWindowSnapshot(from url: URL) throws { try agent.importWindowSnapshot(from: url); refreshAfterMutation() }
    func discardAndReloadStorage(settings: AppSettings) {
        agent.reloadStorage(from: settings, discardingUnsaved: true); refreshAfterMutation()
    }
    var isSummarizing: Bool { agent.isSummarizing }
    var lastSummarySucceeded: Bool? { agent.lastSummarySucceeded }
    var lastSummaryStatus: String { agent.lastSummaryStatus }
    var selectedConversation: Conversation? {
        guard let id = selectedConversationID else { return nil }
        return conversations.first(where: { $0.id == id })
    }
    var allChapters: [StoryChapter] { agent.allChapters }
    var personArchive: [PersonRecord] { agent.personArchive }
    var personLinkProposals: [PersonLinkProposal] { agent.personLinkProposals }
    var userProfileObservations: [UserProfileObservation] { agent.userProfileObservations }
    var emotionTimeline: [EmotionEntry] { agent.emotionTimeline }
    var blindspots: [BlindspotRecord] { agent.blindspots }
    var memoryStore: [MemoryEntry] { agent.memoryStore }
    var narrativeTimeline: [NarrativeEvent] { agent.narrativeTimeline }
    var pendingNarrativeEvent: NarrativeEventProposal? {
        agent.pendingNarrativeEvents.first {
            $0.isCurrent(conversationID: selectedConversationID,
                latestUserMessageID: selectedConversation?.messages.last(where: { $0.role == .user })?.id)
        }
    }
    func confirmNarrativeEvent(id: UUID) { agent.confirmNarrativeEvent(id: id); refreshAfterMutation() }
    func rejectNarrativeEvent(id: UUID) { agent.rejectNarrativeEvent(id: id); refreshAfterMutation() }
    var pendingClarification: UserClarification? { agent.pendingClarification }
    func submitClarification(_ submission: ClarificationSubmission, settings: AppSettings) async {
        await agent.send("", clarification: submission, settings: settings)
        refreshAfterMutation()
    }
    var currentSendTask: Task<Void, Never>? {
        get { agent.currentSendTask }
        set { agent.currentSendTask = newValue }
    }

    init(agent: ChatAgent = ChatAgent()) {
        self.agent = agent
        agent.delegate = self
        syncFromAgent()
    }

    private func syncFromAgent() {
        conversations = agent.conversations
        if selectedConversationID != agent.selectedConversationID { selectedConversationID = agent.selectedConversationID }
        if let messageID = agent.streamingMessageID,
           let conversation = conversations.first(where: { $0.messages.contains(where: { $0.id == messageID }) }),
           let message = conversation.messages.first(where: { $0.id == messageID }) {
            // Global turn/tool transitions can change a placeholder without an
            // SSE delta. Keep the active row synchronized at those boundaries.
            stream.receive(message, in: conversation.id)
        } else {
            stream.clear()
        }
    }

    private func refreshAfterMutation() {
        syncFromAgent()
        stateRevision &+= 1
    }

    func agentStateDidChange() { refreshAfterMutation() }
    func agentDidStream(_ message: ChatMessage, in conversationID: UUID) {
        stream.receive(message, in: conversationID)
    }

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

    func confirmPersonLinkProposal(id: UUID) {
        agent.confirmPersonLinkProposal(id: id)
        refreshAfterMutation()
    }

    func rejectPersonLinkProposal(id: UUID) {
        agent.rejectPersonLinkProposal(id: id)
        refreshAfterMutation()
    }

    func removeUserProfileObservation(id: UUID) {
        agent.removeUserProfileObservation(id: id)
        refreshAfterMutation()
    }

    func removePersonTrait(personID: UUID, traitID: UUID) {
        agent.removePersonTrait(personID: personID, traitID: traitID)
        refreshAfterMutation()
    }

    func removeBlindspot(id: UUID) {
        agent.removeBlindspot(id: id)
        refreshAfterMutation()
    }

    func removeMemoryEntry(id: UUID) {
        agent.removeMemoryEntry(id: id)
        refreshAfterMutation()
    }

    /// Delete confirmations are presented with SwiftUI `.confirmationDialog`
    /// in the view layer (see ContentView's `PendingDelete`), so the store
    /// only exposes the plain mutation.
    func searchMemory(query: String, limit: Int = 10) -> [MemoryEntry] { agent.searchMemory(query: query, limit: limit) }
    func hasActiveSafetyCrisis(for id: UUID) -> Bool { agent.hasActiveSafetyCrisis(for: id) }
    func contextUsage(settings: AppSettings) -> ContextUsageSnapshot {
        let key = ContextCacheKey(conversationID: selectedConversationID, revision: stateRevision,
            model: settings.model, usesFlashParameters: settings.usesFlashParameters,
            language: settings.language, mode: selectedConversation?.mode ?? settings.conversationMode,
            length: settings.responseLength, parameters: settings.parameters,
            flashParameters: settings.flashParameters, summaryInterval: settings.summaryDialogCount)
        if let cached = contextCache, cached.key == key { return cached.value }
        let value = agent.contextUsage(for: selectedConversationID, settings: settings)
        contextCache = (key, value)
        return value
    }

    func send(_ text: String, attachments: [MessageAttachment] = [], settings: AppSettings) async {
        await agent.send(text, attachments: attachments, settings: settings)
    }
    func regenerateAssistantMessage(in cid: UUID, messageID: UUID, settings: AppSettings) async { await agent.regenerateAssistantMessage(in: cid, messageID: messageID, settings: settings) }
    func editAndResend(userMessageID: UUID, newText: String, settings: AppSettings) async { await agent.editAndResend(userMessageID: userMessageID, newText: newText, settings: settings) }
    func summarizeOnDeselect(conversationID: UUID, settings: AppSettings) async { await agent.summarizeOnDeselect(conversationID: conversationID, settings: settings) }
    func fullReSummarize(conversationID: UUID, settings: AppSettings) async { await agent.fullReSummarize(conversationID: conversationID, settings: settings) }
    func fullReSummarize(settings: AppSettings) async { await agent.fullReSummarize(settings: settings) }
}
