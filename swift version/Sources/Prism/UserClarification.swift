import Foundation

struct ClarificationOption: Codable, Equatable, Sendable {
    var label: String
    var description: String
}

struct UserClarification: Identifiable, Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable { case pending, answered, superseded }
    var id = UUID()
    var conversationID: UUID
    var sourceMessageID: UUID
    var assistantMessageID: UUID
    var question: String
    var options: [ClarificationOption]
    var status: Status = .pending
    var answer: String?

    init?(arguments: String, conversationID: UUID, sourceMessageID: UUID, assistantMessageID: UUID) {
        struct Payload: Decodable { var question: String; var options: [ClarificationOption] }
        guard let data = arguments.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        let question = payload.question.trimmingCharacters(in: .whitespacesAndNewlines)
        let options = payload.options.map {
            ClarificationOption(label: $0.label.trimmingCharacters(in: .whitespacesAndNewlines),
                description: $0.description.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard !question.isEmpty, question.count <= 600, (2...4).contains(options.count),
              options.allSatisfy({ !$0.label.isEmpty && $0.label.count <= 120 && $0.description.count <= 300 }),
              Set(options.map { $0.label.lowercased() }).count == options.count else { return nil }
        self.conversationID = conversationID
        self.sourceMessageID = sourceMessageID
        self.assistantMessageID = assistantMessageID
        self.question = question
        self.options = options
    }

    func isCurrent(conversationID: UUID?, latestUserMessageID: UUID?) -> Bool {
        status == .pending && self.conversationID == conversationID && sourceMessageID == latestUserMessageID
    }

    func response(selectedOption: Int?, customText: String, language: AppLanguage) -> String? {
        let custom = customText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard custom.count <= 8_000 else { return nil }
        var parts: [String] = []
        if let selectedOption {
            guard options.indices.contains(selectedOption) else { return nil }
            parts.append(options[selectedOption].label)
        }
        if !custom.isEmpty { parts.append(custom) }
        guard !parts.isEmpty else { return nil }
        let heading = ProviderFailure.localized("针对上一条追问，我的回答是：", "針對上一則追問，我的回答是：", "My answer to your clarification question:", language: language)
        return heading + "\n" + parts.joined(separator: "\n\n")
    }
}

struct ClarificationSubmission: Equatable, Sendable {
    var requestID: UUID
    var selectedOption: Int?
    var customText: String
}

struct ClarificationDraft: Equatable {
    var selectedOption: Int?
    var customText = ""
}

extension ChatAgent {
    var pendingClarification: UserClarification? {
        guard let conversation = selectedConversation else { return nil }
        let sourceID = conversation.messages.last(where: { $0.role == .user })?.id
        return conversation.messages.reversed().first { message in
            guard let request = message.clarification else { return false }
            return request.assistantMessageID == message.id
                && request.isCurrent(conversationID: conversation.id, latestUserMessageID: sourceID)
        }?.clarification
    }

    /// A valid request ends this generation before any accompanying tools run.
    /// No suspended network task or unresolved API tool message is kept alive.
    func pauseForClarification(toolCalls: [ToolCall], assistantID: UUID, conversationID: UUID) -> String? {
        guard let call = toolCalls.first(where: { $0.name == "request_user_input" }),
              let ci = conversations.firstIndex(where: { $0.id == conversationID }),
              let mi = conversations[ci].messages.firstIndex(where: { $0.id == assistantID && $0.role == .assistant }),
              let sourceID = activeToolSourceMessageID ?? conversations[ci].messages.prefix(mi).last(where: { $0.role == .user })?.id,
              conversations[ci].messages.prefix(mi).contains(where: { $0.id == sourceID && $0.role == .user }),
              let request = UserClarification(arguments: call.arguments, conversationID: conversationID,
                  sourceMessageID: sourceID, assistantMessageID: assistantID) else { return nil }
        var conversation = conversations[ci]
        conversation.messages[mi].clarification = request
        conversation.messages[mi].toolCalls = nil
        conversation.messages[mi].content = request.question
        // The setter saves this state and its original question together.
        if selectedConversationID == conversationID { selectedConversation = conversation }
        else { updateClarificationConversation(conversation) }
        return request.question
    }
}
