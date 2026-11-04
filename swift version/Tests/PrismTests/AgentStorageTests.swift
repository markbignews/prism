import Foundation
import CSQLite
import Testing
@testable import Prism

@Suite @MainActor struct AgentStorageTests {
    private func fixture() throws -> (URL, ChatAgent) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let agent = ChatAgent(storagePath: root.path)
        agent.createConversation()
        #expect(agent.flushStorage())
        return (root, agent)
    }
    private func memory(_ id: UUID) -> MemoryEntry {
        MemoryEntry(content: "evidence", keywords: [], sourceConversationID: id, sourceChapterTitle: "chapter")
    }

    @Test func temporaryFailureRetainsDirtyDataAndRecoversWithoutRestart() throws {
        let (root, agent) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let id = try #require(agent.selectedConversationID)
        var db: OpaquePointer?
        #expect(sqlite3_open(root.appendingPathComponent("prism.sqlite3").path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK)
        agent.renameConversation(id: id, newTitle: "unsaved edit")
        #expect(!agent.flushStorage())
        #expect(agent.hasStorageFailure && agent.canRetryStorage && agent.hasUnsavedChanges)
        #expect(agent.selectedConversation?.title == "unsaved edit")
        #expect(sqlite3_exec(db, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
        agent.retryStorage()
        #expect(!agent.hasStorageFailure && !agent.hasUnsavedChanges)
        #expect(ChatAgent(storagePath: root.path).selectedConversation?.title == "unsaved edit")
    }

    @Test func failedDeleteRollsBackArchivesAndConflictCanBeExported() throws {
        let (root, agent) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let id = try #require(agent.selectedConversationID)
        agent.memoryStore = [memory(id)]
        agent.blindspots = [.init(conversationID: id, pattern: "p", evidence: "e", counterQuestion: "q")]
        agent.saveArchives(); #expect(agent.flushStorage())
        let other = try SQLiteStore(root: root)
        let original = try other.read("conversations.json", legacy: root)
        var conversations = try SQLiteStore.decoder().decode([Conversation].self, from: original)
        conversations[0].title = "other window"
        try other.write("conversations.json", data: SQLiteStore.encoder().encode(conversations))
        agent.deleteConversation(id: id)
        #expect(agent.hasStorageFailure && !agent.canRetryStorage && agent.hasUnsavedChanges)
        let disk = ChatAgent(storagePath: root.path)
        #expect(disk.conversations.contains { $0.id == id && $0.title == "other window" })
        #expect(disk.memoryStore.count == 1 && disk.blindspots.count == 1)
        let export = root.appendingPathComponent("unsaved.json")
        try agent.exportWindowSnapshot(to: export)
        #expect(FileManager.default.fileExists(atPath: export.path))
        #expect(disk.flushStorage())
    }

    @Test func startupReconciliationKeepsPeopleAndDoesNotRunAfterDecodeFailure() throws {
        let (root, agent) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let id = try #require(agent.selectedConversationID), orphan = UUID()
        agent.memoryStore = [memory(id), memory(orphan)]
        agent.personArchive = [.init(name: "preserved person", role: "friend", firstMentionedAt: Date(),
            lastMentionedAt: Date(), conversationIDs: [orphan])]
        agent.saveArchives(); #expect(agent.flushStorage())
        let loaded = ChatAgent(storagePath: root.path)
        #expect(loaded.memoryStore.map(\.sourceConversationID) == [id])
        #expect(loaded.personArchive.count == 1 && loaded.personArchive[0].conversationIDs == [])
        let store = try SQLiteStore(root: root)
        _ = try store.read("memory.json", legacy: root)
        _ = try store.read("narrative_timeline.json", legacy: root)
        let event = NarrativeEvent(conversationID: orphan, title: "orphan", summary: "", startLabel: "past")
        try store.writeBatch(["memory.json": Data(#"[{"id":"malformed"}]"#.utf8),
            "narrative_timeline.json": SQLiteStore.encoder().encode([event])])
        let failed = ChatAgent(storagePath: root.path)
        #expect(failed.hasStorageFailure)
        #expect(!failed.flushStorage())
        let persisted = try store.read("narrative_timeline.json", legacy: root)
        #expect(try SQLiteStore.decoder().decode([NarrativeEvent].self, from: persisted).count == 1)
    }

    @Test func snapshotRoundTripIsAtomicAndRejectsIncompleteImports() throws {
        let (root, agent) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let id = try #require(agent.selectedConversationID)
        agent.renameConversation(id: id, newTitle: "exported")
        agent.memoryStore = [memory(id)]; agent.saveArchives()
        let snapshot = root.appendingPathComponent("snapshot.json")
        try agent.exportWindowSnapshot(to: snapshot)
        agent.renameConversation(id: id, newTitle: "later")
        #expect(agent.flushStorage())
        let oldGeneration = agent.storageGeneration
        try agent.importWindowSnapshot(from: snapshot)
        #expect(agent.storageGeneration != oldGeneration)
        let stalePeople = agent.parsePeoplePipelineJSON(#"{"persons":[{"name":"old worker","role":"friend"}]}"#)
        agent.applyPeopleResults(stalePeople, for: id, requestSentAt: Date(), generation: oldGeneration)
        #expect(agent.personArchive.isEmpty)
        #expect(agent.selectedConversation?.title == "exported" && agent.memoryStore.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix("pre-import-") })
        try Data(#"{"prismSnapshotVersion":1}"#.utf8).write(to: snapshot)
        #expect(throws: (any Error).self) { try agent.importWindowSnapshot(from: snapshot) }
        #expect(ChatAgent(storagePath: root.path).selectedConversation?.title == "exported")
    }

    @Test func longConversationEditsCoalesceAndFlushPersistsTheLatestSnapshot() async throws {
        let (root, agent) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var conversation = try #require(agent.selectedConversation)
        conversation.messages = (0..<500).map { index in
            ChatMessage(role: index.isMultiple(of: 2) ? .user : .assistant, content: String(repeating: "long narrative ", count: 50))
        }
        agent.selectedConversation = conversation
        for index in 0..<100 { agent.renameConversation(id: conversation.id, newTitle: "edit \(index)") }
        #expect(agent.hasUnsavedChanges)
        // Observe actual background durability rather than assuming a scheduler deadline.
        for _ in 0..<100 {
            if !agent.hasUnsavedChanges { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!agent.hasUnsavedChanges)
        let loaded = ChatAgent(storagePath: root.path)
        #expect(loaded.selectedConversation?.title == "edit 99")
        #expect(loaded.selectedConversation?.messages.count == 500)
        var db: OpaquePointer?; sqlite3_open(root.appendingPathComponent("prism.sqlite3").path, &db)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT revision FROM collections WHERE name='conversations.json'", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        // Empty import = 1, initial conversation = 2, 101 coalesced edits = 3.
        #expect(sqlite3_column_int(statement, 0) == 3)
    }
}
