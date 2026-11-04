import Foundation
import Testing
@testable import Prism

@Suite @MainActor struct MemoryRebuildTests {
    private func fixture() throws -> (URL, ChatAgent, AppSettings, Conversation) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let agent = ChatAgent(storagePath: root.path)
        let settings = AppSettings(storagePath: root.path, credentialStore: TestCredentials())
        agent.createConversation()
        var conversation = try #require(agent.selectedConversation)
        conversation.messages = [
            ChatMessage(role: .user, content: "高二认识她，高三开始疏远。", createdAt: Date(timeIntervalSince1970: 100)),
            ChatMessage(role: .assistant, content: "助手猜测，不能当成事实。", createdAt: Date(timeIntervalSince1970: 101)),
            ChatMessage(role: .user, content: "我希望回答简短。我已经主动约她了。", createdAt: Date(timeIntervalSince1970: 102))
        ]
        agent.selectedConversation = conversation
        agent.memoryStore = [.init(content: "old", keywords: [], sourceConversationID: conversation.id, sourceChapterTitle: "old")]
        agent.blindspots = [.init(conversationID: conversation.id, pattern: "回避自我", evidence: "old", counterQuestion: "old",
                                 createdAt: Date(timeIntervalSince1970: 100))]
        agent.userProfileObservations = [.init(category: "stated_goal", statement: "old", evidence: "old",
            confidence: 0.5, sourceConversationID: conversation.id, sourceChapterID: nil)]
        agent.saveArchives()
        #expect(agent.flushStorage())
        return (root, agent, settings, conversation)
    }

    private var validJSON: String {
        #"{"insights":[{"content":"高二相识，高三疏远；之后用户已主动邀约。","keywords":["相识","疏远","邀约"],"source_indices":[1,2],"quote":"我已经主动约她了"}],"observations":[{"category":"communication_preference","statement":"偏好简短回答","evidence":"明确要求回答简短","confidence":0.95,"source_indices":[2],"quote":"我希望回答简短"}],"blindspots":[]}"#
    }

    @Test func rebuildReplacesAllThreeSectionsFromOriginalsAndPersistsProvenance() async throws {
        let (root, agent, settings, conversation) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        await agent.rebuildMemory(conversationID: conversation.id, settings: settings) { prompt, transcript in
            #expect(agent.isRebuildingMemory)
            #expect(prompt.contains("替换版"))
            #expect(!transcript.contains("助手猜测"))
            #expect(transcript.contains("[2][sentAt="))
            #expect(agent.memoryStore.first?.content == "old")
            return validJSON
        }
        #expect(agent.memoryRebuildSucceeded == true && !agent.isRebuildingMemory)
        #expect(agent.memoryStore.count == 1 && agent.memoryStore[0].content != "old")
        #expect(agent.blindspots.isEmpty)
        #expect(agent.userProfileObservations.map(\.statement) == ["偏好简短回答"])
        #expect(agent.memoryStore[0].sourceMessageIDs == [conversation.messages[0].id, conversation.messages[2].id])
        #expect(agent.userProfileObservations[0].sourceMessageIDs == [conversation.messages[2].id])
        #expect(agent.selectedConversation == conversation)
        let loaded = ChatAgent(storagePath: root.path)
        #expect(loaded.memoryStore.map(\.content) == agent.memoryStore.map(\.content))
        #expect(loaded.blindspots.isEmpty && loaded.userProfileObservations.count == 1)
        #expect(loaded.userProfileObservations[0].sourceChapterID == nil)
    }

    @Test func partialMalformedAndInventedSourcesCannotReplaceAnySection() async throws {
        let (root, agent, settings, conversation) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = agent.storageSnapshot()
        for raw in ["{truncated", #"{"insights":[]}"#,
                    validJSON.replacingOccurrences(of: "[1,2]", with: "[999]"),
                    validJSON.replacingOccurrences(of: "我希望回答简短\"}", with: "未说过的内容\"}")] {
            await agent.rebuildMemory(conversationID: conversation.id, settings: settings) { _, _ in raw }
            #expect(agent.memoryRebuildSucceeded == false)
            #expect(agent.memoryStore == before.memory && agent.blindspots == before.blindspots && agent.userProfileObservations == before.profile)
        }
        await agent.rebuildMemory(conversationID: conversation.id, settings: settings) { _, _ in throw URLError(.timedOut) }
        #expect(agent.memoryRebuildSucceeded == false && agent.memoryStore == before.memory)
    }

    @Test func concurrentChangesAndDeletedConversationsCannotBeOverwritten() async throws {
        let (root, agent, settings, conversation) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        await agent.rebuildMemory(conversationID: conversation.id, settings: settings) { _, _ in
            agent.removeBlindspot(id: agent.blindspots[0].id)
            return validJSON
        }
        #expect(agent.memoryRebuildSucceeded == false && agent.blindspots.isEmpty)
        #expect(agent.memoryStore.first?.content == "old")
        await agent.rebuildMemory(conversationID: conversation.id, settings: settings) { _, _ in
            agent.deleteConversation(id: conversation.id)
            return validJSON
        }
        #expect(agent.memoryRebuildSucceeded == false)
        #expect(agent.memoryStore.isEmpty && !agent.conversations.contains { $0.id == conversation.id })
    }

    @Test func replacementPreservesOtherConversationsTimelineAndOriginalMessages() throws {
        let (root, agent, _, conversation) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        agent.createConversation()
        let otherID = try #require(agent.selectedConversationID)
        let other = MemoryEntry(content: "other", keywords: [], sourceConversationID: otherID, sourceChapterTitle: "other")
        agent.memoryStore.append(other)
        let event = NarrativeEvent(conversationID: conversation.id, title: "相识", summary: "高二认识她", startLabel: "高二")
        agent.narrativeTimeline = [event]
        agent.saveArchives()
        #expect(agent.flushStorage())
        let rebuilt = try RebuiltMemory.parse(validJSON, conversation: conversation)
        #expect(agent.commitRebuiltMemory(rebuilt, conversationID: conversation.id))
        #expect(agent.memoryStore.contains(other))
        #expect(agent.narrativeTimeline == [event])
        #expect(agent.conversations.first { $0.id == conversation.id } == conversation)
        #expect(!agent.commitRebuiltMemory(rebuilt, conversationID: otherID))
    }

    @Test func databaseConflictCannotPublishOrPartiallyStoreReplacement() throws {
        let (root, agent, _, conversation) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = agent.storageSnapshot()
        let database = try SQLiteStore(root: root)
        _ = try database.read("memory.json", legacy: root)
        var external = before.memory
        external[0].content = "written by another window"
        try database.write("memory.json", data: SQLiteStore.encoder().encode(external))
        let rebuilt = try RebuiltMemory.parse(validJSON, conversation: conversation)
        #expect(!agent.commitRebuiltMemory(rebuilt, conversationID: conversation.id))
        #expect(agent.memoryStore == before.memory && agent.blindspots == before.blindspots && agent.userProfileObservations == before.profile)
        let loaded = ChatAgent(storagePath: root.path)
        #expect(loaded.memoryStore.first?.content == "written by another window")
        #expect(loaded.blindspots == before.blindspots)
        #expect(loaded.userProfileObservations.map(\.statement) == before.profile.map(\.statement))
    }

    @Test func explicitEmptyCompleteResultCanRemoveUnsupportedOldHypotheses() throws {
        let (root, agent, _, conversation) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let rebuilt = try RebuiltMemory.parse(#"{"insights":[],"observations":[],"blindspots":[]}"#, conversation: conversation)
        #expect(agent.commitRebuiltMemory(rebuilt, conversationID: conversation.id))
        #expect(agent.memoryStore.isEmpty && agent.blindspots.isEmpty && agent.userProfileObservations.isEmpty)
        for language in AppLanguage.allCases {
            for key: L10n.Key in [.rebuildMemory, .completeMemory, .memoryRebuildHint, .memoryRebuilding,
                .memoryRebuildComplete, .memoryRebuildFailed, .memoryRebuildChanged, .memoryRebuildNoSource, .timelineNaturalLanguageHint] {
                #expect(L10n.text(key, language) != key.rawValue)
            }
        }
    }

    @Test func naturalLanguageEventDescriptionSupportsMultipleReviewedNodes() async throws {
        let (root, agent, _, conversation) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        agent.activeToolConversationID = conversation.id
        agent.activeToolSourceMessageID = conversation.messages.last?.id
        let first = await ToolRegistry.execute(name: "manage_narrative_timeline", arguments:
            #"{"action":"upsert","title":"相识","summary":"高二时认识了她。","startLabel":"高二期间","sortIndex":10}"#, store: agent)
        let second = await ToolRegistry.execute(name: "manage_narrative_timeline", arguments:
            #"{"action":"upsert","title":"联系变化","summary":"高三开始疏远。","startLabel":"高三期间","sortIndex":20,"confirmed":true}"#, store: agent)
        #expect(first.contains("pending_confirmation") && second.contains("pending_confirmation"))
        #expect(agent.narrativeTimeline.isEmpty && agent.pendingNarrativeEvents.count == 2)
        let firstID = try #require(agent.pendingNarrativeEvents.first?.id)
        agent.confirmNarrativeEvent(id: firstID)
        #expect(agent.narrativeTimeline.count == 1 && agent.pendingNarrativeEvents.count == 1)
        let secondID = try #require(agent.pendingNarrativeEvents.first?.id)
        agent.confirmNarrativeEvent(id: secondID)
        #expect(agent.narrativeEvents(for: conversation.id).map(\.startLabel) == ["高二期间", "高三期间"])
        #expect(agent.narrativeTimeline.allSatisfy { $0.sourceMessageIDs == [conversation.messages.last!.id] })
    }
}
