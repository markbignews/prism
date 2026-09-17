import Foundation

/// A profile update is intentionally independent of the live reply and the
/// chapter summarizer. It is scheduled only after a chapter has been stored.
struct ProfileFinding: Equatable {
    var category: String
    var statement: String
    var evidence: String
    var confidence: Double
}

extension ChatAgent {
    struct ProfilePipelineResult {
        var findings: [ProfileFinding] = []
        var analysisUnavailable = false
    }

    private var profilePipelineSystemPrompt: String {
        """
        你是用户画像整理器。只从用户明确说过的话中提取可长期复用、且对后续对话有实际帮助的信息。

        允许的 category 只有：
        - stated_preference：明确偏好或不喜欢的方式
        - stated_goal：明确、持续的目标或计划
        - stable_context：明确且稳定的背景事实
        - communication_preference：用户对回答风格、语言或协作方式的明确要求

        严禁根据情绪、关系冲突、单次事件或措辞推断人格、心理状态、依恋类型、诊断或敏感身份。没有清楚的、可引用的用户证据时返回空数组。不要复述已经存在且含义相同的观察；不要把模型的猜测当成用户事实。

        严格只返回 JSON：
        {"observations":[{"category":"stated_preference","statement":"...","evidence":"用户原话或简短事实概述","confidence":0.0}]}
        """
    }

    /// Schedules profile work off the live-reply path. A chapter is the
    /// smallest stable unit, so a quick back-and-forth never creates a portrait.
    func scheduleProfileAnalysis(for chapters: [StoryChapter], conversationID: UUID, settings: AppSettings) {
        guard !chapters.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            for chapter in chapters {
                let result = await self.runProfilePipeline(
                    for: chapter,
                    conversationID: conversationID,
                    settings: settings
                )
                self.applyProfileResults(result, from: chapter, conversationID: conversationID)
            }
        }
    }

    private func runProfilePipeline(
        for chapter: StoryChapter,
        conversationID: UUID,
        settings: AppSettings
    ) async -> ProfilePipelineResult {
        guard let conversation = conversations.first(where: { $0.id == conversationID }) else {
            return ProfilePipelineResult(analysisUnavailable: true)
        }
        let sourceMessages = conversation.messages
            .filter { chapter.messageIDs.contains($0.id) && $0.role == .user }
        guard !sourceMessages.isEmpty else { return ProfilePipelineResult() }

        let transcript = sourceMessages.map {
            "[sentAt=\(AgentPrompt.transcriptTimestamp($0.createdAt))] \($0.content)"
        }.joined(separator: "\n\n")
        let existing = userProfileObservations
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(24)
            .map { "- [\($0.category)] \($0.statement)" }
            .joined(separator: "\n")
        let userContent = """
        章节：\(chapter.title)
        章节摘要：\(chapter.summary)

        本章节用户原话：
        \(transcript)

        已有画像观察：
        \(existing.isEmpty ? "（无）" : existing)
        """
        let client = DeepSeekClient(
            apiKey: settings.apiKey,
            baseURL: settings.baseURL,
            model: settings.flashModel,
            parameters: settings.flashParameters,
            language: settings.language
        )
        do {
            let raw = try await client.summarize(systemPrompt: profilePipelineSystemPrompt, userContent: userContent)
            return parseProfilePipelineJSON(raw)
        } catch {
            print("[ProfilePipeline] Flash API error: \(error.localizedDescription)")
            return ProfilePipelineResult(analysisUnavailable: true)
        }
    }

    private func parseProfilePipelineJSON(_ text: String) -> ProfilePipelineResult {
        let cleaned: String = {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let start = trimmed.range(of: "```json"),
               let end = trimmed.range(of: "```", range: start.upperBound..<trimmed.endIndex) {
                return String(trimmed[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return trimmed
        }()
        guard let data = cleaned.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let observations = object["observations"] as? [[String: Any]] else {
            return ProfilePipelineResult(analysisUnavailable: true)
        }
        let allowed: Set<String> = [
            "stated_preference", "stated_goal", "stable_context", "communication_preference"
        ]
        return ProfilePipelineResult(findings: observations.compactMap { item in
            guard let category = item["category"] as? String,
                  allowed.contains(category),
                  let statement = item["statement"] as? String,
                  let evidence = item["evidence"] as? String else { return nil }
            let normalizedStatement = statement.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedEvidence = evidence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedStatement.isEmpty, !normalizedEvidence.isEmpty else { return nil }
            return ProfileFinding(
                category: category,
                statement: String(normalizedStatement.prefix(220)),
                evidence: String(normalizedEvidence.prefix(240)),
                confidence: min(max(item["confidence"] as? Double ?? 0, 0), 1)
            )
        })
    }

    private func applyProfileResults(
        _ result: ProfilePipelineResult,
        from chapter: StoryChapter,
        conversationID: UUID
    ) {
        guard !result.analysisUnavailable else { return }
        for finding in result.findings {
            let normalized = finding.statement.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if let index = userProfileObservations.firstIndex(where: {
                $0.category == finding.category
                    && $0.statement.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normalized
            }) {
                userProfileObservations[index].evidence = finding.evidence
                userProfileObservations[index].confidence = max(userProfileObservations[index].confidence, finding.confidence)
                userProfileObservations[index].sourceConversationID = conversationID
                userProfileObservations[index].sourceChapterID = chapter.id
                userProfileObservations[index].updatedAt = Date()
            } else {
                userProfileObservations.append(UserProfileObservation(
                    category: finding.category,
                    statement: finding.statement,
                    evidence: finding.evidence,
                    confidence: finding.confidence,
                    sourceConversationID: conversationID,
                    sourceChapterID: chapter.id
                ))
            }
        }
        if userProfileObservations.count > 80 {
            userProfileObservations.sort { $0.updatedAt > $1.updatedAt }
            userProfileObservations = Array(userProfileObservations.prefix(80))
        }
        saveUserProfile()
        delegate?.agentStateDidChange()
    }
}
