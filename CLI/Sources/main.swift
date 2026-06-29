import Foundation

// ── Prism CLI ─────────────────────────────────────────────────

@main
@MainActor
struct PrismCLI {
    static func main() async {
        Signal.setup()
        let s = AppSettings()
        let store = ChatStore()
        let state = SessionState()

        if !s.onboardingCompleted && s.apiKey.isEmpty { await wizard(s) }
        guard !s.apiKey.isEmpty else { Term.line("❌ No API key.", style: Term.red); return }

        store.bootstrapIfNeeded(language: s.language)
        banner(s)
        context(store, s)
        if let c = store.selectedConversation, !c.messages.isEmpty { info(store, s) }

        while true {
            guard let input = readInput(prompt: Term.bold + "> " + Term.reset) else { break }
            let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            if t.hasPrefix("/") { if await cmd(t, store, s, state) { break }; continue }
            await chat(t, store, s, state)
        }
        Term.line("\n👋 Goodbye.", style: Term.dim)
    }
}

final class SessionState { var showReasoning = true; var lastFindTerm = ""; var lastFindIndex = 0 }

// ── Banner ────────────────────────────────────────────────────

@MainActor func banner(_ s: AppSettings) {
    print("")
    Term.line("╔══════════════════════════════════════════╗", style: Term.cyan)
    Term.line("║   🧠  Prism CLI · 棱镜                   ║", style: Term.bold+Term.cyan)
    Term.line("║   " + txt(.tagline, s.language) + "   ║", style: Term.cyan)
    Term.line("╚══════════════════════════════════════════╝", style: Term.cyan)
    Term.line(txt(.helpHint, s.language), style: Term.dim)
}

@MainActor func context(_ store: ChatStore, _ s: AppSettings) {
    guard let c = store.selectedConversation else { return }
    let idx = (store.conversations.firstIndex{$0.id==c.id} ?? 0) + 1
    let total = store.conversations.count
    Term.write("\n  📂 ", style: Term.dim)
    Term.write("[\(idx)/\(total)] ", style: Term.cyan)
    Term.write(c.title.truncated(to: 30), style: Term.bold)
    let ch = c.chapters.isEmpty ? "" : " · \(c.chapters.count) chapters"
    Term.line(" · \(c.messages.count) msgs" + ch, style: Term.dim)
    Term.divider("─")
}

// ── Info (replaces dumb history dump) ─────────────────────────

@MainActor func info(_ store: ChatStore, _ s: AppSettings) {
    guard let c = store.selectedConversation, !c.messages.isEmpty else { return }
    let lang = s.language

    // Chapters summary
    if !c.chapters.isEmpty {
        Term.line("  📑 " + txt(.chaptersLabel, lang), style: Term.bold)
        for ch in c.chapters.suffix(4) {
            Term.line("     " + ch.title + " — " + String(ch.summary.prefix(100)), style: Term.dim)
        }
    }

    // People mentioned
    let people = store.personArchive.filter { p in
        c.messages.contains { $0.content.localizedCaseInsensitiveContains(p.name) }
    }
    if !people.isEmpty {
        print("")
        Term.line("  👤 " + txt(.peopleLabel, lang), style: Term.bold)
        for p in people.prefix(5) {
            Term.line("     " + p.name + " (" + p.role + ")", style: Term.dim)
        }
    }

    // Emotion trend
    let recent = store.emotionTimeline.suffix(5)
    if !recent.isEmpty {
        let emotions = recent.map{$0.emotion}.joined(separator: " → ")
        print("")
        Term.line("  📈 " + txt(.emotionLabel, lang) + ": " + emotions, style: Term.dim)
    }

    print("")
    Term.line("  " + txt(.infoHint, lang), style: Term.dim)
    Term.divider("─")
}

// ── Chat ──────────────────────────────────────────────────────

@MainActor func chat(_ text: String, _ store: ChatStore, _ s: AppSettings, _ st: SessionState) async {
    let uname = L10n.text(.userName, s.language)
    let aname = L10n.text(.assistantName, s.language)

    print("")
    Term.line("  " + uname, style: Term.bold)
    Term.line("  " + text, style: Term.dim)
    print("")

    let spin = Term.spinner(txt(.thinking_, s.language) + "...")
    await store.send(text, settings: s)
    spin.cancel()

    guard let c = store.selectedConversation, let last = c.messages.last, last.role == .assistant else {
        if let e = store.errorMessage { Term.line("  ⚠ " + e, style: Term.red) }; return
    }
    if last.content.isEmpty, last.reasoning == nil, let e = store.errorMessage {
        Term.line("  ⚠ " + e, style: Term.red); return
    }

    // Reasoning
    if st.showReasoning, let r = last.reasoning, !r.isEmpty {
        Term.line("  " + txt(.reasoningLabel, s.language) + " ───────────────", style: Term.dim+Term.italic)
        for l in r.components(separatedBy: "\n") { Term.line("  " + l, style: Term.dim) }
        Term.divider("─", width: 50)
    }

    // Content
    Term.line("  " + aname, style: Term.bold+Term.magenta)
    print("")
    for l in last.content.wrapped(to: 72).components(separatedBy: "\n") { print("  " + l) }
    print("")
    Term.divider("─")

    if let latest = c.chapters.last {
        Term.line("  📑 " + txt(.latestChapter, s.language) + ": " + latest.title, style: Term.dim)
    }
}

// ── Commands ──────────────────────────────────────────────────

@MainActor func cmd(_ input: String, _ store: ChatStore, _ s: AppSettings, _ st: SessionState) async -> Bool {
    let p = input.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
    let c = String(p.first ?? "").lowercased()
    let a = p.dropFirst().map(String.init)
    let q = a.joined(separator: " ")  // full query string for search

    switch c {
    case "/exit","/quit","/q": return true
    case "/help","/h","/?": help(s)
    case "/new","/n": store.createConversation(language: s.language); Term.ok(" ✓ "+txt(.newCreated,s.language)); context(store,s)
    case "/list","/ls": list(store,s)
    case "/switch","/s": if let n=a.first.flatMap(Int.init),n>0{sw(n-1,store,s);context(store,s);info(store,s)}else{Term.warn(" "+txt(.switchUsage,s.language))}
    case "/delete","/rm": let n = a.first.flatMap(Int.init) ?? 1; if n>0,n<=store.conversations.count{rm(n-1,store,s);context(store,s)}else{Term.warn(" "+txt(.deleteUsage,s.language))}
    case "/delmsg","/dm": if let n = a.first.flatMap(Int.init), n > 0 { delmsg(n, store, s) } else { Term.warn(" "+txt(.delmsgUsage,s.language)) }
    case "/rename","/rn": let sub=a.joined(separator:" ").split(separator:" ",maxSplits:1,omittingEmptySubsequences:true).map(String.init); if let n=sub.first.flatMap(Int.init),n>0,sub.count>1{rn(n-1,sub[1],store,s);context(store,s)}else{Term.warn(" "+txt(.renameUsage,s.language))}
    case "/search","/find","/grep": search(q,store,s)
    case "/info","/i": info(store,s)
    case "/chapters","/ch": chapters(store,s)
    case "/chapter","/cv": if let n=a.first.flatMap(Int.init),n>0{chapter(n-1,store,s)}else{Term.warn(" "+txt(.chapterUsage,s.language))}
    case "/history","/hi": let n = a.first.flatMap(Int.init) ?? 10; history(n, store, s)
    case "/thinking","/th": st.showReasoning.toggle(); Term.info(" "+txt(.thinkingToggle,s.language)+" "+(st.showReasoning ? txt(.on,s.language):txt(.off,s.language)))
    case "/settings","/cfg": settingsView(s)
    case "/config": if a.count>=2{config(a[0],a[1],s,store)}else{Term.warn(" "+txt(.configUsage,s.language))}
    case "/lang": if let l=a.first{switch l{case"zh","zh-hans":s.language = .simplifiedChinese; case"zh-hant","tw":s.language = .traditionalChinese; case"en":s.language = .english; default:Term.warn(" "+txt(.langUsage,s.language))}; Term.ok(" "+txt(.langChanged,s.language)+" "+langName(s.language))}else{Term.line(" "+txt(.langCurrent,s.language)+" "+langName(s.language))}
    case "/summarize","/sum": Term.info(" "+txt(.summarizing,s.language)); await store.fullReSummarize(settings:s); if !store.lastSummaryStatus.isEmpty { Term.line("  "+store.lastSummaryStatus, style: store.lastSummaryStatus.hasPrefix("已生成")||store.lastSummaryStatus.hasPrefix("新增") ? Term.green : Term.yellow) } else { Term.ok(" ✓ "+txt(.summarizeDone,s.language)) }; context(store,s)
    case "/find","/f": find(a.joined(separator:" "), store, s, st)
    case "/reset": if a.first=="--confirm"{Term.line(" "+txt(.resetWarning,s.language),style:Term.red); if confirm(txt(.resetConfirm,s.language)){s.resetAll();store.resetAll();Term.ok(" "+txt(.resetDone,s.language))}}else{Term.warn(" "+txt(.resetHint,s.language))}
    default: Term.warn(" "+txt(.unknownCmd,s.language)+" — /help")
    }
    return false
}

// ── Search ────────────────────────────────────────────────────

@MainActor func search(_ query: String, _ store: ChatStore, _ s: AppSettings) {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    print("")
    if q.isEmpty { Term.line("  "+txt(.searchUsage,s.language),style:Term.dim); return }
    Term.line("  🔍 " + txt(.searching,s.language) + ": \"" + q + "\"", style: Term.cyan)
    print("")

    let results = store.smartSearch(q)
    guard !results.isEmpty else {
        Term.line("  " + txt(.searchNone,s.language), style: Term.dim)
        return
    }

    for r in results {
        let ci = (store.conversations.firstIndex { $0.id == r.conversationID } ?? -1) + 1
        let marker = r.conversationID == store.selectedConversationID ? Term.green+" ●"+Term.reset : "  "
        let idxStr = ci > 0 ? "[\(ci)]" : "[?]"
        Term.line("  \(idxStr)\(marker) " + r.conversationTitle.truncated(to: 44), style: Term.bold)
        for snippet in r.snippets.prefix(4) {
            let prefix = snippet.source == "chapter" ? "📑" : (snippet.source == "title" ? "📌" : "  ")
            let idx = snippet.messageIndex > 0 ? " #\(snippet.messageIndex)" : ""
            Term.line("      \(prefix)\(idx) \(snippet.context)", style: Term.dim)
        }
        print("")
    }
    Term.line("  \(results.count) 个对话匹配，/switch <n> 切换", style: Term.dim)
}

// ── Find in conversation (browser Ctrl+F style) ────────────────

@MainActor func find(_ query: String, _ store: ChatStore, _ s: AppSettings, _ st: SessionState) {
    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard let conv = store.selectedConversation, !conv.messages.isEmpty else { return }

    // Empty query with previous search → show next match
    if q.isEmpty && !st.lastFindTerm.isEmpty {
        let msgs = conv.messages
        let term = st.lastFindTerm
        var matches: [(msgIndex: Int, pos: Int)] = []
        for (i, msg) in msgs.enumerated() where msg.role != .system {
            let lower = msg.content.lowercased()
            var searchStart = lower.startIndex
            while let r = lower.range(of: term, range: searchStart..<lower.endIndex) {
                let pos = lower.distance(from: lower.startIndex, to: r.lowerBound)
                matches.append((i + 1, pos))
                searchStart = r.upperBound
            }
        }
        guard !matches.isEmpty else { Term.line("  "+txt(.searchNone,s.language),style:Term.dim); return }
        st.lastFindIndex = (st.lastFindIndex + 1) % matches.count
        let m = matches[st.lastFindIndex]
        let msg = msgs[m.msgIndex - 1]
        let ctx = extractFindContext(msg.content, around: m.pos, length: term.count)
        print("")
        Term.line("  [\(m.msgIndex)] \(st.lastFindIndex + 1)/\(matches.count) \(ctx)", style: Term.dim)
        print("")
        return
    }

    guard !q.isEmpty else { return }
    st.lastFindTerm = q
    st.lastFindIndex = 0

    var matches: [(msgIndex: Int, pos: Int, context: String)] = []
    for (i, msg) in conv.messages.enumerated() where msg.role != .system {
        let lower = msg.content.lowercased()
        var searchStart = lower.startIndex
        while let r = lower.range(of: q, range: searchStart..<lower.endIndex) {
            let pos = lower.distance(from: lower.startIndex, to: r.lowerBound)
            let ctx = extractFindContext(msg.content, around: pos, length: q.count)
            matches.append((i + 1, pos, ctx))
            searchStart = r.upperBound
        }
    }

    if matches.isEmpty {
        Term.line("  "+txt(.searchNone,s.language),style:Term.dim)
        return
    }

    print("")
    Term.line("  🔍 \"\(query)\" — \(matches.count) 处匹配", style: Term.cyan)
    print("")
    for m in matches.prefix(12) {
        Term.line("  [#\(m.msgIndex)] \(m.context)", style: Term.dim)
    }
    if matches.count > 12 {
        Term.line("  … 还有 \(matches.count - 12) 处，输入 /find 跳到下一个", style: Term.dim)
    }
    print("")
}

private func extractFindContext(_ text: String, around pos: Int, length: Int) -> String {
    let radius = 40
    let start = max(0, pos - radius)
    let end = min(text.count, pos + length + radius)
    let s = text.index(text.startIndex, offsetBy: start)
    let e = text.index(text.startIndex, offsetBy: end)
    var ctx = String(text[s..<e]).replacingOccurrences(of: "\n", with: " ")
    if start > 0 { ctx = "…" + ctx }
    if end < text.count { ctx = ctx + "…" }
    return ctx
}

// ── Conversation CRUD ─────────────────────────────────────────

@MainActor func list(_ store: ChatStore, _ s: AppSettings) {
    print("")
    let cs = store.conversations
    if cs.isEmpty { Term.line("  "+txt(.noConversations,s.language),style:Term.dim); return }
    for (i,c) in cs.enumerated() {
        let mark = c.id==store.selectedConversationID ? Term.green+" ●"+Term.reset : "  "
        let idx = String(i+1).padding(toLength:2,withPad:" ",startingAt:0)
        let title = c.title.truncated(to: 24).padding(toLength: 26, withPad: " ", startingAt: 0)
        let ago = rel(from:c.updatedAt,s.language)
        let style = c.id==store.selectedConversationID ? Term.bold : Term.reset
        let ch = c.chapters.isEmpty ? "" : " · \(c.chapters.count)章"
        let msgs = "\(c.messages.count)msgs"
        Term.line("  \(idx)\(mark)  \(title)  \(msgs)\(ch)  \(ago)", style: style)
        // Show latest chapter as context
        if let latest = c.chapters.last {
            Term.line("         " + Term.dim + latest.title + " — " + String(latest.summary.prefix(80)) + Term.reset)
        }
    }
    print("")
}

@MainActor func sw(_ i: Int, _ store: ChatStore, _ s: AppSettings) {
    guard i>=0,i<store.conversations.count else { Term.err(" "+txt(.badIndex,s.language)); return }
    let old = store.selectedConversationID
    store.selectedConversationID = store.conversations[i].id
    if let old, old != store.selectedConversationID { Task { await store.summarizeOnDeselect(conversationID:old,settings:s) } }
    Term.ok(" ✓ " + txt(.switched,s.language) + " → " + store.conversations[i].title)
}

@MainActor func rm(_ i: Int, _ store: ChatStore, _ s: AppSettings) {
    guard i>=0,i<store.conversations.count else { Term.err(" "+txt(.badIndex,s.language)); return }
    let t = store.conversations[i].title
    guard confirm(txt(.deleteConfirm,s.language)+" 「\(t)」?") else { return }
    store.deleteConversation(id:store.conversations[i].id)
    Term.ok(" ✓ "+txt(.deleted,s.language))
}

@MainActor func rn(_ i: Int, _ name: String, _ store: ChatStore, _ s: AppSettings) {
    guard i>=0,i<store.conversations.count else { Term.err(" "+txt(.badIndex,s.language)); return }
    store.renameConversation(id:store.conversations[i].id,newTitle:name)
    Term.ok(" ✓ "+txt(.renamed,s.language))
}

@MainActor func delmsg(_ i: Int, _ store: ChatStore, _ s: AppSettings) {
    guard let c = store.selectedConversation, i > 0, i <= c.messages.count else {
        Term.err(" "+txt(.badIndex,s.language)); return
    }
    let msg = c.messages[i - 1]
    let preview = String(msg.content.prefix(60)).replacingOccurrences(of: "\n", with: " ")
    let roleLabel = msg.role == .user ? L10n.text(.userName, s.language) : L10n.text(.assistantName, s.language)

    // If deleting a user message, the paired assistant reply is also removed
    let pairDeleted = msg.role == .user && i < c.messages.count && c.messages[i].role == .assistant

    var prompt = "\(txt(.delmsgConfirm,s.language)) [#\(i)] [\(roleLabel)] \"\(preview)\""
    if pairDeleted {
        let nextPreview = String(c.messages[i].content.prefix(40)).replacingOccurrences(of: "\n", with: " ")
        prompt += "\n  \(txt(.delmsgPairWarn,s.language)): \"\(nextPreview)\""
    }
    prompt += "?"

    guard confirm(prompt) else { return }
    store.deleteMessage(in: c.id, messageID: msg.id)
    Term.ok(" ✓ "+txt(.delmsgDeleted,s.language))
    context(store, s)
}

// ── Chapters ──────────────────────────────────────────────────

@MainActor func chapters(_ store: ChatStore, _ s: AppSettings) {
    guard let c = store.selectedConversation else { return }
    print("")
    if c.chapters.isEmpty { Term.line("  "+L10n.text(.noChapters,s.language),style:Term.dim); return }
    for (i,ch) in c.chapters.enumerated() {
        Term.line("  [\(i+1)] "+ch.title,style:Term.bold+Term.cyan)
        Term.line("      "+String(ch.summary.prefix(140)),style:Term.dim)
        if !ch.keywords.isEmpty { Term.line("      "+ch.keywords.prefix(4).joined(separator:" · "),style:Term.dim) }
        print("")
    }
}

@MainActor func chapter(_ i: Int, _ store: ChatStore, _ s: AppSettings) {
    guard let c = store.selectedConversation, i>=0, i<c.chapters.count else { Term.err(" "+txt(.badIndex,s.language)); return }
    let ch = c.chapters[i]
    print("")
    Term.line("══ "+ch.title+" ══",style:Term.bold+Term.cyan)
    print("")
    for l in ch.summary.wrapped(to:72).components(separatedBy:"\n"){print("  "+l)}
    print("")
    Term.line("  "+txt(.keywords,s.language)+": "+ch.keywords.joined(separator:" · "),style:Term.dim)
    print("")
}

@MainActor func history(_ n: Int = 10, _ store: ChatStore, _ s: AppSettings) {
    guard let c = store.selectedConversation, !c.messages.isEmpty else { return }
    let recent = Array(c.messages.suffix(n))
    let startIdx = c.messages.count - recent.count  // 0-based start
    let lang = s.language
    print("")
    for (offset, msg) in recent.enumerated() {
        let idx = startIdx + offset + 1  // 1-based absolute index
        let icon = msg.role == .user ? "👤" : "🧠"
        let name: String = {
            switch (msg.role, lang) {
            case (.user, .traditionalChinese): return "你"
            case (.user, _): return "你"
            case (.assistant, .traditionalChinese): return "稜鏡"
            case (.assistant, .english): return "Prism"
            case (.assistant, _): return "棱镜"
            default: return ""
            }
        }()
        Term.line("[\(idx)] \(icon) \(name)", style: Term.bold)
        for line in msg.content.wrapped(to: 72).components(separatedBy: "\n") {
            print("  \(line)")
        }
        if let reasoning = msg.reasoning, !reasoning.isEmpty, store.selectedConversation != nil {
            Term.line("  ── \(txt(.reasoningLabel, s.language)) ──", style: Term.dim)
            for line in String(reasoning.prefix(200)).wrapped(to: 68).components(separatedBy: "\n") {
                print("  \(Term.dim)\(line)")
            }
        }
        print("")
    }
}

// ── Settings View ─────────────────────────────────────────────

@MainActor func settingsView(_ s: AppSettings) {
    let l = s.language
    print("")
    Term.line("══ " + L10n.text(.settings, l) + " ══", style: Term.bold)
    print("")
    let rows: [(String, String)] = [
        ("API Key", mask(s.apiKey)),
        ("Model", s.model),
        (L10n.text(.language, l), langName(s.language)),
        ("Response Length", s.responseLength.rawValue),
        (L10n.text(.conversationMode, l), s.conversationMode.rawValue),
        (L10n.text(.thinkingMode, l), s.parameters.thinkingEnabled ? "on" : "off"),
        (L10n.text(.reasoningEffort, l), s.parameters.reasoningEffort),
        (L10n.text(.summaryInterval, l), intLabel(s.summaryDialogCount, l)),
        ("iCloud", s.useiCloud ? "on" : "off"),
        ("Data Path", s.dataPath),
    ]
    for (k, v) in rows {
        Term.write("  " + k.padding(toLength: 18, withPad: " ", startingAt: 0) + "  ", style: Term.dim)
        Term.line(v)
    }
    print("")
    Term.line("  /config <key> <value> " + txt(.configHint, l), style: Term.dim)
}

@MainActor func mask(_ text: String) -> String {
    guard text.count > 8 else { return "***" }
    return String(text.prefix(5)) + "..." + String(text.suffix(3))
}

// ── Config ────────────────────────────────────────────────────

@MainActor func config(_ key: String, _ val: String, _ s: AppSettings, _ store: ChatStore) {
    let v=val.trimmingCharacters(in:.whitespacesAndNewlines)
    switch key.lowercased() {
    case"apikey":s.apiKey=v;Term.ok(" ✓ API Key updated")
    case"baseurl":s.baseURL=v;Term.ok(" ✓ → \(v)")
    case"model":
        guard["pro","flash"].contains(v)else{Term.err(" pro or flash");return}
        s.model = v=="flash" ? "deepseek-v4-flash" : "deepseek-v4-pro"
        Term.ok(" ✓ → \(s.model)")
    case"datapath":
        let expanded = (v as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else {
            Term.err(" "+txt(.badIndex,s.language)+" — \(expanded)"); return
        }
        s.dataPath = expanded
        store.reloadStorage(from: s)
        Term.ok(" ✓ → \(expanded)")
        context(store, s)
        info(store, s)
    case"response":
        guard["brief","standard","detailed"].contains(v)else{Term.err(" brief, standard, or detailed");return}
        s.responseLength = ResponseLength(rawValue:v) ?? .standard; Term.ok(" ✓ → \(v)")
    case"icloud":
        s.useiCloud = (v=="true"||v=="1"||v=="on"); Term.ok(" ✓ iCloud "+(s.useiCloud ? "on":"off"))
        store.reloadStorage(from: s)
    case"thinking":s.parameters.thinkingEnabled=(v=="true"||v=="1");Term.ok(" ✓ Thinking "+(s.parameters.thinkingEnabled ? "on":"off"))
    case"effort":guard["high","max"].contains(v)else{Term.err(" high or max");return};s.parameters.reasoningEffort=v;Term.ok(" ✓ → \(v)")
    case"summary":if let i=Int(v),[0,2,5,10].contains(i){s.summaryDialogCount=i;Term.ok(" ✓ → \(intLabel(i,s.language))")}else{Term.err(" 0(off), 2, 5, or 10")}
    case"mode":guard["rational","balanced","warm"].contains(v)else{Term.err(" rational, balanced, or warm");return};s.conversationMode=ConversationMode(rawValue:v) ?? .balanced;Term.ok(" ✓ → \(v)")
    case"lang":
        guard["zh","tw","en"].contains(v)else{Term.err(" zh, tw, or en");return}
        s.language = v=="tw" ? .traditionalChinese : v=="en" ? .english : .simplifiedChinese
        Term.ok(" ✓ → \(langName(s.language))")
    default:Term.err(" Unknown key: \(key)")
    }
}

// ── Setup Wizard ──────────────────────────────────────────────

@MainActor func wizard(_ s: AppSettings) async {
    print("")
    Term.line("╔══════════════════════════════════════════╗",style:Term.cyan+Term.bold)
    Term.line("║     🧠  Welcome to Prism / 欢迎使用棱镜  ║",style:Term.cyan+Term.bold)
    Term.line("║     Narrative Reflection Companion       ║",style:Term.cyan+Term.bold)
    Term.line("╚══════════════════════════════════════════╝",style:Term.cyan+Term.bold)
    print("")
    Term.line("Prism helps you tell your story, see blind spots,")
    Term.line("and find a way forward. Not a therapist — just a mirror.")
    print("")
    Term.line("→ Language / 语言:",style:Term.bold)
    Term.line("  [1] 简体中文  [2] 繁體中文  [3] English")
    if let c=readInput(prompt:"  Choice (1-3) [default 1]: ")?.trimmingCharacters(in:.whitespacesAndNewlines) {
        switch c{case"2":s.language = .traditionalChinese; case"3":s.language = .english; default:s.language = .simplifiedChinese}
    }
    print("")
    Term.line("→ DeepSeek API Key",style:Term.bold)
    Term.line("  Get one at platform.deepseek.com (free credits for new users).")
    print("")
    while true {
        guard let key = readInput(prompt:"  API Key (sk-...): ")?.trimmingCharacters(in:.whitespacesAndNewlines) else{continue}
        if key.isEmpty{Term.err("  Required. Ctrl+C to skip.");continue}
        if !key.hasPrefix("sk-"),!confirm("  Key doesn't start with sk-. Save anyway?"){continue}
        s.apiKey=key;break
    }
    print("")
    Term.bullet("Type to chat — streaming response")
    Term.bullet("/help — all commands"); Term.bullet("/search — find across conversations")
    print("")
    Term.line("→ Data: "+s.dataPath,style:Term.dim)
    Term.line("  100% local. Only current context sent to DeepSeek API.",style:Term.dim)
    print("")
    s.onboardingCompleted=true; Term.divider("━")
}

// ── Help ──────────────────────────────────────────────────────

@MainActor func help(_ s: AppSettings) {
    print("")
    Term.line("┌──────────────────────────────────────────┐",style:Term.cyan)
    Term.line("│  "+txt(.helpTitle,s.language).padding(toLength:40,withPad:" ",startingAt:0)+"│",style:Term.bold)
    Term.line("├──────────────────────────────────────────┤",style:Term.cyan)
    for h in helpItems {
        let l=Term.cyan+h.cmd.padding(toLength:20,withPad:" ",startingAt:0)+Term.reset
        let r=Term.dim+txt(h.key,s.language)+Term.reset
        Term.line("│  "+l+r+" │")
    }
    Term.line("└──────────────────────────────────────────┘",style:Term.cyan)
    Term.line("  "+txt(.helpFooter,s.language),style:Term.dim)
    print("")
}

struct HI { let cmd: String; let key: K }
let helpItems: [HI] = [
    HI(cmd:"/help",      key:.helpDesc),
    HI(cmd:"/new",       key:.newDesc),
    HI(cmd:"/list",      key:.listDesc),
    HI(cmd:"/switch <n>",key:.switchDesc),
    HI(cmd:"/delete <n>",key:.deleteDesc),
    HI(cmd:"/rename <n> <x>",key:.renameDesc),
    HI(cmd:"/search <kw>",key:.searchDesc),
    HI(cmd:"/info",      key:.infoDesc),
    HI(cmd:"/history [n]", key:.historyDesc),
    HI(cmd:"/delmsg <n>",key:.delmsgDesc),
    HI(cmd:"/chapters",  key:.chaptersDesc),
    HI(cmd:"/chapter <n>",key:.chapterDesc),
    HI(cmd:"/thinking",  key:.thinkingDesc),
    HI(cmd:"/settings",  key:.settingsDesc),
    HI(cmd:"/summarize", key:.summarizeDesc),
    HI(cmd:"/config k v",key:.configDesc),
    HI(cmd:"/lang zh|en",key:.langDesc),
    HI(cmd:"/reset",     key:.resetDesc),
    HI(cmd:"/exit",      key:.exitDesc),
]

// ── Helpers ───────────────────────────────────────────────────

@MainActor func intLabel(_ c: Int, _ l: AppLanguage) -> String {
    switch c{case 0:txt(.intervalOff,l); case 2:txt(.dialog2,l); case 5:txt(.dialog5,l); case 10:txt(.dialog10,l); default:"\(c)"}
}
@MainActor func langName(_ l: AppLanguage) -> String {
    switch l{case.simplifiedChinese:"简体中文"; case.traditionalChinese:"繁體中文"; case.english:"English"}
}
@MainActor func rel(from date: Date, _ lang: AppLanguage) -> String {
    let m = Int(Date().timeIntervalSince(date) / 60)
    let h = m / 60; let day = h / 24; let mo = day / 30
    switch lang {
    case .simplifiedChinese:
        if m < 1 { return "刚刚" }; if m < 60 { return "\(m)分钟前" }
        if h < 24 { return "\(h)小时前" }; if day < 30 { return "\(day)天前" }
        if mo < 12 { return "\(mo)个月前" }; return "一年前"
    case .traditionalChinese:
        if m < 1 { return "剛剛" }; if m < 60 { return "\(m)分鐘前" }
        if h < 24 { return "\(h)小時前" }; if day < 30 { return "\(day)天前" }
        if mo < 12 { return "\(mo)個月前" }; return "一年前"
    case .english:
        if m < 1 { return "just now" }; if m < 60 { return "\(m)m ago" }
        if h < 24 { return "\(h)h ago" }; if day < 30 { return "\(day)d ago" }
        if mo < 12 { return "\(mo)mo ago" }; return "1y ago"
    }
}

enum Signal { static func setup() { signal(SIGINT){_ in fputs("\n\n  Interrupted. /exit to quit.\n\n",stdout);fflush(stdout)} } }

extension String {
    @MainActor func truncated(to n: Int) -> String { count<=n ? self : String(prefix(n-1))+"…" }
    @MainActor func wrapped(to w: Int) -> String {
        var r="";var l=0
        for word in components(separatedBy:" "){if l+word.count+1>w,l>0{r+="\n";l=0};if l>0{r+=" ";l+=1};r+=word;l+=word.count}
        return r
    }
}

// ── L10n ──────────────────────────────────────────────────────

enum K: String {
    case tagline,helpHint,helpTitle,helpFooter,newCreated,noConversations,badIndex,switched,deleted,renamed
    case deleteConfirm,deleteUsage,switchUsage,renameUsage,chapterUsage,configUsage,langUsage
    case on,off,thinkingToggle,unknownCmd
    case resetWarning,resetHint,resetConfirm,resetDone
    case langCurrent,langChanged,keywords,createdAt,reasoningLabel,latestChapter,thinking_
    case helpDesc,newDesc,listDesc,switchDesc,deleteDesc,renameDesc
    case searchDesc,infoDesc,historyDesc,chaptersDesc,chapterDesc,thinkingDesc,configDesc,langDesc,resetDesc,exitDesc
    case intervalOff,dialog2,dialog5,dialog10
    case infoHint,chaptersLabel,peopleLabel,emotionLabel,searchUsage,searching,searchNone
    case settingsDesc,summarizeDesc,summarizing,summarizeDone,configHint
    case delmsgUsage, delmsgConfirm, delmsgDeleted, delmsgDesc, delmsgPairWarn
}

@MainActor func txt(_ k: K, _ l: AppLanguage) -> String {
    switch l {
    case .simplifiedChinese: return zh[k] ?? k.rawValue
    case .traditionalChinese: return tw[k] ?? zh[k] ?? k.rawValue
    case .english: return en[k] ?? k.rawValue
    }
}

let zh: [K: String] = [
    .tagline:"叙事反思伴侣 · 帮你看清盲点，找到出口",
    .helpHint:"/help 查看命令，直接打字开始对话",
    .helpTitle:"命令",.helpFooter:"直接输入文字开始对话",
    .newCreated:"新对话已创建",.noConversations:"暂无对话",
    .badIndex:"无效序号",.switched:"已切换到",.deleted:"已删除",.renamed:"已重命名",
    .deleteConfirm:"确认删除",.deleteUsage:"用法: /delete <序号>",
    .switchUsage:"用法: /switch <序号>",.renameUsage:"用法: /rename <序号> <新名称>",
    .chapterUsage:"用法: /chapter <序号>",.configUsage:"用法: /config <key> <value>",
    .langUsage:"用法: /lang [zh|zh-hant|en]",
    .on:"开",.off:"关",
    .thinkingToggle:"思考链:",.unknownCmd:"未知命令",
    .resetWarning:"⚠ 所有对话和数据将被永久删除。",
    .resetHint:"确认: /reset --confirm",.resetConfirm:"确认还原？",
    .resetDone:"已还原。请重启 prism。",
    .langCurrent:"当前语言:",.langChanged:"已切换为:",
    .keywords:"关键词",.createdAt:"创建",.reasoningLabel:"思考链",.latestChapter:"最新章节",.thinking_:"思考中",
    .helpDesc:"显示帮助",.newDesc:"新建对话",.listDesc:"列出所有对话(含摘要)",
    .switchDesc:"切换对话",.deleteDesc:"删除对话",.renameDesc:"重命名对话",
    .searchDesc:"全文搜索对话/章节",.historyDesc:"查看最近对话内容(默认10条)",
    .infoDesc:"查看当前对话摘要",
    .chaptersDesc:"列出章节",.chapterDesc:"查看章节详情",
    .thinkingDesc:"切换思考链",.configDesc:"修改设置",.langDesc:"切换语言",
    .resetDesc:"还原所有数据",.exitDesc:"退出",
    .intervalOff:"关闭",.dialog2:"每2轮",.dialog5:"每5轮",.dialog10:"每10轮",
    .infoHint:"/search 搜索  /chapters 章节  /chapter n 查看详情",
    .chaptersLabel:"章节",.peopleLabel:"人物",.emotionLabel:"情绪趋势",
    .searchUsage:"用法: /search <关键词>",.searching:"搜索",.searchNone:"无匹配结果",.settingsDesc:"查看设置",.summarizeDesc:"手动归纳对话",.summarizing:"归纳中...",.summarizeDone:"归纳完成",.configHint:"修改设置",
    .delmsgUsage:"用法: /delmsg <消息序号>",.delmsgConfirm:"确认删除消息",.delmsgDeleted:"消息已删除",.delmsgDesc:"删除单条消息(从/history查看序号)",.delmsgPairWarn:"⚠ 后面的助手回复也将被删除",
]

let tw: [K: String] = [
    .tagline:"敘事反思伴侶 · 幫你看清盲點，找到出口",
    .helpHint:"/help 檢視命令，直接打字開始對話",
    .helpTitle:"命令",.helpFooter:"直接輸入文字開始對話",
    .newCreated:"新對話已建立",.noConversations:"暫無對話",
    .badIndex:"無效序號",.switched:"已切換到",.deleted:"已刪除",.renamed:"已重新命名",
    .deleteConfirm:"確認刪除",.deleteUsage:"用法: /delete <序號>",
    .switchUsage:"用法: /switch <序號>",.renameUsage:"用法: /rename <序號> <新名稱>",
    .chapterUsage:"用法: /chapter <序號>",.configUsage:"用法: /config <key> <value>",
    .langUsage:"用法: /lang [zh|zh-hant|en]",
    .on:"開",.off:"關",
    .thinkingToggle:"思考鏈:",.unknownCmd:"未知命令",
    .resetWarning:"⚠ 所有對話和資料將被永久刪除。",
    .resetHint:"確認: /reset --confirm",.resetConfirm:"確認還原？",
    .resetDone:"已還原。請重啟 prism。",
    .langCurrent:"目前語言:",.langChanged:"已切換為:",
    .keywords:"關鍵詞",.createdAt:"建立",.reasoningLabel:"思考鏈",.latestChapter:"最新章節",.thinking_:"思考中",
    .helpDesc:"顯示幫助",.newDesc:"新增對話",.listDesc:"列出所有對話(含摘要)",
    .switchDesc:"切換對話",.deleteDesc:"刪除對話",.renameDesc:"重新命名對話",
    .searchDesc:"全文搜尋對話/章節",.infoDesc:"檢視目前對話摘要",
    .chaptersDesc:"列出章節",.chapterDesc:"檢視章節詳情",
    .thinkingDesc:"切換思考鏈",.configDesc:"修改設定",.langDesc:"切換語言",
    .resetDesc:"還原所有資料",.exitDesc:"退出",
    .intervalOff:"關閉",.dialog2:"每2輪",.dialog5:"每5輪",.dialog10:"每10輪",
    .infoHint:"/search 搜尋  /chapters 章節  /chapter n 查看詳情",
    .chaptersLabel:"章節",.peopleLabel:"人物",.emotionLabel:"情緒趨勢",
    .searchUsage:"用法: /search <關鍵詞>",.searching:"搜尋",.searchNone:"無匹配結果",.settingsDesc:"檢視設定",.summarizeDesc:"手動歸納對話",.summarizing:"歸納中...",.summarizeDone:"歸納完成",.configHint:"修改設定",
    .delmsgUsage:"用法: /delmsg <訊息序號>",.delmsgConfirm:"確認刪除訊息",.delmsgDeleted:"訊息已刪除",.delmsgDesc:"刪除單條訊息(從/history檢視序號)",.delmsgPairWarn:"⚠ 後面的助手回覆也將被刪除",
]

let en: [K: String] = [
    .tagline:"Narrative Reflection Companion — see blind spots, find a way forward",
    .helpHint:"/help for commands, or just start typing to chat",
    .helpTitle:"Commands",.helpFooter:"Just type to start a conversation",
    .newCreated:"New conversation created",.noConversations:"No conversations",
    .badIndex:"Invalid index",.switched:"Switched to",.deleted:"Deleted",.renamed:"Renamed",
    .deleteConfirm:"Delete",.deleteUsage:"Usage: /delete <n>",
    .switchUsage:"Usage: /switch <n>",.renameUsage:"Usage: /rename <n> <name>",
    .chapterUsage:"Usage: /chapter <n>",.configUsage:"Usage: /config <key> <value>",
    .langUsage:"Usage: /lang [zh|zh-hant|en]",
    .on:"ON",.off:"OFF",
    .thinkingToggle:"Reasoning:",.unknownCmd:"Unknown command",
    .resetWarning:"⚠ All conversations and data will be permanently deleted.",
    .resetHint:"Confirm: /reset --confirm",.resetConfirm:"Delete all data?",
    .resetDone:"All data reset. Restart prism.",
    .langCurrent:"Language:",.langChanged:"Changed to:",
    .keywords:"Keywords",.createdAt:"Created",.reasoningLabel:"Reasoning",.latestChapter:"Latest chapter",.thinking_:"Thinking",
    .helpDesc:"Show help",.newDesc:"New conversation",.listDesc:"List all (with summary)",
    .switchDesc:"Switch conversation",.deleteDesc:"Delete conversation",.renameDesc:"Rename conversation",
    .searchDesc:"Full-text search",.infoDesc:"Conversation summary",
    .chaptersDesc:"List chapters",.chapterDesc:"View chapter detail",
    .thinkingDesc:"Toggle reasoning",.configDesc:"Change setting",.langDesc:"Switch language",
    .resetDesc:"Reset all data",.exitDesc:"Exit",
    .intervalOff:"Off",.dialog2:"Every 2",.dialog5:"Every 5",.dialog10:"Every 10",
    .infoHint:"/search to find  /chapters to browse  /chapter n for detail",
    .chaptersLabel:"Chapters",.peopleLabel:"People",.emotionLabel:"Emotion trend",
    .searchUsage:"Usage: /search <keyword>",.searching:"Searching",.searchNone:"No results",.settingsDesc:"Show settings",.summarizeDesc:"Manual summarize",.summarizing:"Summarizing...",.summarizeDone:"Summarization complete",.configHint:"Change setting",
    .delmsgUsage:"Usage: /delmsg <msg#>",.delmsgConfirm:"Delete message",.delmsgDeleted:"Message deleted",.delmsgDesc:"Delete single message (see /history for #)",.delmsgPairWarn:"⚠ The following assistant reply will also be deleted",
]
