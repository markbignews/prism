import SwiftUI
import UniformTypeIdentifiers
import AppKit

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
    var shapeKind: ShapeKind = .rounded

    enum ShapeKind {
        case rounded
        case capsule
    }

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
                .glassEffect(glass, in: backgroundShape)
        } else {
            content
                .background(fallbackMaterial, in: backgroundShape)
                // Depth — glass sits above content
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1.5)
                .overlay {
                    // Outer edge for boundary definition on any background
                    backgroundShape
                        .stroke(.primary.opacity(0.18), lineWidth: 0.5)
                }
                .overlay {
                    // Inner highlight: top-left edge catches ambient light
                    backgroundShape
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

    private var backgroundShape: AnyShape {
        switch shapeKind {
        case .rounded:
            AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        case .capsule:
            AnyShape(Capsule())
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
    func glassBackground(
        cornerRadius: CGFloat = 8,
        style: GlassBackground.GlassStyle = .regular,
        shape: GlassBackground.ShapeKind = .rounded
    ) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius, style: style, shapeKind: shape))
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
    @State private var draftAttachments: [MessageAttachment] = []
    @State private var clarificationDrafts: [UUID: ClarificationDraft] = [:]
    @State private var selectedMessageID: ChatMessage.ID?
    @State private var scrollToMessageID: ChatMessage.ID?
    @State private var selectedChapter: StoryChapter?
    @State private var renameTarget: Conversation.ID?
    @State private var renameText = ""
    @State private var editMessageID: ChatMessage.ID?
    @State private var previousConversationID: Conversation.ID?
    @State private var showMemoryPanel = false
    @State private var pendingDelete: PendingDelete?

    init(initialDraft: String = "") {
        _draft = State(initialValue: initialDraft)
    }

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
                draftAttachments: $draftAttachments,
                clarificationDrafts: $clarificationDrafts,
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
            draftAttachments = []
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
                            .disabled(chatStore.isSummarizing || chatStore.isRebuildingMemory)
                        }
                    }
                }

            }
            .listStyle(.sidebar)
        }
        .onChange(of: chatStore.lastSummaryStatus) { _, newStatus in
            if !newStatus.isEmpty,
               chatStore.lastSummarySucceeded == false {
                showSummaryError = true
            }
        }
        .alert(L10n.text(.summaryFailed, settings.language), isPresented: $showSummaryError) {
            Button(L10n.text(.done, settings.language), role: .cancel) { }
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
    @EnvironmentObject private var settings: AppSettings
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
            .help(L10n.text(.chapterDetails, settings.language))
        }
    }
}

// MARK: - Chat View

struct ChatView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var settings: AppSettings
    @Binding var draft: String
    @Binding var draftAttachments: [MessageAttachment]
    @Binding var clarificationDrafts: [UUID: ClarificationDraft]
    @Binding var selectedMessageID: ChatMessage.ID?
    @Binding var scrollToMessageID: ChatMessage.ID?
    @Binding var selectedChapter: StoryChapter?
    @Binding var editMessageID: ChatMessage.ID?
    @Binding var pendingDelete: PendingDelete?

    /// The most recent user turn already pinned to the top of the viewport.
    /// Tracking the ID avoids re-scrolling while assistant tokens stream in.
    @State private var pinnedUserMessageID: ChatMessage.ID?
    @State private var showScrollToLatest = false
    @State private var showStorageReload = false
    @State private var composerHeight: CGFloat = 68

    /// A stable target immediately after the newest real message. The small
    /// spacer keeps the latest reply clear of the floating composer, while the
    /// larger sending runway remains outside this target.
    private static let latestMessageScrollTarget = "prism.latest-message-bottom"

    private var isNewConversation: Bool {
        let userMsgs = chatStore.selectedConversation?.messages.filter { $0.role == .user } ?? []
        return userMsgs.isEmpty
    }

    private var pendingPersonLinkProposal: PersonLinkProposal? {
        guard let conversationID = chatStore.selectedConversationID else { return nil }
        return chatStore.personLinkProposals
            .filter { $0.conversationID == conversationID && $0.decision == "pending" }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    var body: some View {
        // ZStack lets messages render behind the input area so chat content
        // refracts through the Liquid Glass input box.
        GeometryReader { geometry in
            let hasClarification = !chatStore.isSending && chatStore.pendingClarification != nil
            let reviewCount = hasClarification ? 1 : (pendingPersonLinkProposal == nil ? 0 : 1)
                + ((!chatStore.isSending && chatStore.pendingNarrativeEvent != nil) ? 1 : 0)
            let reviewBodyHeight = ConfirmationLayout.bodyHeight(availableHeight: geometry.size.height, cardCount: reviewCount)
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
                        if chatStore.hasStorageFailure {
                            HStack {
                                if chatStore.canRetryStorage {
                                    Button(L10n.text(.retryStorage, settings.language)) { chatStore.retryStorage() }
                                }
                                Button(L10n.text(.exportSnapshot, settings.language)) {
                                    NativeSupport.exportSnapshot(chatStore, language: settings.language)
                                }
                                Button(L10n.text(.reloadStorage, settings.language)) { showStorageReload = true }
                            }
                            .font(.caption)
                            .confirmationDialog(L10n.text(.reloadStorage, settings.language), isPresented: $showStorageReload) {
                                Button(L10n.text(.reloadStorage, settings.language), role: .destructive) {
                                    chatStore.discardAndReloadStorage(settings: settings)
                                }
                            } message: { Text(L10n.text(.reloadStorageHint, settings.language)) }
                        }
                    }

                    if !hasClarification, let proposal = pendingPersonLinkProposal,
                       let source = chatStore.personArchive.first(where: { $0.id == proposal.sourcePersonID }),
                       let candidate = chatStore.personArchive.first(where: { $0.id == proposal.candidatePersonID }) {
                        PersonLinkConfirmationBanner(
                            source: source,
                            candidate: candidate,
                            evidence: proposal.evidence,
                            language: settings.language,
                            maxBodyHeight: reviewBodyHeight,
                            confirm: { chatStore.confirmPersonLinkProposal(id: proposal.id) },
                            reject: { chatStore.rejectPersonLinkProposal(id: proposal.id) }
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                    }

                    if !hasClarification, !chatStore.isSending, let proposal = chatStore.pendingNarrativeEvent {
                        NarrativeEventApprovalView(proposal: proposal, maxBodyHeight: reviewBodyHeight)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 4)
                    }

                    if !chatStore.isSending, let request = chatStore.pendingClarification {
                        ClarificationCard(request: request, draft: Binding(
                            get: { clarificationDrafts[request.id] ?? ClarificationDraft() },
                            set: { clarificationDrafts[request.id] = $0 }
                        ), maxBodyHeight: min(120, reviewBodyHeight)) { submission in
                            let task = Task { await chatStore.submitClarification(submission, settings: settings) }
                            chatStore.currentSendTask = task
                        }
                        .id(request.id)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                    }

                    ComposerView(
                        draft: $draft,
                        attachments: $draftAttachments,
                        isSending: chatStore.isSending,
                        mode: chatStore.selectedConversation?.mode ?? settings.conversationMode,
                        contextUsage: chatStore.contextUsage(settings: settings),
                        language: settings.language,
                        selectedModel: settings.model,
                        onCycleMode: { cycleMode() },
                        onStop: { chatStore.cancelSend() },
                        onSend: { text, attachments in
                            guard !chatStore.isRebuildingMemory else { return }
                            // `ComposerView` passes an immutable snapshot so the
                            // empty-state → message-list transition cannot race a
                            // second read from the shared draft binding.
                            draft = ""
                            draftAttachments = []
                            let task = Task {
                                if let msgID = editMessageID {
                                    editMessageID = nil
                                    await chatStore.editAndResend(userMessageID: msgID, newText: text, settings: settings)
                                } else {
                                    await chatStore.send(text, attachments: attachments, settings: settings)
                                }
                            }
                            chatStore.currentSendTask = task
                        }
                    )
                    .disabled(chatStore.isRebuildingMemory)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.height } action: { height in
                    composerHeight = height
                }
            }
        }
        .navigationTitle(chatStore.selectedConversation?.title ?? "")
        .navigationSubtitle(Text(L10n.text(.aiGeneratedSubtitle, settings.language)))
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
                .frame(height: composerHeight + 12)
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
        let onEdit: () -> Void = {
            editMessageID = message.id
            draft = message.content
        }
        let onDelete: () -> Void = { pendingDelete = deletionTarget(for: message, conversationID: conversationID) }
        let onRegenerate: (UUID) -> Void = { messageID in
            let task = Task {
                await chatStore.regenerateAssistantMessage(in: conversationID, messageID: messageID, settings: settings)
            }
            chatStore.currentSendTask = task
        }
        return Group {
            if chatStore.isSending && chatStore.streamingMessageID == message.id {
                StreamingMessageBubble(stream: chatStore.stream, fallback: message,
                    isSelected: selectedMessageID == message.id, conversationID: conversationID,
                    onEdit: onEdit, onDelete: onDelete, onRegenerate: onRegenerate)
            } else {
                MessageBubble(message: message, isSelected: selectedMessageID == message.id,
                    conversationID: conversationID, isStreaming: false,
                    onEdit: onEdit, onDelete: onDelete, onRegenerate: onRegenerate)
                    .equatable()
            }
        }
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
            case .simplifiedChinese: return "已整理较早的对话，近期原文仍保留；完整记录可回查。"
            case .traditionalChinese: return "已整理較早的對話，近期原文仍保留；完整記錄可回查。"
            case .english: return "Older context has been summarized; recent messages remain verbatim and originals can be reopened."
            }
        }
        switch language {
        case .simplifiedChinese: return "请求接近约 \(number(snapshot.compressionThresholdTokens)) Token 时，先缩减过长工具结果，再按需整理旧对话。还差约 \(number(snapshot.tokensUntilCompression)) Token。"
        case .traditionalChinese: return "請求接近約 \(number(snapshot.compressionThresholdTokens)) Token 時，先縮減過長工具結果，再依需要整理舊對話。還差約 \(number(snapshot.tokensUntilCompression)) Token。"
        case .english: return "Near \(number(snapshot.compressionThresholdTokens)) tokens, oversized tool results are reduced before older context is summarized if needed. About \(number(snapshot.tokensUntilCompression)) tokens remain."
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
            case .simplifiedChinese: return "当前估算已接近模型上限。Prism 会尝试安全整理；当前消息或附件过大时，仍可能需要缩短后再发送。"
            case .traditionalChinese: return "目前估算已接近模型上限。Prism 會嘗試安全整理；目前訊息或附件過大時，仍可能需要縮短後再傳送。"
            case .english: return "The estimate is close to the model limit. Prism will attempt safe compaction; a very large current message or attachment may still need shortening."
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
                        Label(L10n.text(.chapterSummary, settings.language), systemImage: "text.alignleft")
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
                            Label(L10n.text(.originalMessages, settings.language), systemImage: "bubble.left.and.bubble.right")
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
                        Text(L10n.text(.messageNotFound, settings.language))
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

    @State private var isReasoningExpanded = false

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
                        ReasoningDisclosure(
                            text: reasoning,
                            language: settings.language,
                            isStreaming: isStreaming,
                            isExpanded: $isReasoningExpanded
                        )
                    }

                    if message.role == .user, !message.attachments.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(message.attachments) { attachment in
                                AttachmentPreview(attachment: attachment, compact: true)
                            }
                        }
                    }

                    if message.role == .assistant,
                       let calls = message.toolCalls, !calls.isEmpty,
                       message.isToolPlaceholder {
                        // Tool execution in progress — show live tool badges
                        // Show a wrench badge and tool name while tools run.
                        VStack(alignment: .leading, spacing: 7) {
                            ThinkingIndicator(language: settings.language)
                            HStack(spacing: 6) {
                                ForEach(calls, id: \.id) { call in
                                    HStack(spacing: 4) {
                                        Image(systemName: "wrench.and.screwdriver")
                                            .font(.caption2)
                                        Text(ToolRegistry.displayName(call.name, language: settings.language))
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
                        MarkdownText(text: message.content).equatable()
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
            .onChange(of: message.reasoning?.isEmpty ?? true) { _, isEmpty in
                if !isEmpty && message.content.isEmpty && isStreaming { isReasoningExpanded = true }
            }
            .onChange(of: message.content) { oldContent, newContent in
                // Collapse reasoning when real response content starts flowing.
                // Skip tool-status placeholders so reasoning stays visible during
                // tool execution is tracked by runtime state, independent of language.
                if oldContent.isEmpty, !newContent.isEmpty, isReasoningExpanded,
                   !message.isToolPlaceholder {
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

// MARK: - Reasoning Disclosure

private struct ReasoningDisclosure: View {
    let text: String
    let language: AppLanguage
    let isStreaming: Bool
    @Binding var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bodyHeight: CGFloat = 180
    @State private var followsLatest = true
    @State private var isUserScrolling = false
    @State private var reasoningScrollPosition = ScrollPosition()

    private struct ScrollMetrics: Equatable {
        let contentHeight: CGFloat
        let viewportHeight: CGFloat
        let visibleBottom: CGFloat

        var isAtBottom: Bool { contentHeight - visibleBottom <= 24 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Only the header is a button. Selecting text, opening a Markdown
            // link or copying code must not collapse the reasoning panel.
            Button {
                // Long text should appear immediately, without animating the
                // height/layout of every paragraph and the surrounding history.
                if !isExpanded { followsLatest = true }
                isExpanded.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "brain.head.profile").font(.caption2)
                    Text(L10n.text(.thinking, language)).font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isExpanded)
                }
                .foregroundStyle(.secondary)
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.horizontal, 10)
                ScrollView(.vertical) {
                    MarkdownText(text: text, style: .reasoning).equatable()
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onGeometryChange(for: CGFloat.self) { geometry in
                            // Once capped, incoming text no longer resizes the
                            // bubble or invalidates the outer chat's layout.
                            min(260, max(44, geometry.size.height.rounded(.up)))
                        } action: { height in
                            if bodyHeight != height { bodyHeight = height }
                        }
                }
                .frame(height: bodyHeight)
                .defaultScrollAnchor(.top)
                .defaultScrollAnchor(isStreaming ? .bottom : .top, for: .initialOffset)
                // Follow the rendered Markdown's actual size changes, which
                // arrive after async parsing, rather than the incoming token.
                .defaultScrollAnchor(.top, for: .sizeChanges)
                .scrollPosition($reasoningScrollPosition)
                .onScrollPhaseChange { _, phase, context in
                    isUserScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
                    if isUserScrolling || phase == .idle {
                        followsLatest = context.geometry.contentSize.height - context.geometry.visibleRect.maxY <= 24
                    }
                }
                .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                    ScrollMetrics(contentHeight: geometry.contentSize.height.rounded(),
                                  viewportHeight: geometry.containerSize.height.rounded(),
                                  visibleBottom: geometry.visibleRect.maxY.rounded())
                } action: { old, new in
                    // Scrollbar, keyboard and accessibility scrolling may not
                    // emit a gesture phase. An offset-only change is a scroll,
                    // while a growing document must not disable following.
                    let offsetOnly = old.contentHeight == new.contentHeight
                        && old.viewportHeight == new.viewportHeight
                        && old.visibleBottom != new.visibleBottom
                    if isUserScrolling || offsetOnly { followsLatest = new.isAtBottom }
                    let resized = old.contentHeight != new.contentHeight || old.viewportHeight != new.viewportHeight
                    if resized, isStreaming, followsLatest, !isUserScrolling {
                        reasoningScrollPosition.scrollTo(edge: .bottom)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .transition(.identity)
            }
        }
        .background(.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.primary.opacity(0.10), lineWidth: 0.75)
        }
    }
}

// MARK: - Thinking Indicator

struct ThinkingIndicator: View {
    let language: AppLanguage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // The repeating animation lives in a separate leaf, so stream updates
        // neither restart the sweep nor animate the message's changing layout.
        Text(L10n.text(.thinkingNow, language))
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
            .overlay {
                if !reduceMotion && scenePhase != .background {
                    ThinkingTextWave()
                        .mask(Text(L10n.text(.thinkingNow, language))
                            .font(.callout.weight(.medium)))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

private struct ThinkingTextWave: View {
    @State private var hasStarted = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            // A soft-edged tonal wave with a legible contrast change, rather than a white reflective
            // stripe. Primary ink gently deepens in light mode and lifts in dark.
            let peak = colorScheme == .dark ? 0.68 : 0.56
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .primary.opacity(peak * 0.08), location: 0.18),
                .init(color: .primary.opacity(peak * 0.48), location: 0.35),
                .init(color: .primary.opacity(peak), location: 0.50),
                .init(color: .primary.opacity(peak * 0.48), location: 0.65),
                .init(color: .primary.opacity(peak * 0.08), location: 0.82),
                .init(color: .clear, location: 1)
            ], startPoint: .leading, endPoint: .trailing)
            .frame(width: geometry.size.width * 0.72)
            .offset(x: geometry.size.width * (hasStarted ? 1.10 : -0.85))
            .animation(.linear(duration: 2.2).repeatForever(autoreverses: false), value: hasStarted)
        }
        .clipped()
        .onAppear { hasStarted = true }
    }
}

/// Shared attachment rendering for the composer and sent user messages.
/// Images are kept in memory for the active conversation, so a thumbnail can
/// be shown without creating a second copy on disk.
struct AttachmentPreview: View {
    let attachment: MessageAttachment
    var compact = false

    var body: some View {
        if attachment.isImage, let image = NSImage(data: attachment.data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: compact ? 48 : 58, height: compact ? 42 : 50)
                .clipShape(RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 0.5)
                }
                .help(attachment.fileName)
        } else {
            HStack(spacing: 5) {
                Image(systemName: "doc.text")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(attachment.fileName)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.secondary.opacity(0.10), in: Capsule())
        }
    }
}

// MARK: - Composer with Dynamic Height + Liquid Glass

private enum ComposerMetrics {
    static let actionDiameter: CGFloat = 28
    static let expandedCornerRadius: CGFloat = 22
}

/// Growing native text editor in a rounded glass composer.
struct ComposerView: View {
    @Binding var draft: String
    @Binding var attachments: [MessageAttachment]
    var isSending: Bool
    var mode: ConversationMode
    var contextUsage: ContextUsageSnapshot
    var language: AppLanguage
    var selectedModel: String
    var onCycleMode: () -> Void
    var onStop: () -> Void
    var onSend: (String, [MessageAttachment]) -> Void

    @State private var showFileImporter = false
    @State private var attachmentError: String?
    @State private var isDropTargeted = false

    private let imageTypes = Set(["image/png", "image/jpeg", "image/gif", "image/webp"])
    private let textTypes = Set([
        "text/plain", "text/markdown", "text/csv", "text/html", "text/xml",
        "text/css", "text/javascript", "application/json", "application/xml",
        "application/javascript", "application/x-yaml", "text/yaml"
    ])
    private let maxAttachmentCount = 5
    private let maxSingleImageBytes = 10 * 1024 * 1024
    private let maxTextBytes = 1 * 1024 * 1024
    private let maxTotalAttachmentBytes = 20 * 1024 * 1024

    private var supportsImages: Bool { selectedModel == DeepSeekModels.flash }
    private var hasUnsupportedImage: Bool {
        !supportsImages && attachments.contains(where: { $0.kind == .image })
    }
    private var attachmentBytes: Int { attachments.reduce(0) { $0 + $1.data.count } }
    private var addAttachmentText: String {
        switch language {
        case .english: "Add attachment"
        case .traditionalChinese: "新增附件"
        default: "添加附件"
        }
    }

    private var inputPlaceholder: String {
        switch language {
        case .english: "Message…"
        case .traditionalChinese: "輸入訊息…"
        default: "输入消息…"
        }
    }

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 4) {
            if !supportsImages {
                Text(proImageUnavailableText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let attachmentError {
                Text(attachmentError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if hasUnsupportedImage {
                Text(proImageUnavailableText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !attachments.isEmpty {
                Text(attachmentRetentionText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(.horizontal, 14)
            }

            VStack(spacing: 0) {
                if !attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(attachments) { attachment in
                                ComposerAttachmentChip(
                                    attachment: attachment,
                                    language: language,
                                    remove: { attachments.removeAll { $0.id == attachment.id } }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                }

                HStack(alignment: .bottom, spacing: 8) {
                    Button { showFileImporter = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(addAttachmentText)
                    .help(addAttachmentText)

                    ScrollableComposer(text: $draft, placeholder: inputPlaceholder, onSubmit: submit)
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    ModeBadgeButton(mode: mode, language: language, onCycle: onCycleMode)
                    ContextUsageButton(snapshot: contextUsage, language: language)

                    if isSending {
                        ComposerActionButton(
                            icon: "stop.fill",
                            tint: .red,
                            enabled: true,
                            accessibilityLabel: stopText,
                            action: onStop
                        )
                        .keyboardShortcut(.escape, modifiers: [])
                    } else {
                        ComposerActionButton(
                            icon: "arrow.up",
                            tint: .blue,
                            enabled: canSubmit,
                            accessibilityLabel: sendText,
                            action: submit
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .glassBackground(
                cornerRadius: ComposerMetrics.expandedCornerRadius,
                style: .deep,
                shape: .rounded
            )
            .overlay {
                RoundedRectangle(cornerRadius: ComposerMetrics.expandedCornerRadius, style: .continuous)
                    .stroke(isDropTargeted ? Color.accentColor : .clear, lineWidth: 1.5)
            }
            .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted, perform: handleDrop)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: allowedAttachmentTypes,
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .frame(maxWidth: 720)
    }

    private var canSubmit: Bool {
        (!trimmed.isEmpty || !attachments.isEmpty) && !hasUnsupportedImage
    }

    private var allowedAttachmentTypes: [UTType] {
        supportsImages ? [.image, .text, .data] : [.text, .data]
    }

    private var proImageUnavailableText: String {
        switch language {
        case .english: "DeepSeek V4 Pro does not support image uploads. Remove the image or switch to V4.1 Flash."
        case .traditionalChinese: "DeepSeek V4 Pro 不支援上傳圖片。請移除圖片或切換至 V4.1 Flash。"
        default: "DeepSeek V4 Pro 不支持上传图片。请移除图片或切换至 V4.1 Flash。"
        }
    }

    private var attachmentRetentionText: String {
        switch language {
        case .english: "The message and file name stay in the chat. File contents are used for this request only; select the file again after reopening the app."
        case .traditionalChinese: "訊息和檔名會保留；檔案內容僅用於本次傳送，重新開啟 App 後需要重新選取檔案。"
        default: "消息和文件名会保留；文件内容仅用于本次发送，重新打开 App 后需要重新选择文件。"
        }
    }

    private var sendText: String {
        switch language {
        case .english: return "Send"
        case .traditionalChinese: return "傳送"
        default: return "发送"
        }
    }

    private var stopText: String {
        switch language {
        case .english: return "Stop generating"
        case .traditionalChinese: return "停止生成"
        default: return "停止生成"
        }
    }

    private func submit() {
        let text = trimmed
        guard (!text.isEmpty || !attachments.isEmpty), !isSending else { return }
        onSend(text, attachments)
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        attachmentError = nil
        switch result {
        case .failure(let error):
            attachmentError = L10n.format(.attachmentReadFailed, language, error.localizedDescription)
        case .success(let urls):
            importURLs(urls)
        }
    }

    private func importURLs(_ urls: [URL]) {
        for url in urls {
            guard attachments.count < maxAttachmentCount else {
                attachmentError = L10n.format(.attachmentCountLimit, language, String(maxAttachmentCount))
                break
            }
            do {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let values = try url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
                let type = values.contentType
                let mime = type?.preferredMIMEType
                    ?? mimeType(for: url.pathExtension)
                    ?? "application/octet-stream"
                let fileSize = values.fileSize ?? 0
                let isImage = imageTypes.contains(mime)
                let isText = textTypes.contains(mime) || type?.conforms(to: .text) == true || isTextExtension(url.pathExtension)

                if isImage {
                    guard supportsImages else { throw AttachmentError.unsupported(proImageUnavailableText) }
                    try validateAttachmentSize(fileSize, maximum: maxSingleImageBytes, label: L10n.text(.attachmentImage, language), fileName: url.lastPathComponent)
                } else if isText {
                    try validateAttachmentSize(fileSize, maximum: maxTextBytes, label: L10n.text(.attachmentText, language), fileName: url.lastPathComponent)
                } else {
                    throw AttachmentError.unsupported(L10n.format(.attachmentTypeUnsupported, language, url.lastPathComponent))
                }
                try validateTotalAttachmentSize(fileSize, fileName: url.lastPathComponent)

                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                if isImage {
                    try validateAttachmentSize(data.count, maximum: maxSingleImageBytes, label: L10n.text(.attachmentImage, language), fileName: url.lastPathComponent)
                } else {
                    try validateAttachmentSize(data.count, maximum: maxTextBytes, label: L10n.text(.attachmentText, language), fileName: url.lastPathComponent)
                }
                try validateTotalAttachmentSize(data.count, fileName: url.lastPathComponent)

                attachments.append(MessageAttachment(
                    fileName: url.lastPathComponent,
                    mediaType: isText && mime == "application/octet-stream" ? "text/plain" : mime,
                    kind: isImage ? .image : .text,
                    data: data,
                    textContent: isText ? String(decoding: data, as: UTF8.self) : nil
                ))
            } catch let error as AttachmentError {
                attachmentError = error.localizedDescription
            } catch {
                attachmentError = L10n.format(.attachmentReadFailed, language, url.lastPathComponent)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        attachmentError = nil
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    let url: URL?
                    if let item = item as? URL {
                        url = item
                    } else if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else {
                        url = nil
                    }
                    Task { @MainActor in
                        if let error {
                            attachmentError = L10n.format(.attachmentReadFailed, language, error.localizedDescription)
                        } else if let url {
                            importURLs([url])
                        } else {
                            attachmentError = L10n.format(.attachmentReadFailed, language, L10n.text(.unknownError, language))
                        }
                    }
                }
            } else if let imageType = provider.registeredTypeIdentifiers.first(where: {
                guard let type = UTType($0) else { return false }
                return type.conforms(to: .image)
            }) {
                let imageName = provider.suggestedName ?? L10n.text(.droppedImage, language)
                let imageMime = mimeType(for: imageType) ?? "image/png"
                provider.loadDataRepresentation(forTypeIdentifier: imageType) { data, error in
                    let errorMessage = error?.localizedDescription ?? L10n.text(.unknownError, language)
                    Task { @MainActor in
                        if let data {
                            importDroppedImage(data, mime: imageMime, name: imageName)
                        } else {
                            attachmentError = L10n.format(.attachmentReadFailed, language, errorMessage)
                        }
                    }
                }
            }
        }
        return true
    }

    private func importDroppedImage(_ data: Data, mime: String, name: String) {
        guard supportsImages else {
            attachmentError = proImageUnavailableText
            return
        }
        guard attachments.count < maxAttachmentCount else {
            attachmentError = L10n.format(.attachmentCountLimit, language, String(maxAttachmentCount))
            return
        }
        do {
            try validateAttachmentSize(data.count, maximum: maxSingleImageBytes, label: L10n.text(.attachmentImage, language), fileName: name)
            try validateTotalAttachmentSize(data.count, fileName: name)
            attachments.append(MessageAttachment(
                fileName: name,
                mediaType: mime,
                kind: .image,
                data: data,
                textContent: nil
            ))
        } catch let error as AttachmentError {
            attachmentError = error.localizedDescription
        } catch {
            attachmentError = L10n.format(.attachmentReadFailed, language, name)
        }
    }

    private func validateAttachmentSize(_ bytes: Int, maximum: Int, label: String, fileName: String) throws {
        guard bytes <= maximum else {
            let limit = ByteCountFormatter.string(fromByteCount: Int64(maximum), countStyle: .file)
            throw AttachmentError.tooLarge(L10n.format(.attachmentSizeLimit, language, label, limit, fileName))
        }
    }

    private func validateTotalAttachmentSize(_ incomingBytes: Int, fileName: String) throws {
        guard attachmentBytes + incomingBytes <= maxTotalAttachmentBytes else {
            let remaining = max(0, maxTotalAttachmentBytes - attachmentBytes)
            let remainingText = ByteCountFormatter.string(fromByteCount: Int64(remaining), countStyle: .file)
            throw AttachmentError.tooLarge(L10n.format(.attachmentTotalLimit, language, remainingText, fileName))
        }
    }

    private func isTextExtension(_ ext: String) -> Bool {
        ["txt", "md", "markdown", "csv", "json", "xml", "html", "htm", "css", "js", "jsx", "ts", "tsx", "py", "swift", "rs", "go", "java", "c", "h", "cpp", "cxx", "cs", "rb", "php", "sh", "yaml", "yml", "toml", "ini", "log", "sql"].contains(ext.lowercased())
    }

    private func mimeType(for ext: String) -> String? {
        if let type = UTType(ext), let mime = type.preferredMIMEType {
            return mime
        }
        return switch ext.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "webp": "image/webp"
        case "txt", "md", "markdown", "log": "text/plain"
        case "csv": "text/csv"
        case "json": "application/json"
        case "xml": "application/xml"
        case "html", "htm": "text/html"
        default: nil
        }
    }

    private enum AttachmentError: LocalizedError {
        case tooLarge(String)
        case unsupported(String)
        var errorDescription: String? {
            switch self {
            case .tooLarge(let message), .unsupported(let message): message
            }
        }
    }
}

private struct ComposerAttachmentChip: View {
    let attachment: MessageAttachment
    let language: AppLanguage
    let remove: () -> Void

    private var metadata: String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file)
        let kind: String = attachment.kind == .image
            ? (language == .english ? "Image" : "图片")
            : (language == .english ? "Text" : "文本")
        return "\(kind) · \(size)"
    }

    var body: some View {
        HStack(spacing: 8) {
            AttachmentPreview(attachment: attachment, compact: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(metadata)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 160, alignment: .leading)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language == .english ? "Remove attachment" : language == .traditionalChinese ? "刪除附件" : "删除附件")
        }
        .padding(7)
        .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

/// Compact circular action used by the composer. Keeping this as a plain
/// button avoids the platform's adaptive prominent style changing the control
/// geometry or adding an extra visual treatment inside the input capsule.
private struct ComposerActionButton: View {
    let icon: String
    let tint: Color
    let enabled: Bool
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(enabled ? 1 : 0.72))
                .frame(width: ComposerMetrics.actionDiameter, height: ComposerMetrics.actionDiameter)
                .background(
                    Circle()
                        .fill(tint.opacity(enabled ? 1 : 0.38))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }
}

/// A small, explicit clarification request appears after the related analysis
/// instead of silently changing a person's saved identity.
private struct PersonLinkConfirmationBanner: View {
    let source: PersonRecord
    let candidate: PersonRecord
    let evidence: String
    let language: AppLanguage
    var maxBodyHeight: CGFloat = 120
    let confirm: () -> Void
    let reject: () -> Void

    private var question: String {
        switch language {
        case .english: "Is \(source.name) the same person as \(candidate.name)?"
        case .traditionalChinese: "「\(source.name)」和「\(candidate.name)」是同一人嗎？"
        default: "“\(source.name)”和“\(candidate.name)”是同一个人吗？"
        }
    }

    private var confirmText: String {
        switch language {
        case .english: "Same person"
        case .traditionalChinese: "是同一人"
        default: "是同一人"
        }
    }

    private var rejectText: String {
        switch language {
        case .english: "Keep separate"
        case .traditionalChinese: "分開保留"
        default: "保留为不同的人"
        }
    }

    var body: some View {
        ConfirmationCard(maxBodyHeight: maxBodyHeight) {
            VStack(alignment: .leading, spacing: 4) {
                Label(question, systemImage: "person.badge.questionmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(evidence)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } actions: {
            Button(confirmText, action: confirm)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button(rejectText, action: reject)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

// MARK: - Memory Panel (standalone window)

struct MemoryPanelView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSourceID: UUID?

    private var sourceID: UUID? {
        if let selectedSourceID, chatStore.conversations.contains(where: { $0.id == selectedSourceID }) {
            return selectedSourceID
        }
        return chatStore.selectedConversationID ?? chatStore.conversations.first?.id
    }

    private var sourceSelection: Binding<UUID?> {
        Binding(get: { sourceID }, set: { selectedSourceID = $0 })
    }

    private var sourceLabel: String {
        switch settings.language {
        case .english: "Source conversation"
        case .traditionalChinese: "來源對話"
        case .simplifiedChinese: "来源对话"
        }
    }

    private var removeInsightsLabel: String {
        switch settings.language {
        case .english: "Delete insights from this conversation"
        case .traditionalChinese: "刪除這個對話的洞察"
        case .simplifiedChinese: "删除这个对话的洞察"
        }
    }

    private var currentPeople: [PersonRecord] {
        guard let id = sourceID else { return [] }
        return chatStore.personArchive.filter { $0.conversationIDs?.contains(id) == true }
    }

    private var currentPersonLinkProposals: [PersonLinkProposal] {
        guard let id = sourceID else { return [] }
        return chatStore.personLinkProposals
            .filter { $0.conversationID == id && $0.decision == "pending" }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var currentUserProfile: [UserProfileObservation] {
        guard let id = sourceID else { return [] }
        return chatStore.userProfileObservations.filter { $0.sourceConversationID == id }.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var currentEmotions: [EmotionEntry] {
        guard let id = sourceID else { return [] }
        return chatStore.emotionTimeline.filter { $0.conversationID == id }
    }

    private var currentBlindspots: [BlindspotMemory.Group] {
        guard let id = sourceID else { return [] }
        return BlindspotMemory.groups(chatStore.blindspots.filter { $0.conversationID == id })
    }

    private var currentMemories: [MemoryEntry] {
        guard let id = sourceID else { return [] }
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

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(sourceLabel).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.top, 12)
                    List(selection: sourceSelection) {
                        ForEach(chatStore.conversations.sorted { $0.updatedAt > $1.updatedAt }) { conversation in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conversation.title).font(.callout).lineLimit(2)
                                Text(conversation.createdAt, style: .date)
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .tag(conversation.id)
                        }
                    }
                    .listStyle(.sidebar)
                    .accessibilityLabel(sourceLabel)
                }
                .frame(width: 180)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text(L10n.text(.inferredDataHint, settings.language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary))

                        // The narrative timeline follows when events happened in
                        // the user's story, not when messages were sent.
                        MemorySection(title: L10n.text(.memoryTimeline, settings.language), icon: "clock.arrow.trianglehead.counterclockwise.rotate.90", color: .indigo) {
                            Text(L10n.text(.timelineNaturalLanguageHint, settings.language))
                                .font(.caption).foregroundStyle(.secondary)
                            let events = chatStore.narrativeTimeline
                                .filter { $0.conversationID == sourceID }
                            if events.isEmpty {
                                Text(L10n.text(.narrativeNoEvents, settings.language))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                NarrativeTimelineView(events: events)
                            }
                        }

                        if !currentPersonLinkProposals.isEmpty {
                            MemorySection(
                                title: personLinkTitle,
                                icon: "person.badge.questionmark",
                                color: .orange
                            ) {
                                ForEach(currentPersonLinkProposals) { proposal in
                                    if let source = chatStore.personArchive.first(where: { $0.id == proposal.sourcePersonID }),
                                       let candidate = chatStore.personArchive.first(where: { $0.id == proposal.candidatePersonID }) {
                                        VStack(alignment: .leading, spacing: 7) {
                                            Text(personLinkQuestion(source: source, candidate: candidate))
                                                .font(.callout.weight(.semibold))
                                            Text(proposal.evidence)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(3)
                                            Text(personLinkConfidence(proposal.confidence))
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                            HStack(spacing: 8) {
                                                Button(personLinkConfirmText) {
                                                    chatStore.confirmPersonLinkProposal(id: proposal.id)
                                                }
                                                .buttonStyle(.borderedProminent)
                                                Button(personLinkRejectText) {
                                                    chatStore.rejectPersonLinkProposal(id: proposal.id)
                                                }
                                                .buttonStyle(.bordered)
                                            }
                                        }
                                        .padding(10)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(.orange.opacity(0.08)))
                                    }
                                }
                            }
                        }

                        if !currentUserProfile.isEmpty {
                            MemorySection(title: profileTitle, icon: "person.text.rectangle", color: .teal) {
                                ForEach(currentUserProfile.prefix(16)) { observation in
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(profileCategory(observation.category))
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.teal)
                                            Spacer()
                                            Text("\(Int(observation.confidence * 100))%")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                            Button {
                                                chatStore.removeUserProfileObservation(id: observation.id)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundStyle(.secondary)
                                            .help(L10n.text(.removeInferredObservation, settings.language))
                                            .accessibilityLabel(L10n.text(.removeInferredObservation, settings.language))
                                        }
                                        Text(observation.statement)
                                            .font(.callout)
                                        Text(profileEvidenceLabel + "：" + observation.evidence)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(.teal.opacity(0.06)))
                                }
                            }
                        }

                        // 人物：只展示当前对话明确归属的人物档案。
                        if !currentPeople.isEmpty {
                            MemorySection(title: L10n.text(.memoryPeople, settings.language), icon: "person.2.fill", color: .blue) {
                                ForEach(currentPeople.sorted { $0.mentionCount > $1.mentionCount }) { person in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(person.name).font(.headline)
                                                Text("\(person.isSelf ? L10n.text(.memorySelf, settings.language) : person.role) · \(L10n.text(.memoryMentions, settings.language)) \(person.mentionCount) \(L10n.text(.memoryTimes, settings.language))")
                                                    .font(.caption).foregroundStyle(.secondary)
                                                if !person.aliases.isEmpty {
                                                    Text("\(L10n.text(.memoryAliases, settings.language))：\(person.aliases.joined(separator: "、"))")
                                                        .font(.caption2).foregroundStyle(.tertiary)
                                                }
                                            }
                                            Spacer()
                                            if !person.emotionalArc.isEmpty {
                                                Text(person.emotionalArc)
                                                    .font(.caption).foregroundStyle(.blue)
                                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                                    .background(Capsule().fill(.blue.opacity(0.1)))
                                            }
                                        }

                                        ForEach(person.traits) { trait in
                                            VStack(alignment: .leading, spacing: 3) {
                                                HStack(spacing: 6) {
                                                    Text(L10n.personPattern(trait.pattern, settings.language))
                                                        .font(.caption.weight(.medium))
                                                        .foregroundStyle(.orange)
                                                    Text(L10n.text(.memorySuspected, settings.language))
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 1)
                                                        .background(Capsule().fill(.orange.opacity(0.12)))
                                                    Spacer()
                                                      Text(trait.scope == "repeated_pattern" ? L10n.text(.memoryRepeatedPattern, settings.language) : L10n.text(.memorySingleObservation, settings.language))
                                                          .font(.caption2)
                                                          .foregroundStyle(.secondary)
                                                      Button {
                                                          chatStore.removePersonTrait(personID: person.id, traitID: trait.id)
                                                      } label: {
                                                          Image(systemName: "xmark.circle.fill")
                                                      }
                                                      .buttonStyle(.plain)
                                                      .foregroundStyle(.secondary)
                                                      .help(L10n.text(.removeInferredObservation, settings.language))
                                                      .accessibilityLabel(L10n.text(.removeInferredObservation, settings.language))
                                                  }
                                                ForEach(Array(trait.evidence.prefix(2).enumerated()), id: \.offset) { _, evidence in
                                                    Text("\(L10n.text(.memoryEvidence, settings.language))：\(evidence)")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(2)
                                                }
                                                Text("\(L10n.text(.memoryConfidence, settings.language))：\(Int(trait.confidence * 100))% · \(trait.occurrenceCount)\(L10n.text(.memoryTimes, settings.language))")
                                                    .font(.caption2)
                                                    .foregroundStyle(.tertiary)
                                            }
                                            .padding(8)
                                            .background(RoundedRectangle(cornerRadius: 8).fill(.orange.opacity(0.06)))
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
                                ForEach(currentBlindspots) { group in
                                    BlindspotMemoryCard(group: group, language: settings.language) {
                                        chatStore.removeBlindspotGroup(id: group.latest.id)
                                    }
                                }
                            }
                        }

                        // 洞察
                        if !currentMemories.isEmpty {
                            MemorySection(title: L10n.text(.memoryInsights, settings.language), icon: "lightbulb.fill", color: .yellow) {
                                Text(MemoryInsight.paragraph(currentMemories, language: settings.language))
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                                HStack {
                                    Spacer()
                                    Button {
                                        if let sourceID { chatStore.removeMemoryEntries(conversationID: sourceID) }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                    .help(removeInsightsLabel)
                                    .accessibilityLabel(removeInsightsLabel)
                                }
                            }
                        }

                        if currentPersonLinkProposals.isEmpty && currentUserProfile.isEmpty && currentPeople.isEmpty && currentEmotions.isEmpty
                            && currentBlindspots.isEmpty && currentMemories.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "brain.head.profile").font(.system(size: 32)).foregroundStyle(.tertiary)
                                Text(L10n.text(.memoryEmptyTitle, settings.language)).font(.headline).foregroundStyle(.secondary)
                                Text(L10n.text(.memoryEmptyHint, settings.language))
                                    .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 60)
                        }

                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                guard let id = sourceID else { return }
                                Task { await chatStore.rebuildMemory(conversationID: id, settings: settings) }
                            } label: {
                                Label(L10n.text(.rebuildMemory, settings.language), systemImage: "arrow.triangle.2.circlepath")
                            }
                            .disabled(sourceID == nil || chatStore.isSending || chatStore.isSummarizing || chatStore.isRebuildingMemory || chatStore.hasStorageFailure)
                            Text(L10n.text(.memoryRebuildHint, settings.language))
                                .font(.caption).foregroundStyle(.secondary)
                            if chatStore.memoryRebuildConversationID == sourceID,
                               !chatStore.memoryRebuildStatus.isEmpty {
                                HStack(spacing: 6) {
                                    if chatStore.isRebuildingMemory { ProgressView().controlSize(.small) }
                                    Text(chatStore.memoryRebuildStatus).font(.caption)
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                }
                .id(sourceID)
            }
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 420, idealHeight: 600)
        .onAppear { selectedSourceID = sourceID }
    }
}

private struct EmotionGroup { let emotion: String; let intensity: Double; let count: Int }

// MARK: - Memory Timeline Helpers

private extension MemoryPanelView {
    var profileTitle: String {
        switch settings.language {
        case .english: "User profile"
        case .traditionalChinese: "使用者畫像"
        default: "用户画像"
        }
    }

    var profileEvidenceLabel: String {
        switch settings.language {
        case .english: "Evidence"
        case .traditionalChinese: "依據"
        default: "依据"
        }
    }

    func profileCategory(_ category: String) -> String {
        switch (category, settings.language) {
        case ("stated_preference", .english): "Stated preference"
        case ("stated_goal", .english): "Stated goal"
        case ("stable_context", .english): "Stable context"
        case ("communication_preference", .english): "Communication preference"
        case ("stated_preference", .traditionalChinese): "明確偏好"
        case ("stated_goal", .traditionalChinese): "明確目標"
        case ("stable_context", .traditionalChinese): "穩定背景"
        case ("communication_preference", .traditionalChinese): "溝通偏好"
        case ("stated_preference", _): "明确偏好"
        case ("stated_goal", _): "明确目标"
        case ("stable_context", _): "稳定背景"
        default: "沟通偏好"
        }
    }

    var personLinkTitle: String {
        switch settings.language {
        case .english: "Confirm people"
        case .traditionalChinese: "確認人物"
        default: "确认人物"
        }
    }

    var personLinkConfirmText: String {
        switch settings.language {
        case .english: "Same person"
        case .traditionalChinese: "是同一人"
        default: "是同一人"
        }
    }

    var personLinkRejectText: String {
        switch settings.language {
        case .english: "Keep separate"
        case .traditionalChinese: "分開保留"
        default: "保留为不同的人"
        }
    }

    func personLinkQuestion(source: PersonRecord, candidate: PersonRecord) -> String {
        switch settings.language {
        case .english: "Is \(source.name) the same person as \(candidate.name)?"
        case .traditionalChinese: "「\(source.name)」和「\(candidate.name)」是同一人嗎？"
        default: "“\(source.name)”和“\(candidate.name)”是同一个人吗？"
        }
    }

    func personLinkConfidence(_ value: Double) -> String {
        let percent = Int(value * 100)
        switch settings.language {
        case .english: return "Suggested match: \(percent)%"
        case .traditionalChinese: return "建議比對：\(percent)%"
        default: return "建议匹配：\(percent)%"
        }
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
