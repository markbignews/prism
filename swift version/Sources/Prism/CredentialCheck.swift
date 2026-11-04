import Foundation
import Combine

@MainActor
final class CredentialCheck: ObservableObject {
    enum State: Equatable {
        case idle, checking, success, failure(String)
    }
    @Published private(set) var state: State = .idle
    private(set) var models: [ProviderModel] = []
    private var identity = UUID()
    private var verifiedKey: String?
    private var verifiedBase: String?
    private var task: Task<Void, Never>?

    func validatedKey(for input: String, baseURL: String) -> String? {
        guard state == .success, verifiedBase == baseURL,
              let key = try? APICredentials.normalized(input), key == verifiedKey else { return nil }
        return key
    }

    func schedule(key input: String, baseURL: String, language: AppLanguage,
                  client: ModelCatalogClient = ModelCatalogClient(), delay: Duration = .milliseconds(800)) {
        task?.cancel()
        identity = UUID()
        let current = identity
        verifiedKey = nil
        verifiedBase = nil
        models = []
        state = .idle
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        task = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                guard let self, self.identity == current else { return }
                let key = try APICredentials.normalized(input)
                self.state = .checking
                let models = try await client.fetch(apiKey: key, baseURL: baseURL)
                guard !Task.isCancelled, self.identity == current else { return }
                self.models = models
                self.verifiedKey = key
                self.verifiedBase = baseURL
                self.state = .success
            } catch {
                guard let self, !Task.isCancelled, self.identity == current else { return }
                self.state = .failure(ProviderFailure.message(error, language: language))
            }
        }
    }
}
