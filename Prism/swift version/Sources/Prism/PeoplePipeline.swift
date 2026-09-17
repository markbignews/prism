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
    var candidatePersonID: UUID?
    var matchConfidence: Double
    var matchEvidence: String
    var isSelf: Bool
}

/// This worker owns only entity resolution. It runs after a visible reply, so
/// an unavailable entity pass never delays or changes the live conversation.
extension ChatAgent {
    struct PeoplePipelineResult {
        var persons: [PersonFinding] = []
        var analysisUnavailable = false
    }

    private var peoplePipelineSystemPrompt: String {
        """
        你是人物归档整理器。只分析“本轮用户消息”中提及的真实人物；“此前上下文”只能用于消解称呼，不能重复输出此前已经处理过的人物。返回严格 JSON。

        每项含 mention（当前称呼）/ name（规范名称）/ role（必须来自用户原话或明确上下文）/ speaker(self|other)。不要输出泛化指代（如“他们”），不要从助手的说法新增人物。

        用户可能在姓名、昵称、关系称呼、简称和代词间自然切换。结合用户消息和已知人物判断：
        - 证据充分且置信度至少 0.85：输出 person_id 和规范 name。
        - 有合理候选但证据不足（0.50–0.84）：person_id 必须为 null，candidate_person_id 输出候选 ID，match_evidence 用一句话说明依据；这不会自动合并，用户会确认。
        - 更低置信度：两个 ID 都为 null。
        不要为了减少条目而强行合并。

        可选 traits 只能使用以下 ID：control_autonomy、communication_withdrawal、invalidates_feelings、boundary_violation、guilt_pressure、promise_action_mismatch、threat_or_coercion。每项必须有当前用户消息中的具体可观察 evidence、confidence（证据强度）和 scope(single_event|repeated_pattern)。不要诊断或制造人格标签；没有明确行为证据时返回 []。

        严格只返回：
        {"persons":[{"mention":"...","name":"...","role":"...","speaker":"other","person_id":null,"candidate_person_id":null,"match_confidence":0.0,"match_evidence":"...","traits":[{"pattern":"...","evidence":"...","confidence":0.0,"scope":"single_event"}]}]}
        """
    }

    func schedulePeopleAnalysis(for conversationID: UUID, requestSentAt: Date, settings: AppSettings) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.runPeoplePipeline(
                for: conversationID,
                requestSentAt: requestSentAt,
                settings: settings
            )
            self.applyPeopleResults(result, for: conversationID, requestSentAt: requestSentAt)
        }
    }

    private func runPeoplePipeline(
        for conversationID: UUID,
        requestSentAt: Date,
        settings: AppSettings
    ) async -> PeoplePipelineResult {
        guard let conversation = conversations.first(where: { $0.id == conversationID }) else {
            return PeoplePipelineResult(analysisUnavailable: true)
        }
        let recentUserMessages = conversation.messages
            .filter { $0.role == .user }
            .suffix(10)
        guard let currentMessage = recentUserMessages.last else { return PeoplePipelineResult() }
        let priorContext = recentUserMessages.dropLast().map {
            "[sentAt=\(AgentPrompt.transcriptTimestamp($0.createdAt))] \($0.content)"
        }.joined(separator: "\n\n")
        let knownPeople = personArchive
            .sorted { $0.lastMentionedAt > $1.lastMentionedAt }
            .prefix(40)
            .map { person in
                let aliases = person.aliases.isEmpty ? "（无别名）" : person.aliases.joined(separator: "、")
                return "- person_id=\(person.id.uuidString) canonical=\(person.name) aliases=[\(aliases)] speaker=\(person.isSelf ? "self" : "other") role=\(person.role)"
            }
            .joined(separator: "\n")
        let userContent = """
        \(AgentPrompt.requestTimeContext(sentAt: requestSentAt, language: settings.language))

        本轮用户消息：
        [sentAt=\(AgentPrompt.transcriptTimestamp(currentMessage.createdAt))] \(currentMessage.content)

        此前上下文（只用于称呼消解，不要重复输出其中人物）：
        \(priorContext.isEmpty ? "（无）" : priorContext)

        已知人物：
        \(knownPeople.isEmpty ? "（无）" : knownPeople)
        """
        let client = DeepSeekClient(
            apiKey: settings.apiKey,
            baseURL: settings.baseURL,
            model: settings.flashModel,
            parameters: settings.flashParameters,
            language: settings.language
        )
        do {
            return parsePeoplePipelineJSON(
                try await client.summarize(systemPrompt: peoplePipelineSystemPrompt, userContent: userContent)
            )
        } catch {
            print("[PeoplePipeline] Flash API error: \(error.localizedDescription)")
            return PeoplePipelineResult(analysisUnavailable: true)
        }
    }

    private func parsePeoplePipelineJSON(_ text: String) -> PeoplePipelineResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let json: String = {
            if let start = trimmed.range(of: "```json"),
               let end = trimmed.range(of: "```", range: start.upperBound..<trimmed.endIndex) {
                return String(trimmed[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return trimmed
        }()
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let persons = object["persons"] as? [[String: Any]] else {
            return PeoplePipelineResult(analysisUnavailable: true)
        }
        let allowedPatterns: Set<String> = [
            "control_autonomy", "communication_withdrawal", "invalidates_feelings",
            "boundary_violation", "guilt_pressure", "promise_action_mismatch", "threat_or_coercion"
        ]
        return PeoplePipelineResult(persons: persons.compactMap { item in
            guard let name = item["name"] as? String,
                  let role = item["role"] as? String else { return nil }
            let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedName.isEmpty else { return nil }
            let mention = (item["mention"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let traits = (item["traits"] as? [[String: Any]] ?? []).compactMap { trait -> PersonTraitFinding? in
                guard let pattern = trait["pattern"] as? String,
                      allowedPatterns.contains(pattern),
                      let evidence = trait["evidence"] as? String else { return nil }
                let cleanEvidence = evidence.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanEvidence.isEmpty else { return nil }
                return PersonTraitFinding(
                    pattern: pattern,
                    evidence: String(cleanEvidence.prefix(240)),
                    confidence: min(max(trait["confidence"] as? Double ?? 0, 0), 1),
                    scope: trait["scope"] as? String == "repeated_pattern" ? "repeated_pattern" : "single_event"
                )
            }
            let confidence = min(max(item["match_confidence"] as? Double ?? 0, 0), 1)
            let evidence = String(((item["match_evidence"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
            return PersonFinding(
                name: String(normalizedName.prefix(120)),
                mention: mention?.isEmpty == false ? String(mention!.prefix(120)) : String(normalizedName.prefix(120)),
                role: String(role.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)),
                traits: traits,
                matchedPersonID: (item["person_id"] as? String).flatMap(UUID.init(uuidString:)),
                candidatePersonID: (item["candidate_person_id"] as? String).flatMap(UUID.init(uuidString:)),
                matchConfidence: confidence,
                matchEvidence: evidence,
                isSelf: (item["speaker"] as? String)?.lowercased() == "self"
            )
        })
    }

    private func applyPeopleResults(_ result: PeoplePipelineResult, for conversationID: UUID, requestSentAt: Date) {
        guard !result.analysisUnavailable,
              let conversation = conversations.first(where: { $0.id == conversationID }) else { return }
        for finding in result.persons {
            let mention = finding.mention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? finding.name : finding.mention
            let traits = finding.traits.map {
                PersonTraitRecord(
                    pattern: $0.pattern,
                    evidence: [$0.evidence],
                    confidence: $0.confidence,
                    scope: $0.scope,
                    status: "suspected",
                    occurrenceCount: 1,
                    firstObservedAt: requestSentAt,
                    lastObservedAt: requestSentAt
                )
            }
            let confirmedIndex: Int? = {
                guard let id = finding.matchedPersonID, finding.matchConfidence >= 0.85 else { return nil }
                return personArchive.firstIndex {
                    $0.id == id && $0.isSelf == finding.isSelf && peopleRolesCompatible($0.role, finding.role)
                }
            }()
            let exactIndex = personArchive.firstIndex { person in
                guard person.isSelf == finding.isSelf, peopleRolesCompatible(person.role, finding.role) else { return false }
                return ([person.name] + person.aliases).contains {
                    peopleNormalizedLabel($0) == peopleNormalizedLabel(finding.name)
                        || peopleNormalizedLabel($0) == peopleNormalizedLabel(mention)
                }
            }
            let sourceID: UUID
            if let index = confirmedIndex ?? exactIndex {
                personArchive[index].lastMentionedAt = requestSentAt
                personArchive[index].mentionCount += 1
                personArchive[index].notes.append("\(conversation.title): \(finding.role)")
                personArchive[index].notes = Array(personArchive[index].notes.suffix(24))
                var scopes = Set(personArchive[index].conversationIDs ?? [])
                scopes.insert(conversationID)
                personArchive[index].conversationIDs = Array(scopes)
                if peopleNormalizedLabel(mention) != peopleNormalizedLabel(personArchive[index].name),
                   !personArchive[index].aliases.contains(where: { peopleNormalizedLabel($0) == peopleNormalizedLabel(mention) }) {
                    personArchive[index].aliases.append(mention)
                    personArchive[index].aliases = Array(personArchive[index].aliases.suffix(12))
                }
                mergePeopleTraits(&personArchive[index].traits, incoming: traits)
                sourceID = personArchive[index].id
            } else {
                let record = PersonRecord(
                    name: finding.name,
                    role: finding.role,
                    firstMentionedAt: requestSentAt,
                    lastMentionedAt: requestSentAt,
                    aliases: mention == finding.name ? [] : [mention],
                    isSelf: finding.isSelf,
                    traits: traits,
                    conversationIDs: [conversationID]
                )
                personArchive.append(record)
                sourceID = record.id
            }
            if let candidateID = finding.candidatePersonID,
               finding.matchConfidence >= 0.5, finding.matchConfidence < 0.85,
               candidateID != sourceID,
               let candidate = personArchive.first(where: {
                   $0.id == candidateID && $0.isSelf == finding.isSelf && peopleRolesCompatible($0.role, finding.role)
               }),
               !personLinkProposals.contains(where: {
                   $0.sourcePersonID == sourceID && $0.candidatePersonID == candidate.id
               }) {
                personLinkProposals.append(PersonLinkProposal(
                    conversationID: conversationID,
                    sourcePersonID: sourceID,
                    candidatePersonID: candidate.id,
                    evidence: finding.matchEvidence.isEmpty ? "\(mention) 可能是 \(candidate.name)" : finding.matchEvidence,
                    confidence: finding.matchConfidence
                ))
            }
        }
        if personArchive.count > 200 {
            personArchive.sort { $0.lastMentionedAt > $1.lastMentionedAt }
            personArchive = Array(personArchive.prefix(200))
        }
        savePeopleArchive()
        delegate?.agentStateDidChange()
    }

    private func peopleNormalizedLabel(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func peopleRolesCompatible(_ lhs: String, _ rhs: String) -> Bool {
        let left = peopleNormalizedLabel(lhs)
        let right = peopleNormalizedLabel(rhs)
        if left.isEmpty || right.isEmpty || left == right { return true }
        return ["other", "其他"].contains(left) || ["other", "其他"].contains(right)
    }

    private func mergePeopleTraits(_ existing: inout [PersonTraitRecord], incoming: [PersonTraitRecord]) {
        for observation in incoming {
            guard !observation.pattern.isEmpty, !observation.evidence.isEmpty else { continue }
            if let index = existing.firstIndex(where: { $0.pattern == observation.pattern }) {
                let previous = max(existing[index].occurrenceCount, 1)
                let total = previous + 1
                existing[index].confidence = ((existing[index].confidence * Double(previous)) + observation.confidence) / Double(total)
                existing[index].occurrenceCount = total
                existing[index].lastObservedAt = observation.lastObservedAt
                existing[index].scope = total > 1 || observation.scope == "repeated_pattern" ? "repeated_pattern" : "single_event"
                existing[index].status = "suspected"
                for evidence in observation.evidence where !existing[index].evidence.contains(evidence) {
                    existing[index].evidence.append(evidence)
                }
                existing[index].evidence = Array(existing[index].evidence.suffix(5))
            } else {
                existing.append(observation)
            }
        }
        existing.sort { $0.lastObservedAt > $1.lastObservedAt }
        existing = Array(existing.prefix(8))
    }
}
