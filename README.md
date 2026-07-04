<p align="center">
  <img src="assets/icon.png" alt="Prism" width="120" style="border-radius: 22px;"/>
</p>

<p align="center">
  <strong>Prism / 棱镜</strong><br>
  情感分析 Agent · Emotion Analysis Agent<br>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-SwiftUI-blue" alt="macOS"/>
  <img src="https://img.shields.io/badge/Windows-WinUI_3_(WIP)-lightgrey" alt="Windows"/>
</p>

<p align="center">
  <a href="README_CN.md">简体中文</a> · <a href="README_ZH_HANT.md">繁體中文</a> · <a href="README.md">English</a>
</p>

---

## What is Prism?

Prism is a **local-first, privacy-respecting** emotion analysis Agent powered by DeepSeek. It runs entirely on your device — no cloud storage, no telemetry, no accounts. It analyzes your personal narratives, tracks emotional patterns across conversations, and surfaces cognitive blindspots you might be missing.

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

## How It Works

Every message triggers a pipeline: a Flash guard model analyzes quality + safety + emotion + person extraction → the main Pro model generates a response with guard hints injected as context → archive data is persisted to local JSON.

---

## Screenshots

| Conversation | Cross-Conversation Memory | Person Tracking |
|---|---|---|
| <img src="assets/1.png" width="240" style="border-radius: 16px;"/> | <img src="assets/2.png" width="240" style="border-radius: 16px;"/> | <img src="assets/3.png" width="240" style="border-radius: 16px;"/> |

---

## Key Features

- Streaming conversation with DeepSeek v4-pro (thinking mode) + 5 retrieval tools
- Three modes — Rational, Balanced (default), Warm
- Flash pre-pipeline: 6-dimension quality guard + emotion labeling + person extraction every turn
- Auto-summarization: incremental + periodic full re-scan with chapter generation
- 5 retrieval tools: person tracking, emotion timeline, chapter search, chapter fetch, cross-conversation memory
- 29 synonym groups (Chinese + English) for semantic search
- Safety intervention: code-enforced crisis detection overrides the main model
- 100% local JSON storage — your data never leaves your device

---

## Quick Start

```bash
cd "macOS Version" && swift build -c release
open Prism.app
```

Requires: macOS 15+, Swift 6.0+, DeepSeek API Key.

On first launch, enter your API key in the setup wizard.

---

## Compliance

> 本产品系情感分析 Agent，不属于《人工智能拟人化互动服务管理暂行办法》(2026.7.15施行) 所规定的"拟人化互动服务"。本产品不提供持续性情感陪伴、不模拟自然人人格、不诱导情感依赖、不替代专业心理健康服务。未满14周岁请在监护人陪同下使用。

---

## Privacy

100% local storage · Only conversation context sent to API · No telemetry, no analytics · All data is plain JSON you can read, copy, or delete.

---

## License

[MIT](LICENSE)
