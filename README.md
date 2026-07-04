<p align="center">
  <img src="assets/icon.png" alt="Prism" width="120" style="border-radius: 22px;"/>
</p>

<p align="center">
  <strong>Prism / 棱镜</strong><br>
  情感分析 Agent · Emotion Analysis Agent<br>
  <sub>Swift 6 · SwiftUI + AppKit · Zero external dependencies</sub>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-SwiftUI-blue" alt="macOS"/>
</p>

<p align="center">
  <a href="README_CN.md">简体中文</a> · <a href="README_ZH_HANT.md">繁體中文</a> · <a href="README.md">English</a>
</p>

---

## What is Prism?

Prism is a **local-first, privacy-respecting** emotion analysis Agent powered by DeepSeek. All conversation data and settings are stored locally on your device (iCloud Drive optional). No telemetry, no analytics. AI inference is handled by the DeepSeek API. It analyzes your personal narratives, tracks emotional patterns across conversations, and surfaces cognitive blindspots you might be missing.

**It is an analytical tool, not a companion, not a therapist.** The quality guard system actively prevents emotional pandering and ensures analysis stays grounded in observable facts.

---

## What It Does

- **Emotion Tracking** — automatically labels your emotional states across every conversation, building a searchable timeline of your sentiment journey
- **Narrative Pattern Analysis** — detects recurring themes, explanation loops, and behavioral patterns in how you frame your experiences
- **Blindspot Detection** — surfaces gaps between stated intentions and described actions; flags when you focus extensively on others while omitting your own role
- **Multi-Perspective Analysis** — when your story has enough structure, generates alternative interpretations of the same events from different viewpoints
- **Cross-Conversation Memory** — distills insights from past conversations into a searchable knowledge base that persists across sessions
- **Semantic Search** — keyword pre-filter plus Flash model reranking finds relevant content even when you use different words
- **Safety Intervention** — code-enforced pipeline detects crisis signals and overrides the main model to provide professional resource guidance

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 6 |
| UI | SwiftUI + AppKit interop (`NSViewRepresentable`, `NSTextView`, `NSOpenPanel`, `NSPasteboard`) |
| Concurrency | `async/await`, `Task`, `Task.detached`, `@MainActor` |
| State | `ObservableObject` / `@Published` / `@StateObject` / `@EnvironmentObject` |
| Networking | `URLSession.shared.bytes(for:)` for SSE streaming, `URLSession.shared.data(for:)` for non-streaming |
| Persistence | `JSONEncoder` / `JSONDecoder` → plain `.json` files on disk, `UserDefaults` for safety crisis state |
| Build | Swift Package Manager (`Package.swift`, swift-tools-version 6.0) — no Xcode project needed |
| Minimum | macOS 15.0 (Sequoia), Apple Silicon (arm64) |

**Zero external dependencies.** Every component — Markdown renderer, semantic search, MCP tool registry, JSON persistence, synonym expander — is hand-built using only Apple frameworks (`SwiftUI`, `AppKit`, `Foundation`, `Combine`, `Observation`).

---

## Architecture

```
SwiftUI Layer (ContentView, SidebarView, ChatView, SettingsView, OnboardingView, MemoryPanelView)
       │
       │  @EnvironmentObject / @Published
       ▼
ChatStore (ObservableObject facade)
       │
       ▼
ChatAgent (@MainActor — core business logic)
       │
       ├── DeepSeekClient        HTTP client: SSE streaming + non-streaming summarization
       ├── ToolRegistry          5 MCP tool definitions & local executors
       ├── AgentPrompt           System prompts for all modes + summarization + reranker
       ├── StoryMemory           Local chapter-based memory per conversation
       ├── PrePipeline           Single unified Flash call: guard + emotion + person + blindspot
       └── SearchExpander        ~40 synonym groups for semantic query expansion
```

**Design Pattern — Agent-Facade:** `ChatStore` is a thin `ObservableObject` that bridges SwiftUI to `ChatAgent`. It exposes `@Published` properties and delegates all calls to the agent. During streaming, `append()` writes each token delta directly into the in-memory `Conversation` model and calls `agentStateDidChange()` — SwiftUI re-renders the message bubble on every token without any intermediate buffering layer.

---

## How It Works

Every user message triggers this pipeline:

```
User sends message
  │
  ▼
1. StoryMemory.ingest()
   Split text by paragraphs → create or update local chapters
   Each chapter has: title, summary, keywords, messageID references
   │
  ▼
2. PrePipeline (Flash model, non-streaming, thinking disabled)
   Skips on first exchange (no assistant reply to check for ingratiation)
   Sends last 10 user+assistant messages + known persons + blindspot history
   │
   One Flash API call returns structured JSON covering:
   ├── 6-dimension quality guard:
   │     reality — observable-fact vs interpretation ratio (flag at >2.5:1)
   │     spiral — emotional stagnation, no displacement across turns
   │     blindspots — explanation loops, self-avoidance, intent-action gaps
   │     ingratiation — assistant over-agreement / emotional pandering / mirror-without-insight
   │     action_hollow — stated intentions matching historical blindspot patterns
   │     safety — self-harm, violence, psychosis, minor victimization, explicit help-seeking
   ├── Emotion labeling: 1-3 segments with emotion + intensity (0.0-1.0)
   ├── Person extraction: real names with role, alias-aware deduplication
   └── Blindspot findings: pattern + evidence + counter_question + severity (new|recurring|persistent)
   │
  ▼
3. Safety check
   If safety.flag == "crisis":
     → Build localized safety response (Chinese/English)
     → Stream it to UI character-by-character (8 chars per yield)
     → Persist crisis state to UserDefaults for next turn's PrePipeline context
     → Skip main model entirely
   If safety.flag == "ok" AND previous turn was crisis → auto-clear crisis state
   │
  ▼
4. Main Model (DeepSeek v4-pro, streaming with thinking mode)
   │
   API request structure (DeepSeekClient.stream):
     POST {baseURL}/chat/completions
     Body:
       model: user-configured (default: deepseek-v4-pro)
       messages:
         - system: AgentPrompt.system(language, mode, responseLength)
         - system: "[监督者方向]\n{guard hints}"  (if warnings present)
         - system: memoryContext + cross-conversation memories (if any)
         - last 500 conversation messages (tool_calls stripped from non-last assistant)
         - role:"tool" messages for pending tool results
       temperature: 0.1 (rational) / 0.35 (balanced) / 0.6 (warm)
       top_p: 0.8 (rational) / 0.9 (balanced) / 0.95 (warm)
       max_tokens: 8192
       thinking: {type: "enabled"} + reasoning_effort (user-configurable, default: high)
       stream: true
       tools: ToolRegistry.definitions (5 tools)
       timeout: 300s
   │
   SSE parsing loop (URLSession.shared.bytes):
     for each line in response:
       if "data: [DONE]" → break
       if "data: {...}" → JSONDecode → extract delta:
         reasoning_content → append to reasoning, emit .reasoning(token)
         content → append to content, emit .content(token)
         tool_calls[] → accumulate by index (id, function.name, function.arguments fragments)
   │
   Context window strategy (buildWindowedMessages):
     ≤60 messages total → send everything + chapter index injection
     >60 messages → keep last 40 in full, compress older into chapter summaries
     Chapter index injected as system message so agent knows what's retrievable
   │
   Tool loop (max 3 rounds):
     if model returns tool_calls:
       1. Persist tool_calls to assistant message (required by API for next round)
       2. Show "🔧 正在查询…" placeholder in UI
       3. Execute each tool locally via ToolRegistry:
            track_person       → reads person_archive.json, fuzzy name match
            emotion_timeline   → returns last N entries with ISO8601 dates
            search_chapters    → keyword scoring → top 15 → Flash semantic rerank → top K
            fetch_chapter_messages → returns up to 12 messages for a chapter (1-based index)
            search_memory      → keyword + synonym expansion → Flash semantic rerank → top K
       4. Clear placeholder
       5. Inject results as role:"tool" messages
       6. Rebuild windowed messages, call API again
     if model returns content without tool_calls → done
     After loop: clear tool_calls from assistant message (prevents API errors on next send)
   │
  ▼
5. Post-processing (Flash model, non-streaming, thinking disabled)
   │
   ├── Apply PrePipeline results to archives (detached, non-blocking):
   │     Merge emotions (cap: 200), persons (cap: 200, sorted by lastMentionedAt),
   │     blindspots (cap: 300, sorted by createdAt)
   │
   ├── Summarization (dialog-count-based trigger, configurable interval):
   │     Incremental (Flash, max_tokens: 1024, timeout: 120s):
   │       Sends new messages since lastSummaryMessageIndex + previous 3 chapters
   │       Parses JSON: {title, summary, keywords}
   │       Appends 1 chapter, adds to cross-conversation memory
   │     Full re-scan (Flash, max_tokens: 8192, timeout: 180s):
   │       Sends full transcript with [index][Role] markers + archive context
   │       Parses JSON array: [{title, summary, keywords, startIndex, endIndex}]
   │       Replaces ALL chapters, resets incrementalChapterCount
   │     Hybrid strategy: every 3 incremental chapters → auto full re-scan
   │     Compaction (trimConversation):
   │       Messages covered by chapters → replaced with "[已归纳: 第N章「title」]"
   │       Uncovered messages → truncated to 200 chars
   │       Chapter summaries → truncated to 600 chars
   │       Keeps last 40 messages always in full
   │
   ├── Title update (Flash model):
   │     Runs when first message sent or chapters change
   │     Sends all chapter summaries → Flash generates ≤40 char title
   │
   └── Persist to ~/Documents/Prism/conversations.json (atomic write)
```

---

## Project Structure

```
macOS Version/
├── Package.swift                # SPM manifest (swift-tools-version: 6.0)
├── Sources/
│   └── Prism/
│       ├── PrismApp.swift       # @main entry point, WindowGroup, onboarding sheet, Cmd+N shortcut
│       ├── ContentView.swift    # NavigationSplitView, GlassBackground modifier, SidebarView,
│       │                        #   ChatView, MessageBubble (reasoning expander), ComposerView,
│       │                        #   MacEditor (NSViewRepresentable wrapping IntrinsicTextView),
│       │                        #   MemoryPanelView (person archive, emotion timeline, blindspots, insights)
│       ├── ChatStore.swift      # ObservableObject facade → ChatAgent, publishes on agentStateDidChange
│       ├── ChatAgent.swift      # Core orchestrator: send(), windowed messages, tool loop,
│       │                        #   summarization (incremental + full), smart search, memory search,
│       │                        #   semantic reranker (Flash), archive management, JSON persistence
│       ├── DeepSeekClient.swift # HTTP client: stream() with SSE parsing, summarize()/fullSummarize()
│       │                        #   non-streaming, ChatRequest/APIMessage/ThinkingConfig codable models
│       ├── Models.swift         # Conversation, ChatMessage, StoryChapter, EmotionEntry, PersonRecord,
│       │                        #   BlindspotRecord, MemoryEntry, ToolCall (custom Codable), ToolResult
│       ├── Tools.swift          # ToolRegistry with 5 tools: track_person, emotion_timeline,
│       │                        #   search_chapters, fetch_chapter_messages, search_memory
│       │                        #   ToolDef schema with FunctionDef/Parameters/Property
│       ├── MarkdownText.swift   # Custom Markdown parser → MarkdownBlock enum tree,
│       │                        #   SwiftUI renderer (headings, lists, code blocks, tables via Grid)
│       ├── StoryMemory.swift    # Paragraph-based chapter extraction, relevantContext() retrieval
│       ├── PrePipeline.swift    # Single Flash call: 100+ line system prompt, strict JSON output schema,
│       │                        #   JSON extraction (handles ```json fences), safety crisis state machine
│       ├── AgentPrompt.swift    # Rational/Warm/Balanced system prompts, summarization prompts,
│       │                        #   title update prompt, search reranker prompt
│       ├── L10n.swift           # 190+ localized strings across zh-Hans / zh-Hant / en
│       ├── SettingsView.swift   # API key, base URL, model picker, thinking toggle, reasoning effort,
│       │                        #   language, conversation mode, response length, iCloud, data path
│       ├── OnboardingView.swift # 8-page flow: Welcome → Purpose → Features → UI Tour → API Key →
│       │                        #   Mode Selection → iCloud → Data & Privacy
│       └── SearchExpander.swift # ~40 synonym groups: emotions, family, romance, work, internal patterns
└── Prism.app/                   # Built app bundle (arm64)
```

---

## Screenshots

| Conversation | Cross-Conversation Memory | Person Tracking |
|---|---|---|
| <img src="assets/1.png" width="240" style="border-radius: 16px;"/> | <img src="assets/2.png" width="240" style="border-radius: 16px;"/> | <img src="assets/3.png" width="240" style="border-radius: 16px;"/> |

---

## Key Features

### Pre-Pipeline (Flash Guard Model)

A single Flash API call runs before every main model response. It receives the last 10 user+assistant messages, the known persons list, and historical blindspot records as context. The Flash model returns a single JSON object analyzed across all dimensions simultaneously — no multi-call overhead.

The pipeline **skips the first exchange** of a conversation (no assistant reply exists yet for ingratiation check, no spiral history, no blindspot baseline).

| Dimension | Detection Logic | Flag Threshold |
|---|---|---|
| `reality` | Counts interpretive language ("我觉得"、"应该是"、"意味着"...) vs concrete facts (times, places, names, quoted speech) | interpretation:fact > 2.5:1 |
| `spiral` | Compares emotion diversity and intensity trend across turns | Same emotion + same topic + no displacement |
| `blindspots` | Three sub-checks: explanation loops (rephrasing same event), self-avoidance (describing others, omitting self), intent-action gaps (stated plans, no action described) | Any sub-check positive |
| `ingratiation` | Scans only the last assistant reply: excessive agreement, challenge avoidance, mirror-without-insight, excessive praise | Strict bar — normal empathy is NOT flagged |
| `action_hollow` | Cross-references current user intent with historical blindspot patterns | Intent matches persistent blindspot |
| `safety` | Self-harm, violence/abuse, psychosis, minor victimization, explicit help-seeking — **highest priority** | Any clear signal → crisis, overrides main model |

**Safety crisis state machine:** Crisis is persisted to `UserDefaults` with conversation-level keys. On the next turn, PrePipeline re-injects crisis context. When Flash returns `safety.flag == "ok"` for a conversation previously in crisis, the state auto-clears.

### JSON Output Schema

PrePipeline returns strict JSON (the parser handles ````json` fences and surrounding text):

```json
{
  "guard": {
    "reality":    {"flag":"ok|warning", "ratio":0.0, "interpretive_count":0, "concrete_count":0, "hint":""},
    "spiral":     {"flag":"ok|warning", "emotion_diversity":0, "intensity_trend":"stable|rising|falling", "hint":""},
    "blindspots": {"flag":"ok|warning", "findings":[{...}], "hint":""},
    "ingratiation":{"flag":"ok|warning", "signals":["..."], "hint":""},
    "action_hollow":{"flag":"ok|warning", "matched_count":0, "persistent_count":0, "hint":""},
    "safety":     {"flag":"ok|crisis", "signals":["..."], "suggest":"", "resources":""}
  },
  "emotions": [{"segment":"...", "emotion":"愤怒", "intensity":0.8}],
  "persons": [{"name":"张伟", "role":"ex-partner"}]
}
```

Guard warnings become a `[监督者方向]` system message injected between the main system prompt and conversation history, giving the Pro model structured guidance without overriding its judgment.

### 5 Retrieval Tools (MCP-style)

All tools execute **locally** — reading from on-disk JSON archives, never calling external APIs. Each tool's result is a JSON string returned to the model.

When `settings` is available, `search_chapters` and `search_memory` use the **two-stage semantic pipeline**: keyword pre-filter (top 15) → Flash reranker (scores and ranks by semantic relevance, returns top K).

| Tool | Trigger | Data Source | Returns |
|---|---|---|---|
| `track_person` | User mentions a specific name/identity | `person_archive.json` | Full `PersonRecord` JSON or `{"found":false}` |
| `emotion_timeline` | Model needs emotional context | `emotion_timeline.json` | Last N entries: `{emotion, intensity, date (ISO8601), segment}` |
| `search_chapters` | User references past topic/event | Current conversation chapters | Top matches: `{title, summary (200 chars), keywords}` |
| `fetch_chapter_messages` | `search_chapters` summary is insufficient | Current conversation messages | Up to 12 messages for that chapter: `{role, content}` |
| `search_memory` | Cross-conversation context needed | `memory.json` | Matched memories: `{content, keywords, sourceChapter, recallCount}` |

### Conversation Modes

| Mode | System Prompt Style | Temperature | Top-P |
|---|---|---|---|
| **Rational Mirror** | Analytical, evidence-focused, challenges distortions, demands concrete facts | 0.1 | 0.8 |
| **Balanced Mirror** (default) | Narrative analysis + moderate challenge, balanced empathy and rigor | 0.35 | 0.9 |
| **Warm Mirror** | Empathetic, gentle exploration, emotional validation | 0.6 | 0.95 |

All modes share the same thinking configuration (`thinking: enabled`, `reasoning_effort` user-configurable, default `high`) and `max_tokens: 8192`.

### Context Window Strategy

Prism leverages DeepSeek's 1M token context window strategically:

| Conversation Length | Strategy |
|---|---|
| ≤60 messages (30 exchanges) | **Full context** — all messages sent, plus chapter index injected as system message so agent knows what's retrievable via tools |
| >60 messages | **Windowed** — last 40 messages in full, older messages compressed to chapter summaries. Agent can call `search_chapters` / `fetch_chapter_messages` to retrieve full text |

**Semantic compaction (trimConversation):** On save, messages covered by chapters are replaced with `[已归纳: 第N章「title」]` references — semantically richer than blind truncation. Uncovered messages fall back to 200-char truncation. Chapter summaries are capped at 600 chars. The last 40 messages are always preserved in full.

### Auto-Summarization

Triggered by dialog count (user+assistant pairs). Configurable interval in settings.

| Type | Model | Max Tokens | Timeout | Thinking |
|---|---|---|---|---|
| **Incremental** | Flash | 1024 | 120s | Disabled |
| **Full re-scan** | Flash | 8192 | 180s | Disabled |

**Hybrid strategy:** Every 3 incremental chapters automatically trigger a full re-scan to keep chapter style and granularity consistent.

Full re-scan enriches context with archive data: recent emotion trajectory (last 5), key persons (top 5 by mention count), and active blindspot patterns (last 5). All chapters are regenerated with `startIndex`/`endIndex` fields parsed from the JSON response, mapping back to actual message IDs.

**Cross-conversation memory:** After each summarization, chapters are upserted into `memory.json` (deduplicated by title + conversation ID). Memory store is capped at 500 entries, trimmed to 300 on overflow.

### Smart Search

Multi-keyword, non-overlapping occurrence counting across titles, messages, and chapters:

- **Title match**: full query → +10, keyword hit → +5 each
- **Message match**: keyword occurrence → +2 each, full query → +5
- **Chapter match**: title keyword → +3, summary keyword → +1, full query → +3-5
- **Context snippets**: extracted with 50-char radius around match positions, deduplicated within 20-char proximity
- **Synonym expansion**: ~40 groups (Chinese + English) covering emotions, family, romance, work, internal patterns

### Semantic Reranker

For `search_chapters` and `search_memory` tool calls:

1. **Keyword pre-filter**: local search returns top 15 candidates
2. **Flash reranker**: sends `{query, candidates[index] title — summary}` → Flash returns `[3,1,5,2,4]` (ranked indices)
3. **Fallback**: if Flash fails, returns keyword order directly

### Liquid Glass UI

macOS-native glass effects (`NSGlassWindowBackground` on macOS 26+) with fallback to `.ultraThinMaterial`. The sidebar and chat panel use translucent, depth-layered materials. The message composer wraps `NSTextView` via `NSViewRepresentable` for native text editing (auto-grow, Return-to-send, Shift-Return for newline).

---

## Quick Start

```bash
cd "macOS Version" && swift build -c release
open Prism.app
```

Requires: macOS 15.0+, Swift 6.0+, DeepSeek API Key ([platform.deepseek.com](https://platform.deepseek.com)).

On first launch, the 8-page onboarding wizard walks through: Welcome → Purpose → Features (4-card grid) → UI Tour → API Key Setup → Conversation Mode (3 mode cards) → iCloud Storage → Data & Privacy.

---

## Data & Privacy

```
~/Documents/Prism/               (or custom path, or iCloud Drive)
├── conversations.json           # All conversations and messages
├── config.json                  # App settings & API key
└── Data/
    ├── person_archive.json      # Person records (capped at 200, sorted by lastMentionedAt)
    ├── emotion_timeline.json    # Emotion entries (capped at 200)
    ├── blindspots.json          # Blindspot records (capped at 300)
    └── memory.json              # Cross-conversation memory (capped at 500, trimmed to 300)
```

- **100% local storage** — plain JSON, readable with any text editor
- **Only current conversation context sent to DeepSeek API** — no persistent server-side storage
- **No telemetry, no analytics, no accounts**
- **Optional iCloud Drive** sync for multi-Mac setups (toggle in Settings)
- **Legacy migration** — auto-migrates archives from old bundle-adjacent location to unified data directory

---

## Compliance

> 本产品系情感分析 Agent，不属于《人工智能拟人化互动服务管理暂行办法》(2026.7.15施行) 所规定的"拟人化互动服务"。本产品不提供持续性情感陪伴、不模拟自然人人格、不诱导情感依赖、不替代专业心理健康服务。未满14周岁请在监护人陪同下使用。

---

## License

[MIT](LICENSE)
