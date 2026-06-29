# Prism / 棱镜

> A narrative reflection companion. See blind spots, find a way forward.
>
> 叙事反思伴侣 · 帮你看清盲点，找到出口

Prism is a **local-first, privacy-respecting** AI conversation tool powered by DeepSeek. It helps you tell your story, identify narrative blindspots, explore alternative perspectives, and — when you're ready — move on.

It's not a therapist. It's a mirror.

---

## Features

### Core

- **Streaming conversation** with DeepSeek v4-pro (thinking mode) + 5 MCP retrieval tools
- **Reasoning chain** visible and auto-scrolling during generation
- **Three conversation modes** — Rational (cool analysis), Balanced (default), Warm (empathetic)
- **Quality guard system** — Flash pre-pipeline auto-detects 5 dialogue quality dimensions + safety signals (enforced by code, not model-driven)
- **Safety intervention** — suicide/self-harm/violence/abuse detection triggers an immediate safety response (with crisis hotlines), skipping the main model
- **Cross-conversation memory** — auto-generated from chapter summaries, retrievable in any conversation
- **Auto-summarization** — incremental + full re-scan, generates structured chapters
- **Pre-pipeline** — unified Flash call per turn (guard + emotion + person + blindspot, ~500ms)
- **Windowed context** — ≤60 messages full context (1M token window), >60 compressed with chapter index

### MCP Retrieval Tools (5 total, local execution, 0 API cost)

| Tool | Purpose | AI? |
|------|---------|------|
| `search_chapters` | Semantic search across chapters (keyword + Flash rerank), returns title/summary/keywords | ✅ local keyword + Flash rerank |
| `fetch_chapter_messages` | Retrieve full chapter messages by index | ❌ |
| `search_memory` | Semantic cross-conversation memory search (keyword + Flash rerank) | ✅ local keyword + Flash rerank |
| `track_person` | Track people across conversations (alias-aware) | ❌ |
| `emotion_timeline` | Raw emotion sequence (model judges trend) | ❌ |

**Note**: Quality guards (reality / spiral / blindspots / ingratiation / action_hollow) run automatically in the Flash pre-pipeline every turn — they are not exposed as MCP tools.

### Data & Privacy

- **100% local storage** — platform-adaptive default path (configurable)
  - macOS: `~/Documents/Prism/`
  - Linux: `~/.local/share/prism/`
  - Windows: `%APPDATA%/Prism/`
- Optional iCloud Drive sync (macOS only)
- Only current conversation context is sent to DeepSeek API
- No telemetry, no cloud sync (unless iCloud enabled), no tracking
- Data path migration with automatic file transfer
- Memory, emotions, blindspots all stored locally

### UI (GUI)

- macOS 15+ native SwiftUI + AppKit
- Liquid Glass design (Apple HIG)
- Markdown rendering
- Sidebar with chapters, search, and memory panel
- Chapter detail sheet with jump-to-source
- Message bubbles with copy / edit / regenerate / delete
- Paired message deletion (either side removes both)
- Cmd+F-like search in sidebar (chapter-based, cross-conversation)

### CLI

- ANSI terminal output with streaming
- All core features: chat, summarize, search, find, delete messages
- Full conversation management
- `/config` for live settings changes (mode, data path, etc.)
- Cross-platform (macOS, Linux, Windows)

---

## Quick Start

### Prerequisites

- macOS 15+ (GUI) / macOS, Linux, or Windows (CLI)
- Swift 6.0+
- [DeepSeek API Key](https://platform.deepseek.com)

### GUI

```bash
cd GUI
swift build -c release
cp .build/arm64-apple-macosx/release/Prism Prism.app/Contents/MacOS/Prism
open Prism.app
```

On first launch, enter your API key and preferences in the setup wizard.

### CLI

```bash
cd CLI
swift build -c release
./.build/arm64-apple-macosx/release/prism
```

Type to chat, `/help` for all commands.

---

## Architecture

```
User Message
  │
  ├── Flash Pre-pipeline (code-enforced, ~500ms)
  │     └─ Unified single call:
  │          reality (fact vs interpretation)
  │          spiral (emotional stagnation)
  │          blindspots (narrative blindspots)
  │          ingratiation (assistant pandering)
  │          action_hollow (past unfulfilled intentions)
  │          safety (suicide/self-harm/violence/abuse)
  │          emotions (emotion labeling → emotion_timeline.json)
  │          persons (person extraction, alias-aware → person_archive.json)
  │
  ├── [Safety override] safety == "crisis" → skip main model, return safety response (with hotlines)
  │
  ├── v4-pro (thinking, streaming) + 5 MCP retrieval tools
  │     ├─ System Prompt (mode-aware)
  │     ├─ guard hint (injected via supervisorHint from pre-pipeline)
  │     ├─ StoryMemory + Cross-conversation Memory (top 3)
  │     └─ Chapter Index (for long conversations)
  │
  └── Archive update (Task.detached, non-blocking)
        ├─ emotions → emotion_timeline.json
        ├─ persons → person_archive.json
        └─ blindspots → blindspots.json

Auto-summarization (v4-flash, dialog-count trigger)
  ├─ Incremental (new messages → 1 chapter, enriched with pre-pipeline archive context)
  └─ Full re-scan (every 3 incrementals → 3-10 chapters)
       └─ Auto-ingest into cross-conversation memory (0 extra API calls)

Data Flow: 100% local JSON → API (context only) → local JSON
```

**API calls per turn**: 1 Flash + 1 Pro (normal). First turn skips pre-pipeline (no assistant reply yet).

---

## CLI Commands

```
/help                    Show help
/new                     New conversation
/list                    List all conversations
/switch <n>              Switch to conversation n
/delete <n>              Delete conversation n
/delmsg <n>              Delete message n (paired delete)
/rename <n> <name>       Rename conversation n
/search <keyword>         Cross-conversation chapter search
/find <keyword>           In-conversation search (/find = next)
/history [n]              Show recent n messages
/info                    Conversation summary
/chapters                List chapters
/chapter <n>             Chapter detail
/thinking                Toggle reasoning display
/settings                Show current settings
/summarize               Manual full re-summarize
/config <k> <v>          Set config (apikey, model, mode, response, icloud, ...)
/reset --confirm          Reset all data
/exit                    Quit
```

---

## Configuration

| Key | Default | Description |
|-----|---------|-------------|
| `apiKey` | — | DeepSeek API Key (required) |
| `baseURL` | `https://api.deepseek.com` | API endpoint |
| `model` | `deepseek-v4-pro` | Conversation model (`pro` / `flash`) |
| `response` | `standard` | Response length (`brief` / `standard` / `detailed`) |
| `thinking` | on | Deep thinking mode |
| `effort` | high | Reasoning effort (`high` / `max`) |
| `summary` | 5 | Auto-summary interval (0=off, 2/5/10) |
| `mode` | balanced | Conversation mode (`rational` / `balanced` / `warm`) |
| `icloud` | off | iCloud Drive storage (macOS only) |
| `datapath` | platform-default | Data storage directory |
| `lang` | zh-Hans | UI language (`zh` / `tw` / `en`) |

---

## Privacy & Compliance

- **Safety Rules**: Built-in crisis intervention for self-harm/violence/abuse scenarios
- **No Diagnostics**: Explicitly does not diagnose, label, or replace medical professionals
- **Data Portability**: All data in readable JSON format at `~/Documents/Prism/`

---

## Project Structure

```
chatbot/
├── CLI/
│   ├── Package.swift
│   ├── Sources/
│   │   ├── main.swift           # CLI entry point + commands
│   │   ├── ChatStore.swift      # Core state management (pre-pipeline / tool loop / summarization)
│   │   ├── DeepSeekClient.swift # API client
│   │   ├── AgentPrompt.swift    # System prompts (3 modes)
│   │   ├── Tools.swift          # 5 MCP retrieval tools
│   │   ├── Models.swift         # Data models
│   │   ├── AppSettings.swift    # Configuration
│   │   ├── StoryMemory.swift    # Local memory matching
│   │   ├── L10n.swift           # Localization
│   │   └── Terminal.swift       # ANSI terminal engine
│   └── prism                    # Release binary
├── GUI/
│   ├── Package.swift
│   ├── Sources/Prism/
│   │   ├── PrismApp.swift         # App entry
│   │   ├── ContentView.swift      # Main UI + all views
│   │   ├── ChatStore.swift        # Core state (shared with CLI)
│   │   ├── DeepSeekClient.swift   # API client (shared)
│   │   ├── AgentPrompt.swift      # Prompts (shared)
│   │   ├── Tools.swift            # MCP tools (shared)
│   │   ├── Models.swift           # Data models (shared)
│   │   ├── AppSettings.swift      # Config (shared)
│   │   ├── StoryMemory.swift      # Memory (shared)
│   │   ├── L10n.swift             # Localization
│   │   └── ...
│   └── Prism.app                  # App bundle
├── INTRODUCTION.md
├── REQUIREMENTS.md
├── README.md
└── README_CN.md
```

---

## Building

```bash
# Both
cd CLI  && swift build -c release
cd GUI  && swift build -c release
```

Zero dependencies. Swift 6.0+ standard library only.

---

## License

To be determined.

---

*Prism — not here to keep you. Here to help you leave.*
