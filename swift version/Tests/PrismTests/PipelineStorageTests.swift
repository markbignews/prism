import Foundation
import Testing
@testable import Prism

@Suite @MainActor struct PipelineStorageTests {
    @Test func malformedAndExtremeChapterRangesCannotCrashOrInventMessageIDs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let agent = ChatAgent(storagePath: root.path)
        let messages = [ChatMessage(role: .user, content: "source")]
        #expect(agent.parseChapterArrayJSON("[]", messages: []).isEmpty)
        #expect(agent.parseChapterArrayJSON(#"[{"title":"t","summary":"s","startIndex":999}]"#, messages: messages).isEmpty)
        #expect(agent.parseChapterArrayJSON("[{truncated", messages: messages).isEmpty)
        let object: [[String: Any]] = [["title": "t", "summary": String(repeating: "s", count: 1000),
            "startIndex": Int.min, "endIndex": Int.max, "unknown": true]]
        let parsed = agent.parseChapterArrayJSON(String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self), messages: messages)
        #expect(parsed.count == 1 && parsed[0].messageIDs == messages.map(\.id) && parsed[0].summary.count == 320)
    }

    @Test func peopleAndProfileParsersBoundUntrustedFieldsAndMergeWithoutDuplicates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let agent = ChatAgent(storagePath: root.path)
        agent.createConversation()
        let id = try #require(agent.selectedConversationID)
        #expect(agent.parsePeoplePipelineJSON(#"{"persons":[]}"#).persons.isEmpty)
        #expect(agent.parsePeoplePipelineJSON("invalid").analysisUnavailable)
        #expect(agent.parseProfilePipelineJSON(#"{"observations":[]}"#).findings.isEmpty)
        #expect(agent.parseProfilePipelineJSON("invalid").analysisUnavailable)
        let raw = #"{"persons":[{"name":" Alice ","role":"friend","unknown":true,"match_confidence":8,"traits":[{"pattern":"diagnosis","evidence":"invented"},{"pattern":"boundary_violation","evidence":"observed","confidence":8}]}]}"#
        let result = agent.parsePeoplePipelineJSON(raw)
        #expect(result.persons.count == 1 && result.persons[0].traits.count == 1)
        #expect(result.persons[0].matchConfidence == 1 && result.persons[0].traits[0].confidence == 1)
        agent.applyPeopleResults(result, for: id, requestSentAt: Date())
        agent.applyPeopleResults(result, for: id, requestSentAt: Date())
        #expect(agent.personArchive.count == 1 && agent.personArchive[0].mentionCount == 2)
        let profile = agent.parseProfilePipelineJSON(#"{"observations":[{"category":"stated_preference","statement":"direct answers","evidence":"user said so","confidence":2}]}"#)
        let chapter = StoryChapter(title: "c", summary: "s", keywords: [], messageIDs: [])
        var conversation = try #require(agent.selectedConversation)
        conversation.chapters = [chapter]
        agent.selectedConversation = conversation
        agent.applyProfileResults(profile, from: chapter, conversationID: id)
        agent.applyProfileResults(profile, from: chapter, conversationID: id)
        #expect(agent.userProfileObservations.count == 1 && agent.userProfileObservations[0].confidence == 1)
        agent.applyProfileResults(profile, from: chapter, conversationID: UUID())
        #expect(agent.userProfileObservations[0].sourceConversationID == id)
        #expect(agent.flushStorage())
    }

    @Test func storyMemoryAndContextThresholdsKeepOriginalMessages() throws {
        var conversation = Conversation(title: "c")
        let message = ChatMessage(role: .user, content: String(repeating: "reliable source ", count: 100))
        conversation.messages = [message]
        StoryMemory.ingest(userText: message.content, messageID: message.id, conversation: &conversation)
        #expect(conversation.chapters.count == 1 && conversation.chapters[0].summary.count <= 900)
        #expect(conversation.messages == [message])
        #expect(StoryMemory.relevantContext(for: "chapter 1", in: conversation, language: .english) != nil)
        #expect(ContextUsageSnapshot.preparationThresholdTokens < ContextUsageSnapshot.compressionThresholdTokens)
        #expect(ContextUsageSnapshot.compressionThresholdTokens < ContextUsageSnapshot.criticalThresholdTokens)
    }

    @Test func contextUsesTokenThresholdInsteadOfMessageCountAndPreservesRecentOriginals() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let agent = ChatAgent(storagePath: root.path)
        var conversation = Conversation(title: "window")
        conversation.messages = (0..<100).map { ChatMessage(role: $0.isMultiple(of: 2) ? .user : .assistant, content: "short message \($0)") }
        #expect(agent.buildWindowedMessages(for: 0, includeReasoning: false, context: conversation).map(\.id) == conversation.messages.map(\.id))
        let large = ChatMessage(role: .user, content: String(repeating: "证", count: 1_300_000))
        let recent = [ChatMessage(role: .assistant, content: "recent answer"), ChatMessage(role: .user, content: "current question")]
        conversation.messages = [large] + recent
        let window = agent.buildWindowedMessages(for: 0, includeReasoning: false, context: conversation)
        #expect(window.first?.role == .system)
        #expect(Array(window.suffix(2)) == recent)
        #expect(conversation.messages == [large] + recent)
    }

    @Test func engineeringStringsExistInEveryLanguageAndToolStateIsNotPersisted() throws {
        let keys: [L10n.Key] = [.retryStorage, .exportSnapshot, .importSnapshot, .chapterDetails, .summaryFailed,
            .originalMessages, .messageNotFound, .attachmentReadFailed, .attachmentCountLimit,
            .attachmentTypeUnsupported, .attachmentSizeLimit, .attachmentTotalLimit, .analyzeAttachment]
        for language in AppLanguage.allCases {
            for key in keys { #expect(L10n.text(key, language) != key.rawValue) }
        }
        var message = ChatMessage(role: .assistant, content: "")
        message.isToolPlaceholder = true
        let restored = try SQLiteStore.decoder().decode(ChatMessage.self, from: SQLiteStore.encoder().encode(message))
        #expect(!restored.isToolPlaceholder)
    }
}
