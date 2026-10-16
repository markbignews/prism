<img src="Prism/assets/icon.png" width="88" align="right" alt="Prism icon">

# Prism

**A local-first macOS app for thinking through a relationship — not a companion that agrees with you.**

[简体中文](README_CN.md)

`macOS 15+` · `Swift 6 / SwiftUI` · `Zero third-party dependencies` · `Local SQLite` · `v1.0.23` · `MIT`

---

Most relationship questions cannot be settled by asking for one quick answer. What happened, when it happened, how you understand it, and what the model is guessing get mixed together — and it becomes easy to mistake hope or a guess for a fact.

Companion-style AI tends to make this worse: it agrees with you, so it feels good now and leaves you more certain of a story you never checked. Prism takes the opposite side. It keeps track of what you have told it, compares explanations against the evidence, and says so when the evidence is not there. **The judgment stays yours.**

## Screenshots

<!-- Reserved area — three slots, in this order. New shots go in Prism/assets/screenshots/; naming, size
     and content conventions are documented in Prism/assets/screenshots/README.md. This is the
     ready-to-use replacement block; delete the surrounding comment markers once the files exist:

| Main window: conversations become chapters | Memory: timeline, people, emotions, findings | The card that asks before it acts |
|---|---|---|
| ![Main](Prism/assets/screenshots/01-main.png) | ![Memory](Prism/assets/screenshots/02-memory.png) | ![Confirm](Prism/assets/screenshots/03-confirm.png) |
-->

| Main window: conversations become chapters | Memory: timeline, people, emotions, findings | The card that asks before it acts |
|---|---|---|
| ![Main](Prism/assets/1.png) | ![Memory](Prism/assets/3.png) | *Screenshot pending — the native card shown when Prism needs to ask a question or get your approval.* |

*Interface available in Simplified Chinese, Traditional Chinese, and English. The shots above are from the current build and are the ones meant to be replaced.*

## What it does

- **Chapters instead of a scrolling transcript.** Long conversations are summarized into narrative chapters; the original messages stay on disk and the model can pull them back when they matter.
- **People and aliases, kept separate.** When a name is ambiguous, Prism asks you to confirm before merging two people into one. Behaviour notes stay marked as *suspected*, with the evidence attached — never as a personality verdict.
- **Event time is not message time.** "Told you today" does not become "happened today". Events you narrate get their own timeline, ordered by when they actually occurred.
- **Every answer can be traced back.** Analysis links to the original messages, and the tool calls plus reasoning chain are visible by default, so you can check what it relied on.
- **It asks instead of inventing.** When a missing fact would change the conclusion, the model pauses and asks one question with 2–4 options — and you can always type your own answer.
- **Nothing is written behind your back.** Saving a timeline event, merging two people, or importing a snapshot always goes through a native card that *you* approve. A model saying "saved" changes nothing.
- **Three tones, one evidence standard.** Rational / balanced / warm change wording and ordering only. They cannot change the evidence threshold, the risk reading, or whether Prism suggests ending something.

## How it works

```
your message
  ├─ chapter ingest        local: split and file into the current chapter
  ├─ pre-pass              one fast-model JSON call: 5 reply-quality dimensions,
  │                        safety, emotion labelling
  │      └─ immediate danger? ──▶ bounded safety reply (no tools, no web search);
  │                               local fallback only if that request fails
  └─ main model, streaming up to 2 tool rounds + 1 tool-free final round,
                           so a capped turn still produces a visible answer
       └─ afterwards, off the reply path: observations, people resolution,
          profile, chapter summarization
```

- **Two models, split by job.** Background analysis, summarization, entity resolution and profiling use the fast model; your conversation uses the model you pick (default `deepseek-flash`).
- **Safety routing is deliberately narrow.** The safety path opens only when the assessment reports `flag = crisis` **and** current danger **and** non-empty evidence — all three. Uncertain, malformed, or failed analysis is *not* treated as danger, and there is no keyword tripwire. Quoting a novel, negating an old thought, or discussing a concept is not a crisis.
- **Context is managed by budget, not message count.** With a 1M-token window, 55% only shows a capacity notice, 75% starts compressing older messages into chapter summaries, 85% adds stronger protection. **Local messages are never deleted** — compression only changes what is sent.
- **Retrieval is local.** Chapters, people, emotions, timeline and cross-conversation memory live in SQLite and are ranked locally with keyword and synonym matching. Web search is used only for genuine psychology research questions, only on the official DeepSeek endpoint, and queries are required to be de-identified.

## Privacy and data

Everything is stored locally — by default in `~/Documents/Prism/`:

```
~/Documents/Prism/
├── prism.sqlite3      conversations, people, emotions, timeline, memory
├── config.json        settings only — the API key is not here
├── usage_stats.json   local token accounting
└── prism.log          optional log you can export
```

- **Your API key lives in the macOS Keychain**, not in a config file.
- **Per request, Prism sends**: the conversation needed for the current turn (older messages already replaced by chapter summaries), attachments you deliberately added, and the archive entries retrieved for that turn. Nothing else. **No telemetry, no analytics, no crash reporting.**
- **iCloud storage was removed on purpose.** If your data folder is inside iCloud Drive, Prism asks you to pick a local folder and offers a one-time local import.
- Writes are transactional with revision checking, so a stale writer is rejected rather than silently overwriting; deleting a conversation cleans up its dependent records in the same transaction. Settings can export/import a full snapshot, and an import always backs up the existing database first.
- The database itself is not encrypted — it relies on your disk encryption and folder permissions. Keep the folder out of synced storage if that matters to you.

## Quick start

Requires **macOS 15 or later** and **Xcode 26 or newer** (for the macOS SDK); the packaged app targets Apple Silicon.

```sh
git clone https://github.com/markbignews/prism && cd prism

# build and run
python3 Prism/scripts/build_app.py --run

# automated tests (60 tests; temporary storage and mocked HTTP, no real API key needed)
cd "Prism/swift version" && swift test -Xswiftc -warnings-as-errors

# build and verify an app bundle, then sync it into Prism/release/
python3 Prism/scripts/package_app.py --sync-release
```

A prebuilt bundle is committed at [`Prism/release/Prism-SwiftUI-macOS.app`](Prism/release). It is **ad hoc signed and not notarized**, so macOS will ask you to approve it explicitly ([Apple's instructions](https://support.apple.com/102445)). `package_app.py --help` covers Developer ID signing and notarization, `--digest` reprints the source digest embedded in the bundle, and `--backup-dir` controls where replaced bundles are preserved.

**First-run setup:** open the app, enter your API key and endpoint (default `https://api.deepseek.com`), refresh the model list, and pick a conversation model and a background model — `deepseek-flash` for both is a good default. `deepseek-v4-pro` does not accept image input. Prism ships no API key and no offline model: you pay your own provider directly for what you use.

## Status and limits

Honest version of where this is:

- **v1.0.23**, 60 automated tests covering safety routing, model setup, streaming, confirmation flows, storage recovery, transaction rollback, migration and snapshot round trips. GitHub Actions is configured to run them on `macos-26` and `xcode-27` runners alongside the packaging scripts, and `main` is protected by two required status checks — but the workflow has **not produced a remote run yet**, so "tests pass" currently rests on local runs.
- **Passing automated tests does not mean the model is right.** Semantic and UI acceptance is *not* finished: [`SEMANTIC_ACCEPTANCE.md`](Prism/swift%20version/SEMANTIC_ACCEPTANCE.md) lists 12 scenarios, 4 with real model samples recorded (including one genuine failure — negation was over-interpreted as crisis) and the rest still to be verified by a human.
- **Not a medical service.** No diagnosis, no therapy, no emergency response. If you or someone else is in immediate danger, contact local emergency services — do not rely on this app.
- **macOS 15+ and arm64 only.** No Windows or Linux build; the earlier Tauri/Rust client was removed.
- **No multi-device sync.** Cross-machine use means exporting and importing a snapshot, and configuring your own API key on each machine.
- **Each turn costs several model requests** (background pass + reply, plus optional tool rounds and background summarization), so latency and cost scale with how much you enable thinking mode and long context.
- **Single maintainer, no support commitment.** Without telemetry, diagnosing a problem usually means exporting `prism.log`.

## Repository layout

```
Prism/
├── assets/                    screenshots and icon
├── release/                   committed arm64 bundle (ad hoc signed)
├── scripts/                   build, package, and database maintenance helpers
├── VERSION                    single source of the version number
└── swift version/
    ├── Sources/Prism/         the app (37 Swift files, no third-party packages)
    ├── Tests/PrismTests/      60 tests
    ├── TECHNICAL_SPEC.md      architecture and implementation details
    ├── REGRESSION_CHECKLIST.md what the automated tests do and do not cover
    └── SEMANTIC_ACCEPTANCE.md semantic and UI acceptance checklist
```

Start reading with [`AgentPrompt.swift`](Prism/swift%20version/Sources/Prism/AgentPrompt.swift) (the analysis and evidence rules), [`ChatAgent.swift`](Prism/swift%20version/Sources/Prism/ChatAgent.swift) (the pipeline), and [`SQLiteStore.swift`](Prism/swift%20version/Sources/Prism/SQLiteStore.swift) (storage).

## License

[MIT](Prism/LICENSE)

[markbignews](https://github.com/markbignews)
