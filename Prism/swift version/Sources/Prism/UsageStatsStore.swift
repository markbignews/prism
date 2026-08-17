import Foundation
import Combine

/// Raw usage fields returned by DeepSeek's Chat Completions API.
struct TokenUsage: Codable, Equatable, Sendable {
    var promptTokens: Int64 = 0
    var completionTokens: Int64 = 0
    var promptCacheHitTokens: Int64 = 0
    var promptCacheMissTokens: Int64 = 0

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case promptCacheHitTokens = "prompt_cache_hit_tokens"
        case promptCacheMissTokens = "prompt_cache_miss_tokens"
    }

    init(
        promptTokens: Int64 = 0,
        completionTokens: Int64 = 0,
        promptCacheHitTokens: Int64 = 0,
        promptCacheMissTokens: Int64 = 0
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.promptCacheHitTokens = promptCacheHitTokens
        self.promptCacheMissTokens = promptCacheMissTokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        promptTokens = try container.decodeIfPresent(Int64.self, forKey: .promptTokens) ?? 0
        completionTokens = try container.decodeIfPresent(Int64.self, forKey: .completionTokens) ?? 0
        promptCacheHitTokens = try container.decodeIfPresent(Int64.self, forKey: .promptCacheHitTokens) ?? 0
        promptCacheMissTokens = try container.decodeIfPresent(Int64.self, forKey: .promptCacheMissTokens) ?? 0
    }
}

/// Cumulative, local-only model usage shared by the Swift and Tauri builds.
struct UsageStats: Codable, Equatable, Sendable {
    var inputTokens: Int64 = 0
    var outputTokens: Int64 = 0
    var cacheHitTokens: Int64 = 0
    var cacheMissTokens: Int64 = 0
    var requestCount: Int64 = 0

    var cacheHitRate: Double? {
        // DeepSeek defines prompt_tokens as cache-hit plus cache-miss tokens.
        guard inputTokens > 0 else { return nil }
        return Double(cacheHitTokens) / Double(inputTokens)
    }

    mutating func add(_ usage: TokenUsage) {
        inputTokens += max(0, usage.promptTokens)
        outputTokens += max(0, usage.completionTokens)
        cacheHitTokens += max(0, usage.promptCacheHitTokens)
        cacheMissTokens += max(0, usage.promptCacheMissTokens)
        requestCount += 1
    }
}

/// Main-actor isolation keeps file writes and SwiftUI publication coherent.
@MainActor
final class UsageStatsStore: ObservableObject {
    static let shared = UsageStatsStore()

    @Published private(set) var stats = UsageStats()
    private var fileURL: URL?

    private init() {}

    func configure(dataPath: String) {
        fileURL = URL(fileURLWithPath: dataPath).appendingPathComponent("usage_stats.json")
        reload()
    }

    func record(_ usage: TokenUsage) {
        // Reload before merging so calls made by the Tauri build in the same
        // shared data directory aren't overwritten by a stale Swift snapshot.
        reload()
        stats.add(usage)
        save()
    }

    func reload() {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(UsageStats.self, from: data) else {
            stats = UsageStats()
            return
        }
        stats = decoded
    }

    func reset() {
        stats = UsageStats()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    private func save() {
        guard let fileURL,
              let data = try? JSONEncoder().encode(stats) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
