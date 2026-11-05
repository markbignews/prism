import Foundation
import Testing
@testable import Prism

@Suite @MainActor struct TimelineWordingTests {
    private func fixture(count: Int = 2) throws -> (URL, ChatAgent, AppSettings, UUID) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let agent = ChatAgent(storagePath: root.path)
        let settings = AppSettings(storagePath: root.path, credentialStore: TestCredentials())
        agent.createConversation()
        let id = try #require(agent.selectedConversationID)
        agent.narrativeTimeline = (0..<count).map { index in
            NarrativeEvent(conversationID: id, title: "事件\(index)", summary: "用户描述了具体经过\(index)，没有说明原因。",
                startLabel: "阶段\(index)", sortIndex: index * 10,
                sourceMessageIDs: [UUID()], updatedAt: Date(timeIntervalSince1970: 100))
        }
        agent.saveArchives()
        #expect(agent.flushStorage())
        return (root, agent, settings, id)
    }

    private func response(_ events: [NarrativeEvent], suffix: String = "你描述了当时的经过，原因尚不明确。") throws -> String {
        let nodes = events.map { event in
            ["id": event.id.uuidString, "text": [event.startLabel, event.endLabel].filter { !$0.isEmpty }.joined(separator: "至") + "，" + suffix]
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: ["nodes": nodes]), as: UTF8.self)
    }

    @Test func oldNodesGainConsistentDisplayWordingWithoutChangingOriginals() async throws {
        let (root, agent, settings, id) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = agent.narrativeTimeline
        var calls = 0
        await agent.unifyTimelineWording(conversationID: id, settings: settings) { prompt, input in
            calls += 1
            #expect(prompt.contains("每个节点分别改写"))
            #expect(!input.contains("updatedAt") && !input.contains("sourceMessageIDs"))
            #expect(agent.narrativeTimeline.allSatisfy { $0.wording == nil })
            return try response(before)
        }
        #expect(calls == 1 && !agent.timelineWordingFailed && !agent.timelineWordingIsLoading)
        for (original, rewritten) in zip(before, agent.narrativeTimeline) {
            var source = rewritten
            source.wording = nil
            #expect(source == original)
            #expect(TimelineWording.currentText(for: rewritten, language: .simplifiedChinese)?.contains(original.startLabel) == true)
        }
        #expect(agent.flushStorage())
        let loaded = ChatAgent(storagePath: root.path)
        #expect(loaded.narrativeTimeline == agent.narrativeTimeline)
        await agent.unifyTimelineWording(conversationID: id, settings: settings) { _, _ in
            calls += 1
            throw URLError(.badServerResponse)
        }
        #expect(calls == 1)
        let listed = await ToolRegistry.execute(name: "manage_narrative_timeline", arguments: #"{"action":"list"}"#, store: agent)
        #expect(!listed.contains("wording") && !listed.contains("sourceFingerprint"))
        #expect(listed.contains(before[0].summary))
    }

    @Test func sourceChangesAndLanguageSwitchesInvalidateOnlyDisplayCache() throws {
        let (root, agent, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let event = agent.narrativeTimeline[0]
        let wordings = try TimelineWording.parse(response([event]), events: [event], language: .simplifiedChinese)
        var cached = event
        let wording: TimelineNodeWording = try #require(wordings[event.id])
        cached.wording = wording
        #expect(TimelineWording.fingerprint([cached]) == TimelineWording.fingerprint([event]))
        #expect(TimelineWording.currentText(for: cached, language: .simplifiedChinese) != nil)
        #expect(TimelineWording.currentText(for: cached, language: .english) == nil)
        cached.summary = "用户明确说不是这样。"
        #expect(TimelineWording.currentText(for: cached, language: .simplifiedChinese) == nil)
        cached = event
        cached.wording = wordings[event.id]
        cached.startLabel = "另一个时期"
        #expect(TimelineWording.currentText(for: cached, language: .simplifiedChinese) == nil)
    }

    @Test func invalidOutputCannotMergeDropInventOrRedateNodes() throws {
        let (root, agent, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let events = agent.narrativeTimeline
        let raw = try response(events)
        let bad = ["{truncated", #"{"nodes":[]}"#, try response([events[0]]),
            raw.replacingOccurrences(of: events[0].id.uuidString, with: UUID().uuidString),
            raw.replacingOccurrences(of: events[0].id.uuidString, with: events[1].id.uuidString),
            raw.replacingOccurrences(of: events[0].startLabel, with: "2026年11月5日")]
        for item in bad {
            #expect(throws: (any Error).self) {
                try TimelineWording.parse(item, events: events, language: .simplifiedChinese)
            }
        }
        #expect(throws: (any Error).self) {
            try TimelineWording.parse(raw, events: [events[0], events[0]], language: .simplifiedChinese)
        }
        let long = try response(events, suffix: String(repeating: "字", count: 250))
        #expect(throws: (any Error).self) { try TimelineWording.parse(long, events: events, language: .simplifiedChinese) }
        let multiline = try response(events, suffix: "第一句\n第二句")
        #expect(throws: (any Error).self) { try TimelineWording.parse(multiline, events: events, language: .simplifiedChinese) }
    }

    @Test func failedLaterBatchKeepsEveryExistingNodeUnchanged() async throws {
        let (root, agent, settings, id) = try fixture(count: 9)
        defer { try? FileManager.default.removeItem(at: root) }
        let before = agent.narrativeTimeline
        var calls = 0
        await agent.unifyTimelineWording(conversationID: id, settings: settings) { _, input in
            calls += 1
            let sources = try JSONDecoder().decode([TimelineWording.Source].self, from: Data(input.utf8))
            #expect(sources.count <= 8)
            if calls == 2 { throw URLError(.timedOut) }
            return try response(before.filter { event in sources.contains { $0.id == event.id } })
        }
        #expect(calls == 2 && agent.timelineWordingFailed)
        #expect(agent.narrativeTimeline == before)
    }

    @Test func editedSourceAndDeletedConversationRejectLateRewrites() async throws {
        let (root, agent, settings, id) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = agent.narrativeTimeline
        await agent.unifyTimelineWording(conversationID: id, settings: settings) { _, _ in
            _ = agent.upsertNarrativeEvent(eventID: before[0].id, title: before[0].title,
                summary: "用户已纠正旧说法。", startLabel: "新的时间", endLabel: "", timeKind: "period", sortIndex: 0)
            return try response(before)
        }
        #expect(agent.timelineWordingFailed && agent.narrativeTimeline.allSatisfy { $0.wording == nil })
        #expect(agent.narrativeTimeline[0].startLabel == "新的时间")
        let current = agent.narrativeTimeline
        await agent.unifyTimelineWording(conversationID: id, settings: settings) { _, _ in
            agent.deleteConversation(id: id)
            return try response(current)
        }
        #expect(agent.narrativeTimeline.isEmpty)
    }

    @Test func newerRequestWinsAndFailedRefreshKeepsValidWording() async throws {
        let (root, agent, settings, id) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = agent.narrativeTimeline
        await agent.unifyTimelineWording(conversationID: id, settings: settings) { _, _ in
            await agent.unifyTimelineWording(conversationID: id, settings: settings, force: true) { _, _ in
                try response(sources, suffix: "这是较新的措辞。")
            }
            return try response(sources, suffix: "这是过期的措辞。")
        }
        #expect(agent.narrativeTimeline.allSatisfy { $0.wording?.text.contains("较新") == true })
        let cached = agent.narrativeTimeline
        await agent.unifyTimelineWording(conversationID: id, settings: settings, force: true) { _, _ in throw URLError(.timedOut) }
        #expect(agent.timelineWordingFailed && agent.narrativeTimeline == cached)
    }

    @Test func legacyNodesDecodeAndWordingStringsAreLocalized() throws {
        let (root, agent, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = agent.narrativeTimeline[0]
        var object = try #require(JSONSerialization.jsonObject(with: SQLiteStore.encoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "wording")
        let loaded = try SQLiteStore.decoder().decode(NarrativeEvent.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(loaded == original && loaded.wording == nil)
        for language in AppLanguage.allCases {
            for key: L10n.Key in [.timelineUnifyWording, .timelineUnifyingWording, .timelineWordingFailed, .timelineOriginalNodes, .timelineSourceWording] {
                #expect(L10n.text(key, language) != key.rawValue)
            }
        }
    }
}
