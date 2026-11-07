import Foundation
import Testing
@testable import Prism

@Suite struct ResearchAndQuestionContracts {
    @Test(arguments: ConversationMode.allCases, AppLanguage.allCases)
    func academicConceptAndLowFrictionQuestionRulesReachMainRequests(mode: ConversationMode, language: AppLanguage) throws {
        let client = DeepSeekClient(apiKey: "placeholder", baseURL: "https://api.deepseek.com", model: "deepseek-flash",
            parameters: ModelParameters(), language: language, mode: mode)
        let request = try client.makeStreamRequest(messages: [.init(role: .user, content: "依恋模式和自恋特质怎么区分？")], memoryContext: nil,
            tools: ToolRegistry.availableDefinitions(baseURL: "https://api.deepseek.com", includeHistory: false))
        let data = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])
        let system = try #require(messages.first?["content"] as? String)
        #expect(system.contains(AgentPrompt.academicEvidenceRules))
        #expect(system.contains("NPD（自恋型人格障碍）"))
        #expect(system.contains("只把本轮检索或用户提供的可核对文献资料作为已核实引文"))
        #expect(system.contains("不得凭印象编造作者、年份、题名、DOI"))
        #expect(system.contains("必须调用选项卡工具"))
        #expect(system.contains("是否调用 search_web 由你根据完整上下文自主决定"))
        #expect(system.hasSuffix(AgentPrompt.productScopeRules))
        #expect(body["tool_choice"] as? String == "auto")
    }
}

@Suite struct HumanReadableProviderErrorTests {
    @Test(arguments: [400, 401, 402, 403, 404, 408, 413, 422, 429, 500, 503, 504])
    func statusFailuresExplainAnActionInEveryLanguage(status: Int) {
        for language in AppLanguage.allCases {
            let message = ProviderFailure.httpMessage(status, language: language)
            #expect(message.count > 20)
            #expect(message.contains(String(status)))
            #expect(!message.contains("Invalid Format") && !message.contains("Insufficient Balance"))
        }
    }

    @Test func structuredStreamingFailuresAreTranslatedWithoutEchoingPrivateText() throws {
        for (code, expected) in [("context_length_exceeded", "长度"), ("insufficient_balance", "余额"),
                                 ("server_overloaded", "太忙"), ("content_policy_violation", "内容")] {
            let data = try JSONSerialization.data(withJSONObject: ["error": ["code": code, "message": "secret-user-text-and-key"]])
            let error = try #require(ProviderFailure.streamError(data))
            let displayed = ProviderFailure.message(error, language: .simplifiedChinese)
            #expect(displayed.contains(expected))
            #expect(!displayed.contains("secret-user-text-and-key"))
            #expect(!error.localizedDescription.contains("secret-user-text-and-key"))
        }
        let unknown = try #require(ProviderFailure.streamError(Data(#"{"error":{"message":"secret-user-text-and-key"}}"#.utf8)))
        #expect(!ProviderFailure.message(unknown, language: .simplifiedChinese).contains("secret-user-text-and-key"))
        #expect(ProviderFailure.streamError(Data(#"{"choices":[]}"#.utf8)) == nil)
    }
}
