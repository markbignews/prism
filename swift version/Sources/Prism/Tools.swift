import Foundation

// MARK: - Tool Registry

/// Retrieval and evidence tools available to the main model. Local tools read
/// the app's archives; search_web calls only DeepSeek's official search
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
        .searchWeb,
        .manageNarrativeTimeline,
        .requestUserInput,
    ]

    /// A new chat can retrieve other conversations from its very first turn.
    static func availableDefinitions(baseURL: String, includeHistory: Bool = true) -> [ToolDef] {
        let officialSearch = URL(string: baseURL)?.host?.lowercased() == "api.deepseek.com"
        return definitions.filter { tool in
            let name = tool.function.name
            if name == "search_web", !officialSearch { return false }
            return includeHistory || ["search_web", "search_memory", "search_chapters", "fetch_chapter_messages", "manage_narrative_timeline", "request_user_input"].contains(name)
        }
    }

    // MARK: - Memory Search

    @MainActor private static func searchMemory(query: String, store: ChatAgent, limit: Int) -> String {
        let entries = store.searchMemory(query: query, limit: limit)
        return encodeMemoryResults(entries, store: store)
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
            print("[ToolRegistry] ⚠ invalid UTF-8 or malformed JSON arguments")
            args = [:]
        }

        let result: String
        switch name {
        case "track_person":
            result = trackPerson(name: args["name"] ?? "", store: store)
        case "emotion_timeline":
            let n = min(10, max(1, Int(args["count"] ?? "5") ?? 5))
            result = emotionTimeline(count: n, store: store)
        case "search_chapters":
            if settings != nil {
                let n = min(10, max(1, Int(args["count"] ?? "5") ?? 5))
                let chapters = await store.searchChaptersSemantic(query: args["query"] ?? "", limit: n)
                result = buildChapterResults(chapters: chapters.map(\.chapter), store: store)
            } else {
                result = searchChapters(query: args["query"] ?? "", store: store)
            }
        case "fetch_chapter_messages":
            result = fetchChapterMessages(args: args, store: store)
        case "search_memory":
            let n = min(20, max(1, Int(args["count"] ?? "10") ?? 10))
            if settings != nil {
                let entries = await store.searchMemorySemantic(query: args["query"] ?? "", limit: n)
                result = encodeMemoryResults(entries, store: store)
            } else {
                result = searchMemory(query: args["query"] ?? "", store: store, limit: n)
            }
        case "search_web", "search_psychology": // Replay compatibility for older tool exchanges.
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
        if name == "search_web" || name == "search_psychology" {
            print("[Tool] \(name) | query omitted | result: \(result.count) characters")
        } else {
            let preview = result.count > 120 ? String(result.prefix(120)) + "…" : result
            print("[Tool] \(name) | args: \(arguments.prefix(80)) | → \(preview)")
        }

        return result
    }

    @MainActor private static func manageNarrativeTimeline(args: [String: String], store: ChatAgent) -> String {
        let action = args["action"] ?? "list"
        if action == "list" {
            let events = store.narrativeEvents(for: store.activeToolConversationID ?? store.selectedConversationID).map { original in
                var event = original
                event.wording = nil // Display rewrites are not new source evidence.
                return event
            }
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
    @MainActor private static func encodeMemoryResults(_ entries: [MemoryEntry], store: ChatAgent) -> String {
        let results: [[String: Any]] = entries.map { entry in
            let conversation = store.conversations.first { $0.id == entry.sourceConversationID }
            return [
                "memoryId": entry.id.uuidString,
                "sourceConversationId": entry.sourceConversationID.uuidString,
                "sourceConversationTitle": conversation?.title ?? NSNull(),
                "sourceMessageIds": entry.sourceMessageIDs?.map(\.uuidString) ?? [],
                "evidenceStatus": entry.evidenceStatus ?? "model_inferred",
                "timeSpanStart": entry.timeSpanStart?.ISO8601Format() ?? NSNull(),
                "timeSpanEnd": entry.timeSpanEnd?.ISO8601Format() ?? NSNull(),
                "identityConfirmed": false, // A memory hit is not an identity link.
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
        if let rawID = args["memory_id"] {
            guard let id = UUID(uuidString: rawID),
                  let entry = store.memoryStore.first(where: { $0.id == id }),
                  let conversation = store.conversations.first(where: { $0.id == entry.sourceConversationID }) else {
                return #"{"error":"memory source not found"}"#
            }
            let sourceIDs = Set(entry.sourceMessageIDs ?? [])
            // Legacy memories may have no message IDs; only use the matching
            // chapter, never the whole conversation as purported source evidence.
            let legacyIDs = Set(conversation.chapters.first { $0.title == entry.sourceChapterTitle }?.messageIDs ?? [])
            let ids = sourceIDs.isEmpty ? legacyIDs : sourceIDs
            let originals = conversation.messages.filter { $0.role == .user && ids.contains($0.id) }
            let messages: [[String: Any]] = originals.prefix(12).map {
                ["id": $0.id.uuidString, "role": $0.role.rawValue, "content": String($0.content.prefix(6000)),
                 "truncated": $0.content.count > 6000, "sentAt": $0.createdAt.ISO8601Format()]
            }
            let payload: [String: Any] = [
                "memoryId": entry.id.uuidString,
                "sourceConversationId": conversation.id.uuidString,
                "sourceConversationTitle": conversation.title,
                "messages": messages,
                "sourcesMissing": originals.isEmpty || (!sourceIDs.isEmpty && Set(originals.map(\.id)) != sourceIDs),
                "truncated": originals.count > 12 || originals.contains { $0.content.count > 6000 }
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let string = String(data: data, encoding: .utf8) else { return "{}" }
            return string
        }
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
        let msgs = store.messages(for: chapter).filter { $0.role == .user }
        let conversation = store.conversations.first { $0.chapters.contains { $0.id == chapter.id } }
        let messageList: [[String: Any]] = msgs.prefix(12).map { msg in
            ["id": msg.id.uuidString, "role": msg.role.rawValue, "content": String(msg.content.prefix(6000)),
             "sentAt": msg.createdAt.ISO8601Format(), "truncated": msg.content.count > 6000]
        }

        let result: [String: Any] = [
            "sourceConversationId": conversation?.id.uuidString ?? NSNull(),
            "sourceConversationTitle": conversation?.title ?? NSNull(),
            "sourcesMissing": msgs.isEmpty,
            "truncated": msgs.count > 12 || msgs.contains { $0.content.count > 6000 },
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
        description: "需要询问细节、确认是哪种情况或区分多种可能时，优先用此工具给出一个简短中性问题与2至4个具体易选的选项。若要问情况A还是情况B、前者还是后者，直接用卡片，不要在正文要求用户手打选项或口令。客户端会暂停本轮分析，展示包含选项与手动补充的紧凑追问卡片；只有收到用户答案后才继续。鼓励用卡片降低补充门槛，但不要重复已知信息或为问而问；不把推断当事实，不让用户选病名来确诊，适合时提供两者都有、都不符合或不确定。不必生成其他或手动输入选项，界面始终支持自由输入。使用用户的语言。本次不要同时调用其他工具。",
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
        description: "检索所有对话的历史章节，第一轮即可由模型自主选择。按关键词匹配，返回来源对话、章节编号、摘要和关键词；需要原话时用 fetch_chapter_messages(index)核对。可以换关键词重试，命中不代表人物身份已确认。",
        parameters: .init(properties: [
            "query": .init(type: "string", description: "搜索关键词，留空返回最近5章"),
            "count": .init(type: "integer", description: "返回条数，默认5"),
        ], required: ["query"])
    ))

    static let fetchChapterMessages = ToolDef(function: .init(
        name: "fetch_chapter_messages",
        description: "获取历史依据的原始用户消息：传 index 读取章节，或传 search_memory 返回的 memoryId 为 memory_id 读取该记忆的来源。两者选一。摘要不是独立证据；缺失或截断会明确标记。",
        parameters: .init(properties: [
            "index": .init(type: "integer", description: "章节序号（从1开始），在章节索引中可看到章节编号"),
            "memory_id": .init(type: "string", description: "search_memory 返回的 memoryId，用于核对原话；与 index 二选一"),
        ], required: nil)
    ))

    static let searchMemory = ToolDef(function: .init(
        name: "search_memory",
        description: "检索所有对话的长期记忆，第一轮即可使用，由模型根据上下文自主决定。返回摘要、来源对话、原话ID和memoryId；用 fetch_chapter_messages(memory_id)核对来源。结果只是候选依据，命中姓名或相似经历不证明是同一个人；身份不清时用选项卡确认，不能混用不同人的经历。query用简短的人名、别名或事件词，可换词重试；不是向量语义搜索。",
        parameters: .init(properties: [
            "query": .init(type: "string", description: "搜索关键词或短语，留空返回最近记忆"),
            "count": .init(type: "integer", description: "返回条数，默认10"),
        ], required: ["query"])
    ))

    static let searchWeb = ToolDef(function: .init(
        name: "search_web",
        description: "供模型自主选择的联网核查工具。根据完整上下文、已有依据、时效性、不确定性及检索价值决定是否调用；不按关键词或固定类别触发，不要求用户先说联网，第一轮也可选择。可核查个人关系、情绪、心理健康、睡眠压力或生活背景相关的研究、事实、平台功能、公开规则、近期事件与非即时危机的支持信息；这些只是能力范围示例，不代表一律搜索。仅使用 DeepSeek 官方搜索。查询必须最小必要并脱敏，不含姓名、联系方式、账号和可识别细节；不检索具体身边人物或证明其诊断、人格、动机。不为办公文档、代码或其他生产交付任务检索。即时危险时不要调用搜索延误支持。返回后保留来源链接和日期，区分证据与推断，失败时不得声称已核实。",
        parameters: .init(properties: [
            "query": .init(type: "string", description: "脱敏后的中性核查问题，例如“回应不一致与关系不确定感的研究”“某社交平台当前的公开消息隐私设置说明”；不包含用户私密经历"),
        ], required: ["query"])
    ))

    static let manageNarrativeTimeline = ToolDef(function: .init(
        name: "manage_narrative_timeline",
        description: "从用户自然讲述的对话中识别关键经历、阶段转折或重要更正，主动提出是否加入时间轴，无需用户先要求添加。发现有明确时间归属的新关键节点时，从原话提取标题、一两句简短事件描述和时间阶段；多个关键经历分别生成节点。先list去重，没有新事实的旧节点不重复提议，已有节点用eventId更新。保留高二期间、后来等明确的相对阶段，不使用消息发送时间补日期。时间归属不清且影响排序时先澄清。upsert仅生成待确认的原生预览，必须由用户点击保存才写入；尊重用户拒绝记录的选择。",
        parameters: .init(properties: [
            "action": .init(type: "string", description: "list 或 upsert"),
            "eventId": .init(type: "string", description: "更新已有节点时填写 list 返回的 ID；新增留空"),
            "title": .init(type: "string", description: "事件标题，最多24字"),
            "summary": .init(type: "string", description: "统一写成原有时间阶段＋谁做了什么＋明确变化的一到两句自然句，用户本人的经历称你，保留主体及不确定性，不补动机或因果，最多80字"),
            "startLabel": .init(type: "string", description: "用户表达的开始时间或单一时间节点，如 高二期间、2024年3月12日"),
            "endLabel": .init(type: "string", description: "可选结束时间；单点事件留空"),
            "timeKind": .init(type: "string", description: "period、date 或 mixed"),
            "sortIndex": .init(type: "integer", description: "按经历先后排序的整数，建议10、20、30；插入旧事件可用15等"),
        ], required: ["action"])
    ))
}
