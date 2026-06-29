# Prism / 棱镜

> A narrative reflection companion. See blind spots, find a way forward.
>
> 叙事反思伴侣 · 帮你看清盲点，找到出口

**[English](README.md) · [简体中文](README_CN.md) · [繁體中文](README_ZH_HANT.md)**

Prism is a **local-first, privacy-respecting** AI conversation tool powered by DeepSeek. It helps you tell your story, identify narrative blindspots, explore alternative perspectives, and — when you're ready — move on.

**It's not a therapist. It's a mirror.**

Unlike most AI chat apps that optimize for helpfulness, Prism optimizes for **honesty**. It challenges your interpretations, points out patterns you keep repeating, and refuses to just agree with you. The goal is not to keep you talking — it's to help you reach the point where you no longer need it.

---

## Features

### Core

- **Streaming conversation** with DeepSeek v4-pro (thinking mode) + 5 retrieval tools
- **Reasoning chain** visible and auto-scrolling during generation
- **Three conversation modes** — Rational (cool analysis), Balanced (default), Warm (empathetic)
- **Quality guard system** — Flash pre-pipeline auto-detects 6 dialogue quality dimensions every turn (code-enforced, not model-driven)
- **Safety intervention** — suicide / self-harm / violence / abuse detection overrides the main model with crisis hotlines
- **Cross-conversation memory** — auto-generated from chapter summaries, retrievable in any conversation
- **Auto-summarization** — incremental + full re-scan, generates structured chapters
- **Pre-pipeline** — one Flash call per turn covering guard + emotion + person extraction (~500ms)
- **Windowed context** — ≤60 messages full context (1M token window), >60 compressed with chapter index
- **Semantic search** — keyword pre-filter + Flash reranking for chapter and memory search

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
- Memory, emotions, blindspots all stored locally as plain JSON

### GUI

- macOS 15+ native SwiftUI + AppKit, Liquid Glass design
- Markdown rendering, sidebar with chapters and memory panel
- Chapter detail sheet with jump-to-source, paired message deletion
- 6-page onboarding wizard, settings for API key / model / mode / iCloud

### CLI

- ANSI terminal streaming, cross-platform (macOS, Linux, Windows)
- All core features plus `/config` for live settings (no restart needed)
- Full conversation management with numbered commands

---

## How It Works: Message Flow

```
User Message
  │
  ├── [1] Flash Pre-pipeline (code-enforced, ~500ms)
  │     └─ Unified single call:
  │          reality          — fact vs. interpretation ratio
  │          spiral           — emotional stagnation
  │          blindspots       — explanation loops, avoidance, intention-action gaps
  │          ingratiation     — assistant pandering check
  │          action_hollow    — past unfulfilled intentions
  │          safety           — suicide/self-harm/violence/abuse (highest priority)
  │          emotions         — emotion labeling → emotion_timeline.json
  │          persons          — person extraction (alias-aware) → person_archive.json
  │
  ├── [Safety override] safety == "crisis" → skip main model, return crisis response
  │
  ├── [2] v4-pro main model (thinking, streaming) + 5 MCP tools
  │     ├─ guard hints via [supervisorHint] system message
  │     └─ chapter index for conversations > 60 messages
  │
  └── [3] Archive update (Task.detached, non-blocking)
        ├─ emotions → emotion_timeline.json
        ├─ persons → person_archive.json
        └─ blindspots → blindspots.json
```

**Key behaviors:**
- First exchange skips pre-pipeline (no assistant reply yet to analyze)
- Safety crisis overrides everything — main model is skipped entirely
- Flash failure degrades gracefully — all guard flags default to `ok`

---

## Quality Guard System

Instead of relying on the model to self-check, Prism runs a **code-enforced pre-pipeline** every turn. One Flash call evaluates 6 dimensions:

| Dimension | What it detects | Warning behavior |
|---|---|---|
| `reality` | Too much interpretation, too few facts | Gently pull back to concrete events |
| `spiral` | Same topic repeated, no emotional shift | Switch from analysis to exit guidance |
| `blindspots` | Explanation loops, self-avoidance, intention-action gaps | Surface the blindspot naturally |
| `ingratiation` | Last assistant reply was pandering | Become more independent |
| `action_hollow` | Intention expressed before without follow-through | Gently remind of past patterns |
| `safety` | Suicide, self-harm, violence, abuse | **Override main model — crisis response** |

Results are injected via `[supervisorHint]`. The model doesn't know it's being "checked" — it just receives a natural hint.

---

## Safety Intervention

The only **code-enforced override** in the system. When `safety == "crisis"`:

1. Main model (v4-pro) is **skipped entirely**
2. A pre-defined crisis response with hotlines is injected directly
3. Safety state persists — next turn's pre-pipeline continues monitoring
4. Auto-clears when the user is safe again

**Hotlines:** Chinese: 400-161-9995, 010-82951332, 110. English: 988, HOME to 741741, 911.

---

## Context Window Strategy

| Length | Strategy |
|---|---|
| **≤ 60 messages** | Full text sent + chapter index |
| **> 60 messages** | Last 40 messages full. Older content compressed to chapter summaries. |

Compression is not deletion — the model retrieves any compressed message via search tools.

---

## Summarization

- **Trigger**: every N exchanges (default 5, configurable)
- **Incremental** (default): new messages → 1 chapter, enriched with pre-pipeline archive context
- **Full re-scan** (every 3 incrementals): entire conversation re-chaptered, title regenerated
- **On switch**: pending content summarized when leaving a conversation

---

## Design Decisions

**Why pre-pipeline before the main model?**
Guard signals are available before the model generates its reply, so they integrate naturally into the response. The latency cost is ~500ms.

**Why Agent + MCP for retrieval?**
The model needs context to decide what to search for. Retrieval tools are purely local (zero API cost) and the model can decide when to use them.

**Why context window threshold at 60 messages?**
DeepSeek Pro has 1M token context. Under 60 messages, full context fits. Beyond that, compression kicks in — but the model can still retrieve any compressed message via tools.

**Why hybrid summarization?**
Full re-scan every time wastes tokens. Pure incremental leads to inconsistent chapter styles. 3 incrementals + 1 re-scan balances efficiency and quality. Summarization is enriched with pre-pipeline archive data for deeper chapter insights.

**Why keyword + Flash two-stage search?**
Pure keyword misses semantic matches ("被PUA" won't find "精神控制"). Pure embedding needs a separate API. Two-stage: keyword filters to top 15 (microseconds) → Flash reranks semantically (~300ms). Flash failure falls back to keyword results.

**Why person alias resolution?**
Users change how they refer to the same person ("my boyfriend" → "Zhang Wei" → "my ex"). The pre-pipeline receives the existing person archive and merges new mentions into existing records when they refer to the same person.

**Why emotion_timeline no longer returns trend?**
A hardcoded 3-data-point trend (3 negatives = deteriorating) is statistically meaningless. The model now receives raw emotion sequences and judges trends itself — it's much better at this than hardcoded thresholds.

**Why searchChapters no longer returns messages?**
10 results × 8 messages each = 80 messages of unnecessary context for the model to process. Results now include title, summary, and keywords only. The agent calls fetch_chapter_messages when it needs full text.

---

## Quick Start

### Prerequisites

- Swift 6.0+
- [DeepSeek API Key](https://platform.deepseek.com)
- GUI: macOS 15+, CLI: macOS / Linux / Windows

### GUI

```bash
cd GUI
swift build -c release
cp .build/arm64-apple-macosx/release/Prism Prism.app/Contents/MacOS/Prism
open Prism.app
```

### CLI

```bash
cd CLI
swift build -c release
./.build/arm64-apple-macosx/release/prism
```

---

## CLI Commands

```
Navigation:      /help, /new, /list, /switch <n>, /delete <n>, /rename <n> <name>
Messages:        /history [n], /delmsg <n>, /find <keyword>
Search:          /chapters, /chapter <n>, /search <keyword>
Info:            /info, /settings
Summarization:   /summarize
Config:          /config <key> <value>
Other:           /thinking, /lang zh|tw|en, /reset --confirm, /exit
```

Config keys: `apikey`, `model`, `mode`, `response`, `thinking`, `effort`, `summary`, `icloud`, `datapath`, `lang`.

---

## Project Structure

```
chatbot/
├── CLI/Sources/       — main.swift, ChatStore.swift, PrePipeline.swift, DeepSeekClient.swift,
│                        AgentPrompt.swift, Tools.swift, SearchExpander.swift, StoryMemory.swift,
│                        Models.swift, AppSettings.swift, L10n.swift, Terminal.swift
├── CLI/prism          — Release binary
├── GUI/Sources/Prism/ — Same 8 shared files + PrismApp.swift, ContentView.swift,
│                        OnboardingView.swift, SettingsView.swift, MarkdownText.swift
├── GUI/Prism.app/     — App bundle
├── README.md          — This file
└── README_CN.md       — Chinese version
```

---

## Building

```bash
# Zero dependencies. Swift 6.0+ only.
cd CLI  && swift build -c release
cd GUI  && swift build -c release
```

---

## License

To be determined.

---

*Prism — not here to keep you. Here to help you leave.*
