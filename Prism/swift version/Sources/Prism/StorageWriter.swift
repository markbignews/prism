import Foundation

/// Frozen copies of value-type model arrays. The main actor never mutates these
/// copies; Swift Array/Data copy-on-write isolates later UI/worker mutations.
struct StorageSnapshot: @unchecked Sendable {
    var conversations: [Conversation]
    var people: [PersonRecord]
    var links: [PersonLinkProposal]
    var profile: [UserProfileObservation]
    var emotions: [EmotionEntry]
    var blindspots: [BlindspotRecord]
    var memory: [MemoryEntry]
    var timeline: [NarrativeEvent]

    func encode(names: Set<String>) throws -> [String: Data] {
        let encoder = SQLiteStore.encoder()
        var result: [String: Data] = [:]
        if names.contains("conversations.json") { result["conversations.json"] = try encoder.encode(conversations) }
        if names.contains("person_archive.json") { result["person_archive.json"] = try encoder.encode(people) }
        if names.contains("person_link_proposals.json") { result["person_link_proposals.json"] = try encoder.encode(links) }
        if names.contains("user_profile.json") { result["user_profile.json"] = try encoder.encode(profile) }
        if names.contains("emotion_timeline.json") { result["emotion_timeline.json"] = try encoder.encode(emotions) }
        if names.contains("blindspots.json") { result["blindspots.json"] = try encoder.encode(blindspots) }
        if names.contains("memory.json") { result["memory.json"] = try encoder.encode(memory) }
        if names.contains("narrative_timeline.json") { result["narrative_timeline.json"] = try encoder.encode(timeline) }
        return result
    }
}

/// Encoding and SQLite IO share one serial queue, including lifecycle flushes.
final class StorageWriter: @unchecked Sendable {
    let database: SQLiteStore
    private let queue = DispatchQueue(label: "com.prism.persistence", qos: .utility)
    init(database: SQLiteStore) { self.database = database }

    /// Three attempts, with 250ms/750ms backoff, in addition to SQLite's
    /// 250ms busy timeout per attempt (at most ~1.75s for a blocked batch).
    /// Called on the writer queue; conflicts and non-lock failures propagate.
    static func withBusyRetry<T>(
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        operation: () throws -> T
    ) throws -> T {
        let delays: [TimeInterval] = [0.25, 0.75]
        var retry = 0
        while true {
            do { return try operation() }
            catch {
                guard let failure = error as? SQLiteStore.Failure, failure.allowsAutomaticRetry,
                      retry < delays.count else { throw error }
                sleep(delays[retry]); retry += 1
            }
        }
    }
    private func commit(_ snapshot: StorageSnapshot, names: Set<String>) throws {
        // Encode once. Only the rolled-back transaction is retried.
        let encoded = try snapshot.encode(names: names)
        try Self.withBusyRetry { try database.writeBatch(encoded) }
    }

    func write(_ snapshot: StorageSnapshot, names: Set<String>) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: Result { try self.commit(snapshot, names: names) }) }
        }
    }
    func flush(_ snapshot: StorageSnapshot, names: Set<String>) throws {
        try queue.sync { try commit(snapshot, names: names) }
    }
    func backup(to target: URL) throws { try queue.sync { try database.backup(to: target) } }
}
