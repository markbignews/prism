import SwiftUI

/// Only the active reply observes this object. Sidebar, composer, archives and
/// history snapshots are published at turn boundaries, not for each SSE token.
@MainActor
final class StreamingMessageState: ObservableObject {
    @Published private(set) var message: ChatMessage?
    private(set) var conversationID: UUID?

    func receive(_ message: ChatMessage, in conversationID: UUID) {
        self.conversationID = conversationID
        self.message = message
    }

    func clear() {
        guard message != nil else { return }
        conversationID = nil
        message = nil
    }
}

struct StreamingMessageBubble: View {
    @ObservedObject var stream: StreamingMessageState
    var fallback: ChatMessage
    var isSelected: Bool
    var conversationID: UUID
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onRegenerate: (UUID) -> Void

    var body: some View {
        let message = stream.conversationID == conversationID && stream.message?.id == fallback.id
            ? stream.message! : fallback
        MessageBubble(message: message, isSelected: isSelected, conversationID: conversationID,
            isStreaming: true, onEdit: onEdit, onDelete: onDelete, onRegenerate: onRegenerate)
            .equatable()
    }
}

struct PendingStreamFrame {
    var conversationID: UUID
    var messageID: UUID
    var content = ""
    var reasoning = ""
}
