import Foundation

// MARK: - Tool Registry

/// All retrieval tools available to the main model. Each tool reads from the
/// app's on‑disk JSON archives and returns a JSON result string.
/// Quality guard checks run automatically in the pre‑pipeline — they are not
/// exposed as tools.
enum ToolRegistry {

    /// The `tools` array sent to DeepSeek's API.
    static let definitions: [ToolDef] = [
        .trackPerson,
        .emotionTimeline,
        .searchChapters,
        .fetchChapterMessages,
        .searchMemory,
    ]

    // MARK: - Memory Search

    @MainActor private static func searchMemory(query: String, store: ChatStore, limit: Int) -> String {
        let entries = store.searchMemory(query: query, limit: limit)
        let results: [[String: Any]] = entries.map { entry in
            [
                "content": entry.content,
                "keywords": entry.keywords,
                "sourceChapter": entry.sourceChapterTitle,
                "recallCount": entry.recallCount,
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: results),
              let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str
    }

    /// Execute a retrieval tool call locally and return the result.
    /// Search tools use Flash reranking for semantic understanding when settings are provided.
    @MainActor
    static func execute(
        name: String,
        arguments: String,
        store: ChatStore,
        settings: AppSettings? = nil
    ) async -> String {
        let args: [String: String]
        if let data = arguments.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            args = decoded
        } else {
            print("[ToolRegistry] ⚠ invalid UTF-8 or malformed JSON arguments: \(arguments.prefix(120))")
            args = [:]
        }

        let result: String
        switch name {
        case "track_person":
            result = trackPerson(name: args["name"] ?? "", store: store)
        case "emotion_timeline":
            let n = Int(args["count"] ?? "5") ?? 5
            result = emotionTimeline(count: n, store: store)
        case "search_chapters":
            if let settings {
                let n = Int(args["count"] ?? "5") ?? 5
                let chapters = await store.searchChaptersSemantic(query: args["query"] ?? "", settings: settings, limit: n)
                result = await buildChapterResults(chapters: chapters.map(\.chapter), store: store)
            } else {
                result = searchChapters(query: args["query"] ?? "", store: store)
            }
        case "fetch_chapter_messages":
            result = fetchChapterMessages(args: args, store: store)
        case "search_memory":
            let n = Int(args["count"] ?? "10") ?? 10
            if let settings {
                let entries = await store.searchMemorySemantic(query: args["query"] ?? "", settings: settings, limit: n)
                result = encodeMemoryResults(entries)
            } else {
                result = searchMemory(query: args["query"] ?? "", store: store, limit: n)
            }
        default:
            result = #"{"error":"unknown tool: \#(name)"}"#
        }

        // Log tool execution for observability
        let preview = result.count > 120 ? String(result.prefix(120)) + "…" : result
        print("[Tool] \(name) | args: \(arguments.prefix(80)) | → \(preview)")

        return result
    }

    /// Encode memory entries as JSON for tool response.
    @MainActor private static func encodeMemoryResults(_ entries: [MemoryEntry]) -> String {
        let results: [[String: Any]] = entries.map { entry in
            [
                "content": entry.content,
                "keywords": entry.keywords,
                "sourceChapter": entry.sourceChapterTitle,
                "recallCount": entry.recallCount,
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: results),
              let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str
    }

    // MARK: - Individual Tool Executors

    /// Look up a person across all conversations.
    @MainActor private static func trackPerson(name: String, store: ChatStore) -> String {
        let archive = store.personArchive
        guard !name.isEmpty else {
            return #"{"found":false,"reason":"empty name"}"#
        }
        guard let person = archive.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) else {
            return #"{"found":false,"name":"\#(name)"}"#
        }

        let encoder = JSONEncoder()
        guard let json = try? encoder.encode(person),
              let str = String(data: json, encoding: .utf8) else {
            return #"{"found":false}"#
        }
        return str
    }

    /// Return recent emotional trajectory — raw data only, model judges the trend.
    @MainActor private static func emotionTimeline(count: Int, store: ChatStore) -> String {
        let timeline = store.emotionTimeline.suffix(count)
        var result: [[String: Any]] = []
        for entry in timeline {
            result.append([
                "emotion": entry.emotion,
                "intensity": entry.intensity,
                "date": ISO8601DateFormatter().string(from: entry.createdAt),
                "segment": entry.segment,
            ])
        }

        guard let data = try? JSONSerialization.data(withJSONObject: ["entries": result]),
              let str = String(data: data, encoding: .utf8) else {
            return #"{"entries":[]}"#
        }
        return str
    }

    /// Search past chapter summaries — returns full message content for matches
    /// so the agent can read the original conversation text.
    @MainActor private static func searchChapters(query: String, store: ChatStore) -> String {
        let allChapters = store.allChapters
        let topN = 10

        guard !query.isEmpty else {
            let recent = allChapters.suffix(topN)
            return buildChapterResults(chapters: Array(recent), store: store)
        }

        let q = query.lowercased()
        let terms = expandQuery(q.split(separator: " ").map(String.init).filter { $0.count >= 1 })

        var scored: [(chapter: StoryChapter, score: Int)] = []
        for ch in allChapters {
            let t = ch.title.lowercased()
            let s = ch.summary.lowercased()
            let kw = ch.keywords.map { $0.lowercased() }
            var score = 0

            for term in terms {
                if t.contains(term) { score += 3 }
                else if kw.contains(where: { $0.contains(term) }) { score += 2 }
                if s.contains(term) { score += 1 }
            }
            if t.contains(q) { score += 2 }
            if kw.contains(where: { $0.contains(q) }) { score += 1 }

            if score > 0 { scored.append((ch, score)) }
        }

        scored.sort { $0.score > $1.score }
        let top = Array(scored.prefix(topN).map(\.chapter))

        return buildChapterResults(chapters: top, store: store)
    }

    /// Fetch all messages for a specific chapter by index (1-based).
    @MainActor private static func fetchChapterMessages(args: [String: String], store: ChatStore) -> String {
        guard let indexStr = args["index"],
              let index = Int(indexStr),
              index >= 1 else {
            return #"{"error":"invalid index"}"#
        }

        let allChapters = store.allChapters
        guard index <= allChapters.count else {
            return #"{"error":"chapter not found","max":\#(allChapters.count)}"#
        }

        let chapter = allChapters[index - 1]
        let msgs = store.messages(for: chapter)
            .filter { $0.role != .system }
            .prefix(12)

        let messageList: [[String: String]] = msgs.map { msg in
            ["role": msg.role.rawValue, "content": msg.content]
        }

        let result: [String: Any] = [
            "chapter": index,
            "title": chapter.title,
            "summary": chapter.summary,
            "keywords": chapter.keywords,
            "messages": messageList,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: result),
              let str = String(data: data, encoding: .utf8) else {
            return #"{"error":"serialization failed"}"#
        }
        return str
    }

    @MainActor private static func buildChapterResults(chapters: [StoryChapter], store: ChatStore) -> String {
        let results: [[String: Any]] = chapters.map { ch in
            return [
                "title": ch.title,
                "summary": String(ch.summary.prefix(200)),
                "keywords": ch.keywords,
            ]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: results),
              let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str
    }
}

// MARK: - Tool Definition Schema

struct ToolDef: Encodable {
    var type = "function"
    let function: FunctionDef

    struct FunctionDef: Encodable {
        let name: String
        let description: String
        let parameters: Parameters

        struct Parameters: Encodable {
            var type = "object"
            let properties: [String: Property]
            let required: [String]?
        }

        struct Property: Encodable {
            let type: String
            let description: String
        }
    }

    static let trackPerson = ToolDef(function: .init(
        name: "track_person",
        description: "查询一个人是否在历史对话中出现过，返回跨对话关系档案。当前对话中提到一个具体人名或身份（如'前任''老板''我妈'）时调用。",
        parameters: .init(properties: [
            "name": .init(type: "string", description: "要查询的人名或身份称呼"),
        ], required: ["name"])
    ))

    static let emotionTimeline = ToolDef(function: .init(
        name: "emotion_timeline",
        description: "返回用户最近N轮对话的情绪轨迹（原始数据，含情绪标签、强度和原文片段）。由模型自主判断趋势。当需要了解用户近期整体情绪状态时调用。",
        parameters: .init(properties: [
            "count": .init(type: "integer", description: "查询最近多少轮的情绪，默认5"),
        ], required: nil)
    ))

    static let searchChapters = ToolDef(function: .init(
        name: "search_chapters",
        description: "语义搜索历史章节（关键词 + 语义理解），返回标题、摘录和关键词。如需阅读完整原文请调 fetch_chapter_messages。当用户提到过去的某个话题、事件或关键词时调用。",
        parameters: .init(properties: [
            "query": .init(type: "string", description: "搜索关键词，留空返回最近5章"),
            "count": .init(type: "integer", description: "返回条数，默认5"),
        ], required: ["query"])
    ))

    static let fetchChapterMessages = ToolDef(function: .init(
        name: "fetch_chapter_messages",
        description: "获取指定章节的全部原文消息。当 search_chapters 返回的摘要不够详细、需要阅读完整原文时调用。",
        parameters: .init(properties: [
            "index": .init(type: "integer", description: "章节序号（从1开始），在章节索引中可看到章节编号"),
        ], required: ["index"])
    ))

    static let searchMemory = ToolDef(function: .init(
        name: "search_memory",
        description: "语义搜索跨对话记忆库（关键词 + 语义理解），返回相关的叙事摘要和洞察。当用户提到过去讨论过的话题、想回顾之前分析过的模式、或需要跨对话上下文时调用。这是长期记忆，不同于 search_chapters 只查当前对话。",
        parameters: .init(properties: [
            "query": .init(type: "string", description: "搜索关键词或短语，留空返回最近记忆"),
            "count": .init(type: "integer", description: "返回条数，默认10"),
        ], required: ["query"])
    ))
}
