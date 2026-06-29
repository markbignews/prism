<p align="center">
  <img src="assets/icon.png" alt="Prism" width="120" style="border-radius: 22px;"/>
</p>

<p align="center">
  <strong>Prism / 棱镜</strong><br>
  叙事反思伴侣 · 帮你看清盲点，找到出口<br>
  <em>A narrative reflection companion. See blind spots, find a way forward.</em>
</p>

<p align="center">
  A <strong>Swift</strong> vibe coding project · macOS desktop app + CLI · Supports macOS / Linux / Windows
</p>

<p align="center">
  <a href="README_CN.md">简体中文</a> · <a href="README_ZH_HANT.md">繁體中文</a> · <a href="README.md">English</a>
</p>

---

Prism is a **local-first, privacy-respecting** AI conversation tool powered by DeepSeek. It analyzes your narrative patterns, tracks emotional changes over time, and surfaces blindspots you might be missing. Designed for reflection.

---

### Screenshots

| 对话 | 跨对话记忆 | 人物记忆 |
|---|---|---|
| <img src="assets/1.png" width="240" style="border-radius: 16px;"/> | <img src="assets/2.png" width="240" style="border-radius: 16px;"/> | <img src="assets/3.png" width="240" style="border-radius: 16px;"/> |

---

## Features

- **Streaming conversation** with DeepSeek v4-pro (thinking mode, configurable to v4-flash) + 5 retrieval tools
- **Reasoning chain** visible and auto-scrolling during generation
- **Three conversation modes** — Rational, Balanced (default), Warm
- **Quality guard system** — Flash pre-pipeline detects 6 dimensions every turn (safety override is code-enforced)
- **Safety intervention** — suicide/self-harm/violence/abuse detection skips the main model and outputs a crisis response
- **Cross-conversation memory** — auto-generated from chapter summaries, retrievable in any conversation
- **Auto-summarization** — incremental + full re-scan hybrid strategy
- **Pre-pipeline** — one Flash call per turn covering guard + emotion + person extraction (~500ms)
- **Windowed context** — ≤60 messages full context, >60 compressed with chapter index
- **Semantic search** — keyword pre-filter + Flash reranking for chapters and memory
- **Emotion tracking** — automatically labeled every turn, viewable as timeline
- **Person tracking** — alias-aware extraction across conversations
- **Blindspot scanning** — explanation loops, self-avoidance, intention-action gaps
- **Conversation title generation** — auto-named from chapter summaries via Flash

---

## How It Works

```
User Message
  │
  ├── [1] Flash Pre-pipeline (code-enforced, ~500ms)
  │     └─ Unified single call:
  │          reality          — fact vs. interpretation ratio
  │          spiral           — emotional stagnation
  │          blindspots       — explanation loops, self-avoidance, intention-action gaps
  │          ingratiation     — assistant pandering check
  │          action_hollow    — past unfulfilled intentions
  │          safety           — suicide/self-harm/violence/abuse (highest priority)
  │          emotions         — emotion labeling → emotion_timeline.json
  │          persons          — person extraction (alias-aware) → person_archive.json
  │
  ├── [Safety override] safety == "crisis" → skip main model entirely
  │     return immediate crisis response
  │
  ├── [2] v4-pro main model (thinking, streaming)
  │     ├─ supervisorHint guard hints injected as system message
  │     ├─ 5 retrieval tools available
  │     └─ windowed message context (≤60 full, >60 compressed)
  │
  └── [3] Archive update (Task.detached, non-blocking)
        ├─ emotions → emotion_timeline.json (capped at 200)
        ├─ persons → person_archive.json (capped at 200)
        └─ blindspots → blindspots.json (capped at 300)
```

---

## Quality Guard System

A single Flash call evaluates 6 dimensions every turn. Guard results flow into the main model as `[supervisorHint]` system messages. The safety dimension can **bypass the main model entirely**.

| Dimension | What it detects | Behavior on warning |
|---|---|---|
| `reality` | Too much interpretation, too few facts | Gently pull back to concrete events |
| `spiral` | Same topic repeated, no emotional shift | Switch from analysis to exit guidance |
| `blindspots` | Explanation loops, self-avoidance, intention gaps | Surface the blindspot naturally |
| `ingratiation` | Last assistant reply was pandering | Become more independent |
| `action_hollow` | Intention expressed before without follow-through | Gently remind of past patterns |
| `safety` | Suicide, self-harm, violence, abuse | **Override main model — crisis response** |

**Skips:** first exchange (no assistant reply yet), very short messages (< 5 characters). Flash errors degrade gracefully (all flags default to `ok`).

---

## Safety Intervention

The only **code-enforced override**. When the pre-pipeline returns `safety.flag == "crisis"`:

1. Main model is **skipped entirely**
2. A pre-defined crisis response is streamed directly
3. Safety state persists via UserDefaults — next turn continues monitoring
4. Auto-clears when `safety.flag == "ok"` is returned

---

## Retrieval Tools

5 tools. All execute locally from in-memory JSON archives (zero API cost). `search_chapters` and `search_memory` optionally use Flash reranking: keyword pre-filter → semantic rerank. Falls back to keywords on Flash failure.

| Tool | Parameters | Returns | AI cost |
|---|---|---|---|
| `track_person` | `name` (required) | Person archive record | None |
| `emotion_timeline` | `count` (default 5) | Raw emotion sequence | None |
| `search_chapters` | `query` (required), `count` (default 5) | Title, summary, keywords | Flash rerank (optional) |
| `fetch_chapter_messages` | `index` (required, 1-based) | Full chapter text (≤12 msgs) | None |
| `search_memory` | `query` (required), `count` (default 10) | Memory entries | Flash rerank (optional) |

---

## Conversation Modes

| Mode | Temperature | Tone |
|---|---|---|
| **Rational** | 0.1 | Cool, analytical, minimal emotional framing |
| **Balanced** (default) | 0.35 | Empathetic but honest, challenges when needed |
| **Warm** | 0.6 | Emotional safety prioritized, gentle pushback |

---

## Context Window & Summarization

| Topic | Detail |
|---|---|
| **≤ 60 messages** | Full context + chapter index |
| **> 60 messages** | Last 40 full, older compressed to chapter summaries |
| **Trigger** | Every N exchanges (default 5, configurable 2/5/10/off) |
| **Incremental** | New messages → 1 chapter, enriched with archive context |
| **Full re-scan** | Every 3 incrementals, entire conversation re-chaptered, title regenerated |
| **On switch** | Pending content summarized when leaving a conversation |

Compression is not deletion — model retrieves compressed content via search tools.

---

## Archives

All data stored as local plain JSON at `~/Documents/Prism/Data/`.

| Archive | Cap | Maintained by |
|---|---|---|
| `person_archive.json` | 200 (by recency) | Pre-pipeline |
| `emotion_timeline.json` | 200 (newest) | Pre-pipeline |
| `blindspots.json` | 300 (newest) | Pre-pipeline |
| `memory.json` | 500 (newest) | Summarization |

---

## Project Structure

```
chatbot/
├── CLI/Sources/        (12 files — main.swift, ChatStore, PrePipeline, DeepSeekClient,
│                        AgentPrompt, Tools, SearchExpander, StoryMemory, Models,
│                        AppSettings, L10n, Terminal)
├── GUI/Sources/Prism/  (15 files — same 10 shared + ContentView, OnboardingView,
│                        PrismApp, SettingsView, MarkdownText)
├── assets/             Screenshots and app icon
├── LICENSE
├── README.md           This file
├── README_CN.md        Simplified Chinese
└── README_ZH_HANT.md   Traditional Chinese
```

---

## Quick Start

### Prerequisites
- Swift 6.0+
- [DeepSeek API Key](https://platform.deepseek.com)
- GUI: macOS 15+, CLI: macOS, Linux, Windows

### GUI
```bash
cd GUI && swift build -c release
cp .build/arm64-apple-macosx/release/Prism Prism.app/Contents/MacOS/Prism
open Prism.app
```

### CLI
```bash
cd CLI && swift build -c release
./.build/arm64-apple-macosx/release/prism
```

Type to chat. `/help` for all commands. `/config` for live settings.

---

## CLI Commands

| Category | Commands |
|---|---|
| Navigation | `/help`, `/new`, `/list`, `/switch <n>`, `/delete <n>`, `/rename <n>` |
| Messages | `/history [n]`, `/delmsg <n>`, `/find <keyword>` |
| Search | `/chapters`, `/chapter <n>`, `/search <keyword>` |
| Info | `/info`, `/settings` |
| Summarization | `/summarize` |
| Config | `/config <key> <value>` |
| Other | `/thinking`, `/lang zh\|tw\|en`, `/reset --confirm`, `/exit` |

Config keys: `apikey`, `model`, `mode`, `response`, `thinking`, `effort`, `summary`, `icloud`, `datapath`, `lang`

---

## Building

```bash
# Zero third-party dependencies. Swift 6.0+ only.
cd CLI  && swift build -c release
cd GUI  && swift build -c release
```

---

## Privacy

- **100% local storage** at `~/Documents/Prism/` (configurable)
- Only current conversation context sent to DeepSeek API
- No telemetry, no analytics SDK
- Optional iCloud Drive sync (macOS, opt-in)
- All archives are plain JSON — readable, portable, deletable

---

## License

[MIT](LICENSE)

---

*Prism — not here to keep you. Here to help you leave.*
