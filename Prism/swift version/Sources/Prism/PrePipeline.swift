import Foundation

struct PersonTraitFinding: Equatable {
    var pattern: String
    var evidence: String
    var confidence: Double
    var scope: String
}

struct PersonFinding: Equatable {
    var name: String
    var mention: String
    var role: String
    var traits: [PersonTraitFinding]
    var matchedPersonID: UUID?
    var matchConfidence: Double
    var isSelf: Bool
}

// MARK: - Unified Pre‑Pipeline (extension of ChatStore)

extension ChatAgent {
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

    /// Do not silently continue with ordinary relationship analysis when the
    /// safety pass failed or returned an incomplete result.
    func buildSafetyUncertaintyResponse(language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese:
            return "我暂时无法可靠完成安全判断，所以先不做关系分析。如果你现在有自伤、伤人、暴力、胁迫或无法离开的风险，请先联系当地急救服务、可信任的人或最近的急诊。你现在是否处于安全环境？"
        case .traditionalChinese:
            return "我暫時無法可靠完成安全判斷，所以先不做關係分析。如果你現在有自傷、傷人、暴力、脅迫或無法離開的風險，請先聯絡當地急救服務、可信任的人或最近的急診。你現在是否處於安全環境？"
        case .english:
            return "I could not reliably complete the safety check, so I will pause relationship analysis for now. If there is any risk of self-harm, harm to others, violence, coercion, or being unable to leave, contact local emergency services, someone you trust, or the nearest emergency department. Are you currently in a safe place?"
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
        var safetyUncertain: Bool = false
        var safetySignals: [String] = []
        var safetyHint: String = ""
        var safetyResources: String = ""
        // Parsed archive data
        var emotions: [(segment: String, emotion: String, intensity: Double, confidence: Double?)] = []
        var persons: [PersonFinding] = []
        var blindspotFindings: [(pattern: String, evidence: String, counterQuestion: String)] = []
    }

    /// System prompt for the unified pre‑pipeline Flash call.
    /// Covers guard detection, emotion labeling, person extraction, and blindspot scanning
    /// in a single pass.
    var prePipelineSystemPrompt: String {
        """
        你是一个对话分析系统。分析以下对话，在一次分析中完成所有检测，返回严格的JSON。
        每条消息的 sentAt 是画像证据：用于判断昼夜时段、消息间隔、作息与情绪趋势。它不是用户所述事件的发生时间，除非用户明确这样说。

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
           hint: 建议从分析切换到下一步引导，暂停、换个角度、或承认遗憾。

           3. blindspots — 只检测可供用户检验的暂时性模式假设：
           a) 解释循环：反复用不同措辞解释同一件事
           b) 回避自我：大量描述他人行为，很少描述自己的感受和行动
           c) 意图-行动差距：反复表达意图但缺乏具体行动描述
           每项发现含 pattern / evidence / counter_question / severity(new|recurring|persistent)。不要诊断、不要给用户贴标签；历史结果只能作为待验证假设。
           比对历史盲点判断 severity。无盲点则 flag = ok。

        4. ingratiation — 只检查助手(assistant)最近一轮回复：
           - 过度赞同（连续多个绝对赞同词）
           - 回避挑战（长回复但无不同视角或追问）
           - 镜像无分析（大量复述用户观点但无独立洞察）
           - 过度称赞（频繁使用赞美词）
           严格判断。正常共情不算迎合。无信号时 flag = ok。

        5. action_hollow — 用户当前意图是否与历史记录显示出可能的行动障碍或矛盾（不要称为“空头承诺”）。
           仅当用户表达了新意图且与历史记录明确对应时才 warning；优先探索阻碍和矛盾，不要施压。

        6. safety — 安全信号检测（最高优先级）。
           检测用户消息中是否存在以下安全信号：
           a) 自杀/自伤意图或行为描述
           b) 严重暴力/虐待（用户是受害者或施害者）
           c) 精神错乱状态描述
           d) 未成年人受害场景
           e) 明确求助信号（被囚禁、被控制、极度危险处境）
           明确的安全信号 flag = "crisis"；明确没有安全信号 flag = "ok"；证据不足、输出不完整或无法判断 flag = "uncertain"，不得假装安全。
           提供具体的 suggest 告诉主模型应该怎么说，以及可用的求助资源。
           严格判断，不把普通悲伤、冲突或非主流表达自动标成危机。

        ═══════════════════════════════════════
        二、emotions（情绪标注）
        ═══════════════════════════════════════
        标注用户消息中最显著的1-3个情绪片段。
        每项含 segment（简短摘引）/ emotion（愤怒/悲伤/恐惧/焦虑/释然/希望/困惑/羞耻/孤独）/ intensity（0.0-1.0，粗略估计）/ confidence（0.0-1.0，可选）。
        不标注不明显的情绪。

        ═══════════════════════════════════════
        三、persons（人物与疑似行为模式提取）
        ═══════════════════════════════════════
        提取用户消息中提及的真实人物。每项含 mention（当前称呼）/ name（规范名称）/ role(ex-partner/家人/朋友/同事/其他)，role 必须来自用户原话或明确上下文，不要自行推断。
        不输出泛化指代（如"他们""那些人"）。

        注意自然共指和别名解析：用户可能不会明确说“这是同一个人”，而是自然地从姓名切换到昵称、关系称呼、代词或新称呼。
        结合最近对话中的行为、关系、时间和已知别名判断是否指向同一人。若确定指向已知人物，输出该人物的 person_id 和规范 name，并把当前称呼放入 mention；不要新建条目。
        只有在匹配置信度至少 0.75 时才输出 person_id；不确定时 person_id=null、match_confidence<0.75，并使用当前称呼作为 name。不要为了减少条目而强行合并两个可能不同的人。
        如果人物是用户本人（例如“我叫小王”“大家现在叫我小李”），speaker 输出 self；其他人物输出 other。

        对每个人物，可选地提取当前对话中有具体证据支持的行为模式。只使用以下 pattern ID，不要创造人格、心理疾病或依恋类型标签：
        - control_autonomy：控制或限制对方自主
        - communication_withdrawal：回避沟通、冷处理或消失
        - invalidates_feelings：贬低、否定或无视感受
        - boundary_violation：无视明确表达的边界、同意或拒绝
        - guilt_pressure：通过愧疚、威胁失望或施压来推动对方
        - promise_action_mismatch：承诺与实际行动持续不一致
        - threat_or_coercion：有明确的威胁、胁迫或强迫行为
        只有当当前上下文包含可观察行为时才输出 traits；用户的结论、一次模糊的不适或单纯的性格猜测不算证据。每项 trait 必须含 pattern / evidence / confidence(0.0-1.0) / scope(single_event|repeated_pattern)。evidence 是简短的原话或具体行为概述，不要编造；confidence 是证据强度，不是概率或诊断分数。所有 traits 都只是 suspected，留给用户确认。没有足够证据时 traits 返回 []。

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
            "safety": {"flag":"ok|uncertain|crisis","signals":["..."],"suggest":"","resources":""}
          },
          "emotions": [{"segment":"...","emotion":"...","intensity":0.0,"confidence":0.0}],
          "persons": [{"mention":"...","name":"...","role":"...","speaker":"other","person_id":null,"match_confidence":0.0,"traits":[{"pattern":"...","evidence":"...","confidence":0.0,"scope":"single_event"}]}]
        }
        如果某维度正常，flag 为 ok，hint 为空。只标记明确的模式，不猜测。emotions/persons 数组为空时返回 []。
        """
    }

    /// Run the unified pre‑pipeline: one Flash API call covering guard + emotion + person + blindspots.
    func runPrePipeline(for conversationID: UUID, requestSentAt: Date, settings: AppSettings) async -> PrePipelineResult {
        var result = PrePipelineResult()
        result.safetyUncertain = true
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return result }
        let conv = conversations[index]

        // Gather conversation context
        let recentMessages = conv.messages
            .filter { $0.role == .user || $0.role == .assistant }
            .suffix(10)
        let conversationText = recentMessages
            .map { "[\($0.role.rawValue)][sentAt=\(AgentPrompt.transcriptTimestamp($0.createdAt))] \($0.content)" }
            .joined(separator: "\n\n")

        // Run the safety pass even on the first and very short turns. A short
        // message can still contain an urgent signal (for example, “救我”).
        let lastUserText = conv.messages.last(where: { $0.role == .user })?.content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !lastUserText.isEmpty else {
            result.safetyUncertain = true
            return result
        }

        // Build user content with context
        let knownPersons = personArchive
            .filter { $0.conversationIDs?.contains(conversationID) == true }
            .map { person in
                let aliases = person.aliases.isEmpty ? "（无别名）" : person.aliases.joined(separator: "、")
                let speaker = person.isSelf ? "self" : "other"
                return "- person_id=\(person.id.uuidString) canonical=\(person.name) aliases=[\(aliases)] speaker=\(speaker) role=\(person.role)"
            }
            .joined(separator: "\n")
        let currentBlindspots = blindspots.filter { $0.conversationID == conversationID }
        let blindspotsHistory = currentBlindspots.isEmpty
            ? "（无历史盲点记录）"
            : currentBlindspots.map { "- [暂定-\($0.severity)] \($0.pattern): \($0.evidence)" }.joined(separator: "\n")

        // Check for active safety crisis context from previous turns
        let safetyContext: String
        if hasActiveSafetyCrisis(for: conversationID),
           let hint = UserDefaults.standard.string(forKey: "safety.hint.\(conversationID.uuidString)") {
            safetyContext = "\n\n⚠️ 上轮对话已触发安全干预，本轮继续在安全模式运行。上一轮的安全建议：\n\(hint)\n请判断用户当前是否仍处于危险中，还是已脱离危险。"
        } else {
            safetyContext = ""
        }

        let userContent = """
        \(AgentPrompt.requestTimeContext(sentAt: requestSentAt, language: settings.language))

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
            if !parsePrePipelineJSON(raw, into: &result, conversationID: conversationID) {
                result.safetyUncertain = true
            }
        } catch {
            print("[PrePipeline] ⚠ Flash API error: \(error.localizedDescription)")
            result.safetyUncertain = true
        }

        return result
    }

    /// Build a supervisor hint string from guard warnings.
    func buildGuardHint(from result: PrePipelineResult) -> String? {
        guard !result.guardHint.isEmpty else { return nil }
        return result.guardHint
    }

    /// Apply pre‑pipeline results to local archives (detached, non‑blocking).
    func applyPrePipelineResults(_ result: PrePipelineResult, for conversationID: UUID, requestSentAt: Date) async {
        // Do not persist inferred profiles or relationship hypotheses when the
        // safety pass was incomplete or the turn was escalated to crisis mode.
        guard !result.safetyUncertain, !result.safetyCrisis else { return }
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        let conv = conversations[index]

        // Merge emotions
        for e in result.emotions {
            emotionTimeline.append(EmotionEntry(
                conversationID: conversationID,
                segment: e.segment,
                emotion: e.emotion,
                intensity: e.intensity,
                confidence: e.confidence,
                createdAt: requestSentAt
            ))
        }
        if emotionTimeline.count > 200 { emotionTimeline = Array(emotionTimeline.suffix(200)) }

        // Merge persons (cap at 200 unique entries)
        for p in result.persons {
            let mention = p.mention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? p.name : p.mention
            let incomingTraits = p.traits.map { finding in
                PersonTraitRecord(
                    pattern: finding.pattern,
                    evidence: [finding.evidence],
                    confidence: finding.confidence,
                    scope: finding.scope,
                    status: "suspected",
                    occurrenceCount: 1,
                    firstObservedAt: requestSentAt,
                    lastObservedAt: requestSentAt
                )
            }
            let resolvedIndex = personArchive.firstIndex { person in
                guard person.conversationIDs?.contains(conversationID) == true,
                      person.isSelf == p.isSelf else { return false }
                if let matchedID = p.matchedPersonID,
                   p.matchConfidence >= 0.75,
                   person.id == matchedID {
                    return true
                }
                let labels = [person.name] + person.aliases
                return labels.contains { normalizedPersonLabel($0) == normalizedPersonLabel(p.name) }
                    || labels.contains { normalizedPersonLabel($0) == normalizedPersonLabel(mention) }
            }
            if let idx = resolvedIndex {
                personArchive[idx].lastMentionedAt = requestSentAt
                personArchive[idx].mentionCount += 1
                personArchive[idx].notes.append("\(conv.title): \(p.role)")
                if !mention.isEmpty,
                   normalizedPersonLabel(mention) != normalizedPersonLabel(personArchive[idx].name),
                   !personArchive[idx].aliases.contains(where: { normalizedPersonLabel($0) == normalizedPersonLabel(mention) }) {
                    personArchive[idx].aliases.append(mention)
                    personArchive[idx].aliases = Array(personArchive[idx].aliases.suffix(12))
                }
                mergePersonTraits(&personArchive[idx].traits, incoming: incomingTraits)
            } else {
                personArchive.append(PersonRecord(
                    name: p.name,
                    role: p.role,
                    firstMentionedAt: requestSentAt,
                    lastMentionedAt: requestSentAt,
                    aliases: mention == p.name ? [] : [mention],
                    isSelf: p.isSelf,
                    traits: incomingTraits,
                    conversationIDs: [conversationID]
                ))
            }
        }
        // Trim: keep 200 most recently mentioned persons
        if personArchive.count > 200 {
            personArchive.sort { $0.lastMentionedAt > $1.lastMentionedAt }
            personArchive = Array(personArchive.prefix(200))
        }

        // Merge blindspots
        for f in result.blindspotFindings {
            var severity = "new"
            if let existing = blindspots.first(where: {
                $0.conversationID == conversationID && $0.pattern == f.pattern
            }) {
                severity = existing.severity == "persistent" ? "persistent" : "recurring"
            }
            blindspots.append(BlindspotRecord(
                conversationID: conversationID,
                pattern: f.pattern,
                evidence: f.evidence,
                counterQuestion: f.counterQuestion,
                severity: severity,
                createdAt: requestSentAt
            ))
        }
        // Trim: keep 300 most recent blindspots
        if blindspots.count > 300 {
            blindspots.sort { $0.createdAt > $1.createdAt }
            blindspots = Array(blindspots.prefix(300))
        }

        saveArchives()
    }

    private func normalizedPersonLabel(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Merge behavior-pattern observations without turning them into confirmed labels.
    private func mergePersonTraits(_ existing: inout [PersonTraitRecord], incoming: [PersonTraitRecord]) {
        for observation in incoming {
            guard !observation.pattern.isEmpty, !observation.evidence.isEmpty else { continue }
            if let index = existing.firstIndex(where: { $0.pattern == observation.pattern }) {
                let previousCount = max(existing[index].occurrenceCount, 1)
                let newCount = previousCount + 1
                existing[index].confidence = ((existing[index].confidence * Double(previousCount)) + observation.confidence) / Double(newCount)
                existing[index].occurrenceCount = newCount
                existing[index].lastObservedAt = observation.lastObservedAt
                existing[index].scope = newCount > 1 || observation.scope == "repeated_pattern" ? "repeated_pattern" : "single_event"
                existing[index].status = "suspected"
                for snippet in observation.evidence where !existing[index].evidence.contains(snippet) {
                    existing[index].evidence.append(snippet)
                }
                existing[index].evidence = Array(existing[index].evidence.suffix(5))
            } else {
                existing.append(observation)
            }
        }
        existing.sort { $0.lastObservedAt > $1.lastObservedAt }
        existing = Array(existing.prefix(8))
    }

    // MARK: - Pre‑Pipeline JSON Parser

    @discardableResult
    func parsePrePipelineJSON(_ text: String, into result: inout PrePipelineResult, conversationID: UUID) -> Bool {
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
            return false
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
                    result.safetyUncertain = false
                } else if flag == "ok" && hasActiveSafetyCrisis(for: conversationID) {
                    // Auto-clear: user is no longer in crisis
                    clearSafetyCrisis(for: conversationID)
                    print("[Safety] Crisis cleared for conversation \(conversationID)")
                    result.safetyUncertain = false
                } else if flag == "ok" {
                    result.safetyUncertain = false
                } else {
                    result.safetyUncertain = true
                }
            } else {
                result.safetyUncertain = true
            }
        } else {
            result.safetyUncertain = true
        }

        // ── Parse emotions ──
        if let emotions = obj["emotions"] as? [[String: Any]] {
            result.emotions = emotions.compactMap { e in
                guard let seg = e["segment"] as? String,
                      let emo = e["emotion"] as? String,
                      let int = e["intensity"] as? Double else { return nil }
                let confidence = (e["confidence"] as? Double).map { min(max($0, 0), 1) }
                return (seg, emo, int, confidence)
            }
        }

        // ── Parse persons and evidence-backed behavior patterns ──
        if let persons = obj["persons"] as? [[String: Any]] {
            result.persons = persons.compactMap { p -> PersonFinding? in
                guard let n = p["name"] as? String,
                      let r = p["role"] as? String else { return nil }
                let allowedPatterns: Set<String> = [
                    "control_autonomy",
                    "communication_withdrawal",
                    "invalidates_feelings",
                    "boundary_violation",
                    "guilt_pressure",
                    "promise_action_mismatch",
                    "threat_or_coercion"
                ]
                let traits = (p["traits"] as? [[String: Any]] ?? []).compactMap { trait -> PersonTraitFinding? in
                    guard let pattern = trait["pattern"] as? String,
                          allowedPatterns.contains(pattern),
                          let evidence = trait["evidence"] as? String,
                          !evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                    let scope = (trait["scope"] as? String) == "repeated_pattern" ? "repeated_pattern" : "single_event"
                    let confidence = min(max(trait["confidence"] as? Double ?? 0.0, 0.0), 1.0)
                    return PersonTraitFinding(
                        pattern: pattern,
                        evidence: String(evidence.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240)),
                        confidence: confidence,
                        scope: scope
                    )
                }
                let mention: String = {
                    guard let raw = p["mention"] as? String else { return n }
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? n : trimmed
                }()
                let matchedPersonID = (p["person_id"] as? String).flatMap(UUID.init(uuidString:))
                let matchConfidence = min(max(p["match_confidence"] as? Double ?? 0.0, 0.0), 1.0)
                let isSelf = (p["speaker"] as? String)?.lowercased() == "self"
                return PersonFinding(
                    name: n,
                    mention: mention,
                    role: r,
                    traits: traits,
                    matchedPersonID: matchedPersonID,
                    matchConfidence: matchConfidence,
                    isSelf: isSelf
                )
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

        print("[PrePipeline] guard:\(result.guardWarningDimensions.count)warnings emotions:\(result.emotions.count) persons:\(result.persons.count) blindspots:\(result.blindspotFindings.count) safetyUncertain:\(result.safetyUncertain)")
        return true
    }

}
