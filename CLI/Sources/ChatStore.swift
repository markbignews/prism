import Foundation


@MainActor
final class ChatStore {
    private(set) var conversations: [Conversation] = []
    var selectedConversationID: Conversation.ID?
    var isSending = false
    var errorMessage: String?
    var isSummarizing = false
    var currentSendTask: Task<Void, Never>?
    /// Status of the last summarization attempt (empty = never run / nothing to report).
    var lastSummaryStatus: String = ""

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
        if conversations.isEmpty {
            createConversation(language: language)
        } else if selectedConversationID == nil {
            selectConversation(conversations.first?.id)
        }
    }

    func createConversation(language: AppLanguage = .simplifiedChinese) {
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
        conversations.removeAll { $0.id == selectedConversationID }
        self.selectConversation(conversations.first?.id)
        if conversations.isEmpty {
            createConversation()
        } else {
            save()
        }
    }

    func deleteConversation(id: UUID) {
        conversations.removeAll { $0.id == id }
        if selectedConversationID == id {
            selectConversation(conversations.first?.id)
        }
        // Also clean up orphaned post-pipeline records
        personArchive.removeAll { p in
            !conversations.contains { $0.messages.contains { $0.content.localizedCaseInsensitiveContains(p.name) } }
        }
        emotionTimeline.removeAll { $0.conversationID == id }
        blindspots.removeAll { $0.conversationID == id }
        memoryStore.removeAll { $0.sourceConversationID == id }
        saveArchives()

        if conversations.isEmpty {
            createConversation()
        } else {
            save()
        }
    }

    func resetAll() {
        conversations = []
        selectedConversationID = nil
        personArchive = []
        emotionTimeline = []
        blindspots = []
        memoryStore = []
    }

    /// Reload conversations and archives from the current data path.
    /// Call after changing `AppSettings.dataPath` and migrating files.
    func reloadStorage(from settings: AppSettings? = nil) {
        let dataPath = settings?.dataPath
            ?? UserDefaults.standard.string(forKey: "storage.dataPath")
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/Prism").path
        let folder = URL(fileURLWithPath: dataPath)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storageURL = folder.appendingPathComponent("conversations.json")
        dataFolder = folder.appendingPathComponent("Data", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true)

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

    func deleteMessage(in conversationID: UUID, messageID: UUID) {
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

        // Clean chapter messageIDs — drop deleted IDs, remove empty chapters
        var chapters = conversations[convIndex].chapters
        let oldChapterCount = chapters.count
        for i in (0..<chapters.count).reversed() {
            chapters[i].messageIDs.removeAll { removedIDs.contains($0) }
            if chapters[i].messageIDs.isEmpty {
                chapters.remove(at: i)
            }
        }
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

        // Remove this assistant message
        conversations[convIndex].messages.remove(at: msgIndex)
        conversations[convIndex].updatedAt = Date()
        save()

        // Resend
        isSending = true
        defer {
            isSending = false
            save()
        }

        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        var memoryContext = StoryMemory.relevantContext(for: trimmed, in: conversations[convIndex], language: settings.language)
        let crossMemories = searchMemory(query: trimmed, limit: 3)
        if !crossMemories.isEmpty {
            let crossHeading = switch settings.language {
            case .simplifiedChinese: "\n\n[跨对话记忆]"
            case .traditionalChinese: "\n\n[跨對話記憶]"
            case .english: "\n\n[Cross-conversation memory]"
            }
            let crossBody = crossMemories.enumerated().map { i, m in
                "\(i + 1). \(m.sourceChapterTitle): \(String(m.content.prefix(200)))"
            }.joined(separator: "\n")
            let crossBlock = crossHeading + "\n" + crossBody
            if let existing = memoryContext {
                memoryContext = existing + crossBlock
            } else {
                memoryContext = crossBlock
            }
        }
        errorMessage = nil

        let assistantID = UUID()
        conversations[convIndex].messages.append(
            ChatMessage(id: assistantID, role: .assistant, content: "", reasoning: nil)
        )
        save()

        do {
            let client = DeepSeekClient(
                apiKey: settings.apiKey,
                baseURL: settings.baseURL,
                model: settings.model,
                parameters: settings.parameters,
                language: settings.language,
                mode: settings.conversationMode,
                responseLength: settings.responseLength
            )
            let requestMessages = buildWindowedMessages(for: convIndex)
            let result = try await client.stream(
                messages: requestMessages,
                memoryContext: memoryContext
            ) { [weak self] delta in
                self?.append(delta, to: assistantID, in: conversationID)
            }
            finishStreamingMessage(
                assistantID,
                in: conversationID,
                content: result.content,
                reasoning: result.reasoning ?? fallbackReasoningSummary(language: settings.language)
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

    /// Build a context-aware message list.  For normal-length conversations
    /// (≤60 messages) everything is sent in full — DeepSeek's 1M context is a
    /// strategic advantage we preserve.  Only extreme-length conversations are
    /// windowed, and even then the agent can retrieve compressed content via
    /// `search_chapters`.
    private func buildWindowedMessages(for index: Int) -> [ChatMessage] {
        let conv = conversations[index]
        let threshold = 60   // 30 exchanges — above this, activate windowing

        guard conv.messages.count > threshold else {
            // Normal conversation: send everything.  Inject a lightweight
            // chapter index so the agent knows what else is available.
            let indexMsg = chapterIndexMessage(for: conv)
            if let idx = indexMsg {
                return [idx] + conv.messages
            }
            return conv.messages
        }

        // Extreme-length conversation: keep last 40 messages in full, compress
        // older content into chapter summaries.
        let windowSize = 40
        let splitPoint = conv.messages.count - windowSize
        let recent = Array(conv.messages.suffix(windowSize))

        // Build compressed context from chapters
        let olderIDs = Set(conv.messages.prefix(splitPoint).map(\.id))
        let coveringChapters = conv.chapters.filter { ch in
            ch.messageIDs.contains { olderIDs.contains($0) }
        }

        let contextLines: String
        if coveringChapters.isEmpty {
            contextLines = conv.chapters.prefix(5).map { ch in
                "▸ \(ch.title): \(String(ch.summary.prefix(150)))"
            }.joined(separator: "\n")
        } else {
            contextLines = coveringChapters.map { ch in
                "▸ \(ch.title): \(String(ch.summary.prefix(200)))"
            }.joined(separator: "\n")
        }

        var header = "[历史压缩 — 对话较长，以下为旧内容的章节摘要。"
        header += "如需原文细节，调用 search_chapters 或 fetch_chapter_messages]\n"
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

    func send(_ text: String, settings: AppSettings) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        bootstrapIfNeeded(language: settings.language)
        guard let id = selectedConversationID,
              let index = conversations.firstIndex(where: { $0.id == id }) else { return }

        // Build memory context: local StoryMemory + cross-conversation memories
        var memoryContext = StoryMemory.relevantContext(for: trimmed, in: conversations[index], language: settings.language)
        let crossMemories = searchMemory(query: trimmed, limit: 3)
        if !crossMemories.isEmpty {
            let crossHeading = switch settings.language {
            case .simplifiedChinese: "\n\n[跨对话记忆 — 来自之前对话的相关洞察]"
            case .traditionalChinese: "\n\n[跨對話記憶 — 來自之前對話的相關洞察]"
            case .english: "\n\n[Cross-conversation memory — relevant insights from previous conversations]"
            }
            let crossBody = crossMemories.enumerated().map { i, m in
                "\(i + 1). \(m.sourceChapterTitle): \(String(m.content.prefix(200)))"
            }.joined(separator: "\n")
            let crossBlock = crossHeading + "\n" + crossBody
            if let existing = memoryContext {
                memoryContext = existing + crossBlock
            } else {
                memoryContext = crossBlock
            }
        }
        errorMessage = nil
        let userMessage = ChatMessage(role: .user, content: trimmed)
        conversations[index].messages.append(userMessage)
        StoryMemory.ingest(userText: trimmed, messageID: userMessage.id, conversation: &conversations[index])
        conversations[index].updatedAt = Date()
        updateTitleIfNeeded(for: index, firstUserText: trimmed)

        let requestMessages = buildWindowedMessages(for: index)
        let assistantID = UUID()
        conversations[index].messages.append(
            ChatMessage(id: assistantID, role: .assistant, content: "", reasoning: nil)
        )
        save()

        isSending = true
        var finalContent = ""
        var finalReasoning: String?
        defer {
            isSending = false
            save()
        }

        do {
            // ── Step 1: Pre-pipeline — unified Flash call (guard + emotion + person + blindspots) ──
            let preResult = await runPrePipeline(for: id, settings: settings)
            let guardHint = buildGuardHint(from: preResult)

            // ── Safety crisis — skip main model, return immediate safety response ──
            if preResult.safetyCrisis {
                finalContent = buildSafetyResponse(
                    signals: preResult.safetySignals,
                    hint: preResult.safetyHint,
                    resources: preResult.safetyResources,
                    language: settings.language
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
            let client = DeepSeekClient(
                apiKey: settings.apiKey,
                baseURL: settings.baseURL,
                model: settings.model,
                parameters: settings.parameters,
                language: settings.language,
                mode: settings.conversationMode,
                responseLength: settings.responseLength
            )

            var roundMessages = requestMessages
            var pendingToolResults: [ToolResult] = []
            let maxToolRounds = 3

            for _ in 0..<maxToolRounds {
                let result = try await client.stream(
                    messages: roundMessages,
                    memoryContext: memoryContext,
                    supervisorHint: guardHint,
                    tools: ToolRegistry.definitions,
                    toolResults: pendingToolResults
                ) { [weak self] delta in
                    self?.append(delta, to: assistantID, in: id)
                }

                pendingToolResults = []

                // If the model responds with content and no more tool calls, we're done
                if result.toolCalls.isEmpty {
                    finalContent = result.content
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
                    conversations[index].messages[msgIndex].content = "🔧 正在查询…"
                }

                // Execute all tool calls — yield between each to keep UI responsive
                for tc in result.toolCalls {
                    let resultJSON = await executeTool(name: tc.name, arguments: tc.arguments, settings: settings)
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
                    conversations[index].messages[msgIndex].content = ""
                }
                save()
                await Task.yield()

                // Save last round's content; continue to next round with tool results
                finalContent = result.content
                finalReasoning = result.reasoning
                roundMessages = buildWindowedMessages(for: index)
            }  // end for _ in 0..<maxToolRounds
            }  // end else (non-safety path)

            // If we exited the loop with tool_calls still pending (max rounds), use last content

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

            // ── Step 3: Apply pre-pipeline archive updates (detached, non-blocking) ──
            Task.detached { [weak self] in
                await self?.applyPrePipelineResults(preResult, for: id)
            }
        } catch is CancellationError {
            // User stopped generation — keep partial content with a cancelled marker.
            let existingContent = conversations[index].messages.first(where: { $0.id == assistantID })?.content ?? ""
            let baseContent = finalContent.isEmpty ? existingContent : finalContent
            let displayContent: String
            if baseContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                displayContent = "[Cancelled]"
            } else {
                displayContent = baseContent + "\n\n---\n[Cancelled]"
            }
            finishStreamingMessage(
                assistantID,
                in: id,
                content: displayContent,
                reasoning: "[Cancelled]"
            )
        } catch {
            errorMessage = error.localizedDescription
            finishStreamingMessage(
                assistantID,
                in: id,
                content: "[Request Failed] \(error.localizedDescription)",
                reasoning: "Request failed: \(error.localizedDescription)"
            )
        }

        // Chapter summarization runs regardless of outcome
        await triggerSummarizationAfterSend(for: id, settings: settings)
    }

    func cancelSend() {
        currentSendTask?.cancel()
        currentSendTask = nil
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

        isSummarizing = true
        defer { isSummarizing = false }

        let conv = conversations[index]
        guard conv.messages.count >= 2 else {
            lastSummaryStatus = "消息不足（需至少2条）"
            return
        }

        // Build full transcript with message indices
        let transcript = conv.messages.enumerated().map { i, msg in
            let roleLabel = msg.role == .user ? "User" : "Assistant"
            let preview = String(msg.content.prefix(300))
            return "[\(i + 1)][\(roleLabel)]: \(preview)"
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
        let archiveCtx = buildArchiveContext(for: index)
        let userContent = "\(archiveCtx)完整对话记录（共\(conv.messages.count)条消息）：\n\n\(transcript)"

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

    /// Build a context block from pre‑pipeline archive data to enrich summarization.
    private func buildArchiveContext(for index: Int) -> String {
        guard index < conversations.count else { return "" }
        let conv = conversations[index]

        var parts: [String] = []

        // Recent emotion trajectory
        let recentEmotions = emotionTimeline.filter { $0.conversationID == conv.id }.suffix(5)
        if !recentEmotions.isEmpty {
            let emotionSummary = recentEmotions
                .map { "\($0.emotion)(\(String(format: "%.1f", $0.intensity)))" }
                .joined(separator: " → ")
            parts.append("近期情绪轨迹: \(emotionSummary)")
        }

        // Key persons mentioned
        let activePersons = personArchive
            .filter { $0.mentionCount > 0 }
            .sorted { $0.mentionCount > $1.mentionCount }
            .prefix(5)
        if !activePersons.isEmpty {
            let personSummary = activePersons
                .map { "\($0.name)(\($0.role), 提及\($0.mentionCount)次)" }
                .joined(separator: ", ")
            parts.append("关键人物: \(personSummary)")
        }

        // Active blindspot patterns
        let activeBlindspots = blindspots
            .filter { $0.conversationID == conv.id }
            .suffix(5)
        if !activeBlindspots.isEmpty {
            let blindspotSummary = activeBlindspots
                .map { "- [\($0.severity)] \($0.pattern): \($0.evidence)" }
                .joined(separator: "\n")
            parts.append("已检测到的叙事盲点:\n\(blindspotSummary)")
        }

        guard !parts.isEmpty else { return "" }
        return "\n\n[对话分析上下文 — 来自质量守护系统的洞察]\n" + parts.joined(separator: "\n\n") + "\n"
    }

    private func performSummarization(for index: Int, settings: AppSettings) async {
        guard index < conversations.count else { return }
        isSummarizing = true
        defer { isSummarizing = false }

        let conv = conversations[index]
        let startIndex = conv.lastSummaryMessageIndex
        guard startIndex < conv.messages.count else {
            lastSummaryStatus = "没有新消息需要归纳"
            return
        }

        let newMessages = Array(conv.messages.suffix(from: startIndex))
        guard newMessages.count >= 2 else {
            lastSummaryStatus = "新消息不足（需至少2条）"
            return
        }

        let transcript = newMessages.map { msg in
            let roleLabel = msg.role == .user ? "User" : "Assistant"
            return "[\(roleLabel)]: \(msg.content)"
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
        let archiveCtx = buildArchiveContext(for: index)
        let userContent = "\(archiveCtx)\(chapterContext)\n\n对话片段:\n\(transcript)"

        do {
            let client = DeepSeekClient(
                apiKey: settings.apiKey,
                baseURL: settings.baseURL,
                model: settings.flashModel,
                parameters: settings.flashParameters,
                language: settings.language
            )

            let result = try await client.summarize(systemPrompt: systemPrompt, userContent: userContent)

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
                        summary: String(summary.prefix(800)),
                        keywords: keywords.isEmpty ? StoryMemory.extractKeywordsPublic(from: summary) : keywords,
                        messageIDs: ids
                    )
                }
            }
        }
        return []
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
                return (title, summary, keywords)
            }
        }

        let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let fallbackTitle = lines.first.map { String($0.prefix(24)) } ?? "Chapter"
        let fallbackSummary = text.count > 600 ? String(text.prefix(600)) : text
        return (fallbackTitle, fallbackSummary, [])
    }

    private func updateTitleIfNeeded(for index: Int, firstUserText: String) {
        let defaultTitles = AppLanguage.allCases.map { L10n.text(.newConversationTitle, $0) }
        guard defaultTitles.contains(conversations[index].title) else { return }
        let compact = firstUserText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        conversations[index].title = String(compact.prefix(18))
    }

    private func fallbackReasoningSummary(language: AppLanguage) -> String {
        L10n.text(.fallbackReasoning, language)
    }

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
            break  // handled separately via ChatStore.toolCallHandler
        }
        conversations[conversationIndex].updatedAt = Date()
    }

    private func finishStreamingMessage(_ messageID: UUID, in conversationID: UUID, content: String, reasoning: String) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }

        conversations[conversationIndex].messages[messageIndex].content = content
        conversations[conversationIndex].messages[messageIndex].reasoning = reasoning
        conversations[conversationIndex].updatedAt = Date()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([Conversation].self, from: data) else { return }
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

    func save() {
        // Trim old message content to keep storage manageable
        let trimmed = conversations.map { trimConversation($0) }
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        try? data.write(to: storageURL, options: [.atomic])
    }

    /// Semantic compaction for long conversations.  Instead of blindly truncating
    /// old messages to 200 chars (which often cuts off mid-sentence), messages
    /// covered by a chapter are replaced with a compact reference to that chapter.
    /// The model can then use search_chapters / fetch_chapter_messages to retrieve
    /// the full content when needed.
    private func trimConversation(_ conv: Conversation) -> Conversation {
        var result = conv
        let keepFull = 40
        guard conv.messages.count > keepFull else { return result }

        // Build a reverse map: messageID → chapters that include it
        var msgToChapterIndex: [UUID: Int] = [:]
        for (i, ch) in conv.chapters.enumerated() {
            for mid in ch.messageIDs {
                msgToChapterIndex[mid] = i + 1  // 1-based
            }
        }

        for i in 0..<(conv.messages.count - keepFull) {
            let msg = conv.messages[i]

            if let chapterNum = msgToChapterIndex[msg.id],
               let chapter = conv.chapters.first(where: { $0.messageIDs.contains(msg.id) }) {
                // Replace with a compact chapter reference — semantically richer
                // than a 200-char fragment.
                result.messages[i].content = "[已归纳: 第\(chapterNum)章「\(chapter.title)」]"
                result.messages[i].reasoning = nil
            } else {
                // No chapter coverage — fall back to truncation
                let content = msg.content
                if content.count > 200 {
                    result.messages[i].content = String(content.prefix(200)) + "…"
                }
                if let reasoning = msg.reasoning, reasoning.count > 200 {
                    result.messages[i].reasoning = String(reasoning.prefix(200)) + "…"
                }
            }
        }

        // Trim chapter summaries as well
        for j in 0..<result.chapters.count {
            if result.chapters[j].summary.count > 600 {
                result.chapters[j].summary = String(result.chapters[j].summary.prefix(600)) + "…"
            }
        }
        return result
    }

    // MARK: - MCP Tool Data Stores (local JSON)

    private var dataFolder: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/Prism/Data")

    private var personArchiveURL: URL   { dataFolder.appendingPathComponent("person_archive.json") }
    private var emotionTimelineURL: URL  { dataFolder.appendingPathComponent("emotion_timeline.json") }
    private var blindspotsURL: URL       { dataFolder.appendingPathComponent("blindspots.json") }
    private var memoryURL: URL           { dataFolder.appendingPathComponent("memory.json") }

    internal(set) var personArchive: [PersonRecord] = []
    internal(set) var emotionTimeline: [EmotionEntry] = []
    internal(set) var blindspots: [BlindspotRecord] = []
    internal(set) var memoryStore: [MemoryEntry] = []

    /// Add a blindspot record from external tools (e.g. scan_blindspots MCP).
    func addBlindspot(_ record: BlindspotRecord) {
        blindspots.append(record)
        if blindspots.count > 100 { blindspots = Array(blindspots.suffix(100)) }
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
        if !top.isEmpty { saveArchives() }
        return top
    }

    /// Upsert a memory entry for a chapter. Uses the chapter summary as memory content.
    func upsertMemory(from chapter: StoryChapter, conversationID: UUID) {
        // Deduplicate: if a memory with the same title and conversation already exists, update it
        if let idx = memoryStore.firstIndex(where: {
            $0.sourceChapterTitle == chapter.title && $0.sourceConversationID == conversationID
        }) {
            memoryStore[idx].content = chapter.summary
            memoryStore[idx].keywords = chapter.keywords
        } else {
            let entry = MemoryEntry(
                content: chapter.summary,
                keywords: chapter.keywords,
                sourceConversationID: conversationID,
                sourceChapterTitle: chapter.title
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

    /// Semantic search across chapters: keyword pre-filter + Flash rerank.
    func searchChaptersSemantic(query: String, settings: AppSettings, limit: Int = 5) async -> [(chapter: StoryChapter, score: Int)] {
        // Step 1: keyword search (fast, local)
        let keywordResults = searchChapters(query: query, limit: 15)
        guard !keywordResults.isEmpty else { return [] }

        // Step 2: Flash rerank
        let chapters = keywordResults.map { $0.chapter }
        let reranked = await rerankWithFlash(
            query: query,
            candidates: chapters,
            titleOf: { $0.title },
            summaryOf: { $0.summary },
            settings: settings,
            topK: limit
        )
        return reranked.map { ($0, 0) }
    }

    /// Semantic search across memories: keyword pre-filter + Flash rerank.
    func searchMemorySemantic(query: String, settings: AppSettings, limit: Int = 5) async -> [MemoryEntry] {
        let keywordResults = searchMemory(query: query, limit: 15)
        guard !keywordResults.isEmpty else { return [] }

        let reranked = await rerankWithFlash(
            query: query,
            candidates: keywordResults,
            titleOf: { $0.sourceChapterTitle },
            summaryOf: { $0.content },
            settings: settings,
            topK: limit
        )
        return reranked
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
        emotionTimeline = loadJSON(emotionTimelineURL) ?? []
        blindspots = loadJSON(blindspotsURL) ?? []
        memoryStore = loadJSON(memoryURL) ?? []
    }

    func saveArchives() {
        saveJSON(personArchive, to: personArchiveURL)
        saveJSON(emotionTimeline, to: emotionTimelineURL)
        saveJSON(blindspots, to: blindspotsURL)
        saveJSON(memoryStore, to: memoryURL)
    }

    /// One-time migration: move archive files from old bundle-adjacent location
    /// to the unified data directory. No-op if old location doesn't exist.
    private func migrateArchivesIfNeeded(from old: URL, to new: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: old.path) else { return }
        for file in ["person_archive.json", "emotion_timeline.json", "blindspots.json", "memory.json"] {
            let src = old.appendingPathComponent(file)
            let dst = new.appendingPathComponent(file)
            guard fm.fileExists(atPath: src.path), !fm.fileExists(atPath: dst.path) else { continue }
            try? fm.copyItem(at: src, to: dst)
        }
    }

    private func loadJSON<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(T.self, from: data) else { return nil }
        return decoded
    }

    private func saveJSON<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - MCP Tool Execution

    /// Execute a single tool call from the model and return the JSON result.
    func executeTool(name: String, arguments: String, settings: AppSettings? = nil) async -> String {
        return await ToolRegistry.execute(name: name, arguments: arguments, store: self, settings: settings)
    }

}

extension Notification.Name {
    /// Posted when chapters are created or updated via summarization.
    static let prismChaptersUpdated = Notification.Name("prismChaptersUpdated")
}
