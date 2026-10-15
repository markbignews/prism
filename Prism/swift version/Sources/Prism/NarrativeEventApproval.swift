import SwiftUI

/// A proposal is tied to its source turn. Only a native user action can save it;
/// model arguments and substrings in conversation text cannot grant approval.
struct NarrativeEventProposal: Identifiable, Equatable {
    var id = UUID()
    var conversationID: UUID
    var sourceMessageID: UUID
    var eventID: UUID?
    var title: String
    var summary: String
    var startLabel: String
    var endLabel: String
    var timeKind: String
    var sortIndex: Int

    init?(arguments: [String: String], conversationID: UUID, sourceMessageID: UUID) {
        let title = (arguments["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let start = (arguments["startLabel"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !start.isEmpty else { return nil }
        self.conversationID = conversationID
        self.sourceMessageID = sourceMessageID
        let eventIDText = (arguments["eventId"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard eventIDText.isEmpty || UUID(uuidString: eventIDText) != nil else { return nil }
        eventID = UUID(uuidString: eventIDText)
        self.title = String(title.prefix(24))
        summary = String((arguments["summary"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        startLabel = String(start.prefix(120))
        endLabel = String((arguments["endLabel"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        timeKind = ["period", "date", "mixed"].contains(arguments["timeKind"] ?? "") ? arguments["timeKind"]! : "period"
        sortIndex = Int(arguments["sortIndex"] ?? "10") ?? 10
    }

    func isCurrent(conversationID: UUID?, latestUserMessageID: UUID?) -> Bool {
        self.conversationID == conversationID && sourceMessageID == latestUserMessageID
    }
}

extension ChatAgent {
    func proposeNarrativeEvent(arguments: [String: String]) -> Bool {
        guard let conversationID = activeToolConversationID ?? selectedConversationID,
              let sourceID = activeToolSourceMessageID ?? conversations.first(where: { $0.id == conversationID })?.messages.last(where: { $0.role == .user })?.id,
              let proposal = NarrativeEventProposal(arguments: arguments, conversationID: conversationID, sourceMessageID: sourceID),
              proposal.eventID == nil || narrativeTimeline.contains(where: { $0.id == proposal.eventID && $0.conversationID == conversationID }) else { return false }
        pendingNarrativeEvents.removeAll {
            $0.conversationID == conversationID && ($0.title == proposal.title || (proposal.eventID != nil && $0.eventID == proposal.eventID))
        }
        pendingNarrativeEvents.append(proposal)
        delegate?.agentStateDidChange()
        return true
    }

    func confirmNarrativeEvent(id: UUID) {
        guard !isSending, let proposal = pendingNarrativeEvents.first(where: { $0.id == id }),
              proposal.isCurrent(conversationID: selectedConversationID,
                  latestUserMessageID: selectedConversation?.messages.last(where: { $0.role == .user })?.id) else { return }
        _ = upsertNarrativeEvent(eventID: proposal.eventID, title: proposal.title, summary: proposal.summary,
            startLabel: proposal.startLabel, endLabel: proposal.endLabel, timeKind: proposal.timeKind, sortIndex: proposal.sortIndex)
        rejectNarrativeEvent(id: id)
    }

    func rejectNarrativeEvent(id: UUID) {
        pendingNarrativeEvents.removeAll { $0.id == id }
        delegate?.agentStateDidChange()
    }
}

struct NarrativeEventApprovalView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var settings: AppSettings
    let proposal: NarrativeEventProposal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(proposal.title).font(.headline)
            Text([proposal.startLabel, proposal.endLabel].filter { !$0.isEmpty }.joined(separator: " → "))
                .font(.subheadline)
            ScrollView { Text(proposal.summary).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(maxHeight: 80)
            Text(L10n.text(.timelineApprovalHint, settings.language)).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(L10n.text(.saveTimelineEvent, settings.language)) { chatStore.confirmNarrativeEvent(id: proposal.id) }
                    .buttonStyle(.borderedProminent)
                Button(L10n.text(.cancel, settings.language)) { chatStore.rejectNarrativeEvent(id: proposal.id) }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
