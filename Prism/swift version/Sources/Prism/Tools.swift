import Foundation

// MARK: - Tool Registry

/// Retrieval and evidence tools available to the main model. Local tools read
/// the app's archives; search_psychology calls only DeepSeek's official search
/// endpoint and returns a JSON result string.
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
        .searchPsychology,
        .manageNarrativeTimeline,
        .requestUserInput,
    ]

    // MARK: - Memory Search

    @MainActor private static func searchMemory(query: String, store: ChatAgent, limit: Int) -> String {
        let entries = store.searchMemory(query: query, limit: limit)
        let results: [[String: Any]] = entries.map { entry in
            [
                "content": entry.content,
                "keywords": entry.keywords,
                "sourceChapter": entry.sourceChapterTitle,
                "timeSpanStart": entry.timeSpanStart?.ISO8601Format() ?? NSNull(),
                "timeSpanEnd": entry.timeSpanEnd?.ISO8601Format() ?? NSNull(),
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
    /// Local search uses keyword candidates; the main model interprets returned evidence.
    @MainActor
    static func execute(
        name: String,
        arguments: String,
        store: ChatAgent,
        settings: AppSettings? = nil
    ) async -> String {
        let args: [String: String]
        if let data = arguments.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            args = decoded.reduce(into: [:]) { result, pair in
                if let value = pair.value as? String { result[pair.key] = value }
                else if let value = pair.value as? NSNumber { result[pair.key] = value.stringValue }
            }
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
                result = buildChapterResults(chapters: chapters.map(\.chapter), store: store)
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
        case "search_psychology":
            if let settings {
                result = await DeepSeekWebSearchClient.search(query: args["query"] ?? "", settings: settings)
            } else {
                result = #"{"error":"DeepSeek official search requires the current app settings."}"#
            }
        case "request_user_input":
            // Valid questions are intercepted by ChatAgent before execution.
            result = #"{"error":"Invalid clarification. Supply one nonempty question and 2-4 distinct options, each with label and description. Do not claim the user answered."}"#
        case "manage_narrative_timeline":
            result = manageNarrativeTimeline(args: args, store: store)
        default:
            result = #"{"error":"unknown tool: \#(name)"}"#
        }

        // Log tool execution for observability
        let preview = result.count > 120 ? String(result.prefix(120)) + "…" : result
        print("[Tool] \(name) | args: \(arguments.prefix(80)) | → \(preview)")

        return result
    }

    @MainActor private static func manageNarrativeTimeline(args: [String: String], store: ChatAgent) -> String {
        let action = args["action"] ?? "list"
        if action == "list" {
            let events = store.narrativeEvents(for: store.activeToolConversationID ?? store.selectedConversationID)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(events),
                  let string = String(data: data, encoding: .utf8) else { return "[]" }
            return string
        }

        guard action == "upsert" else { return #"{"error":"unknown timeline action"}"# }
        guard store.proposeNarrativeEvent(arguments: args) else {
            return #"{"error":"a title, clear time label and valid event ID are required"}"#
        }
        return #"{"pending_confirmation":true,"instruction":"A native review card will appear after this reply. The event is NOT saved. The user must review it and click Save; do not ask for a magic phrase or claim it is saved."}"#
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

    /// Look up a person only within the selected conversation.
    @MainActor private static func trackPerson(name: String, store: ChatAgent) -> String {
        let archive = store.personArchive
        guard !name.isEmpty else {
            return #"{"found":false,"reason":"empty name"}"#
        }
        guard let conversationID = store.activeToolConversationID ?? store.selectedConversationID,
              let person = archive.first(where: {
                  ($0.name.localizedCaseInsensitiveContains(name)
                      || $0.aliases.contains(where: { $0.localizedCaseInsensitiveContains(name) }))
                      && $0.conversationIDs?.contains(conversationID) == true
              }) else {
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
    @MainActor private static func emotionTimeline(count: Int, store: ChatAgent) -> String {
        let timeline = store.emotionTimeline
            .filter { $0.conversationID == (store.activeToolConversationID ?? store.selectedConversationID) }
            .suffix(count)
        var result: [[String: Any]] = []
        for entry in timeline {
            result.append([
                "emotion": entry.emotion,
                "intensity": entry.intensity,
                "confidence": entry.confidence ?? NSNull(),
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
    @MainActor private static func searchChapters(query: String, store: ChatAgent) -> String {
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
    @MainActor private static func fetchChapterMessages(args: [String: String], store: ChatAgent) -> String {
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

    @MainActor private static func buildChapterResults(chapters: [StoryChapter], store: ChatAgent) -> String {
        // Each result carries conversation context and the
        // chapter's global 1-based index (across all conversations), so the
        // model can feed it straight back to fetch_chapter_messages.
        let allChapters = store.allChapters
        let results: [[String: Any]] = chapters.map { ch in
            let conv = store.conversations.first { conv in
                conv.chapters.contains { $0.id == ch.id }
            }
            let globalIndex: Any = allChapters.firstIndex(where: { $0.id == ch.id })
                .map { $0 + 1 } ?? NSNull()
            return [
                "conversationId": conv?.id.uuidString ?? NSNull(),
                "conversationTitle": conv?.title ?? NSNull(),
                "chapter": globalIndex,
                "title": ch.title,
                "summary": String(ch.summary.prefix(240)),
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

struct ToolDef: Encodable, Sendable {
    var type = "function"
    let function: FunctionDef

    struct FunctionDef: Encodable, Sendable {
        let name: String
        let description: String
        let parameters: Parameters

        struct Parameters: Encodable, Sendable {
            var type = "object"
            let properties: [String: Property]
            let required: [String]?
        }

        struct Property: Encodable, Sendable {
            let type: String
            let description: String
            var items: Items? = nil
            var minItems: Int? = nil
            var maxItems: Int? = nil
        }
        struct Items: Encodable, Sendable {
            let type: String
            let properties: [String: Property]
            let required: [String]
            var additionalProperties = false
        }
    }

    static let requestUserInput = ToolDef(function: .init(
        name: "request_user_input",
        description: "当一个缺失事实会实质改变判断或下一步时，提出一个简短中性问题，并给出2至4个便于回答的选项。客户端会暂停本轮分析，展示包含选项与手动补充的紧凑追问卡片；只有收到用户答案后才继续。不要每轮都问，不要重复已知信息，不要把推断写成选项中的事实；允许不确定。不必生成其他或手动输入选项，界面始终支持自由输入。使用用户的语言。本次不要同时调用其他工具。",
        parameters: .init(properties: [
            "question": .init(type: "string", description: "一个真正影响判断的澄清问题，最多600字"),
            "options": .init(type: "array", description: "2至4个中性、不同的选项，标签最多120字，说明最多300字",
                items: .init(type: "object", properties: [
                    "label": .init(type: "string", description: "简短选项"),
                    "description": .init(type: "string", description: "可为空的简短说明，不暗示用户应选哪个")
                ], required: ["label", "description"]), minItems: 2, maxItems: 4)
        ], required: ["question", "options"])
    ))

    static let trackPerson = ToolDef(function: .init(
        name: "track_person",
        description: "查询一个人是否在当前对话中出现过，避免跨对话暴露人物档案。当前对话中提到一个具体人名或身份（如'前任''老板''我妈'）时调用。",
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

    static let searchPsychology = ToolDef(function: .init(
        name: "search_psychology",
        description: "仅在用户的问题明确需要心理学、心理健康或关系沟通方面的研究依据、概念解释或较新的专业资料时调用。搜索由 DeepSeek 官方联网搜索完成，不访问其他搜索服务。查询必须改写成不含姓名、联系方式和可识别细节的中性研究问题；不要用它证明某个人的诊断、人格或主观动机。危机或安全风险下不要调用。返回结果后必须区分研究发现、来源陈述和对用户处境的推断，并保留来源链接。",
        parameters: .init(properties: [
            "query": .init(type: "string", description: "脱敏后的心理学研究问题，例如“亲密关系中的回应不一致与关系不确定感有哪些研究发现”"),
        ], required: ["query"])
    ))

    static let manageNarrativeTimeline = ToolDef(function: .init(
        name: "manage_narrative_timeline",
        description: "读取或写入用户叙述中事件实际发生的时间轴，不使用消息发送时间。用户给出明确的具体日期、时间段（如高二期间）或两者混合时使用。若时间归属不清且会影响排序，先向用户提一个澄清问题，不要写入。写入或修改会生成待用户点击确认的原生预览卡片，点击前不得声称已保存；补充旧事件前先 action=list，再用 eventId 更新。",
        parameters: .init(properties: [
            "action": .init(type: "string", description: "list 或 upsert"),
            "eventId": .init(type: "string", description: "更新已有节点时填写 list 返回的 ID；新增留空"),
            "title": .init(type: "string", description: "事件标题，最多24字"),
            "summary": .init(type: "string", description: "去重后的简短事实摘要，最多80字"),
            "startLabel": .init(type: "string", description: "用户表达的开始时间或单一时间节点，如 高二期间、2024年3月12日"),
            "endLabel": .init(type: "string", description: "可选结束时间；单点事件留空"),
            "timeKind": .init(type: "string", description: "period、date 或 mixed"),
            "sortIndex": .init(type: "integer", description: "按经历先后排序的整数，建议10、20、30；插入旧事件可用15等"),
        ], required: ["action"])
    ))
}
