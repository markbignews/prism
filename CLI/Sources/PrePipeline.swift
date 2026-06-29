import Foundation

// MARK: - Unified Pre‑Pipeline (extension of ChatStore)

extension ChatStore {
    // MARK: - Safety Crisis Response

    /// Build a safety intervention response in the user's language.
    /// Called when the pre‑pipeline detects a safety crisis — skips the main model entirely.
    func buildSafetyResponse(signals: [String], hint: String, resources: String, language: AppLanguage) -> String {
        let signalList = signals.map { "• \($0)" }.joined(separator: "\n")
        let resourceBlock = resources.isEmpty ? "" : "\n\n\(resources)"

        switch language {
        case .simplifiedChinese, .traditionalChinese:
            return """
            我听到了你正在经历的事情，也感受到了你的痛苦。

            有些情况需要我们认真对待——你现在不需要故事分析，你需要的是专业的支持。

            检测到的安全信号：
            \(signalList)

            请尽快联系专业的心理援助机构或前往最近的医院急诊科。专业人员能提供你需要的帮助。

            你的安全是最重要的。我暂停叙事分析，这些话题等你安全了再回来聊。你愿意告诉我你现在是否安全吗？
            """
        case .english:
            return """
            I hear what you're going through, and I can feel how much pain you're in.

            This is a moment that calls for professional support, not conversation analysis.

            Safety signals detected:
            \(signalList)
            \(resourceBlock)

            Please reach out to a mental health professional or go to your nearest emergency room. They can provide the help you need.

            Your safety comes first. I'm pausing all narrative analysis. We can talk about these things when you're in a safe place. Can you tell me if you're safe right now?
            """
        }
    }

    /// Save safety crisis context so the next turn's pre‑pipeline can re‑inject it.
    @MainActor
    func saveSafetyContext(for index: Int, hint: String, resources: String) async {
        guard index < conversations.count else { return }
        // Store in UserDefaults so the supervisor can pick it up next round
        UserDefaults.standard.set(true, forKey: "safety.crisis.\(conversations[index].id.uuidString)")
        UserDefaults.standard.set("\(hint)\n\(resources)", forKey: "safety.hint.\(conversations[index].id.uuidString)")
    }

    /// Check if a conversation is in safety crisis mode.
    func hasActiveSafetyCrisis(for conversationID: UUID) -> Bool {
        return UserDefaults.standard.bool(forKey: "safety.crisis.\(conversationID.uuidString)")
    }

    /// Clear safety crisis mode for a conversation.
    func clearSafetyCrisis(for conversationID: UUID) {
        UserDefaults.standard.removeObject(forKey: "safety.crisis.\(conversationID.uuidString)")
        UserDefaults.standard.removeObject(forKey: "safety.hint.\(conversationID.uuidString)")
    }

    // MARK: - Unified Pre‑Pipeline (runs BEFORE main model, 1 Flash call)

    /// Result of the unified pre‑pipeline Flash call.
    struct PrePipelineResult {
        var rawJSON: String = ""
        // Parsed guard signals for supervisor hint
        var guardWarningDimensions: [String] = []   // e.g. ["reality", "spiral"]
        var guardHint: String = ""
        // Safety crisis — separate from normal guard hints, triggers immediate override
        var safetyCrisis: Bool = false
        var safetySignals: [String] = []
        var safetyHint: String = ""
        var safetyResources: String = ""
        // Parsed archive data
        var emotions: [(segment: String, emotion: String, intensity: Double)] = []
        var persons: [(name: String, role: String)] = []
        var blindspotFindings: [(pattern: String, evidence: String, counterQuestion: String)] = []
    }

    /// System prompt for the unified pre‑pipeline Flash call.
    /// Covers guard detection, emotion labeling, person extraction, and blindspot scanning
    /// in a single pass.
    var prePipelineSystemPrompt: String {
        """
        你是一个对话分析系统。分析以下对话，在一次分析中完成所有检测，返回严格的JSON。

        ═══════════════════════════════════════
        一、guard（对话质量守护，5个维度）
        ═══════════════════════════════════════

        1. reality — 用户叙述中「可观察事实」vs「主观解释」的比例。
           事实信号：具体时间/地点/人名、引述原话（"他说……""她回了……"）、可验证行为描述。
           解释信号："我觉得""我认为""应该是""可能是""大概是""说明""意味着""代表着"。
           解释性语言远多于事实描述（比例 > 2.5:1）时 flag = warning。
           hint: 温和建议拉回具体事实层，问一个具体的时间/行为/场景问题。

        2. spiral — 用户是否在同一情绪状态下反复讨论同一话题，没有情感位移。
           有位移（新角度/新行动/强度下降）= ok；原地打转 = warning。
           hint: 建议从分析切换到出口引导，暂停、换个角度、或承认遗憾。

        3. blindspots — 检测三种叙事盲点：
           a) 解释循环：反复用不同措辞解释同一件事
           b) 回避自我：大量描述他人行为，很少描述自己的感受和行动
           c) 意图-行动差距：反复表达意图但缺乏具体行动描述
           每项发现含 pattern / evidence / counter_question / severity(new|recurring|persistent)。
           比对历史盲点判断 severity。无盲点则 flag = ok。

        4. ingratiation — 只检查助手(assistant)最近一轮回复：
           - 过度赞同（连续多个绝对赞同词）
           - 回避挑战（长回复但无不同视角或追问）
           - 镜像无分析（大量复述用户观点但无独立洞察）
           - 过度称赞（频繁使用赞美词）
           严格判断。正常共情不算迎合。无信号时 flag = ok。

        5. action_hollow — 用户当前意图是否与历史盲点模式匹配（说过类似话但未行动）。
           仅当用户表达了新意图且与历史盲点明确对应时才 warning。

        6. safety — 安全信号检测（最高优先级）。
           检测用户消息中是否存在以下安全信号：
           a) 自杀/自伤意图或行为描述
           b) 严重暴力/虐待（用户是受害者或施害者）
           c) 精神错乱状态描述
           d) 未成年人受害场景
           e) 明确求助信号（被囚禁、被控制、极度危险处境）
           只要有明确的安全信号，flag = "crisis"，不得是 ok。
           提供具体的 suggest 告诉主模型应该怎么说，以及可用的求助资源。
           严格判断——宁紧勿松。不确定时不标记 crisis。

        ═══════════════════════════════════════
        二、emotions（情绪标注）
        ═══════════════════════════════════════
        标注用户消息中最显著的1-3个情绪片段。
        每项含 segment（简短摘引）/ emotion（愤怒/悲伤/恐惧/焦虑/释然/希望/困惑/羞耻/孤独）/ intensity（0.0-1.0）。
        不标注不明显的情绪。

        ═══════════════════════════════════════
        三、persons（人物提取）
        ═══════════════════════════════════════
        提取用户消息中提及的真实人物。每项含 name / role(ex-partner/家人/朋友/同事/其他)。
        不输出泛化指代（如"他们""那些人"）。

        注意别名解析：用户可能在不同时间用不同称呼指代同一人。
        如果当前消息中的人物与「已知人物」列表中的某人是同一人（如"我男朋友"→"张伟"→"前任"、或"我妈"→"我母亲"→"妈妈"），
        请使用已知人物的标准 name，不要新建条目。
        不确定是否为同一人时，使用用户当前使用的称呼作为 name。

        ═══════════════════════════════════════
        输出格式 — 严格返回以下JSON，不要包含任何其他文字：
        ═══════════════════════════════════════
        {
          "guard": {
            "reality": {"flag":"ok|warning","ratio":0.0,"interpretive_count":0,"concrete_count":0,"hint":""},
            "spiral": {"flag":"ok|warning","emotion_diversity":0,"intensity_trend":"stable|rising|falling","hint":""},
            "blindspots": {"flag":"ok|warning","findings":[{"pattern":"...","evidence":"...","counter_question":"...","severity":"new|recurring|persistent"}],"hint":""},
            "ingratiation": {"flag":"ok|warning","signals":["..."],"hint":""},
            "action_hollow": {"flag":"ok|warning","matched_count":0,"persistent_count":0,"hint":""},
            "safety": {"flag":"ok|crisis","signals":["..."],"suggest":"","resources":""}
          },
          "emotions": [{"segment":"...","emotion":"...","intensity":0.0}],
          "persons": [{"name":"...","role":"..."}]
        }
        如果某维度正常，flag 为 ok，hint 为空。只标记明确的模式，不猜测。emotions/persons 数组为空时返回 []。
        """
    }

    /// Run the unified pre‑pipeline: one Flash API call covering guard + emotion + person + blindspots.
    func runPrePipeline(for conversationID: UUID, settings: AppSettings) async -> PrePipelineResult {
        var result = PrePipelineResult()
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return result }
        let conv = conversations[index]

        // Gather conversation context
        let recentMessages = conv.messages
            .filter { $0.role == .user || $0.role == .assistant }
            .suffix(10)
        let conversationText = recentMessages
            .map { "[\($0.role.rawValue)] \($0.content)" }
            .joined(separator: "\n\n")

        // Skip for trivial messages
        let lastUserText = conv.messages.last(where: { $0.role == .user })?.content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard lastUserText.count >= 5 else { return result }

        // Skip on first exchange: no assistant reply exists yet, so ingratiation
        // has nothing to check, spiral has no history, and action_hollow has no
        // blindspot baseline. Emotions and persons will be richer starting from
        // the second exchange (2 user msgs + 1 assistant reply).
        let hasAssistantReply = conv.messages.contains(where: {
            $0.role == .assistant && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
        guard hasAssistantReply else { return result }

        // Build user content with context
        let knownPersons = personArchive.map { "\($0.name)(\($0.role))" }.joined(separator: ", ")
        let blindspotsHistory = blindspots.isEmpty
            ? "（无历史盲点记录）"
            : blindspots.map { "- [\($0.severity)] \($0.pattern): \($0.evidence)" }.joined(separator: "\n")

        // Check for active safety crisis context from previous turns
        let safetyContext: String
        if hasActiveSafetyCrisis(for: conversationID),
           let hint = UserDefaults.standard.string(forKey: "safety.hint.\(conversationID.uuidString)") {
            safetyContext = "\n\n⚠️ 上轮对话已触发安全干预，本轮继续在安全模式运行。上一轮的安全建议：\n\(hint)\n请判断用户当前是否仍处于危险中，还是已脱离危险。"
        } else {
            safetyContext = ""
        }

        let userContent = """
        最近对话：
        \(conversationText)

        已知人物：\(knownPersons.isEmpty ? "（无）" : knownPersons)

        历史盲点记录（用于 action_hollow 比对和 blindspots 严重程度判断）：
        \(blindspotsHistory)
        \(safetyContext)
        """

        let client = DeepSeekClient(
            apiKey: settings.apiKey,
            baseURL: settings.baseURL,
            model: settings.flashModel,
            parameters: settings.flashParameters,
            language: settings.language
        )

        do {
            let raw = try await client.summarize(systemPrompt: prePipelineSystemPrompt, userContent: userContent)
            result.rawJSON = raw
            parsePrePipelineJSON(raw, into: &result, conversationID: conversationID)
        } catch {
            print("[PrePipeline] ⚠ Flash API error: \(error.localizedDescription)")
        }

        return result
    }

    /// Build a supervisor hint string from guard warnings.
    func buildGuardHint(from result: PrePipelineResult) -> String? {
        guard !result.guardHint.isEmpty else { return nil }
        return result.guardHint
    }

    /// Apply pre‑pipeline results to local archives (detached, non‑blocking).
    func applyPrePipelineResults(_ result: PrePipelineResult, for conversationID: UUID) async {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        let conv = conversations[index]

        // Merge emotions
        for e in result.emotions {
            emotionTimeline.append(EmotionEntry(
                conversationID: conversationID,
                segment: e.segment,
                emotion: e.emotion,
                intensity: e.intensity
            ))
        }
        if emotionTimeline.count > 200 { emotionTimeline = Array(emotionTimeline.suffix(200)) }

        // Merge persons (cap at 200 unique entries)
        for p in result.persons {
            if let idx = personArchive.firstIndex(where: { $0.name == p.name }) {
                personArchive[idx].lastMentionedAt = Date()
                personArchive[idx].mentionCount += 1
                personArchive[idx].notes.append("\(conv.title): \(p.role)")
            } else {
                personArchive.append(PersonRecord(
                    name: p.name,
                    role: p.role,
                    firstMentionedAt: Date(),
                    lastMentionedAt: Date()
                ))
            }
        }
        // Trim: keep 200 most recently mentioned persons
        if personArchive.count > 200 {
            personArchive.sort { ($0.lastMentionedAt ?? .distantPast) > ($1.lastMentionedAt ?? .distantPast) }
            personArchive = Array(personArchive.prefix(200))
        }

        // Merge blindspots
        for f in result.blindspotFindings {
            var severity = "new"
            if let existing = blindspots.first(where: { $0.pattern == f.pattern }) {
                severity = existing.severity == "persistent" ? "persistent" : "recurring"
            }
            blindspots.append(BlindspotRecord(
                conversationID: conversationID,
                pattern: f.pattern,
                evidence: f.evidence,
                counterQuestion: f.counterQuestion,
                severity: severity
            ))
        }
        // Trim: keep 300 most recent blindspots
        if blindspots.count > 300 {
            blindspots.sort { $0.createdAt > $1.createdAt }
            blindspots = Array(blindspots.prefix(300))
        }

        saveArchives()
    }

    // MARK: - Pre‑Pipeline JSON Parser

    func parsePrePipelineJSON(_ text: String, into result: inout PrePipelineResult, conversationID: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract JSON object — Flash may wrap in markdown or add surrounding text
        func extractJSON(_ s: String) -> String? {
            // Direct JSON
            if s.hasPrefix("{") { return s }
            // Markdown code block
            if let start = s.range(of: "```json"),
               let end = s.range(of: "```", range: start.upperBound..<s.endIndex) {
                let inner = String(s[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if inner.hasPrefix("{") { return inner }
            }
            if let start = s.range(of: "```"),
               let end = s.range(of: "```", range: start.upperBound..<s.endIndex) {
                let inner = String(s[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if inner.hasPrefix("{") { return inner }
            }
            // Find braces
            if let first = s.range(of: "{"), let last = s.range(of: "}", options: .backwards) {
                return String(s[first.lowerBound...last.lowerBound])
            }
            return nil
        }

        guard let jsonStr = extractJSON(trimmed),
              let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[PrePipeline] ⚠ Could not parse JSON from response")
            return
        }

        // ── Parse guard ──
        if let guardObj = obj["guard"] as? [String: Any] {
            var warnings: [String] = []
            var hints: [String] = []
            let dims = ["reality", "spiral", "blindspots", "ingratiation", "action_hollow"]
            for dim in dims {
                if let d = guardObj[dim] as? [String: Any],
                   let flag = d["flag"] as? String, flag == "warning" {
                    warnings.append(dim)
                    if let hint = d["hint"] as? String, !hint.isEmpty {
                        hints.append("[\(dim)] \(hint)")
                    }
                }
            }
            result.guardWarningDimensions = warnings
            result.guardHint = hints.joined(separator: "\n")

            // ── Parse safety crisis (special: overrides normal flow) ──
            if let safetyObj = guardObj["safety"] as? [String: Any],
               let flag = safetyObj["flag"] as? String {
                if flag == "crisis" {
                    result.safetyCrisis = true
                    result.safetySignals = (safetyObj["signals"] as? [String]) ?? []
                    result.safetyHint = (safetyObj["suggest"] as? String) ?? "立即进行安全干预。"
                    result.safetyResources = (safetyObj["resources"] as? String) ?? ""
                } else if flag == "ok" && hasActiveSafetyCrisis(for: conversationID) {
                    // Auto-clear: user is no longer in crisis
                    clearSafetyCrisis(for: conversationID)
                    print("[Safety] Crisis cleared for conversation \(conversationID)")
                }
            }
        }

        // ── Parse emotions ──
        if let emotions = obj["emotions"] as? [[String: Any]] {
            result.emotions = emotions.compactMap { e in
                guard let seg = e["segment"] as? String,
                      let emo = e["emotion"] as? String,
                      let int = e["intensity"] as? Double else { return nil }
                return (seg, emo, int)
            }
        }

        // ── Parse persons ──
        if let persons = obj["persons"] as? [[String: Any]] {
            result.persons = persons.compactMap { p in
                guard let n = p["name"] as? String,
                      let r = p["role"] as? String else { return nil }
                return (n, r)
            }
        }

        // ── Parse blindspot findings from guard ──
        if let guardObj = obj["guard"] as? [String: Any],
           let blindspotsObj = guardObj["blindspots"] as? [String: Any],
           let findings = blindspotsObj["findings"] as? [[String: Any]] {
            result.blindspotFindings = findings.compactMap { f in
                guard let p = f["pattern"] as? String,
                      let e = f["evidence"] as? String,
                      let q = f["counter_question"] as? String else { return nil }
                return (p, e, q)
            }
        }

        print("[PrePipeline] guard:\(result.guardWarningDimensions.count)warnings emotions:\(result.emotions.count) persons:\(result.persons.count) blindspots:\(result.blindspotFindings.count)")
    }

}
