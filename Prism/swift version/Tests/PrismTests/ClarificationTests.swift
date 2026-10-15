import Foundation
import Testing
@testable import Prism

private let questionArguments = #"{"question":"这件事发生在哪个阶段？","options":[{"label":"高中期间","description":"仍在读高中"},{"label":"工作以后","description":"开始工作之后"},{"label":"记不清","description":"暂时无法确定"}]}"#

@Suite struct ClarificationParsingTests {
    private func request() throws -> UserClarification {
        try #require(UserClarification(arguments: questionArguments, conversationID: UUID(), sourceMessageID: UUID(), assistantMessageID: UUID()))
    }
    @Test func optionsCustomInputAndCombinedAnswersAreAcceptedWithoutInferringAnAnswer() throws {
        let request = try request()
        #expect(request.status == .pending && request.answer == nil)
        #expect(request.response(selectedOption: 1, customText: "", language: .simplifiedChinese)?.contains("工作以后") == true)
        #expect(request.response(selectedOption: nil, customText: "  高中毕业后的暑假  ", language: .simplifiedChinese)?.hasSuffix("高中毕业后的暑假") == true)
        let combined = try #require(request.response(selectedOption: 0, customText: "具体是高二下学期", language: .simplifiedChinese))
        #expect(combined.contains("高中期间") && combined.contains("具体是高二下学期"))
        #expect(request.response(selectedOption: nil, customText: " \n", language: .english) == nil)
        #expect(request.response(selectedOption: -1, customText: "补充", language: .english) == nil)
        #expect(request.response(selectedOption: 99, customText: "补充", language: .english) == nil)
        #expect(request.response(selectedOption: nil, customText: String(repeating: "字", count: 8001), language: .english) == nil)
    }

    @Test(arguments: [
        #"{}"#, #"{"question":"?","options":["a","b"]}"#,
        #"{"question":" ","options":[{"label":"a","description":""},{"label":"b","description":""}]}"#,
        #"{"question":"?","options":[{"label":"A","description":""},{"label":" a ","description":""}]}"#,
        #"{"question":"?","options":[{"label":"a","description":""}]}"#,
        #"{"question":"?","options":[{"label":"","description":""},{"label":"b","description":""}]}"#
    ])
    func malformedRequestsCannotPauseTheAgent(arguments: String) {
        #expect(UserClarification(arguments: arguments, conversationID: UUID(), sourceMessageID: UUID(), assistantMessageID: UUID()) == nil)
    }

    @Test func toolSchemaExposesStructuredOptionsAndSharedRulesInEveryMode() throws {
        #expect(ToolRegistry.definitions.contains { $0.function.name == "request_user_input" })
        let data = try JSONEncoder().encode(ToolDef.requestUserInput)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let function = try #require(json["function"] as? [String: Any])
        let parameters = try #require(function["parameters"] as? [String: Any])
        let properties = try #require(parameters["properties"] as? [String: Any])
        let options = try #require(properties["options"] as? [String: Any])
        #expect(options["type"] as? String == "array")
        #expect(options["minItems"] as? Int == 2 && options["maxItems"] as? Int == 4)
        for mode in ConversationMode.allCases {
            for language in AppLanguage.allCases {
                #expect(AgentPrompt.system(language: language, mode: mode).contains(AgentPrompt.userClarificationRules))
            }
        }
    }
}

@Suite(.serialized) @MainActor struct ClarificationLifecycleTests {
    private func fixture() throws -> (URL, ChatAgent, AppSettings, UUID, UUID) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var conversation = Conversation(title: "追问回归")
        conversation.messages = [.init(role: .user, content: "请分析这件事。"), .init(role: .assistant, content: "准备澄清")]
        try JSONEncoder().encode([conversation]).write(to: folder.appendingPathComponent("conversations.json"))
        let agent = ChatAgent(storagePath: folder.path)
        let settings = AppSettings(storagePath: folder.path)
        settings.apiKey = "" // Intentional: tests never contact a provider.
        settings.summaryDialogCount = 0
        return (folder, agent, settings, conversation.id, conversation.messages.last!.id)
    }
    private func stage(_ agent: ChatAgent, _ cid: UUID, _ mid: UUID) throws -> UserClarification {
        let call = ToolCall(id: "ask", name: "request_user_input", arguments: questionArguments)
        #expect(agent.pauseForClarification(toolCalls: [call], assistantID: mid, conversationID: cid) == "这件事发生在哪个阶段？")
        return try #require(agent.pendingClarification)
    }

    @Test func pendingQuestionPersistsAndSurvivesConversationSwitchWithoutInventingAnAnswer() throws {
        let (folder, agent, _, cid, mid) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let request = try stage(agent, cid, mid)
        let restored = ChatAgent(storagePath: folder.path)
        restored.selectedConversationID = cid
        #expect(restored.pendingClarification == request)
        #expect(restored.selectedConversation?.messages.last?.toolCalls == nil)
        restored.createConversation()
        #expect(restored.pendingClarification == nil)
        restored.selectedConversationID = cid
        #expect(restored.pendingClarification?.id == request.id)
        #expect(restored.pendingClarification?.answer == nil)
    }

    @Test func acceptedAnswerBecomesOneUserTurnAndDuplicateSubmissionIsIgnored() async throws {
        let (folder, agent, settings, cid, mid) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let request = try stage(agent, cid, mid)
        let submission = ClarificationSubmission(requestID: request.id, selectedOption: 0, customText: "具体是高二下学期")
        await agent.send("", clarification: submission, settings: settings)
        let users = agent.selectedConversation?.messages.filter { $0.role == .user } ?? []
        #expect(users.count == 2)
        #expect(users.last?.content.contains("高中期间") == true)
        #expect(users.last?.content.contains("具体是高二下学期") == true)
        let savedRequest = agent.selectedConversation?.messages.first(where: { $0.id == mid })?.clarification
        #expect(savedRequest?.status == .answered)
        #expect(savedRequest?.answer == users.last?.content)
        #expect(agent.pendingClarification == nil)
        let count = agent.selectedConversation?.messages.count
        await agent.send("", clarification: submission, settings: settings)
        #expect(agent.selectedConversation?.messages.count == count)
    }

    @Test func staleInvalidAndBusyAnswersDoNotChangeConversationOrResolveQuestion() async throws {
        let (folder, agent, settings, cid, mid) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let request = try stage(agent, cid, mid)
        for submission in [
            ClarificationSubmission(requestID: UUID(), selectedOption: 0, customText: ""),
            ClarificationSubmission(requestID: request.id, selectedOption: nil, customText: " \n"),
            ClarificationSubmission(requestID: request.id, selectedOption: 100, customText: "")
        ] { await agent.send("", clarification: submission, settings: settings) }
        #expect(agent.selectedConversation?.messages.count == 2)
        agent.isSending = true
        await agent.send("", clarification: .init(requestID: request.id, selectedOption: 0, customText: ""), settings: settings)
        agent.isSending = false
        #expect(agent.pendingClarification?.status == .pending)
        agent.createConversation()
        await agent.send("", clarification: .init(requestID: request.id, selectedOption: 0, customText: ""), settings: settings)
        #expect(agent.selectedConversation?.messages.isEmpty == true)
    }

    @Test func newUserMessageSupersedesAnUnansweredQuestion() async throws {
        let (folder, agent, settings, cid, mid) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try stage(agent, cid, mid)
        await agent.send("换个问题，我想先说另一件事。", settings: settings)
        #expect(agent.pendingClarification == nil)
        #expect(agent.selectedConversation?.messages.first(where: { $0.id == mid })?.clarification?.status == .superseded)
    }

    @Test func oldChatMessagesDecodeWithoutClarificationMetadata() throws {
        let data = try JSONEncoder().encode(ChatMessage(role: .assistant, content: "旧记录"))
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        #expect(decoded.clarification == nil)
    }
}
