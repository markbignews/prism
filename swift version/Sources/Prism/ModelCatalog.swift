import Foundation

struct ProviderModel: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    var name: String?

    var displayName: String { name?.isEmpty == false ? name! : id }
    var isFlash: Bool { id.localizedCaseInsensitiveContains("flash") || (name?.localizedCaseInsensitiveContains("flash") == true) }

    static func sorted(_ models: [ProviderModel]) -> [ProviderModel] {
        var seen = Set<String>()
        return models.filter { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0.id).inserted }
            .sorted {
                if $0.isFlash != $1.isFlash { return $0.isFlash }
                if ($0.id == DeepSeekModels.flash) != ($1.id == DeepSeekModels.flash) { return $0.id == DeepSeekModels.flash }
                return $0.id.localizedStandardCompare($1.id) == .orderedAscending
            }
    }

    static func selection(current: String, from models: [ProviderModel]) -> String {
        if models.contains(where: { $0.id == current }) { return current }
        return sorted(models).first?.id ?? current
    }
}

/// Model discovery reads provider metadata only; it never invokes a language model.
struct ModelCatalogClient: Sendable {
    var session: URLSession = .shared

    static func endpoint(baseURL: String, suffix: String = "models") throws -> URL {
        guard var parts = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), ["https", "http"].contains(scheme),
              parts.host?.isEmpty == false, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else { throw DeepSeekError.invalidBaseURL }
        parts.path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        parts.path = "/" + (parts.path.isEmpty ? suffix : parts.path + "/" + suffix)
        guard let url = parts.url else { throw DeepSeekError.invalidBaseURL }
        return url
    }

    func fetch(apiKey: String, baseURL: String) async throws -> [ProviderModel] {
        let key = try APICredentials.normalized(apiKey)
        var request = URLRequest(url: try Self.endpoint(baseURL: baseURL))
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw DeepSeekError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            // Do not echo provider bodies: some gateways include request credentials.
            throw DeepSeekError.http(http.statusCode)
        }
        struct Response: Decodable { var data: [ProviderModel] }
        let models = ProviderModel.sorted(try JSONDecoder().decode(Response.self, from: data).data)
        guard !models.isEmpty else { throw DeepSeekError.emptyResponse }
        return models
    }
}
