import SwiftUI

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

/// Deletion confirmation state — presented with SwiftUI `.confirmationDialog`
/// at the ContentView root so it cannot be lost inside List/contextMenu
/// hierarchies (replaces the previous AppKit NSAlert approach).
enum PendingDelete: Identifiable {
    case conversation(UUID)
    case message(conversationID: UUID, messageID: UUID, paired: Bool)

    var id: String {
        switch self {
        case .conversation(let id): "conv-\(id)"
        case .message(let cid, let mid, _): "msg-\(cid)-\(mid)"
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
    @State private var pendingDelete: PendingDelete?

    private var appToolbarGroup: some ToolbarContent {
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

    var body: some View {
        NavigationSplitView {
            SidebarView(
                scrollToMessageID: $scrollToMessageID,
                selectedChapter: $selectedChapter,
                renameTarget: $renameTarget,
                renameText: $renameText,
                pendingDelete: $pendingDelete
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            ChatView(
                draft: $draft,
                selectedMessageID: $selectedMessageID,
                scrollToMessageID: $scrollToMessageID,
                selectedChapter: $selectedChapter,
                editMessageID: $editMessageID,
                pendingDelete: $pendingDelete
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
        .onReceive(NotificationCenter.default.publisher(for: .openMemoryPanel)) { _ in
            showMemoryPanel = true
        }
        .toolbar {
            // Keep these actions in one logical group. On macOS 26+ the
            // system supplies one shared, interactive Liquid Glass capsule.
            appToolbarGroup
        }
        // Keep the system's automatic toolbar surface. It stays visually light
        // at rest and participates in the scroll-edge blur as content moves
        // beneath the title bar.
        .toolbarBackgroundVisibility(.automatic, for: .windowToolbar)
        .sheet(isPresented: $showMemoryPanel) {
            MemoryPanelView()
                .environmentObject(chatStore)
                .environmentObject(settings)
        }
        .confirmationDialog(
            L10n.text(.delete, settings.language),
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { delete in
            Button(L10n.text(.delete, settings.language), role: .destructive) {
                switch delete {
                case .conversation(let id):
                    chatStore.deleteConversation(id: id)
                case .message(let cid, let mid, _):
                    chatStore.deleteMessage(in: cid, messageID: mid)
                }
                pendingDelete = nil
            }
            Button(L10n.text(.cancel, settings.language), role: .cancel) {
                pendingDelete = nil
            }
        } message: { delete in
            switch delete {
            case .conversation:
                Text(L10n.text(.confirmDeleteConversation, settings.language))
            case .message(_, _, let paired):
                Text(paired
                    ? L10n.text(.deletePairHint, settings.language)
                    : L10n.text(.deleteMessageHint, settings.language))
            }
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
    @Binding var pendingDelete: PendingDelete?

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
                                            pendingDelete = .conversation(conversation.id)
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
    @Binding var pendingDelete: PendingDelete?

    /// The most recent user turn already pinned to the top of the viewport.
    /// Tracking the ID avoids re-scrolling while assistant tokens stream in.
    @State private var pinnedUserMessageID: ChatMessage.ID?
    @State private var showScrollToLatest = false

    /// A stable target immediately after the newest real message. The small
    /// spacer keeps the latest reply clear of the floating composer, while the
    /// larger sending runway remains outside this target.
    private static let latestMessageScrollTarget = "prism.latest-message-bottom"

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

                ComposerView(
                    draft: $draft,
                    isSending: chatStore.isSending,
                    mode: chatStore.selectedConversation?.mode ?? settings.conversationMode,
                    contextUsage: chatStore.contextUsage(settings: settings),
                    language: settings.language,
                    onCycleMode: { cycleMode() },
                    onStop: { chatStore.cancelSend() },
                    onSend: { text in
                        // `ComposerView` passes an immutable snapshot so the
                        // empty-state → message-list transition cannot race a
                        // second read from the shared draft binding.
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
                )
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
    }

    /// Cycle the active conversation's mode: rational → balanced → warm (→ …).
    /// The visible capsule and refresh symbol make the action discoverable.
    private func cycleMode() {
        guard let convID = chatStore.selectedConversationID else { return }
        let current = chatStore.selectedConversation?.mode ?? settings.conversationMode
        let all = ConversationMode.allCases
        guard let idx = all.firstIndex(of: current) else { return }
        chatStore.setMode(all[(idx + 1) % all.count], for: convID)
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

    /// Apple's modern programmatic scroll API (macOS 14+).
    @State private var scrollPosition = ScrollPosition()

    private var messageList: some View {
        GeometryReader { viewport in
            ScrollView {
                messageStack(viewportHeight: viewport.size.height)
                .scrollTargetLayout()
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .scrollPosition($scrollPosition, anchor: .top)
            .defaultScrollAnchor(.top)
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .prismTopScrollEdge()
            .onScrollGeometryChange(for: Bool.self) { geometry in
                // Ignore the temporary generation runway when deciding whether
                // the user has moved away from the newest actual message.
                let sendingRunway = chatStore.isSending
                    ? max(140, viewport.size.height - 150)
                    : 0
                let latestMessageBottom = geometry.contentSize.height - sendingRunway
                return geometry.visibleRect.maxY < latestMessageBottom - 80
            } action: { _, isAwayFromLatest in
                withAnimation(.easeOut(duration: 0.16)) {
                    showScrollToLatest = isAwayFromLatest
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showScrollToLatest {
                    Button(action: scrollToLatestMessage) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassBackground(cornerRadius: 16, style: .interactive)
                    .help(scrollToLatestHelp)
                    .padding(.trailing, 28)
                    .padding(.bottom, 82)
                    .transition(.opacity.combined(with: .scale(scale: 0.88)))
                }
            }
        }
        .onAppear {
            pinnedUserMessageID = latestUserMessageID
            scrollToTop()
        }
        .onChange(of: messageIDs) { _, _ in
            guard let latestUserMessageID,
                  latestUserMessageID != pinnedUserMessageID else { return }
            pinnedUserMessageID = latestUserMessageID
            pinMessageToTop(latestUserMessageID)
        }
        .onChange(of: scrollToMessageID) {
            guard let targetID = scrollToMessageID else { return }
            selectedMessageID = targetID
            DispatchQueue.main.async {
                scrollPosition.scrollTo(id: targetID)
                scrollToMessageID = nil
            }
        }
        .onChange(of: chatStore.selectedConversationID) { _, _ in
            pinnedUserMessageID = latestUserMessageID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                scrollToTop()
            }
        }
        .onChange(of: editMessageID) {
            syncDraftWithEditedMessage()
        }
    }

    private func scrollToTop() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            scrollPosition.scrollTo(edge: .top)
        }
    }

    private func pinMessageToTop(_ messageID: ChatMessage.ID) {
        DispatchQueue.main.async {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                scrollPosition.scrollTo(id: messageID)
            }
        }
    }

    private func scrollToLatestMessage() {
        withAnimation(.easeInOut(duration: 0.22)) {
            scrollPosition.scrollTo(id: Self.latestMessageScrollTarget, anchor: .bottom)
        }
    }

    private var scrollToLatestHelp: String {
        switch settings.language {
        case .simplifiedChinese:
            return "回到最新消息"
        case .traditionalChinese:
            return "回到最新訊息"
        case .english:
            return "Jump to latest message"
        }
    }

    private var latestUserMessageID: ChatMessage.ID? {
        chatStore.selectedConversation?.messages.last(where: { $0.role == .user })?.id
    }

    private var messageIDs: [ChatMessage.ID] {
        chatStore.selectedConversation?.messages.map(\.id) ?? []
    }

    private func messageStack(viewportHeight: CGFloat) -> some View {
        let messages: [ChatMessage] = chatStore.selectedConversation?.messages ?? []

        return LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(messages) { message in
                messageRow(message)
            }

            // Keep only enough permanent clearance for the floating composer.
            Color.clear
                .frame(height: 60)
                .id(Self.latestMessageScrollTarget)
                .accessibilityHidden(true)

            // The generation runway lets the newest prompt pin to the top. It
            // sits after the "latest message" target so the return button never
            // jumps into this temporary blank area.
            if chatStore.isSending {
                Color.clear
                    .frame(height: max(140, viewportHeight - 150))
                    .accessibilityHidden(true)
            }
        }
    }

    private func syncDraftWithEditedMessage() {
        guard let messageID = editMessageID else { return }
        guard let conversation = chatStore.selectedConversation else { return }
        guard let message = conversation.messages.first(where: { $0.id == messageID }) else { return }
        draft = message.content
    }

    private func messageRow(_ message: ChatMessage) -> some View {
        let conversationID = chatStore.selectedConversationID ?? UUID()
        let isLast = message.id == chatStore.selectedConversation?.messages.last?.id

        return MessageBubble(
            message: message,
            isSelected: selectedMessageID == message.id,
            conversationID: conversationID,
            isStreaming: chatStore.isSending && isLast,
            onEdit: {
                editMessageID = message.id
                draft = message.content
            },
            onDelete: {
                pendingDelete = deletionTarget(for: message, conversationID: conversationID)
            },
            onRegenerate: { messageID in
                let task = Task {
                    await chatStore.regenerateAssistantMessage(
                        in: conversationID,
                        messageID: messageID,
                        settings: settings
                    )
                }
                chatStore.currentSendTask = task
            }
        )
        .equatable()
        // Make the scroll target begin slightly before the visible bubble.
        // With the target aligned to `.top`, this leaves a 12 pt clearance
        // below the window toolbar without changing normal row spacing.
        .padding(.top, 12)
        .id(message.id)
    }

    private func deletionTarget(for message: ChatMessage, conversationID: UUID) -> PendingDelete {
        let messages = chatStore.selectedConversation?.messages ?? []
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else {
            return .message(conversationID: conversationID, messageID: message.id, paired: false)
        }

        if message.role == .user,
           index + 1 < messages.count,
           messages[index + 1].role == .assistant {
            return .message(conversationID: conversationID, messageID: message.id, paired: true)
        }

        if message.role == .assistant,
           index > 0,
           messages[index - 1].role == .user {
            return .message(conversationID: conversationID, messageID: messages[index - 1].id, paired: true)
        }

        return .message(conversationID: conversationID, messageID: message.id, paired: false)
    }

}

private extension View {
    @ViewBuilder
    func prismTopScrollEdge() -> some View {
        if #available(macOS 26, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}

// MARK: - Mode Badge (per-conversation mode cycling)

/// Compact mode control. The enclosing toolbar supplies its native capsule on
/// macOS 26+, including the platform hover treatment.
struct ModeBadgeButton: View {
    let mode: ConversationMode
    let language: AppLanguage
    let onCycle: () -> Void
    @State private var isHovering = false

    private var dotColor: Color {
        switch mode {
        case .rational: .teal
        case .balanced: .orange
        case .warm: .red
        }
    }

    private var label: String {
        switch mode {
        case .rational: L10n.text(.modeRational, language)
        case .balanced: L10n.text(.modeBalanced, language)
        case .warm: L10n.text(.modeWarm, language)
        }
    }

    var body: some View {
        Button(action: onCycle) {
            HStack(spacing: 5) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(isHovering ? Color.primary.opacity(0.09) : .clear)
            }
            .overlay {
                Capsule()
                    .stroke(Color.primary.opacity(isHovering ? 0.16 : 0), lineWidth: 0.5)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(L10n.text(.conversationModeHint, language))
    }
}

// MARK: - Current-conversation context usage

struct ContextUsageButton: View {
    let snapshot: ContextUsageSnapshot
    let language: AppLanguage
    @State private var isHovering = false
    @State private var isPresented = false

    private var accent: Color {
        if snapshot.critical { return .red }
        if snapshot.compressionActive { return .orange }
        if snapshot.preparationActive { return .yellow }
        return .secondary
    }

    var body: some View {
        Button { isPresented.toggle() } label: {
            Text(snapshot.percentageLabel)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background {
                    Capsule().fill(isHovering ? Color.primary.opacity(0.09) : .clear)
                }
                .overlay {
                    Capsule().stroke(Color.primary.opacity(isHovering ? 0.16 : 0), lineWidth: 0.5)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(contextTitle)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            contextDetails
        }
    }

    private var contextDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(contextTitle).font(.headline)
                Spacer()
                Text(snapshot.percentageLabel)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(accent)
            }
            ProgressView(value: snapshot.percentage, total: 100)
                .tint(accent)

            VStack(alignment: .leading, spacing: 7) {
                detailRow(tokensLabel, "\(number(snapshot.estimatedTokens)) / \(number(snapshot.capacityTokens))")
                if snapshot.compressionActive {
                    detailRow(uncompressedTokensLabel, number(snapshot.uncompressedEstimatedTokens))
                }
                detailRow(outputReserveLabel, number(snapshot.reservedOutputTokens))
                detailRow(messageCountLabel, "\(snapshot.messageCount)")
            }
            .font(.caption)

            Divider()

            contextNoteRow(
                compressionText,
                systemImage: snapshot.compressionActive ? "archivebox.fill" : "clock"
            )
            contextNoteRow(summaryText, systemImage: "text.badge.checkmark")
            Text(riskText)
                .font(.caption)
                .foregroundStyle(snapshot.preparationActive ? accent : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 360)
    }

    private func contextNoteRow(_ text: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 14)
            Text(text)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
    }

    private func number(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    private var contextTitle: String {
        switch language {
        case .simplifiedChinese: "当前会话上下文（估算）"
        case .traditionalChinese: "目前對話上下文（估算）"
        case .english: "Current conversation context (estimated)"
        }
    }

    private var tokensLabel: String {
        language == .english ? "Estimated input tokens" : language == .traditionalChinese ? "估算輸入 Token" : "估算输入 Token"
    }

    private var outputReserveLabel: String {
        language == .english ? "Reserved for reply" : language == .traditionalChinese ? "回覆預留" : "回复预留"
    }

    private var uncompressedTokensLabel: String {
        language == .english ? "Before compression" : language == .traditionalChinese ? "壓縮前估算" : "压缩前估算"
    }

    private var messageCountLabel: String {
        language == .english ? "Messages in this chat" : language == .traditionalChinese ? "本對話訊息數" : "本会话消息数"
    }

    private var compressionText: String {
        if snapshot.compressionActive {
            switch language {
            case .simplifiedChinese: return "已达到 75%：发送时压缩旧内容，保留最近约 \(number(snapshot.retainedRecentTokens)) Token 原文；本地记录不删除。"
            case .traditionalChinese: return "已達到 75%：傳送時壓縮舊內容，保留最近約 \(number(snapshot.retainedRecentTokens)) Token 原文；本機記錄不刪除。"
            case .english: return "At 75%: older request context is compressed while about \(number(snapshot.retainedRecentTokens)) recent tokens stay verbatim; local history is untouched."
            }
        }
        if snapshot.preparationActive {
            switch language {
            case .simplifiedChinese: return "当前占用已超过 55%。这只是容量提醒，发送内容不会变化；达到 75% 后才会压缩旧内容，还差约 \(number(snapshot.tokensUntilCompression)) Token。"
            case .traditionalChinese: return "目前佔用已超過 55%。這只是容量提醒，傳送內容不會變化；達到 75% 後才會壓縮舊內容，還差約 \(number(snapshot.tokensUntilCompression)) Token。"
            case .english: return "Usage is above 55%. This is only a capacity notice and does not change the request; older context is compressed at 75%, about \(number(snapshot.tokensUntilCompression)) tokens away."
            }
        }
        switch language {
        case .simplifiedChinese: return "达到 55% 时仅显示容量提醒，不会改变发送内容（还差约 \(number(snapshot.tokensUntilPreparation)) Token）；达到 75% 后才会压缩旧内容。"
        case .traditionalChinese: return "達到 55% 時只顯示容量提醒，不會改變傳送內容（還差約 \(number(snapshot.tokensUntilPreparation)) Token）；達到 75% 後才會壓縮舊內容。"
        case .english: return "At 55%, Prism only shows a capacity notice and does not change the request (about \(number(snapshot.tokensUntilPreparation)) tokens away); older context is compressed at 75%."
        }
    }

    private var summaryText: String {
        if snapshot.summaryInterval == 0 {
            return language == .english ? "Automatic chapter synthesis is disabled." : language == .traditionalChinese ? "自動章節歸納已停用。" : "自动章节归纳已停用。"
        }
        switch language {
        case .simplifiedChinese: return "章节约每 \(snapshot.summaryInterval) 轮更新；距下次归纳约 \(snapshot.dialogsUntilSummary) 轮。"
        case .traditionalChinese: return "章節約每 \(snapshot.summaryInterval) 輪更新；距下次歸納約 \(snapshot.dialogsUntilSummary) 輪。"
        case .english: return "Chapters update about every \(snapshot.summaryInterval) turns; roughly \(snapshot.dialogsUntilSummary) turns until the next synthesis."
        }
    }

    private var riskText: String {
        if snapshot.critical {
            switch language {
            case .simplifiedChinese: return "未压缩内容已超过 85%。Prism 会强制压缩请求，避免截断、失败或挤占回复空间。"
            case .traditionalChinese: return "未壓縮內容已超過 85%。Prism 會強制壓縮請求，避免截斷、失敗或擠佔回覆空間。"
            case .english: return "Uncompressed context is above 85%. Prism compacts the request to avoid truncation, failure, or crowding out the reply."
            }
        }
        if snapshot.preparationActive {
            switch language {
            case .simplifiedChinese: return "占用升高会增加延迟与输入成本；正式压缩前，原始对话仍完整发送。"
            case .traditionalChinese: return "佔用升高會增加延遲與輸入成本；正式壓縮前，原始對話仍完整傳送。"
            case .english: return "Higher usage increases latency and input cost; the raw transcript remains intact until formal compression."
            }
        }
        switch language {
        case .simplifiedChinese: return "Prism 按 Token 占用管理上下文；章节归纳不会提前删除或替换原始对话。"
        case .traditionalChinese: return "Prism 按 Token 佔用管理上下文；章節歸納不會提前刪除或替換原始對話。"
        case .english: return "Prism manages context by token usage; chapter synthesis does not prematurely replace the raw conversation."
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
                                    .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            // Clip only the moving disclosure content. Keeping
                            // the glass modifier outside preserves its edge
                            // refraction in both collapsed and expanded states.
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .glassBackground(cornerRadius: 14, style: .secondary)
                    }

                    if message.role == .assistant,
                       let calls = message.toolCalls, !calls.isEmpty,
                       message.content == "🔧 正在查询…" {
                        // Tool execution in progress — show live tool badges
                        // (Tauri parity: wrench badge + tool name while tools run).
                        VStack(alignment: .leading, spacing: 7) {
                            ThinkingIndicator(language: settings.language)
                            HStack(spacing: 6) {
                                ForEach(calls, id: \.id) { call in
                                    HStack(spacing: 4) {
                                        Image(systemName: "wrench.and.screwdriver")
                                            .font(.caption2)
                                        Text(call.name)
                                            .font(.caption2.weight(.medium))
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(.quaternary))
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    } else if message.content.isEmpty, message.role == .assistant {
                        ThinkingIndicator(language: settings.language)
                            .padding(.vertical, 2)
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
                        .stroke(borderColor, lineWidth: 0.75)
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
        NativeSupport.copyToClipboard(message.content)
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

// MARK: - Thinking Indicator

struct ThinkingIndicator: View {
    let language: AppLanguage
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color.secondary)
                .frame(width: 7, height: 7)
                .scaleEffect(isPulsing ? 1 : 0.55)
                .opacity(isPulsing ? 0.95 : 0.35)

            Text(L10n.text(.thinkingNow, language))
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Composer with Dynamic Height + Liquid Glass (pure SwiftUI)

/// Multi-line composer built entirely with SwiftUI.
///
/// `TextField(axis: .vertical)` grows with wrapped text up to
/// `lineLimit(1...8)` and scrolls internally beyond that. Return sends and
/// Shift+Return inserts a newline. Plain Return is observed through both
/// `.onSubmit` and `.onKeyPress`: behavior differs slightly across macOS and
/// input methods, so the two paths provide a reliable fallback for each other.
///
/// Note: during active Chinese/Japanese IME composition, Return is normally
/// consumed by the input session before `.onKeyPress` (so candidate
/// confirmation keeps working); verify on first use.
struct ComposerView: View {
    @Binding var draft: String
    var isSending: Bool
    var mode: ConversationMode
    var contextUsage: ContextUsageSnapshot
    var language: AppLanguage
    var onCycleMode: () -> Void
    var onStop: () -> Void
    var onSend: (String) -> Void

    @FocusState private var isFocused: Bool

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            TextField("", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...8)
                .focused($isFocused)
                .submitLabel(.send)
                .onSubmit { submit() }
                .onAppear {
                    // Defer until the new-conversation view is attached to the
                    // key window; immediate focus can be dropped on first load.
                    DispatchQueue.main.async { isFocused = true }
                }
                .onKeyPress(keys: [.return]) { press in
                    if press.modifiers.contains(.shift) {
                        // Shift+Return → newline
                        draft += "\n"
                        return .handled
                    }
                    // Return → send
                    submit()
                    return .handled
                }
                .padding(.horizontal, 12)
                .padding(.trailing, 178)
                .padding(.vertical, 11)
                .frame(minHeight: 54)
                .glassBackground(cornerRadius: 20, style: .deep)

            HStack(spacing: 6) {
                ModeBadgeButton(mode: mode, language: language, onCycle: onCycleMode)
                ContextUsageButton(snapshot: contextUsage, language: language)

                if isSending {
                    Button(action: onStop) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                } else {
                    Button {
                        submit()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(trimmed.isEmpty ? .secondary : .blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmed.isEmpty)
                }
            }
            .padding(.trailing, 12)
        }
        .frame(maxWidth: 720)
    }

    private func submit() {
        let text = trimmed
        guard !text.isEmpty, !isSending else { return }
        onSend(text)
    }
}

// MARK: - Memory Panel (standalone window)

struct MemoryPanelView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var usageStatsStore = UsageStatsStore.shared

    private var currentPeople: [PersonRecord] {
        guard let id = chatStore.selectedConversationID else { return [] }
        return chatStore.personArchive.filter { $0.conversationIDs?.contains(id) == true }
    }

    private var currentEmotions: [EmotionEntry] {
        guard let id = chatStore.selectedConversationID else { return [] }
        return chatStore.emotionTimeline.filter { $0.conversationID == id }
    }

    private var currentBlindspots: [BlindspotRecord] {
        guard let id = chatStore.selectedConversationID else { return [] }
        return chatStore.blindspots.filter { $0.conversationID == id }
    }

    private var currentMemories: [MemoryEntry] {
        guard let id = chatStore.selectedConversationID else { return [] }
        return chatStore.memoryStore.filter { $0.sourceConversationID == id }
    }

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
                    MemorySection(title: L10n.text(.modelUsage, settings.language), icon: "gauge.with.dots.needle.50percent", color: .teal) {
                        usageBlock
                    }

                    // The narrative timeline follows when events happened in
                    // the user's story, not when messages were sent.
                    MemorySection(title: L10n.text(.memoryTimeline, settings.language), icon: "clock.arrow.trianglehead.counterclockwise.rotate.90", color: .indigo) {
                        let events = chatStore.narrativeTimeline
                            .filter { $0.conversationID == chatStore.selectedConversationID }
                            .sorted { $0.sortIndex < $1.sortIndex }
                        if events.isEmpty {
                            Text(L10n.text(.narrativeNoEvents, settings.language))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            timelineBlock(events: events)
                        }
                    }

                    // 人物：只展示当前对话明确归属的人物档案。
                    if !currentPeople.isEmpty {
                        MemorySection(title: L10n.text(.memoryPeople, settings.language), icon: "person.2.fill", color: .blue) {
                            ForEach(currentPeople.sorted { $0.mentionCount > $1.mentionCount }) { person in
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
                    if !currentEmotions.isEmpty {
                        MemorySection(title: L10n.text(.memoryEmotions, settings.language), icon: "waveform.path.ecg", color: .purple) {
                            let grouped = groupEmotions(currentEmotions.suffix(20))
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
                    if !currentBlindspots.isEmpty {
                        MemorySection(title: L10n.text(.memoryBlindspots, settings.language), icon: "eye.slash.fill", color: .red) {
                            ForEach(currentBlindspots.suffix(10).reversed()) { spot in
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
                    if !currentMemories.isEmpty {
                        MemorySection(title: L10n.text(.memoryInsights, settings.language), icon: "lightbulb.fill", color: .yellow) {
                            let memories = currentMemories.sorted { ($0.lastRecalledAt ?? $0.createdAt) > ($1.lastRecalledAt ?? $1.createdAt) }
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

                    if currentPeople.isEmpty && currentEmotions.isEmpty
                        && currentBlindspots.isEmpty && currentMemories.isEmpty {
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
        .onAppear {
            usageStatsStore.reload()
            if settings.providerBalance == nil {
                Task { await settings.refreshProviderBalance() }
            }
        }
    }
}

private struct EmotionGroup { let emotion: String; let intensity: Double; let count: Int }

// MARK: - Memory Timeline Helpers

private extension MemoryPanelView {
    var usageBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                usageMetric(L10n.text(.inputTokens, settings.language), tokenText(usageStatsStore.stats.inputTokens))
                usageMetric(L10n.text(.outputTokens, settings.language), tokenText(usageStatsStore.stats.outputTokens))
                usageMetric(
                    L10n.text(.cacheHitRate, settings.language),
                    usageStatsStore.stats.cacheHitRate.map { String(format: "%.1f%%", $0 * 100) } ?? "—"
                )
            }

            if let providerBalance = settings.providerBalance, !providerBalance.balanceInfos.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text(.accountBalance, settings.language))
                        .font(.caption.weight(.semibold))
                    ForEach(providerBalance.balanceInfos) { info in
                        HStack {
                            Text(info.currency).font(.caption.monospaced())
                            Spacer()
                            Text("\(info.totalBalance)  ·  \(L10n.text(.grantedBalance, settings.language)): \(info.grantedBalance)  ·  \(L10n.text(.toppedUpBalance, settings.language)): \(info.toppedUpBalance)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary))
            } else if settings.balanceUnavailable {
                Text(L10n.text(.balanceUnavailable, settings.language))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    func usageMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary))
    }

    func tokenText(_ value: Int64) -> String {
        if value >= 1_000_000 { return String(format: "%.2fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return String(value)
    }

    /// Vertical event chronology derived from the user's account.
    @ViewBuilder
    func timelineBlock(events: [NarrativeEvent]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                let timeText = event.endLabel.isEmpty
                    ? event.startLabel
                    : "\(event.startLabel) – \(event.endLabel)"
                timelineRow(
                    icon: event.timeKind == "date" ? "calendar" : "calendar.badge.clock",
                    color: event.timeKind == "date" ? .blue : .indigo,
                    title: event.title,
                    value: timeText,
                    detail: event.summary,
                    isLast: index == events.count - 1
                )
            }
        }
    }

    func timelineRow(icon: String, color: Color, title: String, value: String, detail: String = "", isLast: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(color)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(color.opacity(0.12)))
                if !isLast {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 2, height: 22)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }

    func memoryDateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: settings.language == .english ? "en_US_POSIX" : "zh_CN")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }

    func memoryDurationText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if settings.language == .english {
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
}

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
