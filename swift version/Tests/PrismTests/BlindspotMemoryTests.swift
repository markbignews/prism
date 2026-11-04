import Foundation
import Testing
@testable import Prism

@Suite @MainActor struct BlindspotMemoryTests {
    private func record(_ id: UUID, evidence: String = "用户说先不主动找她，但还未说明执行情况。",
                        date: Date = Date(timeIntervalSince1970: 100)) -> BlindspotRecord {
        BlindspotRecord(conversationID: id, pattern: "意图-行动差距", evidence: evidence,
                        counterQuestion: "后来执行了吗？", createdAt: date)
    }

    @Test func repeatedEvidenceAndChangedQuestionsDoNotCreateOccurrences() {
        let first = record(UUID())
        var records = [first]
        var repeated = first
        repeated.id = UUID()
        repeated.pattern = " 意图—行动差距 "
        repeated.evidence = " 用户说先不主动找她，\n但还未说明执行情况。 "
        repeated.counterQuestion = "明天准备怎么回复？"
        repeated.createdAt = Date(timeIntervalSince1970: 200)
        for _ in 0..<10 { BlindspotMemory.insert(repeated, into: &records) }
        #expect(records == [first])
        #expect(records[0].severity == "new")
    }

    @Test func sameMessageRetryCannotCreateParaphrasedDuplicate() {
        var first = record(UUID())
        first.sourceMessageID = UUID()
        var records = [first]
        var retry = first
        retry.id = UUID()
        retry.evidence = "用户表示想减少联系，尚未说明结果。"
        BlindspotMemory.insert(retry, into: &records)
        #expect(records == [first])
    }

    @Test func newEventsNegationsAndOtherConversationsRemainSeparate() {
        let id = UUID(), other = UUID()
        var records: [BlindspotRecord] = []
        let first = record(id, evidence: "昨天我没有主动联系她。")
        let negation = record(id, evidence: "昨天我主动联系她。")
        let nextEvent = record(id, evidence: "今天约她见面，但还没发出邀请。")
        for item in [first, negation, nextEvent, record(other, evidence: first.evidence)] {
            BlindspotMemory.insert(item, into: &records)
        }
        #expect(records.count == 4)
        #expect(records[1].severity == "recurring")
        #expect(records[3].severity == "new")
        let groups = BlindspotMemory.groups(records)
        #expect(groups.count == 2)
        #expect(groups.first { $0.latest.conversationID == id }?.observations.count == 3)
    }

    @Test func legacyRowsGroupWithoutChangingArchiveAndKeepFullDistinctEvidence() throws {
        let id = UUID()
        let first = record(id)
        var repeated = record(id, date: Date(timeIntervalSince1970: 200))
        repeated.pattern = "意圖－行動差距"
        repeated.counterQuestion = "换一个反问？"
        let distinct = record(id, evidence: String(repeating: "另一个事件的完整依据", count: 30),
                              date: Date(timeIntervalSince1970: 300))
        let archive = [first, repeated, distinct]
        let groups = BlindspotMemory.groups(archive)
        let group = try #require(groups.first)
        #expect(groups.count == 1 && group.latest.id == distinct.id)
        #expect(group.observations.map(\.id) == [distinct.id, repeated.id])
        #expect(group.observations[0].evidence == distinct.evidence)
        #expect(Set(group.recordIDs) == Set(archive.map(\.id)))
        #expect(archive.count == 3 && archive[0] == first)
        let context = BlindspotMemory.historyContext(archive)
        #expect(context.components(separatedBy: "\n").count == 1)
        #expect(!context.contains("换一个反问"))
        #expect(context.count < 400)
    }

    @Test func parserAllowsNoFindingAndBoundsOverproduction() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let agent = ChatAgent(storagePath: root.path)
        let id = UUID()
        let finding: [String: Any] = ["pattern": "意图-行动差距", "evidence": String(repeating: "证", count: 500),
                                      "counter_question": String(repeating: "问", count: 200)]
        func json(_ flag: String, _ findings: [[String: Any]]) throws -> String {
            let object: [String: Any] = ["guard": ["safety": ["flag": "ok", "immediate_danger": false],
                "blindspots": ["flag": flag, "findings": findings]], "emotions": []]
            return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        }
        var result = ChatAgent.PrePipelineResult()
        #expect(agent.parsePrePipelineJSON(try json("warning", [finding, finding, finding]), into: &result, conversationID: id))
        #expect(result.blindspotFindings.count == 1)
        #expect(result.blindspotFindings.first?.evidence.count == 160)
        #expect(result.blindspotFindings.first?.counterQuestion.count == 80)
        #expect(agent.parsePrePipelineJSON(try json("ok", [finding]), into: &result, conversationID: id))
        #expect(result.blindspotFindings.isEmpty)
        #expect(agent.parsePrePipelineJSON(try json("warning", [["pattern": " ", "evidence": " ", "counter_question": ""]]), into: &result, conversationID: id))
        #expect(result.blindspotFindings.isEmpty)
    }

    @Test func pipelineAndExternalWritesDeduplicateAndPersistSourceAcrossReload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let agent = ChatAgent(storagePath: root.path)
        agent.createConversation()
        var conversation = try #require(agent.selectedConversation)
        // Archive dates use ISO-8601 seconds, so use a whole-second fixture for
        // exact round-trip comparison rather than comparing lost fractions.
        let message = ChatMessage(role: .user, content: "我想先不主动找她。",
                                  createdAt: Date(timeIntervalSince1970: 100))
        conversation.messages = [message]
        agent.selectedConversation = conversation
        var result = ChatAgent.PrePipelineResult()
        result.blindspotFindings = [("意图-行动差距", "本轮提出暂不主动联系，结果尚待确认。", "后来呢？")]
        await agent.applyPrePipelineResults(result, for: conversation.id, requestSentAt: message.createdAt)
        result.blindspotFindings = [("意图—行动差距", "用户打算减少联系，尚未提供结果。", "执行了吗？")]
        await agent.applyPrePipelineResults(result, for: conversation.id, requestSentAt: message.createdAt)
        #expect(agent.blindspots.count == 1 && agent.blindspots[0].sourceMessageID == message.id)
        var external = try #require(agent.blindspots.first)
        external.id = UUID()
        agent.addBlindspot(external)
        #expect(agent.blindspots.count == 1)
        #expect(agent.flushStorage())
        let loaded = ChatAgent(storagePath: root.path)
        #expect(loaded.blindspots == agent.blindspots)
        #expect(loaded.selectedConversation?.messages == [message])
    }

    @Test func oldSchemaDecodesAndRemovingCardDoesNotResurrectOlderRows() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let agent = ChatAgent(storagePath: root.path)
        agent.createConversation()
        let id = try #require(agent.selectedConversationID)
        let first = record(id)
        var object = try #require(JSONSerialization.jsonObject(with: SQLiteStore.encoder().encode(first)) as? [String: Any])
        object.removeValue(forKey: "sourceMessageID")
        let old = try SQLiteStore.decoder().decode(BlindspotRecord.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.sourceMessageID == nil && old.id == first.id)
        let unrelated = record(UUID())
        agent.blindspots = [old, record(id, evidence: "另一条观察"), unrelated]
        agent.removeBlindspotGroup(id: old.id)
        #expect(agent.blindspots == [unrelated])
        #expect(agent.flushStorage())
        for language in AppLanguage.allCases {
            for key: L10n.Key in [.memoryObservationDetails, .removeBlindspotGroup] {
                #expect(L10n.text(key, language) != key.rawValue)
            }
        }
    }
}
