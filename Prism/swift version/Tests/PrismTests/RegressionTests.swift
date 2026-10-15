import Foundation
import Synchronization
import Testing
@testable import Prism

@Suite struct SafetyRoutingTests {
    @Test(arguments: [
        #"{"flag":"ok"}"#,
        #"{"flag":"uncertain","immediate_danger":false,"evidence":"尚需确认当前状况"}"#,
        #"{"flag":"crisis"}"#,
        #"{"flag":"crisis","immediate_danger":false,"evidence":"过去的经历"}"#,
        #"{"flag":"crisis","immediate_danger":true,"evidence":"  "}"#
    ])
    func incompleteOrNonImmediateAssessmentDoesNotForceIntervention(json: String) throws {
        let result = try JSONDecoder().decode(SafetyAssessment.self, from: Data(json.utf8))
        #expect(!result.requiresIntervention)
    }

    @Test func contextualImmediateDangerStillRoutesToSupport() throws {
        let result = try JSONDecoder().decode(SafetyAssessment.self, from: Data(
            #"{"flag":"crisis","immediate_danger":true,"evidence":"用户明确描述当前正在面临危险"}"#.utf8))
        #expect(result.requiresIntervention)
        #expect(!result.isUncertain)
    }

    @Test func oldCrisisLabelWithoutCurrentEvidenceIsUncertain() throws {
        let result = try JSONDecoder().decode(SafetyAssessment.self, from: Data(#"{"flag":"crisis"}"#.utf8))
        #expect(result.isUncertain)
    }

    @Test(arguments: [#"{}"#, #"{"flag":"unknown"}"#, #"{"flag":"crisis","immediate_danger":"true"}"#])
    func malformedAssessmentCannotBecomeAConfirmedCrisis(json: String) {
        #expect(throws: (any Error).self) { try JSONDecoder().decode(SafetyAssessment.self, from: Data(json.utf8)) }
    }
}

@Suite struct ModelSelectionTests {
    @Test func flashIsFirstAndCatalogIsDeduplicated() {
        let models = ProviderModel.sorted([
            .init(id: "z-pro"), .init(id: "other-flash"), .init(id: "deepseek-flash"),
            .init(id: "z-pro"), .init(id: ""), .init(id: "fast", name: "Vendor Flash")
        ])
        #expect(models.first?.id == "deepseek-flash")
        #expect(models.map(\.id) == ["deepseek-flash", "fast", "other-flash", "z-pro"])
    }

    @Test func manualSelectionIsPreservedButMissingSelectionPrefersFlash() {
        let models: [ProviderModel] = [.init(id: "a-pro"), .init(id: "z-flash")]
        #expect(ProviderModel.selection(current: "a-pro", from: models) == "a-pro")
        #expect(ProviderModel.selection(current: "retired-model", from: models) == "z-flash")
        #expect(DeepSeekModels.supportedConversationModel("vendor-chat") == "vendor-chat")
        #expect(DeepSeekModels.canonical("vendor-chat", baseURL: "https://example.test/v1") == "vendor-chat")
    }

    @Test func basePathIsPreserved() throws {
        #expect(try ModelCatalogClient.endpoint(baseURL: " https://example.test/v1/ ").absoluteString == "https://example.test/v1/models")
        #expect(try ModelCatalogClient.endpoint(baseURL: "https://api.deepseek.com").path == "/models")
    }

    @Test(arguments: ["not-a-url", "file:///tmp/test", "https://user:secret@example.test", "https://example.test?key=secret", "https://example.test/#fragment"])
    func invalidEndpointsAreRejected(base: String) {
        #expect(throws: (any Error).self) { try ModelCatalogClient.endpoint(baseURL: base) }
    }
}

@Suite struct TimelineApprovalTests {
    @Test func modelArgumentCannotWriteOrApproveAnEvent() throws {
        let conversationID = UUID(), sourceID = UUID()
        let proposal = try #require(NarrativeEventProposal(arguments: [
            "title": "确认这句话的含义？", "startLabel": "高二期间", "confirmed": "true"
        ], conversationID: conversationID, sourceMessageID: sourceID))
        #expect(proposal.isCurrent(conversationID: conversationID, latestUserMessageID: sourceID))
        #expect(!proposal.isCurrent(conversationID: UUID(), latestUserMessageID: sourceID))
        #expect(!proposal.isCurrent(conversationID: conversationID, latestUserMessageID: UUID()))
    }

    @Test func missingEventTimeCannotProduceAReviewCard() {
        #expect(NarrativeEventProposal(arguments: ["title": "事件"], conversationID: UUID(), sourceMessageID: UUID()) == nil)
    }
}

private final class CatalogURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)
    static let handler = Mutex<Handler?>(nil)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let action = Self.handler.withLock { $0 }
            guard let action else { throw URLError(.badServerResponse) }
            let (status, data) = try action(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct CatalogTransportTests {
    private func client(handler: @escaping CatalogURLProtocol.Handler) -> ModelCatalogClient {
        CatalogURLProtocol.handler.withLock { $0 = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogURLProtocol.self]
        return ModelCatalogClient(session: URLSession(configuration: configuration))
    }

    @Test func fetchUsesMetadataEndpointAndBearerHeader() async throws {
        let client = client { request in
            #expect(request.url?.absoluteString == "https://provider.test/v1/models")
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-placeholder")
            #expect(request.httpBody == nil)
            return (200, Data(#"{"data":[{"id":"pro"},{"id":"flash-new","name":"Flash new","extra":42}]}"#.utf8))
        }
        let models = try await client.fetch(apiKey: " test-placeholder ", baseURL: "https://provider.test/v1/")
        #expect(models.first?.id == "flash-new")
    }

    @MainActor
    @Test func settingsPersistCustomModelsAndKeepThemOnFetchFailure() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = AppSettings(storagePath: folder.path)
        settings.apiKey = "test-placeholder"
        settings.baseURL = "https://provider.test/v1"
        settings.model = "vendor-chat"
        settings.flashModel = "vendor-fast"
        let restored = AppSettings(storagePath: folder.path)
        #expect(restored.model == "vendor-chat")
        #expect(restored.flashModel == "vendor-fast")
        let failing = client { _ in (503, Data()) }
        await restored.refreshModels(client: failing)
        #expect(restored.model == "vendor-chat")
        #expect(restored.flashModel == "vendor-fast")
        #expect(restored.modelCatalogError != nil)
        #expect(!restored.isFetchingModels)
    }

    @MainActor
    @Test func settingsChooseFlashForUnavailableIDsAndClearCatalogWhenCredentialsChange() async {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = AppSettings(storagePath: folder.path)
        settings.apiKey = "test-placeholder"
        settings.baseURL = "https://provider.test/v1"
        settings.model = "unavailable"
        let client = client { _ in (200, Data(#"{"data":[{"id":"pro"},{"id":"vendor-flash"}]}"#.utf8)) }
        await settings.refreshModels(client: client)
        #expect(settings.model == "vendor-flash")
        #expect(settings.flashModel == "vendor-flash")
        #expect(settings.availableModels.count == 2)
        settings.apiKey = "replacement-placeholder"
        #expect(settings.availableModels.isEmpty)
        #expect(settings.modelCatalogError == nil)
    }

    @MainActor
    @Test func staleProviderResponseCannotOverwriteNewProvider() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = AppSettings(storagePath: folder.path)
        settings.apiKey = "test-placeholder"
        settings.baseURL = "https://old.test"
        let started = Mutex(false)
        let client = client { request in
            if request.url?.host == "old.test" {
                started.withLock { $0 = true }
                Thread.sleep(forTimeInterval: 0.08)
                return (200, Data(#"{"data":[{"id":"old-flash"}]}"#.utf8))
            }
            return (200, Data(#"{"data":[{"id":"new-flash"}]}"#.utf8))
        }
        let old = Task { await settings.refreshModels(client: client) }
        for _ in 0..<100 {
            if started.withLock({ $0 }) { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(started.withLock { $0 })
        settings.baseURL = "https://new.test"
        await settings.refreshModels(client: client)
        await old.value
        #expect(settings.availableModels.map(\.id) == ["new-flash"])
        #expect(settings.model == "new-flash")
        #expect(!settings.isFetchingModels)
    }

    @Test func streamingAndSummaryErrorsUseStatusWithoutEchoingProviderSecrets() async {
        let transport = client { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer placeholder")
            return (401, Data(#"{"error":{"message":"Authentication Fails (governor) secret-echo"}}"#.utf8))
        }
        let chat = DeepSeekClient(apiKey: " placeholder ", baseURL: "https://provider.test", model: "model", parameters: ModelParameters(), language: .simplifiedChinese, session: transport.session)
        do {
            _ = try await chat.stream(messages: [.init(role: .user, content: "测试")], memoryContext: nil) { _ in }
            Issue.record("Expected authentication rejection")
        } catch {
            let message = ProviderFailure.message(error, language: .simplifiedChinese)
            #expect(message.contains("密钥验证失败"))
            #expect(!message.contains("secret-echo"))
        }
        do {
            _ = try await chat.summarize(systemPrompt: "测试", userContent: "测试")
            Issue.record("Expected authentication rejection")
        } catch {
            #expect(ProviderFailure.message(error, language: .simplifiedChinese).contains("密钥验证失败"))
        }
    }

    @MainActor
    @Test func onboardingRequiresSuccessfulValidationOfTheExactKeyAndEndpoint() async throws {
        let check = CredentialCheck()
        let success = client { _ in (200, Data(#"{"data":[{"id":"vendor-flash"}]}"#.utf8)) }
        #expect(check.validatedKey(for: "placeholder", baseURL: "https://provider.test") == nil)
        check.schedule(key: " placeholder ", baseURL: "https://provider.test", language: .simplifiedChinese, client: success, delay: .zero)
        for _ in 0..<100 {
            if check.state == .success { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(check.validatedKey(for: "placeholder", baseURL: "https://provider.test") == "placeholder")
        #expect(check.validatedKey(for: "different", baseURL: "https://provider.test") == nil)
        #expect(check.validatedKey(for: "placeholder", baseURL: "https://other.test") == nil)
        let failure = client { _ in (401, Data(#"{"error":"secret-echo"}"#.utf8)) }
        check.schedule(key: "rejected", baseURL: "https://provider.test", language: .simplifiedChinese, client: failure, delay: .zero)
        #expect(check.validatedKey(for: "placeholder", baseURL: "https://provider.test") == nil)
        for _ in 0..<100 {
            if case .failure = check.state { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case .failure(let message) = check.state else { Issue.record("Expected authentication failure"); return }
        #expect(message.contains("密钥验证失败"))
        #expect(!message.contains("secret-echo"))
        #expect(check.validatedKey(for: "rejected", baseURL: "https://provider.test") == nil)
    }

    @MainActor
    @Test func changedOrClearedKeyCancelsPendingOnboardingValidation() async throws {
        let check = CredentialCheck()
        let started = Mutex(false)
        let slow = client { _ in
            started.withLock { $0 = true }
            Thread.sleep(forTimeInterval: 0.08)
            return (200, Data(#"{"data":[{"id":"old-model"}]}"#.utf8))
        }
        check.schedule(key: "old-placeholder", baseURL: "https://provider.test", language: .english, client: slow, delay: .zero)
        for _ in 0..<100 {
            if started.withLock({ $0 }) { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(started.withLock { $0 })
        check.schedule(key: "", baseURL: "https://provider.test", language: .english, client: slow, delay: .zero)
        try await Task.sleep(for: .milliseconds(120))
        #expect(check.state == .idle)
        #expect(check.models.isEmpty)
        #expect(check.validatedKey(for: "old-placeholder", baseURL: "https://provider.test") == nil)
    }

    @Test(arguments: [401, 403, 429, 500])
    func serverErrorDoesNotLeakProviderBody(status: Int) async {
        let client = client { _ in (status, Data("sensitive-provider-body".utf8)) }
        do {
            _ = try await client.fetch(apiKey: "test-placeholder", baseURL: "https://provider.test")
            Issue.record("Expected server failure")
        } catch {
            #expect(error.localizedDescription.contains("\(status)"))
            #expect(!error.localizedDescription.contains("sensitive-provider-body"))
        }
    }

    @Test(arguments: [#"{"data":[]}"#, #"{"data":[{"id":""}]}"#, #"{"error":"bad"}"#, "not JSON"])
    func emptyOrMalformedCatalogIsNotSuccess(body: String) async {
        let client = client { _ in (200, Data(body.utf8)) }
        await #expect(throws: (any Error).self) {
            try await client.fetch(apiKey: "test-placeholder", baseURL: "https://provider.test")
        }
    }
}

@Suite(.serialized) @MainActor struct SupervisorIntegrationTests {
    @Test func unavailablePassDoesNotRetainPartialWarningsOrForceCrisis() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let agent = ChatAgent(storagePath: folder.path)
        var result = ChatAgent.PrePipelineResult()
        let parsed = agent.parsePrePipelineJSON(#"{"guard":{"safety":{"flag":"invalid"},"reality":{"flag":"warning","hint":"partial-model-output"}}}"#,
            into: &result, conversationID: UUID())
        #expect(!parsed)
        #expect(!result.safetyCrisis)
        #expect(result.safetyUncertain)
        result.analysisUnavailable = true
        let hint = agent.buildGuardHint(from: result) ?? ""
        #expect(!hint.contains("partial-model-output"))
        #expect(!hint.isEmpty)
    }

    @Test func parserRequiresImmediateEvidenceAndDropsUnverifiedResources() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let agent = ChatAgent(storagePath: folder.path)
        var result = ChatAgent.PrePipelineResult()
        #expect(agent.parsePrePipelineJSON(#"{"guard":{"safety":{"flag":"crisis","resources":"unverified-resource"}}}"#,
            into: &result, conversationID: UUID()))
        #expect(!result.safetyCrisis)
        #expect(result.safetyUncertain)
        #expect(result.safetyResources.isEmpty)
        #expect(agent.parsePrePipelineJSON(#"{"guard":{"safety":{"flag":"crisis","immediate_danger":true,"evidence":"current danger","resources":"unverified-resource"}}}"#,
            into: &result, conversationID: UUID()))
        #expect(result.safetyCrisis)
        #expect(!result.safetyUncertain)
        #expect(result.safetyResources.isEmpty)
    }
}
