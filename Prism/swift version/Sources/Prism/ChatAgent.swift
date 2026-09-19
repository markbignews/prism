import Foundation

@MainActor protocol ChatAgentDelegate: AnyObject {
    func agentStateDidChange()
}

@MainActor
final class ChatAgent {
    weak var delegate: ChatAgentDelegate?
    private(set) var conversations: [Conversation] = []
    var selectedConversationID: Conversation.ID?
    var isSending = false
    var errorMessage: String?
    var isSummarizing = false
    var currentSendTask: Task<Void, Never>?
    /// Throttles UI publishes during streaming to avoid layout thrashing.
    /// Status of the last summarization attempt (empty = never run / nothing to report).
    var lastSummaryStatus: String = ""

    private var database: SQLiteStore?
    private var storageFailure = false
    private var storageURL: URL

    init() {
        let dataPath = UserDefaults.standard.string(forKey: "storage.dataPath")
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/Prism").path
        let folder = URL(fileURLWithPath: dataPath)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storageURL = folder.appendingPathComponent("conversations.json")

        // Archives live in a Data/ subfolder inside the same data directory.
        let archiveFolder = folder.appendingPathComponent("Data", isDirectory: true)
        try? FileManager.default.createDirectory(at: archiveFolder, withIntermediateDirectories: true)
        dataFolder = archiveFolder

        // Migrate archives from old location (next to .app bundle) → new unified directory
        migrateArchivesIfNeeded(from: Bundle.main.bundleURL
            .deletingLastPathComponent().appendingPathComponent("Data"),
            to: archiveFolder)

        openDatabase(folder)
        load()
        loadArchives()
    }

    var selectedConversation: Conversation? {
        get {
            guard let selectedConversationID else { return nil }
            return conversations.first(where: { $0.id == selectedConversationID })
        }
        set {
            guard let newValue,
                  let index = conversations.firstIndex(where: { $0.id == newValue.id }) else { return }
            conversations[index] = newValue
            save()
        }
    }

    // MARK: - Conversation Management

    func bootstrapIfNeeded(language: AppLanguage = .simplifiedChinese) {
        guard !storageFailure else { return }
        if conversations.isEmpty {
            createConversation(language: language)
        } else if selectedConversationID == nil {
            selectConversation(conversations.first?.id)
        }
    }

    func createConversation(language: AppLanguage = .simplifiedChinese) {
        guard !isSending, !isSummarizing, !storageFailure else { return }
        let title = L10n.text(.newConversationTitle, language)
        let conversation = Conversation(title: title, messages: [])
        conversations.insert(conversation, at: 0)
        selectConversation(conversation.id)
        save()
    }

    /// Set selected conversation and persist immediately.
    private func selectConversation(_ id: UUID?) {
        selectedConversationID = id
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: "ui.lastConversationID")
        }
    }

    func deleteSelectedConversation() {
        guard let selectedConversationID else { return }
        deleteConversation(id: selectedConversationID)
    }

    func deleteConversation(id: UUID) {
        guard !isSending, !isSummarizing else { return }  // block deletion during summarization
        currentSendTask?.cancel()
        currentSendTask = nil
        conversations.removeAll { $0.id == id }
        if selectedConversationID == id {
            selectConversation(conversations.first?.id)
        }
        // Remove only this conversation from a person's explicit scope. Name
        // substring matching could erase a person still used elsewhere.
        personArchive = personArchive.compactMap { person in
            guard var ids = person.conversationIDs else { return person }
            ids.removeAll { $0 == id }
            guard !ids.isEmpty else { return nil }
            var retained = person
            retained.conversationIDs = ids
            return retained
        }
        emotionTimeline.removeAll { $0.conversationID == id }
        blindspots.removeAll { $0.conversationID == id }
        memoryStore.removeAll { $0.sourceConversationID == id }
        narrativeTimeline.removeAll { $0.conversationID == id }
        userProfileObservations.removeAll { $0.sourceConversationID == id }
        personLinkProposals.removeAll { proposal in
            proposal.conversationID == id
                || !personArchive.contains(where: { $0.id == proposal.sourcePersonID })
                || !personArchive.contains(where: { $0.id == proposal.candidatePersonID })
        }
        clearSafetyCrisis(for: id)
        saveArchives()

        if conversations.isEmpty {
            createConversation()
        } else {
            save()
        }
        delegate?.agentStateDidChange()
    }

    func resetAll() {
        guard !isSending, !isSummarizing, !storageFailure else { return }
        conversations = []
        selectedConversationID = nil
        personArchive = []
        emotionTimeline = []
        blindspots = []
        memoryStore = []
        narrativeTimeline = []
        personLinkProposals = []
        userProfileObservations = []
    }

    /// Reload conversations and archives from the current data path.
    /// Call after changing `AppSettings.dataPath` and migrating files.
    func reloadStorage(from settings: AppSettings? = nil) {
        guard !isSending, !isSummarizing else { return }
        let dataPath = settings?.dataPath
            ?? UserDefaults.standard.string(forKey: "storage.dataPath")
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/Prism").path
        let folder = URL(fileURLWithPath: dataPath)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storageURL = folder.appendingPathComponent("conversations.json")
        dataFolder = folder.appendingPathComponent("Data", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true)

        openDatabase(folder)
        load()
        loadArchives()

        // If the previously selected conversation no longer exists, pick the first.
        if let sid = selectedConversationID, !conversations.contains(where: { $0.id == sid }) {
            selectConversation(conversations.first?.id)
        }
        if selectedConversationID == nil {
            selectConversation(conversations.first?.id)
        }
    }

    func renameConversation(id: UUID, newTitle: String) {
        guard let index = conversations.firstIndex(where: { $0.id == id }),
              !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        conversations[index].title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        conversations[index].updatedAt = Date()
        save()
    }

    /// Set a per-conversation mode override.
    /// The override follows the conversation and persists across launches.
    func setMode(_ mode: ConversationMode, for conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].mode = mode
        conversations[index].updatedAt = Date()
        save()
        delegate?.agentStateDidChange()
    }

    func deleteMessage(in conversationID: UUID, messageID: UUID) {
        guard !isSending, !isSummarizing, !storageFailure else { return }
        guard let convIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }

        // Paired deletion: deleting either user or assistant in a pair removes both.
        let role = conversations[convIndex].messages[msgIndex].role
        let isUser = role == .user
        let isAssistant = role == .assistant
        let nextIsAssistant = isUser && msgIndex + 1 < conversations[convIndex].messages.count
            && conversations[convIndex].messages[msgIndex + 1].role == .assistant
        let prevIsUser = isAssistant && msgIndex > 0
            && conversations[convIndex].messages[msgIndex - 1].role == .user

        let removedIDs: Set<UUID>
        if nextIsAssistant {
            // Deleting user → also remove following assistant
            removedIDs = Set([
                conversations[convIndex].messages[msgIndex].id,
                conversations[convIndex].messages[msgIndex + 1].id,
            ])
            conversations[convIndex].messages.removeSubrange(msgIndex...(msgIndex + 1))
            conversations[convIndex].completedDialogCount = max(0, conversations[convIndex].completedDialogCount - 1)
        } else if prevIsUser {
            // Deleting assistant → also remove preceding user
            removedIDs = Set([
                conversations[convIndex].messages[msgIndex - 1].id,
                conversations[convIndex].messages[msgIndex].id,
            ])
            conversations[convIndex].messages.removeSubrange((msgIndex - 1)...msgIndex)
            conversations[convIndex].completedDialogCount = max(0, conversations[convIndex].completedDialogCount - 1)
        } else {
            removedIDs = [conversations[convIndex].messages[msgIndex].id]
            conversations[convIndex].messages.remove(at: msgIndex)
        }

        // A summary depending on a removed message is invalid, even if its
        // other source messages remain. Rebuild it from originals later.
        var chapters = conversations[convIndex].chapters
        let oldChapterCount = chapters.count
        chapters.removeAll { chapter in chapter.messageIDs.contains(where: removedIDs.contains) }
        memoryStore.removeAll { memory in
            memory.sourceConversationID == conversationID && (memory.sourceMessageIDs == nil || memory.sourceMessageIDs!.contains(where: removedIDs.contains))
        }
        saveArchives()
        conversations[convIndex].chapters = chapters

        // Adjust incrementalChapterCount for removed chapters
        let removedChapterCount = oldChapterCount - chapters.count
        conversations[convIndex].incrementalChapterCount = max(
            0,
            conversations[convIndex].incrementalChapterCount - removedChapterCount
        )

        // Recalculate lastSummaryMessageIndex from remaining chapters.
        // If chapters exist, it's the index after the last message covered by any chapter.
        // If no chapters remain, reset to 0 (nothing summarized).
        if chapters.isEmpty {
            conversations[convIndex].lastSummaryMessageIndex = 0
        } else {
            let coveredIDs = Set(chapters.flatMap(\.messageIDs))
            let lastCoveredIndex = conversations[convIndex].messages.lastIndex(where: { coveredIDs.contains($0.id) })
            if let idx = lastCoveredIndex {
                conversations[convIndex].lastSummaryMessageIndex = idx + 1
            } else {
                // Remaining chapters reference messages that no longer exist — reset
                conversations[convIndex].lastSummaryMessageIndex = 0
                conversations[convIndex].chapters = []
                conversations[convIndex].incrementalChapterCount = 0
            }
        }

        conversations[convIndex].updatedAt = Date()
        save()
        delegate?.agentStateDidChange()
    }

    func regenerateAssistantMessage(in conversationID: UUID, messageID: UUID, settings: AppSettings) async {
        guard !isSending,
              let convIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == messageID }),
              msgIndex > 0 else { return }

        // Find the user message right before this assistant message
        let prevIndex = msgIndex - 1
        guard conversations[convIndex].messages[prevIndex].role == .user else { return }
        let userText = conversations[convIndex].messages[prevIndex].content
        let requestSentAt = conversations[convIndex].messages[prevIndex].createdAt

        // Remove this assistant message
        conversations[convIndex].messages.remove(at: msgIndex)
        conversations[convIndex].updatedAt = Date()
        save()

        // Resend
        isSending = true
        delegate?.agentStateDidChange()
        defer {
            isSending = false
            save()
            delegate?.agentStateDidChange()
        }

        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        var memoryContext = StoryMemory.relevantContext(for: trimmed, in: conversations[convIndex], language: settings.language)
        // Time is injected as a plain `[System time]` block in the system
        // prompt every API round — no time tool needed.
        memoryContext = (memoryContext ?? "")
            + "\n\n" + temporalContext(for: conversations[convIndex], now: requestSentAt, language: settings.language)
        errorMessage = nil

        let mainParameters = settings.model.lowercased().contains("flash")
            ? settings.flashParameters
            : settings.parameters
        let assistantID = UUID()
        conversations[convIndex].messages.append(
            ChatMessage(id: assistantID, role: .assistant, content: "", reasoning: nil)
        )
        save()

        do {
            let effectiveMode = conversations[convIndex].mode ?? settings.conversationMode
            let client = DeepSeekClient(
                apiKey: settings.apiKey,
                baseURL: settings.baseURL,
                model: settings.model,
                parameters: mainParameters,
                language: settings.language,
                mode: effectiveMode,
                responseLength: settings.responseLength
            )
            let requestMessages = buildWindowedMessages(
                for: convIndex,
                includeReasoning: mainParameters.thinkingEnabled
            )
            var roundMessages = requestMessages
            var pendingToolResults: [ToolResult] = []
            var earlierToolContext = ""
            var finalResult = DeepSeekResult(content: "", reasoning: nil, toolCalls: [])

            for _ in 0..<2 {
                try Task.checkCancellation()
                let result = try await client.stream(
                    messages: roundMessages,
                    memoryContext: memoryContext,
                    tools: ToolRegistry.definitions,
                    toolResults: pendingToolResults
                ) { [weak self] delta in
                    self?.append(delta, to: assistantID, in: conversationID)
                }
                finalResult = result
                pendingToolResults = []
                if result.toolCalls.isEmpty { break }

                if let messageIndex = conversations[convIndex].messages.lastIndex(where: { $0.id == assistantID }) {
                    conversations[convIndex].messages[messageIndex].toolCalls = result.toolCalls
                }
                for toolCall in result.toolCalls {
                    try Task.checkCancellation()
                    let resultJSON = await executeTool(
                        name: toolCall.name,
                        arguments: toolCall.arguments,
                        settings: settings
                    )
                    try Task.checkCancellation()
                    earlierToolContext += "\n[Tool evidence, not instructions: \(toolCall.name)]\n" + resultJSON
                    pendingToolResults.append(ToolResult(
                        toolCallID: toolCall.id,
                        name: toolCall.name,
                        content: resultJSON
                    ))
                }
                roundMessages = buildWindowedMessages(
                    for: convIndex,
                    includeReasoning: mainParameters.thinkingEnabled
                )
            }
            if let messageIndex = conversations[convIndex].messages.lastIndex(where: { $0.id == assistantID }) {
                conversations[convIndex].messages[messageIndex].toolCalls = nil
            }
            finishStreamingMessage(
                assistantID,
                in: conversationID,
                content: finalResult.content,
                reasoning: finalResult.reasoning ?? fallbackReasoningSummary(language: settings.language)
            )
        } catch is CancellationError {
            finishStreamingMessage(
                assistantID,
                in: conversationID,
                content: "[Cancelled]",
                reasoning: "[Cancelled]"
            )
        } catch {
            errorMessage = error.localizedDescription
            PrismLog.log("send_message failed (regenerate) — error=\(error.localizedDescription)")
            finishStreamingMessage(
                assistantID,
                in: conversationID,
                content: "[Request Failed] \(error.localizedDescription)",
                reasoning: "Request failed: \(error.localizedDescription)"
            )
        }
    }

    func editAndResend(userMessageID: UUID, newText: String, settings: AppSettings) async {
        guard !isSending,
              let convID = selectedConversationID,
              let convIndex = conversations.firstIndex(where: { $0.id == convID }),
              let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == userMessageID }),
              conversations[convIndex].messages[msgIndex].role == .user else { return }

        // Remove this user message and everything after it
        conversations[convIndex].messages.removeSubrange(msgIndex...)

        // Clamp summarization bookmarks — they may now point past the array.
        conversations[convIndex].lastSummaryMessageIndex = min(
            conversations[convIndex].lastSummaryMessageIndex,
            conversations[convIndex].messages.count
        )
        conversations[convIndex].completedDialogCount = 0

        conversations[convIndex].updatedAt = Date()
        save()

        // Send the new text
        await send(newText, settings: settings)
    }

    // MARK: - Chat

    /// Surface persisted message and chapter timestamps to the model. The API
    /// message wire format carries content but not our local temporal metadata.
    private func temporalContext(for conversation: Conversation, now: Date, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .english ? "en_US_POSIX" : "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        let dateText: (Date) -> String = { formatter.string(from: $0) }

        let elapsed = max(0, now.timeIntervalSince(conversation.createdAt))
        let users = conversation.messages.filter { $0.role == .user }
        let recentUsers = Array(users.suffix(8))
        let messageLines = recentUsers.enumerated().map { index, message in
            let previousDate = index > 0 ? recentUsers[index - 1].createdAt : conversation.createdAt
            let gap = max(0, message.createdAt.timeIntervalSince(previousDate))
            return "- \(dateText(message.createdAt)) [\(dayPart(message.createdAt, language: language))] gap=\(formatDuration(gap, language: language)): \(message.content.prefix(180))"
        }.joined(separator: "\n")

        let chapterLines = conversation.chapters.suffix(6).enumerated().map { index, chapter in
            let dates = conversation.messages
                .filter { chapter.messageIDs.contains($0.id) }
                .map(\.createdAt)
            let chapterStart = dates.min() ?? chapter.createdAt
            let chapterEnd = dates.max() ?? chapter.updatedAt
            return "- \(index + 1). \(chapter.title): \(dateText(chapterStart)) → \(dateText(chapterEnd)) (\(formatDuration(chapterEnd.timeIntervalSince(chapterStart), language: language)))"
        }.joined(separator: "\n")

        let emotionLines = emotionTimeline
            .filter { $0.conversationID == conversation.id }
            .suffix(5)
            .map { entry in
                let confidence = entry.confidence.map { String(format: " confidence=%.1f", $0) } ?? ""
                return "- \(dateText(entry.createdAt)) \(entry.emotion) intensity=\(String(format: "%.1f", entry.intensity))\(confidence)"
            }
            .joined(separator: "\n")

        let personLines = personArchive
            .filter { $0.mentionCount > 0 && $0.conversationIDs?.contains(conversation.id) == true }
            .sorted { $0.lastMentionedAt > $1.lastMentionedAt }
            .prefix(5)
            .map { person in
                let aliasSummary = person.aliases.isEmpty ? "" : "; aliases=\(person.aliases.joined(separator: ","))"
                let speaker = person.isSelf ? "self" : "other"
                let traitSummary = person.traits.prefix(3).map { trait in
                    let evidence = trait.evidence.first ?? ""
                    return "\(trait.pattern)[suspected,\(trait.scope),c=\(String(format: "%.1f", trait.confidence))]: \(evidence)"
                }.joined(separator: " | ")
                let suffix = traitSummary.isEmpty ? "" : "; suspected behavior patterns (not facts or diagnoses): \(traitSummary)"
                return "- \(person.name) (\(person.role), speaker=\(speaker)): \(dateText(person.firstMentionedAt)) → \(dateText(person.lastMentionedAt)), mentions=\(person.mentionCount)\(aliasSummary)\(suffix)"
            }
            .joined(separator: "\n")

        let memoryLines = memoryStore
            .filter { $0.sourceConversationID == conversation.id }
            .suffix(5)
            .map { entry in
                let from = entry.timeSpanStart ?? entry.createdAt
                let to = entry.timeSpanEnd ?? from
                return "- \(entry.sourceChapterTitle): \(dateText(from)) → \(dateText(to))"
            }
            .joined(separator: "\n")

        let labels: (String, String, String, String) = switch language {
        case .simplifiedChinese: ("时间轴", "对话发起", "已跨时长", "最近用户消息")
        case .traditionalChinese: ("時間軸", "對話發起", "已跨時長", "最近用戶訊息")
        case .english: ("Temporal timeline", "Conversation started", "Elapsed", "Recent user messages")
        }
        let instruction = language == .english
            ? "Use timestamps, gaps, and daypart when interpreting emotional state. If the user adds a concrete event or detail without an absolute or relative time, ask a concise follow-up for an approximate time before analyzing it. Never invent the event time."
            : "判断心理状态和关系变化时必须结合时间戳、间隔和昼夜时段。如果用户补充具体事件或细节却没有绝对或相对时间，必须先二次询问大概发生在什么时候，再继续分析；不要自行编造时间。"

        return """
        [\(labels.0)]
        \(labels.1): \(dateText(conversation.createdAt)) [\(dayPart(conversation.createdAt, language: language))]
        \(labels.2): \(formatDuration(elapsed, language: language))
        \(labels.3):
        \(messageLines.isEmpty ? "(none)" : messageLines)
        Chapters:
        \(chapterLines.isEmpty ? "(none)" : chapterLines)
        Emotion timeline:
        \(emotionLines.isEmpty ? "(none)" : emotionLines)
        Relationship timeline:
        \(personLines.isEmpty ? "(none)" : personLines)
        Memory time spans:
        \(memoryLines.isEmpty ? "(none)" : memoryLines)
        Temporal policy: \(instruction)
        """
    }

    private func dayPart(_ date: Date, language: AppLanguage) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        if language == .english {
            return hour < 6 ? "late night" : hour < 12 ? "morning" : hour < 18 ? "afternoon" : hour < 23 ? "evening" : "late night"
        }
        return hour < 6 ? "深夜" : hour < 12 ? "上午" : hour < 18 ? "下午" : hour < 23 ? "晚上" : "深夜"
    }

    private func formatDuration(_ seconds: TimeInterval, language: AppLanguage) -> String {
        let minutes = Int(seconds / 60)
        if language == .english {
            if minutes < 1 { return "under 1 min" }
            if minutes < 60 { return "\(minutes) min" }
            let hours = minutes / 60
            return hours < 24 ? "\(hours) hr \(minutes % 60) min" : "\(hours / 24)d \(hours % 24)h"
        }
        if minutes < 1 { return "不到1分钟" }
        if minutes < 60 { return "\(minutes)分钟" }
        let hours = minutes / 60
        return hours < 24 ? "\(hours)小时\(minutes % 60)分钟" : "\(hours / 24)天\(hours % 24)小时"
    }

    func contextUsage(for conversationID: UUID?, settings: AppSettings) -> ContextUsageSnapshot {
        guard let conversationID,
              let index = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return ContextUsageSnapshot(
                reservedOutputTokens: settings.responseLength.maxTokens,
                summaryInterval: settings.summaryDialogCount
            )
        }

        let conversation = conversations[index]
        let mainParameters = settings.model.lowercased().contains("flash")
            ? settings.flashParameters
            : settings.parameters
        let effectiveMessages = buildWindowedMessages(
            for: index,
            includeReasoning: mainParameters.thinkingEnabled
        )
        let mode = conversation.mode ?? settings.conversationMode

        var fixedTokens = estimateTokens(AgentPrompt.system(
            language: settings.language,
            mode: mode,
            responseLength: settings.responseLength
        ))
        fixedTokens += estimateTokens(temporalContext(for: conversation, now: Date(), language: settings.language))
        if let toolData = try? JSONEncoder().encode(ToolRegistry.definitions),
           let toolText = String(data: toolData, encoding: .utf8) {
            fixedTokens += estimateTokens(toolText)
        }
        // Story-memory and supervisor blocks depend on the next draft. Keep a
        // small explicit reserve so the preflight percentage is not optimistic.
        fixedTokens += 512

        let chapterIndex = chapterIndexMessage(for: conversation).map {
            estimateMessageTokens($0, includeReasoning: false)
        } ?? 0
        let raw = conversation.messages.reduce(0) {
            $0 + estimateMessageTokens($1, includeReasoning: mainParameters.thinkingEnabled)
        }
        let uncompressed = fixedTokens + chapterIndex + raw
        let estimated = fixedTokens + effectiveMessages.reduce(0) {
            $0 + estimateMessageTokens($1, includeReasoning: mainParameters.thinkingEnabled)
        }

        let summaryInterval = max(0, settings.summaryDialogCount)
        let dialogsUntilSummary = summaryInterval == 0
            ? 0
            : max(0, summaryInterval - conversation.completedDialogCount)

        return ContextUsageSnapshot(
            estimatedTokens: estimated,
            uncompressedEstimatedTokens: uncompressed,
            rawConversationTokens: raw,
            reservedOutputTokens: settings.responseLength.maxTokens,
            messageCount: conversation.messages.count,
            retainedRecentTokens: raw >= ContextUsageSnapshot.criticalThresholdTokens
                ? ContextUsageSnapshot.criticalRetainedRecentTokens
                : ContextUsageSnapshot.retainedRecentTokens,
            tokensUntilPreparation: max(0, ContextUsageSnapshot.preparationThresholdTokens - raw),
            tokensUntilCompression: max(0, ContextUsageSnapshot.compressionThresholdTokens - raw),
            preparationActive: raw >= ContextUsageSnapshot.preparationThresholdTokens,
            compressionActive: raw >= ContextUsageSnapshot.compressionThresholdTokens,
            critical: raw >= ContextUsageSnapshot.criticalThresholdTokens,
            summaryInterval: summaryInterval,
            dialogsUntilSummary: dialogsUntilSummary
        )
    }

    private func estimateMessageTokens(_ message: ChatMessage, includeReasoning: Bool) -> Int {
        var total = estimateTokens(message.content) + 8
        if message.role == .user {
            total += estimateTokens("[sentAt=\(AgentPrompt.transcriptTimestamp(message.createdAt))]")
        }
        if includeReasoning, let reasoning = message.reasoning {
            total += estimateTokens(reasoning)
        }
        if let toolCalls = message.toolCalls,
           let data = try? JSONEncoder().encode(toolCalls),
           let text = String(data: data, encoding: .utf8) {
            total += estimateTokens(text)
        }
        return total
    }

    private func estimateTokens(_ text: String) -> Int {
        var estimate = 0.0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3400...0x9FFF, 0xF900...0xFAFF:
                estimate += 0.6
            case 0x1F000...0x1FAFF:
                estimate += 1.0
            default:
                estimate += CharacterSet.whitespacesAndNewlines.contains(scalar) ? 0.05 : 0.3
            }
        }
        return Int(ceil(estimate))
    }

    /// Keep the full transcript until it approaches DeepSeek V4's 1M context.
    /// Chapter synthesis remains an index/memory feature and does not evict
    /// raw messages. At the 75% hard threshold, only the request payload is
    /// compacted; every original message remains stored locally.
    private func buildWindowedMessages(for index: Int, includeReasoning: Bool) -> [ChatMessage] {
        let conv = conversations[index]
        let rawTokens = conv.messages.reduce(0) {
            $0 + estimateMessageTokens($1, includeReasoning: includeReasoning)
        }

        guard rawTokens >= ContextUsageSnapshot.compressionThresholdTokens else {
            let indexMsg = chapterIndexMessage(for: conv)
            if let idx = indexMsg {
                return [idx] + conv.messages
            }
            return conv.messages
        }

        var splitPoint = conv.messages.count
        var recentTokens = 0
        let recentTokenBudget = rawTokens >= ContextUsageSnapshot.criticalThresholdTokens
            ? ContextUsageSnapshot.criticalRetainedRecentTokens
            : ContextUsageSnapshot.retainedRecentTokens
        for messageIndex in conv.messages.indices.reversed() {
            let messageTokens = estimateMessageTokens(
                conv.messages[messageIndex],
                includeReasoning: includeReasoning
            )
            if splitPoint < conv.messages.count,
               recentTokens + messageTokens > recentTokenBudget {
                break
            }
            splitPoint = messageIndex
            recentTokens += messageTokens
            if recentTokens >= recentTokenBudget { break }
        }
        let recent = Array(conv.messages.suffix(from: splitPoint))

        // Build compressed context from chapters
        let olderIDs = Set(conv.messages.prefix(splitPoint).map(\.id))
        let coveringChapters = conv.chapters.filter { ch in
            ch.messageIDs.contains { olderIDs.contains($0) }
        }

        var contextLines: String
        if coveringChapters.isEmpty {
            contextLines = conv.chapters.prefix(5).map { ch in
                "▸ \(ch.title): \(String(ch.summary.prefix(150)))"
            }.joined(separator: "\n")
        } else {
            contextLines = coveringChapters.map { ch in
                "▸ \(ch.title): \(String(ch.summary.prefix(200)))"
            }.joined(separator: "\n")
        }

        if contextLines.isEmpty {
            contextLines = conv.messages.prefix(splitPoint).suffix(24).map { message in
                let role = message.role == .user ? "user" : "assistant"
                return "▸ [\(role) \(AgentPrompt.transcriptTimestamp(message.createdAt))] \(String(message.content.prefix(240)))"
            }.joined(separator: "\n")
        }

        var header = "[历史上下文压缩 — 未压缩输入已达到模型窗口的 75%。以下为旧内容摘要，完整原文仍保存在本地。"
        header += "如需细节，调用 search_chapters 或 fetch_chapter_messages]\n"
        let contextMsg = ChatMessage(role: .system, content: header + contextLines)

        // Also inject chapter index for the recent messages' chapters
        let recentChapterIDs = Set(recent.map(\.id))
        let recentChapters = conv.chapters.filter { ch in
            ch.messageIDs.contains { recentChapterIDs.contains($0) }
        }
        let recentIndex = recentChapters.map { ch in
            "▸ \(ch.title): \(String(ch.summary.prefix(150)))"
        }.joined(separator: "\n")

        if !recentIndex.isEmpty {
            let idxMsg = ChatMessage(role: .system,
                content: "[近期章节索引]\n\(recentIndex)")
            return [contextMsg, idxMsg] + recent
        }

        return [contextMsg] + recent
    }

    /// Lightweight chapter index — tells the agent what topics are available
    /// without sending full message content.
    private func chapterIndexMessage(for conv: Conversation) -> ChatMessage? {
        guard !conv.chapters.isEmpty else { return nil }
        let lines = conv.chapters.enumerated().map { i, ch in
            "第\(i+1)章「\(ch.title)」: \(String(ch.summary.prefix(150)))"
        }.joined(separator: "\n")
        return ChatMessage(
            role: .system,
            content: "[章节索引 — 可用 search_chapters / fetch_chapter_messages 检索原文]\n\(lines)"
        )
    }

    /// Public helper: look up full message content for a chapter.
    func messages(for chapter: StoryChapter) -> [ChatMessage] {
        guard let conv = conversations.first(where: { conv in
            conv.chapters.contains(where: { $0.id == chapter.id })
        }) else { return [] }
        return conv.messages.filter { chapter.messageIDs.contains($0.id) }
    }

    func send(
        _ text: String,
        attachments: [MessageAttachment] = [],
        settings: AppSettings
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!trimmed.isEmpty || !attachments.isEmpty), !isSending, !isSummarizing, !storageFailure else { return }
        let effectiveText = trimmed.isEmpty && !attachments.isEmpty
            ? "请分析我上传的附件。"
            : trimmed
        bootstrapIfNeeded(language: settings.language)
        guard let id = selectedConversationID,
              let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        PrismLog.log("send_message requested — conv_id=\(id.uuidString) text_len=\(effectiveText.count)")
        let requestSentAt = Date()

        // Build only current-conversation memory automatically. Cross-conversation
        // memory remains an explicit search tool so old narratives do not bias
        // every new turn without the user's request.
        var memoryContext = StoryMemory.relevantContext(for: effectiveText, in: conversations[index], language: settings.language)
        // Capture the user's send time once and reuse it across the reply,
        // profile pre-pipeline, tool rounds, and later summaries.
        errorMessage = nil
        let attachmentNote = attachments.isEmpty
            ? ""
            : "\n\n" + attachments.map { "[附件：\($0.fileName)]" }.joined(separator: "\n")
        let userMessage = ChatMessage(
            role: .user,
            content: effectiveText + attachmentNote,
            createdAt: requestSentAt,
            attachments: attachments
        )
        conversations[index].messages.append(userMessage)
        StoryMemory.ingest(userText: effectiveText, messageID: userMessage.id, conversation: &conversations[index])
        conversations[index].updatedAt = requestSentAt
        updateTitleIfNeeded(for: index, firstUserText: effectiveText)
        memoryContext = (memoryContext ?? "")
            + "\n\n" + temporalContext(for: conversations[index], now: requestSentAt, language: settings.language)

        let mainParameters = settings.model.lowercased().contains("flash")
            ? settings.flashParameters
            : settings.parameters
        let requestMessages = buildWindowedMessages(
            for: index,
            includeReasoning: mainParameters.thinkingEnabled
        )
        let assistantID = UUID()
        conversations[index].messages.append(
            ChatMessage(id: assistantID, role: .assistant, content: "", reasoning: nil)
        )
        isSending = true
        save()
        // Publish only after the user message, assistant placeholder and
        // sending state form one coherent frame. Publishing before mutation
        // can make the composer clear while the new turn is still absent.
        delegate?.agentStateDidChange()

        var finalContent = ""
        var finalReasoning: String?
        var hasCompletedAnalysis = false
        defer {
            isSending = false
            save()
            // Publish the terminal state explicitly. Without this, SwiftUI
            // can retain `isSending == true` until an unrelated background
            // update arrives, causing subsequent Return presses to be ignored
            // and leaving the temporary scroll runway in place.
            delegate?.agentStateDidChange()
        }

        do {
            try Task.checkCancellation()
            // ── Step 1: Supervisor — safety + response-quality guard only ──
            let preResult = await runPrePipeline(for: id, requestSentAt: requestSentAt, settings: settings)
            try Task.checkCancellation()
            let guardHint = buildGuardHint(from: preResult)

            // ── Safety gate — never continue silently after an unknown check ──
            if preResult.safetyUncertain {
                finalContent = buildSafetyUncertaintyResponse(language: settings.language)
                finalReasoning = "⚠️ 安全检查未完成 — 已暂停关系分析。"

                let words = finalContent.map { String($0) }
                for i in stride(from: 0, to: words.count, by: 8) {
                    let chunk = words[i..<min(i + 8, words.count)].joined()
                    append(.content(chunk), to: assistantID, in: id)
                    await Task.yield()
                }
            } else if preResult.safetyCrisis {
                // Persist the safety state before composing the response so the
                // next turn is re-checked in safety mode. The response composer
                // may personalize wording, but it cannot call tools or resume
                // the main relationship-analysis path.
                await saveSafetyContext(
                    for: index,
                    hint: preResult.safetyHint,
                    resources: preResult.safetyResources
                )
                let latestUserText = conversations[index].messages
                    .last(where: { $0.role == .user })?.content ?? ""
                finalContent = await generateSafetyResponse(
                    userMessage: latestUserText,
                    signals: preResult.safetySignals,
                    hint: preResult.safetyHint,
                    resources: preResult.safetyResources,
                    settings: settings
                )
                finalReasoning = "⚠️ 安全干预 — 检测到严重安全信号，叙事分析已暂停。"

                // Stream safety response to the UI chunk by chunk
                let words = finalContent.map { String($0) }
                for i in stride(from: 0, to: words.count, by: 8) {
                    let chunk = words[i..<min(i + 8, words.count)].joined()
                    append(.content(chunk), to: assistantID, in: id)
                    await Task.yield()
                }
            } else {
                // ── Step 2: Main Agent (v4-pro, streaming) with retrieval tools ──
            let effectiveMode = conversations[index].mode ?? settings.conversationMode
            let client = DeepSeekClient(
                apiKey: settings.apiKey,
                baseURL: settings.baseURL,
                model: settings.model,
                parameters: mainParameters,
                language: settings.language,
                mode: effectiveMode,
                responseLength: settings.responseLength
            )

            var roundMessages = requestMessages
            var pendingToolResults: [ToolResult] = []
            var earlierToolContext = ""
            // DeepSeek supports parallel function calls in one response.
            // Two rounds cover retrieval followed by a dependent fetch while
            // preventing an accidental tool/reasoning loop from multiplying
            // completion tokens.
            let maxToolExecutionRounds = 2

            // On a brand-new conversation (no assistant reply yet),
            // do not expose retrieval tools on the first round — there is no
            // history, chapter, or archive context to retrieve, so inviting
            // speculative tool calls would only delay the first visible reply.
            let hasCompletedTurn = conversations[index].messages.contains(where: {
                $0.role == .assistant
                    && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
            let psychologySearchAvailable = URL(string: settings.baseURL)?.host?.lowercased() == "api.deepseek.com"
            let availableTools = psychologySearchAvailable
                ? ToolRegistry.definitions
                : ToolRegistry.definitions.filter { $0.function.name != "search_psychology" }
            let toolsForRound: (Int) -> [ToolDef]? = { round in
                // A new conversation has no history to retrieve, but it can
                // already contain a clear autobiographical time node.
                (round == 0 && !hasCompletedTurn)
                    ? [.manageNarrativeTimeline]
                    : availableTools
            }

            // Reserve one final, tool-free request after the capped execution
            // rounds. This guarantees that hitting the cap still produces a
            // user-visible answer instead of leaving an empty assistant bubble.
            for round in 0...maxToolExecutionRounds {
                let isFinalSynthesisRound = round == maxToolExecutionRounds
                let result = try await client.stream(
                    messages: roundMessages,
                    memoryContext: (memoryContext ?? "") + earlierToolContext,
                    supervisorHint: guardHint,
                    tools: isFinalSynthesisRound ? nil : toolsForRound(round),
                    toolResults: pendingToolResults
                ) { [weak self] delta in
                    self?.append(delta, to: assistantID, in: id)
                }

                pendingToolResults = []

                // If the model responds with content and no more tool calls, we're done
                if result.toolCalls.isEmpty {
                    hasCompletedAnalysis = !result.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    finalContent = !hasCompletedAnalysis
                        ? (settings.language == .english ? "The model returned no answer. Please retry." : settings.language == .traditionalChinese ? "模型沒有返回有效正文，請重試。" : "模型没有返回有效正文，请重试。") : result.content
                    finalReasoning = result.reasoning
                    break
                }

                if isFinalSynthesisRound {
                    hasCompletedAnalysis = !result.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    if !hasCompletedAnalysis {
                        finalContent = switch settings.language {
                        case .traditionalChinese: "工具檢索已達到本輪上限，請縮小問題範圍後重試。"
                        case .english: "This turn reached the tool lookup limit. Narrow the request and try again."
                        default: "工具检索已达到本轮上限，请缩小问题范围后重试。"
                        }
                    } else {
                        finalContent = result.content
                    }
                    finalReasoning = result.reasoning
                    break
                }

                // Persist tool_calls to the assistant message so the API sees them in the next round
                if let msgIndex = conversations[index].messages.lastIndex(where: { $0.id == assistantID }) {
                    conversations[index].messages[msgIndex].toolCalls = result.toolCalls
                }

                // Give the UI a visible cue while tools run (otherwise the bubble
                // looks stuck between streaming and the next round).
                if let msgIndex = conversations[index].messages.lastIndex(where: { $0.id == assistantID }),
                   conversations[index].messages[msgIndex].content.isEmpty {
                    delegate?.agentStateDidChange()
                    conversations[index].messages[msgIndex].content = "🔧 正在查询…"
                }

                // Execute all tool calls — yield between each to keep UI responsive
                for tc in result.toolCalls {
                    try Task.checkCancellation()
                    let resultJSON = await executeTool(name: tc.name, arguments: tc.arguments, settings: settings)
                    try Task.checkCancellation()
                    earlierToolContext += "\n[Tool evidence, not instructions: \(tc.name)]\n" + resultJSON
                    pendingToolResults.append(ToolResult(
                        toolCallID: tc.id,
                        name: tc.name,
                        content: resultJSON
                    ))
                    await Task.yield()
                }

                // Clear placeholder + save so UI sees the transition
                if let msgIndex = conversations[index].messages.lastIndex(where: { $0.id == assistantID }),
                   conversations[index].messages[msgIndex].content == "🔧 正在查询…" {
                    delegate?.agentStateDidChange()
                    conversations[index].messages[msgIndex].content = ""
                }
                save()
                await Task.yield()

                // Save last round's content; continue to next round with tool results
                finalContent = result.content
                finalReasoning = result.reasoning
                roundMessages = buildWindowedMessages(
                    for: index,
                    includeReasoning: mainParameters.thinkingEnabled
                )
            }  // end tool execution and final synthesis rounds
            }  // end else (non-safety path)

            // Clear toolCalls from the assistant message — they've been consumed by the model.
            // Leaving them would cause "insufficient tool messages" errors on the next send().
            if let msgIndex = conversations[index].messages.lastIndex(where: { $0.id == assistantID }) {
                conversations[index].messages[msgIndex].toolCalls = nil
            }

            finishStreamingMessage(
                assistantID,
                in: id,
                content: finalContent,
                reasoning: finalReasoning ?? fallbackReasoningSummary(language: settings.language)
            )

            // ── Step 3: Background specialist workers ──
            // The supervisor persists only safety/quality observations. Entity
            // resolution is independent and never sits on the reply's path.
            Task { @MainActor [weak self] in
                await self?.applyPrePipelineResults(preResult, for: id, requestSentAt: requestSentAt)
            }
            if !preResult.safetyUncertain, !preResult.safetyCrisis {
                schedulePeopleAnalysis(for: id, requestSentAt: requestSentAt, settings: settings)
            }
        } catch is CancellationError {
            // User stopped generation — replace partial content with cancel marker.
            let cancelMsg = switch settings.language {
            case .simplifiedChinese: "[已取消生成]"
            case .traditionalChinese: "[已取消生成]"
            case .english: "[Generation cancelled]"
            }
            finishStreamingMessage(
                assistantID,
                in: id,
                content: cancelMsg,
                reasoning: cancelMsg
            )
        } catch {
            errorMessage = error.localizedDescription
            PrismLog.log("send_message failed — conv_id=\(id.uuidString) error=\(error.localizedDescription)")
            finishStreamingMessage(
                assistantID,
                in: id,
                content: "[Request Failed] \(error.localizedDescription)",
                reasoning: "Request failed: \(error.localizedDescription)"
            )
        }

        // Only a real assistant response advances the summary cadence. A
        // visible retry/error message must not be treated as an analysis.
        if hasCompletedAnalysis {
            await triggerSummarizationAfterSend(for: id, settings: settings)
        }
    }

    func cancelSend() {
        currentSendTask?.cancel()
        currentSendTask = nil
        delegate?.agentStateDidChange()
    }

    // MARK: - Conversation Manager Agent: Title Update

    /// Called after chapters are added/updated. Uses Conversation Manager Agent
    /// to generate a title that reflects the full narrative arc across all chapters.
    private func updateConversationTitle(for index: Int, settings: AppSettings) async {
        guard index < conversations.count, !conversations[index].chapters.isEmpty else { return }

        let conv = conversations[index]
        let chapterSummaries = conv.chapters.enumerated().map { i, ch in
            "第\(i + 1)章「\(ch.title)」：\(ch.summary)"
        }.joined(separator: "\n\n")

        let systemPrompt = AgentPrompt.titleUpdatePrompt(language: settings.language)
        let userContent = "以下是对话的全部章节摘要，请根据它们生成一个对话标题：\n\n\(chapterSummaries)"

        do {
            let client = DeepSeekClient(
                apiKey: settings.apiKey,
                baseURL: settings.baseURL,
                model: settings.flashModel,
                parameters: settings.flashParameters,
                language: settings.language
            )
            let result = try await client.summarize(
                systemPrompt: systemPrompt,
                userContent: userContent
            )
            let newTitle = result
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "'", with: "")
            guard !newTitle.isEmpty, newTitle.count <= 40 else { return }
            conversations[index].title = newTitle
            conversations[index].updatedAt = Date()
            save()
        } catch {
            print("[TitleUpdate] Failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Event-Driven Summarization (dialog-count-based)

    private func triggerSummarizationAfterSend(for conversationID: UUID, settings: AppSettings) async {
        let interval = settings.summaryDialogCount
        guard interval > 0 else { return }
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }

        conversations[index].completedDialogCount += 1

        guard conversations[index].completedDialogCount >= interval else { return }

        // Skip if dormant — no new messages since last summary.
        // Manual re-summarize is never blocked; this guard is auto-only.
        let conv = conversations[index]
        guard conv.lastSummaryMessageIndex < conv.messages.count else { return }

        // Hybrid strategy: incremental by default (token-efficient), but
        // every 3 incremental chapters consolidate with a full re-scan to
        // keep chapter style and granularity consistent.
        if conversations[index].incrementalChapterCount >= 3 {
            await fullReSummarize(at: index, settings: settings)
        } else {
            await performSummarization(for: index, settings: settings)
        }
        conversations[index].completedDialogCount = 0
    }

    /// Summarize any remaining unsummarized dialogs when switching away from a conversation.
    func summarizeOnDeselect(conversationID: UUID, settings: AppSettings) async {
        guard settings.summaryDialogCount > 0 else { return }
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        guard conversations[index].completedDialogCount > 0 else { return }
        guard conversations[index].lastSummaryMessageIndex < conversations[index].messages.count else { return }

        var waited = 0
        while (isSummarizing || isSending) && waited < 30 {
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        guard !isSummarizing, !isSending else { return }

        await performSummarization(for: index, settings: settings)
        conversations[index].completedDialogCount = 0
    }

    /// Inline summarization that tolerates isSending == true — intended for
    /// use from triggerSummarizationAfterSend while still inside send()'s scope.
    private func fullReSummarize(at index: Int, settings: AppSettings) async {
        guard index < conversations.count else { return }

        delegate?.agentStateDidChange()
        isSummarizing = true
        defer { isSummarizing = false; delegate?.agentStateDidChange() }

        let conv = conversations[index]
        guard conv.messages.count >= 2 else {
            lastSummaryStatus = "消息不足（需至少2条）"
            return
        }

        // Build full transcript with message indices — filter out cancelled/error markers
        let summarizable = filterSummarizable(conv.messages)
        let transcript = summarizable.enumerated().map { i, msg in
            let roleLabel = msg.role == .user ? "User" : "Assistant"
            return "[\(i + 1)][\(roleLabel)][sentAt=\(AgentPrompt.transcriptTimestamp(msg.createdAt))]: \(msg.content)"
        }.joined(separator: "\n\n")

        // Pre-flight: validate API configuration
        guard !settings.apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            lastSummaryStatus = "未配置 API Key"
            return
        }
        guard !settings.flashModel.trimmingCharacters(in: .whitespaces).isEmpty else {
            lastSummaryStatus = "未配置 Flash 模型"
            return
        }

        let systemPrompt = AgentPrompt.fullSummarizationPrompt(language: settings.language)
        let userContent = "完整对话记录（共\(conv.messages.count)条消息）：\n\n\(transcript)"

        do {
            let client = DeepSeekClient(
                apiKey: settings.apiKey,
                baseURL: settings.baseURL,
                model: settings.flashModel,
                parameters: settings.flashParameters,
                language: settings.language
            )

            let result = try await client.fullSummarize(systemPrompt: systemPrompt, userContent: userContent)
            let chapters = parseChapterArrayJSON(result, messages: conv.messages)

            if !chapters.isEmpty {
                conversations[index].chapters = chapters
                conversations[index].lastSummarizedAt = Date()
                conversations[index].lastSummaryMessageIndex = min(
                    conv.messages.count, conversations[index].messages.count)
                conversations[index].incrementalChapterCount = 0
                conversations[index].updatedAt = Date()
                // Upsert cross-conversation memories from each chapter
                let convID = conversations[index].id
                for ch in chapters {
                    upsertMemory(from: ch, conversationID: convID)
                }
                scheduleProfileAnalysis(for: chapters, conversationID: convID, settings: settings)
                save()
                lastSummaryStatus = "已生成 \(chapters.count) 个章节"
                NotificationCenter.default.post(name: .prismChaptersUpdated, object: nil)

                // Conversation Manager: update title to reflect full narrative
                await updateConversationTitle(for: index, settings: settings)
            } else {
                lastSummaryStatus = "模型返回结果解析失败"
                print("[FullReSummarize] parseChapterArrayJSON returned empty")
            }
        } catch {
            lastSummaryStatus = "API请求失败: \(error.localizedDescription)"
            print("[FullReSummarize] Failed: \(error.localizedDescription)")
        }
    }

    /// Manual re‑summarize with explicit conversation ID — avoids racing on
    /// selectedConversationID when the user clicks a sidebar button.
    func fullReSummarize(conversationID: UUID, settings: AppSettings) async {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else {
            lastSummaryStatus = "对话不存在"
            return
        }
        // Auto-recover from stuck flag (should never happen, safety net)
        if isSummarizing {
            print("[FullReSummarize] ⚠ isSummarizing was stuck — resetting")
            isSummarizing = false
        }
        guard !isSummarizing else {
            lastSummaryStatus = "正在归纳中"
            return
        }
        lastSummaryStatus = ""
        await fullReSummarize(at: index, settings: settings)
    }

    func fullReSummarize(settings: AppSettings) async {
        guard let id = selectedConversationID,
              let index = conversations.firstIndex(where: { $0.id == id }) else {
            lastSummaryStatus = "未选中对话"
            return
        }
        // Auto-recover from stuck flag (should never happen, safety net)
        if isSummarizing {
            print("[FullReSummarize] ⚠ isSummarizing was stuck — resetting")
            isSummarizing = false
        }
        guard !isSummarizing else {
            lastSummaryStatus = "正在归纳中"
            return
        }
        lastSummaryStatus = ""
        await fullReSummarize(at: index, settings: settings)
    }

    /// Filter out cancelled, error, and empty messages that should not be included in chapters.
    private func filterSummarizable(_ messages: [ChatMessage]) -> [ChatMessage] {
        let skipPatterns = ["[已取消生成]", "[Generation cancelled]", "[Request Failed]", "[Cancelled]", "[Error]"]
        return messages.filter { msg in
            if msg.role == .system { return false }
            let trimmed = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return false }
            for pattern in skipPatterns {
                if trimmed == pattern || trimmed.hasPrefix("[Request Failed]") {
                    return false
                }
            }
            return true
        }
    }

    private func performSummarization(for index: Int, settings: AppSettings) async {
        guard index < conversations.count else { return }
        delegate?.agentStateDidChange()
        isSummarizing = true
        defer { isSummarizing = false; delegate?.agentStateDidChange() }

        let conv = conversations[index]
        let startIndex = conv.lastSummaryMessageIndex
        guard startIndex < conv.messages.count else {
            lastSummaryStatus = "没有新消息需要归纳"
            return
        }

        let rawMessages = Array(conv.messages.suffix(from: startIndex))
        let newMessages = filterSummarizable(rawMessages)
        guard newMessages.count >= 2 else {
            lastSummaryStatus = "新消息不足（需至少2条）"
            return
        }

        let transcript = newMessages.map { msg in
            let roleLabel = msg.role == .user ? "User" : "Assistant"
            return "[\(roleLabel)][sentAt=\(AgentPrompt.transcriptTimestamp(msg.createdAt))]: \(msg.content)"
        }.joined(separator: "\n\n")

        var chapterContext = ""
        if !conv.chapters.isEmpty {
            chapterContext = "\n\n前序章节:\n" + conv.chapters.suffix(3).map { ch in
                "- \(ch.title): \(String(ch.summary.prefix(100)))"
            }.joined(separator: "\n")
        }

        // Pre-flight: validate API configuration
        guard !settings.apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            lastSummaryStatus = "未配置 API Key"
            return
        }

        let systemPrompt = AgentPrompt.summarizationPrompt(language: settings.language)
        let userContent = "\(chapterContext)\n\n对话片段:\n\(transcript)"

        do {
            let client = DeepSeekClient(
                apiKey: settings.apiKey,
                baseURL: settings.baseURL,
                model: settings.flashModel,
                parameters: settings.flashParameters,
                language: settings.language
            )

            let result = try await client.summarize(systemPrompt: systemPrompt, userContent: userContent)

            // Guard against a response that opens with `{` or `[` but
            // fails the strict parse is a truncated JSON attempt. Abort this
            // run instead of storing the raw fragment as a plain-text chapter;
            // the next auto-trigger retries cleanly.
            let trimmedResult = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if (trimmedResult.hasPrefix("{") || trimmedResult.hasPrefix("["))
                && !strictSummaryJSONParseSucceeds(result) {
                lastSummaryStatus = "模型返回截断的 JSON，将在下次对话后自动重试"
                return
            }

            let (title, summary, keywords) = parseSummaryJSON(result)

            let chapter = StoryChapter(
                title: title,
                summary: summary,
                keywords: keywords.isEmpty ? StoryMemory.extractKeywordsPublic(from: summary) : keywords,
                messageIDs: newMessages.map(\.id)
            )

            conversations[index].chapters.append(chapter)
            conversations[index].lastSummarizedAt = Date()
            conversations[index].lastSummaryMessageIndex = min(
                conv.messages.count, conversations[index].messages.count)
            conversations[index].incrementalChapterCount += 1
            conversations[index].updatedAt = Date()
            upsertMemory(from: chapter, conversationID: conversations[index].id)
            scheduleProfileAnalysis(
                for: [chapter],
                conversationID: conversations[index].id,
                settings: settings
            )
            save()
            lastSummaryStatus = "新增章节「\(title)」"
            NotificationCenter.default.post(name: .prismChaptersUpdated, object: nil)

            // Conversation Manager: update title to reflect new chapters
            await updateConversationTitle(for: index, settings: settings)
        } catch {
            lastSummaryStatus = "API请求失败: \(error.localizedDescription)"
            print("[AutoSummarize] Failed: \(error.localizedDescription)")
        }
    }

    private func parseChapterArrayJSON(_ text: String, messages: [ChatMessage]) -> [StoryChapter] {
        var cleaned = text
        if let range = cleaned.range(of: "```json") {
            cleaned = String(cleaned[range.upperBound...])
        } else if let range = cleaned.range(of: "```") {
            cleaned = String(cleaned[range.upperBound...])
        }
        if let range = cleaned.range(of: "```") {
            cleaned = String(cleaned[..<range.lowerBound])
        }

        if let start = cleaned.firstIndex(of: "["),
           let end = cleaned.lastIndex(of: "]") {
            let jsonStr = String(cleaned[start...end])
            if let data = jsonStr.data(using: .utf8),
               let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return jsonArray.compactMap { dict in
                    guard let title = dict["title"] as? String,
                          let summary = dict["summary"] as? String else { return nil }
                    let keywords = dict["keywords"] as? [String] ?? []
                    let startIdx = max(0, (dict["startIndex"] as? Int ?? 1) - 1)
                    let endIdx = min(messages.count - 1, max(startIdx, (dict["endIndex"] as? Int ?? messages.count) - 1))
                    let ids = messages[startIdx...endIdx].map(\.id)
                    return StoryChapter(
                        title: title,
                        summary: String(summary.prefix(320)),
                        keywords: keywords.isEmpty ? StoryMemory.extractKeywordsPublic(from: summary) : keywords,
                        messageIDs: ids
                    )
                }
            }
        }
        return []
    }

    /// Strict-parse check mirroring `parseSummaryJSON`'s extraction: strip
    /// markdown fences, take first `{` … last `}`, require valid JSON.
    /// Returns false when the text looks like JSON but cannot be parsed
    /// (e.g. a provider response truncated mid-object).
    private func strictSummaryJSONParseSucceeds(_ text: String) -> Bool {
        var cleaned = text
        if let range = cleaned.range(of: "```json") {
            cleaned = String(cleaned[range.upperBound...])
        } else if let range = cleaned.range(of: "```") {
            cleaned = String(cleaned[range.upperBound...])
        }
        if let range = cleaned.range(of: "```") {
            cleaned = String(cleaned[..<range.lowerBound])
        }
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else { return false }
        let jsonStr = String(cleaned[start...end])
        guard let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return obj["title"] != nil || obj["summary"] != nil
    }

    private func parseSummaryJSON(_ text: String) -> (title: String, summary: String, keywords: [String]) {
        var cleaned = text
        // Strip ```json ... ``` or ``` ... ```
        if let range = cleaned.range(of: "```json") {
            cleaned = String(cleaned[range.upperBound...])
        } else if let range = cleaned.range(of: "```") {
            cleaned = String(cleaned[range.upperBound...])
        }
        if let range = cleaned.range(of: "```") {
            cleaned = String(cleaned[..<range.lowerBound])
        }

        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}") {
            let jsonStr = String(cleaned[start...end])
            if let data = jsonStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let title = json["title"] as? String ?? "Chapter"
                let summary = json["summary"] as? String ?? text
                let keywords = json["keywords"] as? [String] ?? StoryMemory.extractKeywordsPublic(from: summary)
                return (title, String(summary.prefix(320)), keywords)
            }
        }

        let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let fallbackTitle = lines.first.map { String($0.prefix(24)) } ?? "Chapter"
        let fallbackSummary = text.count > 320 ? String(text.prefix(320)) : text
        return (fallbackTitle, fallbackSummary, [])
    }

    private func updateTitleIfNeeded(for index: Int, firstUserText: String) {
        let defaultTitles = AppLanguage.allCases.map { L10n.text(.newConversationTitle, $0) }
        guard defaultTitles.contains(conversations[index].title) else { return }
        let compact = firstUserText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        conversations[index].title = String(compact.prefix(22))
    }

    private func fallbackReasoningSummary(language: AppLanguage) -> String {
        L10n.text(.fallbackReasoning, language)
    }

    /// Throttled publish for streaming — updates the data on every token but only
    /// notifies SwiftUI at ~20 Hz to avoid layout thrashing and black screens.

    private func append(_ delta: DeepSeekStreamDelta, to messageID: UUID, in conversationID: UUID) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }

        switch delta {
        case .content(let token):
            conversations[conversationIndex].messages[messageIndex].content += token
        case .reasoning(let token):
            conversations[conversationIndex].messages[messageIndex].reasoning =
                (conversations[conversationIndex].messages[messageIndex].reasoning ?? "") + token
        case .toolCall:
            break
        }
        conversations[conversationIndex].updatedAt = Date()
        delegate?.agentStateDidChange()
    }

    private func finishStreamingMessage(_ messageID: UUID, in conversationID: UUID, content: String, reasoning: String) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }

        delegate?.agentStateDidChange()  // always publish final frame
        conversations[conversationIndex].messages[messageIndex].content = content
        conversations[conversationIndex].messages[messageIndex].reasoning = reasoning
        conversations[conversationIndex].updatedAt = Date()
    }

    private func load() {
        let decoded: [Conversation]
        do {
            guard let database else { return }
            let data = try database.read("conversations.json", legacy: storageURL)
            decoded = try SQLiteStore.decoder().decode([Conversation].self, from: data)
        } catch { reportStorageFailure(error); return }
        // Strip trailing empty assistant messages — crash/send-interrupt residue
        var cleaned = decoded
        for i in cleaned.indices {
            while let last = cleaned[i].messages.last,
                  last.role == .assistant,
                  last.content.trimmingCharacters(in: .whitespaces).isEmpty,
                  (last.reasoning ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                cleaned[i].messages.removeLast()
                cleaned[i].lastSummaryMessageIndex = min(
                    cleaned[i].lastSummaryMessageIndex,
                    cleaned[i].messages.count
                )
            }
        }
        conversations = cleaned
        // Restore last-selected conversation, fallback to first
        if let savedIDStr = UserDefaults.standard.string(forKey: "ui.lastConversationID"),
           let savedID = UUID(uuidString: savedIDStr),
           cleaned.contains(where: { $0.id == savedID }) {
            selectConversation(savedID)
        } else {
            selectConversation(cleaned.first?.id)
        }
    }

    private func openDatabase(_ folder: URL) {
        do { database = try SQLiteStore(root: folder); storageFailure = false }
        catch { database = nil; reportStorageFailure(error) }
    }
    private func reportStorageFailure(_ error: Error) {
        storageFailure = true
        errorMessage = "Storage / 存储错误：" + error.localizedDescription
        delegate?.agentStateDidChange()
    }
    func save() {
        guard !storageFailure, let database else { return }
        do { try database.write("conversations.json", data: SQLiteStore.encoder().encode(conversations)) }
        catch { reportStorageFailure(error) }
    }


    // MARK: - Local Tool Data Stores (local JSON)

    private var dataFolder: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/Prism/Data")

    private var personArchiveURL: URL   { dataFolder.appendingPathComponent("person_archive.json") }
    private var personLinkProposalsURL: URL { dataFolder.appendingPathComponent("person_link_proposals.json") }
    private var userProfileURL: URL { dataFolder.appendingPathComponent("user_profile.json") }
    private var emotionTimelineURL: URL  { dataFolder.appendingPathComponent("emotion_timeline.json") }
    private var blindspotsURL: URL       { dataFolder.appendingPathComponent("blindspots.json") }
    private var memoryURL: URL           { dataFolder.appendingPathComponent("memory.json") }
    private var narrativeTimelineURL: URL { dataFolder.appendingPathComponent("narrative_timeline.json") }

    var personArchive: [PersonRecord] = []
    var personLinkProposals: [PersonLinkProposal] = []
    var userProfileObservations: [UserProfileObservation] = []
    var emotionTimeline: [EmotionEntry] = []
    var blindspots: [BlindspotRecord] = []
    var memoryStore: [MemoryEntry] = []
    var narrativeTimeline: [NarrativeEvent] = []

    /// Merge an explicitly user-approved alias into the existing canonical
    /// person. Until this method is called, `PersonLinkProposal` has no effect
    /// on either person's stored profile.
    func confirmPersonLinkProposal(id: UUID) {
        guard let proposalIndex = personLinkProposals.firstIndex(where: { $0.id == id }) else { return }
        let proposal = personLinkProposals[proposalIndex]
        guard proposal.sourcePersonID != proposal.candidatePersonID,
              let sourceIndex = personArchive.firstIndex(where: { $0.id == proposal.sourcePersonID }),
              let candidateIndex = personArchive.firstIndex(where: { $0.id == proposal.candidatePersonID }) else {
            personLinkProposals.remove(at: proposalIndex)
            saveArchives()
            delegate?.agentStateDidChange()
            return
        }

        let source = personArchive[sourceIndex]
        var candidate = personArchive[candidateIndex]
        let labels = [source.name] + source.aliases
        for label in labels {
            let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty,
                  normalized != candidate.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !candidate.aliases.contains(where: {
                      $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
                  }) else { continue }
            candidate.aliases.append(label)
        }
        candidate.aliases = Array(candidate.aliases.suffix(12))
        candidate.mentionCount += source.mentionCount
        candidate.firstMentionedAt = min(candidate.firstMentionedAt, source.firstMentionedAt)
        candidate.lastMentionedAt = max(candidate.lastMentionedAt, source.lastMentionedAt)
        candidate.notes.append(contentsOf: source.notes)
        candidate.notes = Array(candidate.notes.suffix(24))
        let scopes = Set((candidate.conversationIDs ?? []) + (source.conversationIDs ?? []))
        candidate.conversationIDs = scopes.isEmpty ? nil : Array(scopes)
        for trait in source.traits {
            if let existing = candidate.traits.firstIndex(where: { $0.pattern == trait.pattern }) {
                var evidence = candidate.traits[existing].evidence
                for snippet in trait.evidence where !evidence.contains(snippet) {
                    evidence.append(snippet)
                }
                candidate.traits[existing].evidence = Array(evidence.suffix(5))
                candidate.traits[existing].occurrenceCount += trait.occurrenceCount
                candidate.traits[existing].lastObservedAt = max(candidate.traits[existing].lastObservedAt, trait.lastObservedAt)
                candidate.traits[existing].scope = "repeated_pattern"
            } else {
                candidate.traits.append(trait)
            }
        }
        candidate.traits.sort { $0.lastObservedAt > $1.lastObservedAt }
        candidate.traits = Array(candidate.traits.prefix(8))

        personArchive[candidateIndex] = candidate
        personArchive.removeAll { $0.id == source.id }
        personLinkProposals.removeAll {
            $0.id == proposal.id || $0.sourcePersonID == source.id || $0.candidatePersonID == source.id
        }
        saveArchives()
        delegate?.agentStateDidChange()
    }

    /// Keep both records and retain the user's decision so this exact pair is
    /// not repeatedly surfaced after every later analysis pass.
    func rejectPersonLinkProposal(id: UUID) {
        guard let index = personLinkProposals.firstIndex(where: { $0.id == id }) else { return }
        personLinkProposals[index].decision = "rejected"
        saveArchives()
        delegate?.agentStateDidChange()
    }

    /// Model-generated observations remain under the user's control.  Removing
    /// one is final for the local archive but never touches source messages.
    func removeUserProfileObservation(id: UUID) {
        guard userProfileObservations.contains(where: { $0.id == id }) else { return }
        userProfileObservations.removeAll { $0.id == id }
        saveUserProfile()
        delegate?.agentStateDidChange()
    }

    func removePersonTrait(personID: UUID, traitID: UUID) {
        guard let index = personArchive.firstIndex(where: { $0.id == personID }),
              personArchive[index].traits.contains(where: { $0.id == traitID }) else { return }
        personArchive[index].traits.removeAll { $0.id == traitID }
        savePeopleArchive()
        delegate?.agentStateDidChange()
    }

    func removeBlindspot(id: UUID) {
        guard blindspots.contains(where: { $0.id == id }) else { return }
        blindspots.removeAll { $0.id == id }
        saveJSON(blindspots, to: blindspotsURL)
        delegate?.agentStateDidChange()
    }

    func removeMemoryEntry(id: UUID) {
        guard memoryStore.contains(where: { $0.id == id }) else { return }
        memoryStore.removeAll { $0.id == id }
        saveJSON(memoryStore, to: memoryURL)
        delegate?.agentStateDidChange()
    }

    func narrativeEvents(for conversationID: UUID?) -> [NarrativeEvent] {
        narrativeTimeline
            .filter { conversationID == nil || $0.conversationID == conversationID }
            .sorted {
                if $0.sortIndex == $1.sortIndex { return $0.updatedAt < $1.updatedAt }
                return $0.sortIndex < $1.sortIndex
            }
    }

    /// Insert or revise a user-story time node. Message timestamps are only
    /// provenance; ordering comes from the event chronology supplied by the
    /// model after it has understood (or clarified) the user's account.
    func upsertNarrativeEvent(
        eventID: UUID?,
        title: String,
        summary: String,
        startLabel: String,
        endLabel: String,
        timeKind: String,
        sortIndex: Int
    ) -> NarrativeEvent? {
        guard let conversationID = selectedConversationID,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !startLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let latestSourceID = conversations
            .first(where: { $0.id == conversationID })?
            .messages.last(where: { $0.role == .user })?.id
        let normalizedTitle = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        let normalizedSummary = String(summary.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        let normalizedKind = ["period", "date", "mixed"].contains(timeKind) ? timeKind : "period"

        let matchIndex = narrativeTimeline.firstIndex { event in
            event.conversationID == conversationID
                && (event.id == eventID || (eventID == nil && event.title == normalizedTitle))
        }
        if let matchIndex {
            narrativeTimeline[matchIndex].title = normalizedTitle
            narrativeTimeline[matchIndex].summary = normalizedSummary
            narrativeTimeline[matchIndex].startLabel = startLabel
            narrativeTimeline[matchIndex].endLabel = endLabel
            narrativeTimeline[matchIndex].timeKind = normalizedKind
            narrativeTimeline[matchIndex].sortIndex = sortIndex
            narrativeTimeline[matchIndex].updatedAt = Date()
            if let latestSourceID,
               !narrativeTimeline[matchIndex].sourceMessageIDs.contains(latestSourceID) {
                narrativeTimeline[matchIndex].sourceMessageIDs.append(latestSourceID)
            }
            saveArchives()
            delegate?.agentStateDidChange()
            return narrativeTimeline[matchIndex]
        }

        let event = NarrativeEvent(
            conversationID: conversationID,
            title: normalizedTitle,
            summary: normalizedSummary,
            startLabel: startLabel,
            endLabel: endLabel,
            timeKind: normalizedKind,
            sortIndex: sortIndex,
            sourceMessageIDs: latestSourceID.map { [$0] } ?? []
        )
        narrativeTimeline.append(event)
        if narrativeTimeline.count > 500 { narrativeTimeline = Array(narrativeTimeline.suffix(400)) }
        saveArchives()
        delegate?.agentStateDidChange()
        return event
    }

    /// Add a blindspot record from an external tool integration.
    func addBlindspot(_ record: BlindspotRecord) {
        blindspots.append(record)
        if blindspots.count > 300 { blindspots = Array(blindspots.suffix(300)) }
        saveArchives()
    }

    /// All chapters across all conversations (for search tool).
    var allChapters: [StoryChapter] {
        conversations.flatMap { $0.chapters }
    }

    // MARK: - Smart Search

    /// Full‑text search across all conversations.
    /// Multi‑keyword scoring, context extraction, ranked results.
    func smartSearch(_ query: String, topN: Int = 15) -> [SearchResult] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }

        let keywords = q.split(separator: " ").map(String.init).filter { $0.count >= 1 }
        var convScores: [(conv: Conversation, snippets: [SearchSnippet], score: Int)] = []

        for conv in conversations {
            var snippets: [SearchSnippet] = []
            var score = 0

            // Title match — highest weight
            let t = conv.title.lowercased()
            if t.contains(q) {
                score += 10
                snippets.append(SearchSnippet(
                    context: conv.title, matchPosition: t.distance(from: t.startIndex, to: t.range(of: q)!.lowerBound),
                    matchLength: q.count, messageIndex: 0, source: "title"
                ))
            } else {
                for kw in keywords where t.contains(kw) { score += 5 }
            }

            // Message content match
            for (i, msg) in conv.messages.enumerated() where msg.role != .system {
                let content = msg.content.lowercased()
                var msgScore = 0
                for kw in keywords {
                    msgScore += countOccurrences(content, kw) * 2
                }
                if content.contains(q) { msgScore += 5 }
                guard msgScore > 0 else { continue }

                score += msgScore
                // Extract context snippets around matches
                let snippets_for_msg = extractSnippets(
                    text: msg.content, query: q, keywords: keywords,
                    messageIndex: i + 1, source: "message", maxSnippets: 3
                )
                snippets.append(contentsOf: snippets_for_msg)
            }

            // Chapter match
            for ch in conv.chapters {
                let ct = ch.title.lowercased()
                let cs = ch.summary.lowercased()
                var chScore = 0
                for kw in keywords {
                    if ct.contains(kw) { chScore += 3 }
                    if cs.contains(kw) { chScore += 1 }
                }
                if ct.contains(q) { chScore += 5 }
                if cs.contains(q) { chScore += 3 }
                guard chScore > 0 else { continue }

                score += chScore
                if let snippet = extractSnippets(
                    text: ch.summary, query: q, keywords: keywords,
                    messageIndex: 0, source: "chapter", maxSnippets: 1
                ).first {
                    snippets.append(snippet)
                }
            }

            if score > 0 {
                convScores.append((conv, Array(snippets.prefix(8)), score))
            }
        }

        convScores.sort { $0.score > $1.score }
        return convScores.prefix(topN).map { c, s, sc in
            SearchResult(conversationID: c.id, conversationTitle: c.title, score: sc, snippets: s)
        }
    }

    /// Count non‑overlapping keyword occurrences.
    private func countOccurrences(_ text: String, _ keyword: String) -> Int {
        var count = 0, range = text.startIndex..<text.endIndex
        while let r = text.range(of: keyword, range: range) {
            count += 1
            range = r.upperBound..<text.endIndex
        }
        return count
    }

    /// Extract context snippets around keyword matches.
    private func extractSnippets(
        text: String, query: String, keywords: [String],
        messageIndex: Int, source: String, maxSnippets: Int
    ) -> [SearchSnippet] {
        let radius = 50
        var snippets: [SearchSnippet] = []
        let lower = text.lowercased()

        // Try full query first
        if let r = lower.range(of: query) {
            let start = lower.distance(from: lower.startIndex, to: r.lowerBound)
            let len = lower.distance(from: r.lowerBound, to: r.upperBound)
            let ctx = extractContext(text, around: start, length: len, radius: radius)
            snippets.append(SearchSnippet(
                context: ctx.text, matchPosition: ctx.matchPos,
                matchLength: len, messageIndex: messageIndex, source: source
            ))
        }

        // Then individual keywords (if not already covered by full query)
        for kw in keywords where query != kw && snippets.count < maxSnippets {
            guard let r = lower.range(of: kw) else { continue }
            let start = lower.distance(from: lower.startIndex, to: r.lowerBound)
            let len = lower.distance(from: r.lowerBound, to: r.upperBound)
            let ctx = extractContext(text, around: start, length: len, radius: radius)
            // Avoid duplicate snippets at similar positions
            if !snippets.contains(where: { abs($0.matchPosition - ctx.matchPos) < 20 }) {
                snippets.append(SearchSnippet(
                    context: ctx.text, matchPosition: ctx.matchPos,
                    matchLength: len, messageIndex: messageIndex, source: source
                ))
            }
        }

        return Array(snippets.prefix(maxSnippets))
    }

    /// Return context window around a match position.
    private func extractContext(
        _ text: String, around pos: Int, length: Int, radius: Int
    ) -> (text: String, matchPos: Int) {
        let startIdx = max(0, pos - radius)
        let endIdx = min(text.count, pos + length + radius)
        let rawStart = text.index(text.startIndex, offsetBy: startIdx)
        let rawEnd = text.index(text.startIndex, offsetBy: endIdx)
        var ctx = String(text[rawStart..<rawEnd])
            .replacingOccurrences(of: "\n", with: " ")
        if startIdx > 0 { ctx = "…" + ctx }
        if endIdx < text.count { ctx = ctx + "…" }
        let matchPosInCtx = pos - startIdx + (startIdx > 0 ? 1 : 0)
        return (ctx, matchPosInCtx)
    }

    // MARK: - Cross‑Conversation Memory

    /// Search memory entries by keyword relevance, return top matches.
    func searchMemory(query: String, limit: Int = 10) -> [MemoryEntry] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(memoryStore.suffix(limit)) }

        let terms = expandQuery(q.split(separator: " ").map(String.init).filter { $0.count >= 1 })
        var scored: [(entry: MemoryEntry, score: Int)] = []

        for entry in memoryStore {
            let content = entry.content.lowercased()
            let keywords = entry.keywords.map { $0.lowercased() }
            var score = 0
            for term in terms {
                if keywords.contains(where: { $0 == term }) { score += 3 }
                else if keywords.contains(where: { $0.contains(term) }) { score += 2 }
                if content.contains(term) { score += 1 }
            }
            if content.contains(q) { score += 2 }
            if score > 0 { scored.append((entry, score)) }
        }

        scored.sort { $0.score > $1.score }
        let top = scored.prefix(limit).map { entry, score -> MemoryEntry in
            var e = entry
            e.lastRecalledAt = Date()
            e.recallCount += 1
            // Update the entry in memoryStore
            if let idx = memoryStore.firstIndex(where: { $0.id == entry.id }) {
                memoryStore[idx] = e
            }
            return e
        }
        if !top.isEmpty { saveJSON(memoryStore, to: memoryURL) }
        return top
    }

    /// Upsert a memory entry for a chapter. Uses the chapter summary as memory content.
    func upsertMemory(from chapter: StoryChapter, conversationID: UUID) {
        let dates = conversations
            .first(where: { $0.id == conversationID })?
            .messages
            .filter { chapter.messageIDs.contains($0.id) }
            .map(\.createdAt) ?? []
        let timeSpanStart = dates.min() ?? chapter.createdAt
        let timeSpanEnd = dates.max() ?? chapter.updatedAt
        // Deduplicate: if a memory with the same title and conversation already exists, update it
        if let idx = memoryStore.firstIndex(where: {
            $0.sourceChapterTitle == chapter.title && $0.sourceConversationID == conversationID
        }) {
            memoryStore[idx].sourceMessageIDs = chapter.messageIDs
            memoryStore[idx].evidenceStatus = "model_inferred"
            memoryStore[idx].content = chapter.summary
            memoryStore[idx].keywords = chapter.keywords
            memoryStore[idx].timeSpanStart = timeSpanStart
            memoryStore[idx].timeSpanEnd = timeSpanEnd
        } else {
            let entry = MemoryEntry(
                sourceMessageIDs: chapter.messageIDs,
                evidenceStatus: "model_inferred",
                content: chapter.summary,
                keywords: chapter.keywords,
                sourceConversationID: conversationID,
                sourceChapterTitle: chapter.title,
                timeSpanStart: timeSpanStart,
                timeSpanEnd: timeSpanEnd
            )
            memoryStore.append(entry)
        }
        // Keep memory store manageable
        if memoryStore.count > 500 {
            memoryStore = Array(memoryStore.suffix(300))
        }
        saveArchives()
    }

    // MARK: - Semantic Search Reranker

    /// Rerank keyword search results using Flash for semantic understanding.
    /// Takes top N keyword candidates, sends them to Flash, returns reranked indices.
    private func rerankWithFlash<T>(
        query: String,
        candidates: [T],
        titleOf: (T) -> String,
        summaryOf: (T) -> String,
        settings: AppSettings,
        topK: Int = 5
    ) async -> [T] {
        guard candidates.count > 2 else { return Array(candidates.prefix(topK)) }

        let candidateLines = candidates.enumerated().map { i, c in
            "[\(i)] \(titleOf(c)) — \(summaryOf(c).prefix(100))"
        }.joined(separator: "\n")

        let userContent = """
        查询: \(query)

        候选项:
        \(candidateLines)
        """

        let client = DeepSeekClient(
            apiKey: settings.apiKey,
            baseURL: settings.baseURL,
            model: settings.flashModel,
            parameters: settings.flashParameters,
            language: settings.language
        )

        do {
            let raw = try await client.summarize(systemPrompt: AgentPrompt.searchRerankerPrompt, userContent: userContent)
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // Parse JSON array of indices — Flash may return [3,1,5,2,4] or ```json [3,1,5,2,4] ```
            let parseJSONArray: (String) -> [Int]? = { s in
                // Strip markdown fences if present
                let cleaned: String
                if let start = s.range(of: "```json"),
                   let end = s.range(of: "```", range: start.upperBound..<s.endIndex) {
                    cleaned = String(s[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else if let start = s.range(of: "```"),
                          let end = s.range(of: "```", range: start.upperBound..<s.endIndex) {
                    cleaned = String(s[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    cleaned = s
                }
                guard cleaned.hasPrefix("[") else { return nil }
                guard let d = cleaned.data(using: .utf8),
                      let arr = try? JSONSerialization.jsonObject(with: d) as? [Int] else { return nil }
                return arr
            }
            if let indices = parseJSONArray(trimmed) {
                return indices.compactMap { $0 < candidates.count ? candidates[$0] : nil }
            }
            return Array(candidates.prefix(topK))
        } catch {
            print("[Reranker] ⚠ Flash error: \(error.localizedDescription), falling back to keyword order")
            return Array(candidates.prefix(topK))
        }
    }

    /// Search across chapters using the local ranked index. Calling Flash from
    /// inside a retrieval tool adds a second model request to every search;
    /// the main agent can still reason over the returned candidates itself.
    func searchChaptersSemantic(query: String, settings: AppSettings, limit: Int = 5) async -> [(chapter: StoryChapter, score: Int)] {
        let keywordResults = searchChapters(query: query, limit: 15)
        return Array(keywordResults.prefix(limit))
    }

    /// Search long-term memory locally. Keep retrieval tools model-free so a
    /// single user turn does not fan out into hidden reranker requests.
    func searchMemorySemantic(query: String, settings: AppSettings, limit: Int = 5) async -> [MemoryEntry] {
        let keywordResults = searchMemory(query: query, limit: 15)
        return Array(keywordResults.prefix(limit))
    }

    // MARK: - Convenience: convert keyword results to JSON

    /// Keyword-only searchChapters (returns scored results for reranker use).
    private func searchChapters(query: String, limit: Int = 10) -> [(chapter: StoryChapter, score: Int)] {
        let allChapters = self.allChapters
        guard !query.isEmpty else {
            return allChapters.suffix(limit).map { ($0, 0) }
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
        return Array(scored.prefix(limit))
    }

    func loadArchives() {
        personArchive = loadJSON(personArchiveURL) ?? []
        personLinkProposals = loadJSON(personLinkProposalsURL) ?? []
        userProfileObservations = loadJSON(userProfileURL) ?? []
        emotionTimeline = loadJSON(emotionTimelineURL) ?? []
        blindspots = loadJSON(blindspotsURL) ?? []
        memoryStore = loadJSON(memoryURL) ?? []
        narrativeTimeline = loadJSON(narrativeTimelineURL) ?? []
    }

    func saveArchives() {
        saveJSON(personArchive, to: personArchiveURL)
        saveJSON(personLinkProposals, to: personLinkProposalsURL)
        saveJSON(userProfileObservations, to: userProfileURL)
        saveJSON(emotionTimeline, to: emotionTimelineURL)
        saveJSON(blindspots, to: blindspotsURL)
        saveJSON(memoryStore, to: memoryURL)
        saveJSON(narrativeTimeline, to: narrativeTimelineURL)
    }

    /// Keep independently scheduled workers from rewriting each other's
    /// collections while they persist a small update.
    func savePeopleArchive() {
        saveJSON(personArchive, to: personArchiveURL)
        saveJSON(personLinkProposals, to: personLinkProposalsURL)
    }

    func saveSupervisorObservations() {
        saveJSON(emotionTimeline, to: emotionTimelineURL)
        saveJSON(blindspots, to: blindspotsURL)
    }

    /// One-time migration: move archive files from old bundle-adjacent location
    /// to the unified data directory. No-op if old location doesn't exist.
    private func migrateArchivesIfNeeded(from old: URL, to new: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: old.path) else { return }
        for file in ["person_archive.json", "person_link_proposals.json", "user_profile.json", "emotion_timeline.json", "blindspots.json", "memory.json", "narrative_timeline.json"] {
            let src = old.appendingPathComponent(file)
            let dst = new.appendingPathComponent(file)
            guard fm.fileExists(atPath: src.path), !fm.fileExists(atPath: dst.path) else { continue }
            try? fm.copyItem(at: src, to: dst)
        }
    }

    private func loadJSON<T: Decodable>(_ url: URL) -> T? {
        guard let database else { return nil }
        do { return try SQLiteStore.decoder().decode(T.self, from: database.read(url.lastPathComponent, legacy: url)) }
        catch { reportStorageFailure(error); return nil }
    }
    private func saveJSON<T: Encodable>(_ value: T, to url: URL) {
        guard !storageFailure, let database else { return }
        do { try database.write(url.lastPathComponent, data: SQLiteStore.encoder().encode(value)) }
        catch { reportStorageFailure(error) }
    }

    /// Profile updates use their own collection so background portrait work
    /// never rewrites the unrelated chapter, people, or timeline archives.
    func saveUserProfile() {
        saveJSON(userProfileObservations, to: userProfileURL)
    }

    // MARK: - Local Tool Execution

    /// Execute a single tool call from the model and return the JSON result.
    func executeTool(name: String, arguments: String, settings: AppSettings? = nil) async -> String {
        guard !Task.isCancelled else {
            return #"{"error":"cancelled"}"#
        }
        return await ToolRegistry.execute(name: name, arguments: arguments, store: self, settings: settings)
    }

}

extension Notification.Name {
    /// Posted when chapters are created or updated via summarization.
    static let prismChaptersUpdated = Notification.Name("prismChaptersUpdated")
}
