# Prism

[简体中文](README_CN.md)

Prism is an AI tool for analyzing complex relationships and personal narratives. It organizes what you describe, traces recurring patterns, and compares possible explanations.

**A conclusion should be no stronger than the evidence behind it.**

## How it should reason

- **Keep facts, interpretations, and inferences separate.** What the user reports, how they understand it, and what the model infers are different kinds of information. A reported event is not independently verified evidence.
- **Behavior does not establish motive.** Repeated contact may reflect habit, practical need, dependence, or attraction. The behavior alone does not settle which explanation is right.
- **Repetition does not turn an inference into a fact.** An earlier model judgment should remain provisional when reused. Without new evidence, repeating it adds no certainty.
- **Message time is not event time.** Something described today may have happened years ago. An approximate period should stay approximate.
- **People are not labels.** Patterns can be discussed with supporting examples; they do not justify personality or clinical diagnoses.
- **Prism can disagree with the user.** It should check counterevidence and alternative explanations, including whether a wish has been treated as a fact. Sometimes there is not enough information to decide.
- **Tone and judgment are separate.** Rational, balanced, and warm response styles share the same evidence standards. A warmer answer should not imply a more optimistic conclusion.

These are design constraints, not guarantees of model accuracy. **When the answer is unknown, it should stay unknown.** Prism cannot read another person's mind or decide what a relationship means on the user's behalf.

## Current implementation

Prism is an experimental native **SwiftUI macOS application** under active development. The current source includes:

- Conversations organized into chapters, with summaries and retrieval of earlier context.
- People and aliases, with user confirmation for uncertain identity matches.
- Separate narrative-event and emotion timelines.
- Evidence references and provisional analysis records, plus blind-spot and response-quality checks.
- Separate workers for people, chapter summaries, and user profiles.
- Rational, balanced, and warm response styles governed by shared judgment rules.

Conversations and structured records use SQLite (`prism.sqlite3`). Source-message references and evidence status support traceability, but do not make every interpretation correct or every claim independently verified. The current client is SwiftUI; earlier Tauri and Windows instructions no longer describe this source tree.

## Run

Requirements: macOS 15 or later and a Swift 6 toolchain with the macOS SDK. The bundled app targets Apple Silicon. See the [package manifest](Prism/swift%20version/Package.swift) for build settings.

From the repository root:

```sh
cd "Prism/swift version"
swift run -c release Prism
```

If using the checked-in app, open `Prism/release/Prism-SwiftUI-macOS.app`. It may lag behind the source; running the command above builds the current checkout and does not install it in `/Applications`.

On first launch, configure your API key, endpoint, and models in onboarding or Settings. The current defaults use the DeepSeek endpoint and `deepseek-flash`; Prism does not include an API key or an offline model.

Model requests send the required messages, supplied attachments, and relevant analysis or retrieved context to the configured provider. Only upload information you are authorized to share. Outputs can be incomplete or wrong; Prism is not a therapy, diagnostic, or emergency service.

## Source

- [SwiftUI application](Prism/swift%20version/Sources/Prism/)
- [Analysis and response rules](Prism/swift%20version/Sources/Prism/AgentPrompt.swift)
- [Data models](Prism/swift%20version/Sources/Prism/Models.swift)

[MIT License](Prism/LICENSE) · [markbignews](https://github.com/markbignews)
