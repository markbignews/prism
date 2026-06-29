import SwiftUI
@preconcurrency import AppKit

// MARK: - Glass Background Modifier

/// Liquid Glass effect following Apple HIG.
///
/// On macOS 26+: uses the native `.glassEffect()` API — automatic ambient-light
/// adaptation, pointer interactivity, and Reduce Transparency support.
///
/// Fallback (macOS ≤25): system material + double-border to simulate
/// the glass edge refraction and depth.
struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 8
    var style: GlassStyle = .regular

    enum GlassStyle {
        /// Standard Liquid Glass — visible boundary, adapts to light/dark.
        case regular
        /// Thinner glass for secondary surfaces inside containers.
        case secondary
        /// Interactive glass — pointer/hover response, thicker for input areas.
        case interactive
        /// Deep glass — more opaque, stronger presence.
        case deep
    }

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .glassEffect(glass, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .background(fallbackMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                // Depth — glass sits above content
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1.5)
                .overlay {
                    // Outer edge for boundary definition on any background
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.primary.opacity(0.18), lineWidth: 0.5)
                }
                .overlay {
                    // Inner highlight: top-left edge catches ambient light
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.20), lineWidth: 0.5)
                        .mask(
                            VStack(spacing: 0) {
                                HStack(spacing: 0) {
                                    Rectangle().frame(width: cornerRadius, height: cornerRadius)
                                    Spacer()
                                }
                                Spacer()
                            }
                        )
                }
        }
    }

    @available(macOS 26, *)
    private var glass: Glass {
        switch style {
        case .regular:
            return Glass.regular
        case .secondary:
            return Glass.regular
        case .interactive:
            return Glass.regular.interactive()
        case .deep:
            return Glass.regular
        }
    }

    private var fallbackMaterial: Material {
        switch style {
        case .regular:
            return .regularMaterial
        case .secondary:
            return .thinMaterial
        case .interactive:
            return .regularMaterial
        case .deep:
            return .thickMaterial
        }
    }
}

extension View {
    func glassBackground(cornerRadius: CGFloat = 8, style: GlassBackground.GlassStyle = .regular) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius, style: style))
    }
}

// MARK: - Relative Time

/// Simple relative time: "5分钟前", "3小时前", "2天前", "1个月前", "半年前"
private func relativeTimeString(from date: Date, language: AppLanguage) -> String {
    let now = Date()
    let diff = now.timeIntervalSince(date)
    let minutes = Int(diff / 60)
    let hours = minutes / 60
    let days = hours / 24
    let months = days / 30

    switch language {
    case .simplifiedChinese, .traditionalChinese:
        let isTrad = language == .traditionalChinese
        if minutes < 1 {
            return isTrad ? "剛剛" : "刚刚"
        } else if minutes < 60 {
            return "\(minutes)" + (isTrad ? "分鐘前" : "分钟前")
        } else if hours < 24 {
            return "\(hours)" + (isTrad ? "小時前" : "小时前")
        } else if days < 30 {
            return "\(days)" + (isTrad ? "天前" : "天前")
        } else if months < 12 {
            return "\(months)" + (isTrad ? "個月前" : "个月前")
        } else {
            return isTrad ? "超過一年" : "超过一年"
        }
    case .english:
        if minutes < 1 {
            return "just now"
        } else if minutes < 60 {
            return "\(minutes) min ago"
        } else if hours < 24 {
            return "\(hours) hr ago"
        } else if days < 30 {
            return "\(days) day\(days == 1 ? "" : "s") ago"
        } else if months < 12 {
            return "\(months) month\(months == 1 ? "" : "s") ago"
        } else {
            return "over a year ago"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openSettings) private var openSettings
    @State private var draft = ""
    @State private var selectedMessageID: ChatMessage.ID?
    @State private var scrollToMessageID: ChatMessage.ID?
    @State private var selectedChapter: StoryChapter?
    @State private var renameTarget: Conversation.ID?
    @State private var renameText = ""
    @State private var editMessageID: ChatMessage.ID?
    @State private var previousConversationID: Conversation.ID?
    @State private var showMemoryPanel = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                scrollToMessageID: $scrollToMessageID,
                selectedChapter: $selectedChapter,
                renameTarget: $renameTarget,
                renameText: $renameText
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            ChatView(
                draft: $draft,
                selectedMessageID: $selectedMessageID,
                scrollToMessageID: $scrollToMessageID,
                selectedChapter: $selectedChapter,
                editMessageID: $editMessageID
            )
        }
        .onChange(of: chatStore.selectedConversationID) { oldID, newID in
            if let oldID, oldID != newID {
                Task { await chatStore.summarizeOnDeselect(conversationID: oldID, settings: settings) }
            }
            // Persist immediately — sidebar clicks bypass selectConversation()
            if let newID {
                UserDefaults.standard.set(newID.uuidString, forKey: "ui.lastConversationID")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showMemoryPanel = true
                } label: {
                    Label(L10n.text(.memory, settings.language), systemImage: "brain.head.profile")
                }

                Button {
                    chatStore.createConversation(language: settings.language)
                } label: {
                    Label(L10n.text(.newConversation, settings.language), systemImage: "square.and.pencil")
                }

                Button {
                    openSettings()
                } label: {
                    Label(L10n.text(.settings, settings.language), systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showMemoryPanel) {
            MemoryPanelView()
                .environmentObject(chatStore)
                .environmentObject(settings)
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var settings: AppSettings
    @Binding var scrollToMessageID: ChatMessage.ID?
    @Binding var selectedChapter: StoryChapter?
    @Binding var renameTarget: Conversation.ID?
    @Binding var renameText: String

    @State private var searchText = ""
    @State private var isConversationsExpanded = true
    @State private var isChaptersExpanded = true
    @State private var isMemoryExpanded = true
    @State private var showChapterDone = false
    @State private var showSummaryError = false

    private var filteredConversations: [Conversation] {
        chatStore.conversations  // full list shown when not searching
    }

    /// Search results when query is active.
    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Simple chapter-based search: title + summary matching across all conversations.
    /// Returns conversation + matching chapter snippet pairs.
    private var searchResults: [(conversation: Conversation, snippets: [(chapter: StoryChapter, context: String)])] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var results: [(Conversation, [(StoryChapter, String)])] = []
        for conv in chatStore.conversations {
            var matches: [(StoryChapter, String)] = []
            for ch in conv.chapters {
                let ct = ch.title.lowercased()
                let cs = ch.summary.lowercased()
                if ct.contains(q) {
                    matches.append((ch, "📑 \(ch.title)"))
                } else if cs.contains(q) {
                    if let r = cs.range(of: q) {
                        let start = max(cs.startIndex, cs.index(r.lowerBound, offsetBy: -30, limitedBy: cs.startIndex) ?? cs.startIndex)
                        let end = min(cs.endIndex, cs.index(r.upperBound, offsetBy: 30, limitedBy: cs.endIndex) ?? cs.endIndex)
                        var ctx = String(ch.summary[cs.index(cs.startIndex, offsetBy: cs.distance(from: cs.startIndex, to: start))..<cs.index(cs.startIndex, offsetBy: cs.distance(from: cs.startIndex, to: end))])
                        if start > cs.startIndex { ctx = "…" + ctx }
                        if end < cs.endIndex { ctx = ctx + "…" }
                        matches.append((ch, ctx))
                    }
                }
            }
            // Also match conversation title
            if conv.title.lowercased().contains(q), matches.isEmpty {
                matches.append((StoryChapter(title: conv.title, summary: "", keywords: [], messageIDs: []), "📌 \(conv.title)"))
            }
            if !matches.isEmpty {
                results.append((conv, Array(matches.prefix(3))))
            }
        }
        return results
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField(L10n.text(.search, settings.language), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.body)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            List(selection: $chatStore.selectedConversationID) {
                // Conversations section with collapse toggle
                Section {
                    if isConversationsExpanded {
                        if isSearching {
                            // Search results with context snippets
                            if searchResults.isEmpty {
                                HStack {
                                    Image(systemName: "text.magnifyingglass")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                    Text(L10n.text(.noResults, settings.language))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                ForEach(searchResults, id: \.conversation.id) { result in
                                    ForEach(Array(result.snippets.enumerated()), id: \.element.chapter.id) { _, snippet in
                                        HStack(spacing: 6) {
                                            Image(systemName: "bookmark")
                                                .font(.caption2)
                                                .foregroundStyle(.blue)
                                                .frame(width: 16)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(result.conversation.title)
                                                    .font(.subheadline.weight(.medium))
                                                    .lineLimit(1)
                                                Text(snippet.context)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                            }
                                        }
                                        .padding(.vertical, 3)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            chatStore.selectedConversationID = result.conversation.id
                                            selectedChapter = snippet.chapter
                                        }
                                    }
                                }
                            }
                        } else {
                            // Normal conversation list (no search)
                            if filteredConversations.isEmpty {
                                HStack {
                                    Image(systemName: "text.magnifyingglass")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                    Text(L10n.text(.noResults, settings.language))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                ForEach(filteredConversations) { conversation in
                                    HStack(spacing: 6) {
                                        Image(systemName: "text.book.closed")
                                            .font(.caption2)
                                            .foregroundStyle(.blue)
                                            .frame(width: 16)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(conversation.title)
                                                .font(.headline)
                                                .lineLimit(1)
                                            Text(relativeTimeString(from: conversation.updatedAt, language: settings.language))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 5)
                                    .tag(conversation.id)
                                    .contextMenu {
                                        Button {
                                            renameTarget = conversation.id
                                            renameText = conversation.title
                                        } label: {
                                            Label(L10n.text(.rename, settings.language), systemImage: "pencil")
                                        }
                                        Divider()
                                        Button(role: .destructive) {
                                            chatStore.deleteConversation(id: conversation.id)
                                        } label: {
                                            Label(L10n.text(.delete, settings.language), systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        collapseChevron(isExpanded: $isConversationsExpanded)
                        Image(systemName: "bubble.left.and.bubble.right")
                            .frame(width: 14)
                        Text(L10n.text(.conversations, settings.language))
                        Spacer(minLength: 4)
                    }
                }

                // Chapters section with collapse toggle
                Section {
                    if isChaptersExpanded {
                        if let chapters = chatStore.selectedConversation?.chapters, !chapters.isEmpty {
                            ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                                ChapterRow(
                                    index: index,
                                    chapter: chapter,
                                    scrollToMessageID: $scrollToMessageID,
                                    selectedChapter: $selectedChapter
                                )
                            }
                        } else {
                            HStack {
                                Image(systemName: "bookmark.slash")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text(L10n.text(.noChapters, settings.language))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        collapseChevron(isExpanded: $isChaptersExpanded)
                        Image(systemName: "bookmark")
                            .frame(width: 14)
                        Text(L10n.text(.chapters, settings.language))
                        if chatStore.isSummarizing {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .controlSize(.small)
                                    .colorScheme(.dark)
                                    .scaleEffect(0.6)
                                Text(L10n.text(.summarizing, settings.language))
                                    .font(.caption2.weight(.medium))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.red))
                        } else if showChapterDone {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                Text(L10n.text(.chapterSynthesized, settings.language))
                                    .font(.caption2.weight(.medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.blue))
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        showChapterDone = false
                                    }
                                }
                            }
                        } else {
                            Button {
                                guard let convID = chatStore.selectedConversationID else { return }
                                Task { await chatStore.fullReSummarize(conversationID: convID, settings: settings) }
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .help(L10n.text(.reSummarize, settings.language))
                            .disabled(chatStore.isSummarizing)
                        }
                    }
                }

            }
            .listStyle(.sidebar)
        }
        .onChange(of: chatStore.lastSummaryStatus) { newStatus in
            if !newStatus.isEmpty,
               !newStatus.hasPrefix("已生成"),
               !newStatus.hasPrefix("新增") {
                showSummaryError = true
            }
        }
        .alert("归纳失败", isPresented: $showSummaryError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(chatStore.lastSummaryStatus)
        }
        .onReceive(NotificationCenter.default.publisher(for: .prismChaptersUpdated)) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showChapterDone = true
            }
        }
        .alert(L10n.text(.rename, settings.language), isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField(L10n.text(.rename, settings.language), text: $renameText)
            Button(L10n.text(.save, settings.language)) {
                if let id = renameTarget {
                    chatStore.renameConversation(id: id, newTitle: renameText)
                }
                renameTarget = nil
            }
            Button(L10n.text(.cancel, settings.language), role: .cancel) {
                renameTarget = nil
            }
        } message: {
            Text(L10n.text(.renameHint, settings.language))
        }
    }

    private func collapseChevron(isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                .font(.body.weight(.semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chapter Row (split: big button → scroll, info → detail)

struct ChapterRow: View {
    let index: Int
    let chapter: StoryChapter
    @Binding var scrollToMessageID: ChatMessage.ID?
    @Binding var selectedChapter: StoryChapter?

    var body: some View {
        HStack(spacing: 0) {
            // Big tappable area — scrolls to source text
            Button {
                if let firstMsgID = chapter.messageIDs.first {
                    scrollToMessageID = firstMsgID
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(index + 1). \(chapter.title)")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Text(chapter.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if !chapter.keywords.isEmpty {
                        Text(chapter.keywords.prefix(4).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 6)
                .padding(.leading, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Info button — opens chapter detail sheet (larger hit target)
            Button {
                selectedChapter = chapter
            } label: {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
            .help("查看章节详情")
        }
    }
}

// MARK: - Chat View

struct ChatView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var settings: AppSettings
    @Binding var draft: String
    @Binding var selectedMessageID: ChatMessage.ID?
    @Binding var scrollToMessageID: ChatMessage.ID?
    @Binding var selectedChapter: StoryChapter?
    @Binding var editMessageID: ChatMessage.ID?

    /// Back-to-bottom button visible when the user scrolls up.
    @State private var isScrolledUp = true
    @State private var scrollToBottomCounter = 0
    /// Pending paired-message delete (user msg with following assistant reply).
    @State private var pendingPairedDelete: ChatMessage?

    private var isNewConversation: Bool {
        let userMsgs = chatStore.selectedConversation?.messages.filter { $0.role == .user } ?? []
        return userMsgs.isEmpty
    }

    var body: some View {
        // ZStack lets messages render behind the input area so chat content
        // refracts through the Liquid Glass input box.
        ZStack(alignment: .bottom) {
            if isNewConversation {
                emptyStateView
            } else {
                messageList
                    .onAppear {
                        scrollToBottomCounter += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            scrollToBottomCounter += 1
                        }
                    }
            }

            // Error + input floating above messages, no background bar
            VStack(spacing: 0) {
                if let error = chatStore.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isScrolledUp, !isNewConversation {
                    Button {
                        scrollToBottomCounter += 1
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 32, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .glassBackground(cornerRadius: 18, style: .deep)
                    .padding(.bottom, 6)
                }

                ComposerView(draft: $draft, isSending: chatStore.isSending, onStop: {
                    chatStore.cancelSend()
                }) {
                    let text = draft
                    draft = ""
                    let task = Task {
                        if let msgID = editMessageID {
                            editMessageID = nil
                            await chatStore.editAndResend(userMessageID: msgID, newText: text, settings: settings)
                        } else {
                            await chatStore.send(text, settings: settings)
                        }
                    }
                    chatStore.currentSendTask = task
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .navigationTitle(chatStore.selectedConversation?.title ?? "")
        .navigationSubtitle(chatStore.selectedConversation?.messages.isEmpty == false
            ? L10n.text(.aiLabelDisclaimer, settings.language) : "")
        .sheet(item: $selectedChapter) { chapter in
            ChapterDetailView(
                chapter: chapter,
                messages: chatStore.selectedConversation?.messages ?? [],
                scrollToMessageID: $scrollToMessageID
            )
            .environmentObject(settings)
        }
        .alert(L10n.text(.delete, settings.language), isPresented: Binding(
            get: { pendingPairedDelete != nil },
            set: { if !$0 { pendingPairedDelete = nil } }
        )) {
            Button(L10n.text(.cancel, settings.language), role: .cancel) {
                pendingPairedDelete = nil
            }
            Button(L10n.text(.delete, settings.language), role: .destructive) {
                if let msg = pendingPairedDelete,
                   let convID = chatStore.selectedConversationID {
                    chatStore.deleteMessage(in: convID, messageID: msg.id)
                }
                pendingPairedDelete = nil
            }
        } message: {
            Text(L10n.text(.deletePairHint, settings.language))
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "text.book.closed")
                .font(.system(size: 40))
                .foregroundStyle(.indigo.opacity(0.6))

            Text(L10n.text(.emptyMirrorTitle, settings.language))
                .font(.title3.weight(.medium))

            Text(L10n.text(.emptyMirrorHint, settings.language))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Scroll trigger: fires when message count changes (send, receive, regenerate).
    private var scrollTrigger: Int {
        chatStore.selectedConversation?.messages.count ?? 0
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(chatStore.selectedConversation?.messages ?? []) { message in
                        let convID = chatStore.selectedConversationID ?? UUID()
                        let isLast = message.id == chatStore.selectedConversation?.messages.last?.id
                        MessageBubble(
                            message: message,
                            isSelected: selectedMessageID == message.id,
                            conversationID: convID,
                            isStreaming: chatStore.isSending && isLast,
                            onEdit: { editMessageID = message.id; draft = message.content },
                            onDelete: {
                                let msgs = chatStore.selectedConversation?.messages ?? []
                                if message.role == .user,
                                   let idx = msgs.firstIndex(where: { $0.id == message.id }),
                                   idx + 1 < msgs.count,
                                   msgs[idx + 1].role == .assistant {
                                    pendingPairedDelete = message
                                } else {
                                    chatStore.deleteMessage(in: convID, messageID: message.id)
                                }
                            },
                            onRegenerate: { msgID in
                                let task = Task { await chatStore.regenerateAssistantMessage(in: convID, messageID: msgID, settings: settings) }
                                chatStore.currentSendTask = task
                            }
                        )
                        .equatable()
                        .id(message.id)
                        .onTapGesture {
                            selectedMessageID = message.id
                        }
                    }

                    // Invisible anchor — scroll-to-bottom always hits
                    // the absolute bottom regardless of bubble height.
                    Color.clear
                        .frame(height: 1)
                        .id("bottomAnchor")
                        .onAppear { isScrolledUp = false }
                        .onDisappear { isScrolledUp = true }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .defaultScrollAnchor(.bottom)  // macOS 15+ native chat scrolling — no scroll war
            .safeAreaInset(edge: .bottom) {
                Spacer().frame(height: 60)
            }
            .onChange(of: chatStore.sendCounter) { _, _ in
                // User pressed send — immediately scroll to the user message
                guard let lastID = chatStore.selectedConversation?.messages.last?.id else { return }
                proxy.scrollTo(lastID, anchor: .bottom)
            }
            .onChange(of: scrollTrigger) { _, newCount in
                // New message added to the list (could be from regenerate or conversation switch)
                guard newCount > 0,
                      let lastID = chatStore.selectedConversation?.messages.last?.id else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
            .onChange(of: scrollToMessageID) {
                guard let targetID = scrollToMessageID else { return }
                selectedMessageID = targetID
                DispatchQueue.main.async {
                    proxy.scrollTo(targetID, anchor: .center)
                    scrollToMessageID = nil
                }
            }
            .onChange(of: scrollToBottomCounter) {
                // Scroll to the last message directly — avoids the LazyVStack
                // layout race that the bottomAnchor can hit before render.
                if let lastID = chatStore.selectedConversation?.messages.last?.id {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
            .onChange(of: chatStore.selectedConversationID) { _, _ in
                // Scroll to last message when switching conversations
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if let lastID = chatStore.selectedConversation?.messages.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            .onChange(of: editMessageID) {
                if let msgID = editMessageID,
                   let conv = chatStore.selectedConversation,
                   let msg = conv.messages.first(where: { $0.id == msgID }) {
                    draft = msg.content
                }
            }
        }
    }

}

// MARK: - Chapter Detail Sheet

struct ChapterDetailView: View {
    @EnvironmentObject private var settings: AppSettings
    let chapter: StoryChapter
    let messages: [ChatMessage]
    @Binding var scrollToMessageID: ChatMessage.ID?
    @Environment(\.dismiss) private var dismiss

    private var chapterMessages: [ChatMessage] {
        messages.filter { chapter.messageIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(chapter.title)
                            .font(.title3.weight(.semibold))
                        Button {
                            if let firstMsgID = chapter.messageIDs.first {
                                scrollToMessageID = firstMsgID
                            }
                            dismiss()
                        } label: {
                            Label(L10n.text(.jumpToSource, settings.language), systemImage: "arrow.right.circle.fill")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(.blue))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.text(.jumpToSource, settings.language))
                    }
                    Text(chapter.createdAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Chapter summary
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Summary", systemImage: "text.alignleft")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        MarkdownText(text: chapter.summary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassBackground(cornerRadius: 14)
                    }

                    if !chapter.keywords.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(chapter.keywords, id: \.self) { kw in
                                    Text(kw)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(.quaternary))
                                }
                            }
                        }
                    }

                    // Original messages with full bubble rendering
                    if !chapterMessages.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("对话原文", systemImage: "bubble.left.and.bubble.right")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            ForEach(chapterMessages) { msg in
                                MessageBubble(
                                    message: msg,
                                    isSelected: false,
                                    conversationID: UUID(),
                                    isStreaming: false,
                                    onEdit: {},
                                    onDelete: {},
                                    onRegenerate: { _ in }
                                )
                                .disabled(true)
                            }
                        }
                    } else {
                        Text("无法定位到对应消息")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 480, idealWidth: 600, minHeight: 420, idealHeight: 600)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    var message: ChatMessage
    var isSelected: Bool
    var conversationID: UUID
    var isStreaming: Bool
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onRegenerate: (UUID) -> Void

    @State private var isReasoningExpanded = true

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            HStack(alignment: .top) {
                if message.role == .user { Spacer(minLength: 80) }

                VStack(alignment: .leading, spacing: 4) {
                    // Role label
                    Text(message.role == .user ? L10n.text(.userName, settings.language) : L10n.text(.assistantName, settings.language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    // Thinking chain
                    if message.role == .assistant, let reasoning = message.reasoning, !reasoning.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isReasoningExpanded.toggle()
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 4) {
                                    Image(systemName: "brain.head.profile").font(.caption2)
                                    Text(L10n.text(.thinking, settings.language)).font(.caption.weight(.semibold))
                                    Spacer()
                                    Image(systemName: isReasoningExpanded ? "chevron.down" : "chevron.right").font(.caption2.weight(.semibold))
                                }
                                .foregroundStyle(.secondary)
                                if isReasoningExpanded {
                                    VStack(alignment: .leading, spacing: 1) {
                                        ForEach(Array(reasoningLines.enumerated()), id: \.offset) { _, line in
                                            Text(verbatim: line.isEmpty ? " " : line).font(.callout).foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .glassBackground(cornerRadius: 14, style: .secondary)
                    }

                    if message.content.isEmpty, message.role == .assistant {
                        StreamingDots().padding(.vertical, 2)
                    } else {
                        MarkdownText(text: message.content)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundColor(bubbleTextColor)
                .background(bubbleFill)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(borderColor, lineWidth: isSelected ? 1.5 : 0.75)
                }
                .frame(minWidth: 0, idealWidth: 660, maxWidth: 660, alignment: message.role == .user ? .trailing : .leading)

                if message.role != .user { Spacer(minLength: 80) }
            }
            .frame(maxWidth: .infinity)
            .onChange(of: message.content) { oldContent, newContent in
                // Collapse reasoning when real response content starts flowing.
                // Skip tool-status placeholders so reasoning stays visible during
                // tool execution (ChatStore sets "🔧 正在查询…" as interim content).
                if oldContent.isEmpty, !newContent.isEmpty, isReasoningExpanded,
                   newContent != "🔧 正在查询…" {
                    isReasoningExpanded = false
                }
            }

            // Action buttons outside bubble, below, with gap
            if !isStreaming {
                actionButtons
                    .padding(.top, 2)
                    .padding(message.role == .user ? .trailing : .leading, 4)
                    .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
            }
        }
    }

    private var reasoningLines: [String] {
        var trimmed = message.reasoning?.components(separatedBy: "\n") ?? []
        while let last = trimmed.last, last.trimmingCharacters(in: .whitespaces).isEmpty { trimmed.removeLast() }
        return trimmed
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 6) {
            if message.role == .user {
                bubbleActionButton("doc.on.doc", L10n.text(.copy, settings.language)) { copyContent() }
                bubbleActionButton("pencil", L10n.text(.edit, settings.language), action: onEdit)
            }
            if message.role == .assistant, !message.content.isEmpty {
                bubbleActionButton("doc.on.doc", L10n.text(.copy, settings.language)) { copyContent() }
                bubbleActionButton("arrow.triangle.2.circlepath", L10n.text(.regenerate, settings.language)) {
                    onRegenerate(message.id)
                }
                bubbleActionButton("trash", L10n.text(.delete, settings.language), action: onDelete)
            }
        }
    }

    private func copyContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
    }

    private func bubbleActionButton(_ systemImage: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private var bubbleFill: Color {
        switch (message.role, colorScheme) {
        case (.user, .dark):
            // iMessage blue — slightly brighter for dark mode
            Color(red: 0.0, green: 0.522, blue: 1.0)
        case (.user, _):
            // iMessage blue — light mode
            Color(red: 0.0, green: 0.478, blue: 1.0)
        case (.assistant, .dark):
            Color(white: 0.18)
        case (.assistant, _):
            Color(white: 0.93)
        case (.system, .dark):
            Color(white: 0.10)
        case (.system, _):
            Color(white: 0.93)
        }
    }

    private var bubbleTextColor: Color {
        switch message.role {
        case .user:
            .white
        case .assistant, .system:
            colorScheme == .dark ? .white : .primary
        }
    }

    private var borderColor: Color {
        if isSelected {
            return Color.blue.opacity(0.65)
        }
        return colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.1)
    }
}

// MARK: - Equatable support for MessageBubble

extension MessageBubble: @MainActor Equatable {
    static func == (lhs: MessageBubble, rhs: MessageBubble) -> Bool {
        lhs.message == rhs.message
        && lhs.isSelected == rhs.isSelected
        && lhs.conversationID == rhs.conversationID
        && lhs.isStreaming == rhs.isStreaming
    }
}

// MARK: - Streaming Dots

struct StreamingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 5, height: 5)
                    .opacity(phase == index ? 1 : 0.35)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(220))
                phase = (phase + 1) % 3
            }
        }
    }
}

// MARK: - Composer with Dynamic Height + Liquid Glass

struct ComposerView: View {
    @Binding var draft: String
    var isSending: Bool
    var onStop: () -> Void
    var onSend: () -> Void

    @FocusState private var isFocused: Bool
    @State private var editorHeight: CGFloat = 34

    private let minEditorHeight: CGFloat = 34
    private let maxEditorHeight: CGFloat = 200

    var body: some View {
        ZStack(alignment: .trailing) {
            MacEditor(
                text: $draft,
                dynamicHeight: $editorHeight,
                minHeight: minEditorHeight,
                maxHeight: maxEditorHeight,
                onSubmit: {
                    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, !isSending else { return }
                    editorHeight = minEditorHeight
                    onSend()
                },
                isSending: isSending
            )
            .focused($isFocused)
            .onAppear { isFocused = true }
            .font(.system(size: NSFont.systemFontSize + 1))
            .frame(height: editorHeight)
            .padding(.horizontal, 12)
            .padding(.trailing, 36)
            .padding(.vertical, 8)
            .glassBackground(cornerRadius: 18, style: .deep)

            if isSending {
                Button(action: onStop) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .padding(.trailing, 14)
            } else {
                Button {
                    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, !isSending else { return }
                    editorHeight = minEditorHeight
                    onSend()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .blue)
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.trailing, 14)
            }
        }
        .frame(maxWidth: 720)
    }
}

// MARK: - Intrinsic-Content-Size Text View

/// NSTextView subclass that reports its content height as `intrinsicContentSize`.
/// Paired with `invalidateIntrinsicContentSize()` in `didChangeText`, this lets
/// SwiftUI's `.fixedSize(vertical: true)` automatically track line wrapping.
final class IntrinsicTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        guard let tc = textContainer, let lm = layoutManager else {
            return super.intrinsicContentSize
        }
        lm.ensureLayout(for: tc)
        let h = lm.usedRect(for: tc).height + textContainerInset.height * 2
        return NSSize(width: NSView.noIntrinsicMetric, height: max(h, 0))
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }
}

// MARK: - MacEditor

/// NSTextView wrapper:  Return = submit,  Shift+Return = newline,
/// auto-grows with wrapped text up to `maxHeight`, then shows scrollbar.
struct MacEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var dynamicHeight: CGFloat
    var minHeight: CGFloat
    var maxHeight: CGFloat
    var onSubmit: () -> Void
    var isSending: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = IntrinsicTextView(frame: NSRect(x: 0, y: 0, width: 680, height: 0))
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.isEditable = true
        tv.isSelectable = true
        tv.allowsUndo = true
        tv.font = NSFont.systemFont(ofSize: NSFont.systemFontSize + 1)
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 0, height: 8)
        tv.textContainer?.lineFragmentPadding = 0

        // ── critical config for auto-grow + wrapping ──
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.heightTracksTextView = false
        tv.textContainer?.containerSize = NSSize(
            width: 680,
            height: CGFloat.greatestFiniteMagnitude
        )

        let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: 680, height: minHeight))
        sv.documentView = tv
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.drawsBackground = false
        sv.borderType = .noBorder
        sv.automaticallyAdjustsContentInsets = false
        sv.contentInsets = NSEdgeInsetsZero

        context.coordinator.scrollView = sv
        context.coordinator.textView = tv
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = sv.documentView as? IntrinsicTextView else { return }

        // Keep the text view width pinned to the scroll view's content area
        // so word wrapping produces the correct intrinsic height. This is
        // critical when text is loaded programmatically (e.g. edit button)
        // because the AppKit view was created with a placeholder width.
        let targetWidth = sv.contentView.bounds.width
        if targetWidth > 0 && abs(tv.frame.width - targetWidth) > 0.5 {
            tv.frame.size.width = targetWidth
        }

        if tv.string != text {
            let savedRanges = text.isEmpty ? nil : tv.selectedRanges
            tv.string = text
            if let ranges = savedRanges, !ranges.isEmpty { tv.selectedRanges = ranges }
            tv.invalidateIntrinsicContentSize()
            tv.layout()
        }
        tv.isEditable = !isSending

        // Sync the measured height to SwiftUI so the Glass background grows.
        context.coordinator.pushHeightToSwiftUI()

        // After SwiftUI finishes layout (which may change the width of this
        // view), re-measure so word-wrap height is accurate.
        DispatchQueue.main.async {
            context.coordinator.pushHeightToSwiftUI()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacEditor!
        weak var scrollView: NSScrollView?
        weak var textView: IntrinsicTextView?

        // ── NSTextViewDelegate ─────────────────────────────────────

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? IntrinsicTextView,
                  let p = parent else { return }
            p.text = tv.string
            tv.invalidateIntrinsicContentSize()
            tv.layout()
            pushHeightToSwiftUI()
        }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            guard sel == #selector(NSResponder.insertNewline(_:)),
                  let p = parent else { return false }
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            if flags.contains(.shift) {
                tv.insertNewlineIgnoringFieldEditor(nil)
            } else {
                let t = p.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty, !p.isSending {
                    p.onSubmit()
                    // Shrink the scroll view immediately for instant visual
                    // feedback. The synchronous draft="" in ChatView will
                    // trigger updateNSView → pushHeightToSwiftUI() shortly
                    // after, which clears the text and confirms the reset.
                    scrollView?.frame.size.height = p.minHeight
                }
            }
            return true
        }

        // ── Height ────────────────────────────────────────────────

        func pushHeightToSwiftUI() {
            guard let tv = textView, let sv = scrollView, let p = parent else { return }

            // Keep text view width in sync so word wrapping produces the
            // correct intrinsic height.
            let targetWidth = sv.contentView.bounds.width
            if targetWidth > 0 && abs(tv.frame.width - targetWidth) > 0.5 {
                tv.frame.size.width = targetWidth
            }

            // Read the intrinsic content height (which our subclass computes
            // from usedRect + insets, independent of any caching).
            let idealH = tv.intrinsicContentSize.height
            let clamped = min(max(idealH, p.minHeight), p.maxHeight)

            // Resize the scroll view so it grows with content (up to maxHeight).
            if abs(sv.frame.height - clamped) > 0.5 {
                sv.frame.size.height = clamped
            }
            // Notify SwiftUI so the Glass background and parent layout adapt.
            if abs(p.dynamicHeight - clamped) > 0.5 {
                p.dynamicHeight = clamped
            }
        }
    }
}

// MARK: - Memory Panel (standalone window)

struct MemoryPanelView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text(.memory, settings.language))
                    .font(.title2.weight(.semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 人物
                    if !chatStore.personArchive.isEmpty {
                        MemorySection(title: L10n.text(.memoryPeople, settings.language), icon: "person.2.fill", color: .blue) {
                            ForEach(chatStore.personArchive.sorted { $0.mentionCount > $1.mentionCount }) { person in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(person.name).font(.headline)
                                        Text("\(person.role) · \(L10n.text(.memoryMentions, settings.language)) \(person.mentionCount) \(L10n.text(.memoryTimes, settings.language))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if !person.emotionalArc.isEmpty {
                                        Text(person.emotionalArc)
                                            .font(.caption).foregroundStyle(.blue)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Capsule().fill(.blue.opacity(0.1)))
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    // 情绪轨迹 — grouped by type, most recent intensity
                    if !chatStore.emotionTimeline.isEmpty {
                        MemorySection(title: L10n.text(.memoryEmotions, settings.language), icon: "waveform.path.ecg", color: .purple) {
                            let grouped = groupEmotions(chatStore.emotionTimeline.suffix(20))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(grouped, id: \.emotion) { item in
                                        VStack(spacing: 4) {
                                            Text(item.emotion)
                                                .font(.caption.weight(.medium))
                                            Text("\(Int(item.intensity * 100))%")
                                                .font(.caption2).foregroundStyle(.secondary)
                                            Text("×\(item.count)")
                                                .font(.caption2).foregroundStyle(.tertiary)
                                        }
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
                                    }
                                }
                            }
                        }
                    }

                    // 盲点
                    if !chatStore.blindspots.isEmpty {
                        MemorySection(title: L10n.text(.memoryBlindspots, settings.language), icon: "eye.slash.fill", color: .red) {
                            ForEach(chatStore.blindspots.suffix(10).reversed()) { spot in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(spot.pattern).font(.headline)
                                        Spacer()
                                        Text(spot.severity == "persistent" ? L10n.text(.memoryPersistent, settings.language) : spot.severity == "recurring" ? L10n.text(.memoryRecurring, settings.language) : L10n.text(.memoryNew, settings.language))
                                            .font(.caption2).foregroundStyle(spot.severity == "persistent" ? .red : .secondary)
                                            .padding(.horizontal, 6).padding(.vertical, 1)
                                            .background(Capsule().fill(.quaternary))
                                    }
                                    Text(spot.evidence).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    Text("\(L10n.text(.memoryCounterQuestion, settings.language))：\(spot.counterQuestion)").font(.caption).foregroundStyle(.blue)
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }

                    // 洞察
                    if !chatStore.memoryStore.isEmpty {
                        MemorySection(title: L10n.text(.memoryInsights, settings.language), icon: "lightbulb.fill", color: .yellow) {
                            let memories = chatStore.memoryStore.sorted { ($0.lastRecalledAt ?? $0.createdAt) > ($1.lastRecalledAt ?? $1.createdAt) }
                            ForEach(memories.prefix(20)) { memory in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(memory.content).font(.callout).lineLimit(4)
                                    HStack(spacing: 4) {
                                        ForEach(memory.keywords.prefix(4), id: \.self) { kw in
                                            Text(kw).font(.caption2)
                                                .padding(.horizontal, 5).padding(.vertical, 1)
                                                .background(Capsule().fill(.quaternary))
                                        }
                                        Spacer()
                                        if memory.recallCount > 0 {
                                            Image(systemName: "arrow.triangle.2.circlepath").font(.caption2)
                                            Text("\(memory.recallCount)").font(.caption2).foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    if chatStore.personArchive.isEmpty && chatStore.emotionTimeline.isEmpty
                        && chatStore.blindspots.isEmpty && chatStore.memoryStore.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "brain.head.profile").font(.system(size: 32)).foregroundStyle(.tertiary)
                            Text(L10n.text(.memoryEmptyTitle, settings.language)).font(.headline).foregroundStyle(.secondary)
                            Text(L10n.text(.memoryEmptyHint, settings.language))
                                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 60)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 480, idealWidth: 560, minHeight: 420, idealHeight: 600)
    }
}

private struct EmotionGroup { let emotion: String; let intensity: Double; let count: Int }

private func groupEmotions(_ entries: some Collection<EmotionEntry>) -> [EmotionGroup] {
    var dict: [String: (total: Double, count: Int, latest: Double, latestDate: Date)] = [:]
    for e in entries {
        if var existing = dict[e.emotion] {
            existing.total += e.intensity
            existing.count += 1
            if e.createdAt > existing.latestDate {
                existing.latest = e.intensity
                existing.latestDate = e.createdAt
            }
            dict[e.emotion] = existing
        } else {
            dict[e.emotion] = (e.intensity, 1, e.intensity, e.createdAt)
        }
    }
    let raw = dict.map { EmotionGroup(emotion: $0.key, intensity: $0.value.latest, count: $0.value.count) }
    let total = raw.reduce(0) { $0 + $1.intensity }
    let normalized = total > 0 ? raw.map { EmotionGroup(emotion: $0.emotion, intensity: $0.intensity / total, count: $0.count) } : raw
    return normalized.sorted { $0.intensity > $1.intensity }
}

private struct MemorySection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.title3.weight(.semibold))
            }
            content
                .padding(.leading, 26)
        }
    }
}
