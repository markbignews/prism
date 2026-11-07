import Foundation
import Testing
@testable import Prism

@Suite @MainActor struct CrossConversationMemoryTests {
    private func fixture() throws -> (URL, ChatAgent, MemoryEntry, MemoryEntry) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let agent = ChatAgent(storagePath: root.path)
        agent.createConversation()
        var first = try #require(agent.selectedConversation)
        first.title = "高中同学"
        first.messages = [.init(role: .user, content: "小林是我的高中同学，上周我们见面了。"),
                          .init(role: .assistant, content: "助手的推断不是原始依据。")]
        agent.selectedConversation = first
        let old = MemoryEntry(sourceMessageIDs: [first.messages[0].id], evidenceStatus: "model_inferred",
                              content: "小林：高中同学，上周见面。", keywords: ["小林"],
                              sourceConversationID: first.id, sourceChapterTitle: "完整记忆")
        agent.createConversation()
        var second = try #require(agent.selectedConversation)
        second.title = "同事"
        second.messages = [.init(role: .user, content: "另一位小林是同事，今天一起加班。")]
        agent.selectedConversation = second
        let other = MemoryEntry(sourceMessageIDs: [second.messages[0].id], evidenceStatus: "model_inferred",
                                content: "小林：同事，今天加班。", keywords: ["小林"],
                                sourceConversationID: second.id, sourceChapterTitle: "完整记忆")
        agent.memoryStore = [old, other]
        agent.createConversation() // No completed turn, but the archive is not empty.
        return (root, agent, old, other)
    }

    @Test func firstTurnCanRetrieveBothCandidatesWithSeparateSourcesAndThenFetchOriginals() async throws {
        let (root, agent, old, other) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let current = agent.selectedConversationID
        let tools = ToolRegistry.availableDefinitions(baseURL: "https://api.deepseek.com", includeHistory: false)
        #expect(tools.contains { $0.function.name == "search_memory" })
        #expect(tools.contains { $0.function.name == "fetch_chapter_messages" })
        for settings in [nil, AppSettings(storagePath: root.path, credentialStore: TestCredentials())] {
            let raw = await ToolRegistry.execute(name: "search_memory", arguments: #"{"query":"小林"}"#,
                                                 store: agent, settings: settings)
            let hits = try #require(try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]])
            #expect(hits.count == 2)
            #expect(Set(hits.compactMap { $0["sourceConversationId"] as? String }) ==
                    [old.sourceConversationID.uuidString, other.sourceConversationID.uuidString])
            #expect(Set(hits.compactMap { $0["sourceConversationTitle"] as? String }) == ["高中同学", "同事"])
            #expect(hits.allSatisfy { $0["identityConfirmed"] as? Bool == false })
            #expect(hits.allSatisfy { ($0["sourceMessageIds"] as? [String])?.count == 1 })
        }
        let fetched = await ToolRegistry.execute(name: "fetch_chapter_messages",
            arguments: "{\"memory_id\":\"\(old.id.uuidString)\"}", store: agent)
        let evidence = try #require(try JSONSerialization.jsonObject(with: Data(fetched.utf8)) as? [String: Any])
        #expect(evidence["sourceConversationTitle"] as? String == "高中同学")
        #expect(evidence["sourcesMissing"] as? Bool == false)
        #expect(fetched.contains("高中同学，上周我们见面了"))
        #expect(!fetched.contains("加班") && !fetched.contains("助手的推断"))
        #expect(agent.selectedConversationID == current)
        #expect(agent.personArchive.isEmpty && agent.personLinkProposals.isEmpty)
    }

    @Test func missingSourcesCannotFallBackToAnUnrelatedChatAndTruncationIsExplicit() async throws {
        let (root, agent, old, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        agent.memoryStore[0].sourceMessageIDs = [UUID()]
        let missing = await ToolRegistry.execute(name: "fetch_chapter_messages",
            arguments: "{\"memory_id\":\"\(old.id.uuidString)\"}", store: agent)
        let parsed = try #require(try JSONSerialization.jsonObject(with: Data(missing.utf8)) as? [String: Any])
        #expect(parsed["sourcesMissing"] as? Bool == true)
        #expect((parsed["messages"] as? [Any])?.isEmpty == true)
        let active = agent.selectedConversationID
        agent.selectedConversationID = old.sourceConversationID
        var conversation = try #require(agent.selectedConversation)
        conversation.messages[0].content = String(repeating: "原文", count: 4000)
        agent.selectedConversation = conversation
        agent.selectedConversationID = active
        agent.memoryStore[0].sourceMessageIDs = old.sourceMessageIDs
        let bounded = await ToolRegistry.execute(name: "fetch_chapter_messages",
            arguments: "{\"memory_id\":\"\(old.id.uuidString)\"}", store: agent)
        let result = try #require(try JSONSerialization.jsonObject(with: Data(bounded.utf8)) as? [String: Any])
        #expect(result["truncated"] as? Bool == true)
        #expect(bounded.count < 7000)
        let empty = await ToolRegistry.execute(name: "search_memory", arguments: #"{"query":"不存在","count":-1}"#, store: agent)
        #expect(empty == "[]")
    }

    @Test func concisePanelPreviewDoesNotDestroyRetrievableEvidenceAndDeletionIsScoped() throws {
        let (root, agent, old, other) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var long = old
        long.content = String(repeating: "具体事件及其变化。", count: 100)
        let before = [long, long]
        for language in AppLanguage.allCases {
            let paragraph = MemoryInsight.paragraph(before, language: language)
            #expect(!paragraph.contains("\n"))
            #expect(paragraph.count <= (language == .english ? 600 : 220))
            #expect(!paragraph.isEmpty)
        }
        #expect(before[0].content.count > 220) // The display did not mutate the archive.
        #expect(agent.searchMemory(query: "小林").count == 2)
        agent.removeMemoryEntries(conversationID: old.sourceConversationID)
        #expect(agent.memoryStore.count == 1 && agent.memoryStore.first?.id == other.id)
        #expect(agent.conversations.contains { $0.id == old.sourceConversationID })
    }

    @Test func sameNameCannotBypassPendingCrossConversationIdentityConfirmation() throws {
        let (root, agent, old, other) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let person = PersonRecord(name: "小林", role: "朋友", firstMentionedAt: Date(), lastMentionedAt: Date(),
                                  conversationIDs: [old.sourceConversationID])
        agent.personArchive = [person]
        var finding = PersonFinding(name: "小林", mention: "小林", role: "朋友", traits: [],
                                    matchedPersonID: nil, candidatePersonID: person.id,
                                    matchConfidence: 0.65, matchEvidence: "同名但缺少独特依据", isSelf: false)
        agent.applyPeopleResults(.init(persons: [finding]), for: other.sourceConversationID, requestSentAt: Date())
        #expect(agent.personArchive.count == 2)
        #expect(agent.personArchive.first { $0.id == person.id }?.conversationIDs == [old.sourceConversationID])
        #expect(agent.personLinkProposals.count == 1 && agent.personLinkProposals[0].decision == "pending")
        // A later mention in that same chat reuses its own record, never the old candidate.
        finding.candidatePersonID = nil
        finding.matchConfidence = 0
        agent.applyPeopleResults(.init(persons: [finding]), for: other.sourceConversationID, requestSentAt: Date())
        #expect(agent.personArchive.count == 2)
        agent.confirmPersonLinkProposal(id: agent.personLinkProposals[0].id)
        #expect(agent.personArchive.count == 1)
        #expect(Set(agent.personArchive[0].conversationIDs ?? []) == [old.sourceConversationID, other.sourceConversationID])
    }

    @Test func legacyMemoryUsesOnlyItsOwnChapterOriginals() async throws {
        let (root, agent, old, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let active = agent.selectedConversationID
        agent.selectedConversationID = old.sourceConversationID
        var conversation = try #require(agent.selectedConversation)
        let chapter = StoryChapter(title: old.sourceChapterTitle, summary: old.content,
                                   keywords: old.keywords, messageIDs: conversation.messages.map(\.id))
        conversation.chapters = [chapter]
        agent.selectedConversation = conversation
        agent.selectedConversationID = active
        agent.memoryStore[0].sourceMessageIDs = nil
        let byMemory = await ToolRegistry.execute(name: "fetch_chapter_messages",
            arguments: "{\"memory_id\":\"\(old.id.uuidString)\"}", store: agent)
        let index = try #require(agent.allChapters.firstIndex { $0.id == chapter.id }) + 1
        let byChapter = await ToolRegistry.execute(name: "fetch_chapter_messages",
            arguments: "{\"index\":\(index)}", store: agent)
        for raw in [byMemory, byChapter] {
            let parsed = try #require(try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
            #expect(parsed["sourceConversationTitle"] as? String == "高中同学")
            #expect(raw.contains("高中同学，上周我们见面了"))
            #expect(!raw.contains("助手的推断") && !raw.contains("加班"))
            #expect(parsed["sourcesMissing"] as? Bool == false)
        }
    }

    @Test func rebuiltInsightsMustBeOneSourcedParagraph() throws {
        let user = ChatMessage(role: .user, content: "我们高中认识。现在仍偶尔见面。")
        let conversation = Conversation(title: "来源", messages: [user])
        let item = #"{"content":"高中相识。\n现在偶尔见面，关系尚未明确。","keywords":["相识"],"source_indices":[1],"quote":"高中认识"}"#
        let parsed = try RebuiltMemory.parse("{\"insights\":[\(item)],\"observations\":[],\"blindspots\":[]}", conversation: conversation)
        #expect(parsed.insights.count == 1)
        #expect(!parsed.insights[0].content.contains("\n"))
        #expect(parsed.insights[0].sourceMessageIDs == [user.id])
        #expect(throws: (any Error).self) {
            try RebuiltMemory.parse("{\"insights\":[\(item),\(item)],\"observations\":[],\"blindspots\":[]}", conversation: conversation)
        }
        #expect(AgentPrompt.crossConversationMemoryRules.contains("相同姓名"))
        #expect(AgentPrompt.crossConversationMemoryRules.contains("request_user_input"))
    }
}
