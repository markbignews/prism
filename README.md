# Prism

[简体中文](README_CN.md)

Many relationship questions cannot be settled by asking for one quick answer. What happened, when it happened, how you understand it, and what the model is guessing can get mixed together. That makes it easy to mistake hope or a guess for a fact.

I am building Prism to sort those things out. You can keep related conversations and experiences together, then have the model look back at the messages, timeline, and available evidence to compare explanations. It can point out what may have been missed, and it should include counterevidence. The judgment is still yours.

## What it does

- Organizes conversations into chapters, keeps summaries, and retrieves earlier context when it is relevant.
- Tracks people and aliases. If an identity is unclear, you can confirm it.
- Keeps event dates and emotional changes separate. “Told today” does not mean “happened today.”
- Links analysis to the original messages so you can check what it relies on.
- Asks for a missing detail when it could affect the answer. Choose an option or write your own.
- Supports different response styles without changing the evidence standard.

## How Prism should reason

I do not want the model to say “everything will work out” just to make someone feel better. I also do not want it to focus only on the worst outcome to sound objective. Whether optimism makes sense depends on the facts. Do not promise what the evidence cannot support; explain the real possibilities and the actions still within reach.

That means keeping events, your interpretation, and the model's guesses separate. Behavior does not prove motive, and repeating a guess does not make it evidence. A timeline should reflect when something happened, not only when a message was sent. Explain the basis for an interpretation and consider counterevidence. If there is not enough information, say so.

This is what I expect from Prism, not a promise that the model will always get it right. It can miss context or make a poor judgment. Prism cannot read minds or decide what a relationship means for you.

## Current version

This repository currently contains **only the Swift version**: a native macOS app built with SwiftUI. It requires macOS 15 or later and uses Swift 6. Building requires Xcode 26 or newer with its macOS SDK. The bundled app targets Apple Silicon.

Prism uses the model service you configure. The default is the DeepSeek endpoint and `deepseek-flash`. Enter an API key, endpoint, and model during setup. Settings can fetch or manually refresh the model list, or you can enter a model ID directly. Prism does not include an API key or an offline model.

Conversations and structured records are stored in a local SQLite database. API keys are stored in the system Keychain; settings contain only a credential reference. Settings can export/import a conversation-and-archive snapshot, with an automatic database backup before import. Requests send the conversation needed for the current task, attachments you choose to add, and relevant analysis or retrieved context to the configured provider. Only share information you are authorized to provide.

## Run

From the repository root:

```sh
cd "Prism/swift version"
swift run -c release Prism
```

## Build an app bundle

From the repository root:

```sh
python3 Prism/scripts/package_app.py
```

The version comes from [Prism/VERSION](Prism/VERSION). This builds and verifies an arm64 app at `Prism/swift version/Prism.app`, preserving an existing app in a temporary backup. Run with `--help` for Developer ID signing and notarization options, or `--digest` to recompute the source digest embedded in the bundle. A source digest identifies inputs; it is not a promise of byte-identical binaries across toolchains.

The default build is **ad hoc signed and not notarized**. A downloaded build may require the explicit approval described in [Apple's opening instructions](https://support.apple.com/102445). The committed `Prism/release/` bundle is a historical build; build current source for these repairs.

GitHub Actions is configured to test, build, and package on macOS 26 and Xcode 27 runners. Required status checks must also be enabled in repository branch protection. See the [technical specification](Prism/swift%20version/TECHNICAL_SPEC.md) and [semantic acceptance checklist](Prism/swift%20version/SEMANTIC_ACCEPTANCE.md) for verification boundaries.

## Limits

Prism helps organize and think through information. It does not decide what a relationship means for you, and it is not a mental health diagnostic, treatment, or emergency service. Treat its answers as material for consideration and judge them against your own experience and the available evidence.

Automated regression tests cover safety routing, model setup, streaming, confirmation, storage recovery, transaction rollback, migration, and snapshot round trips. Run `swift test -Xswiftc -warnings-as-errors` in the Swift package directory. Passing automated tests does not prove that a model will understand every real-world situation correctly.

## Source

- [SwiftUI application](Prism/swift%20version/Sources/Prism/)
- [Analysis and response rules](Prism/swift%20version/Sources/Prism/AgentPrompt.swift)
- [Data models](Prism/swift%20version/Sources/Prism/Models.swift)
- [MIT License](Prism/LICENSE)

[markbignews](https://github.com/markbignews)
