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

This repository currently contains **only the Swift version**: a native macOS app built with SwiftUI. It requires macOS 15 or later and a Swift 6 toolchain with the macOS SDK. The bundled app targets Apple Silicon.

Prism uses the model service you configure. The default is the DeepSeek endpoint and `deepseek-flash`. Enter an API key, endpoint, and model during setup. Settings can fetch or manually refresh the model list, or you can enter a model ID directly. Prism does not include an API key or an offline model.

Conversations and structured records are stored in a local SQLite database. Requests send the conversation needed for the current task, attachments you choose to add, and relevant analysis or retrieved context to the configured provider. Only share information you are authorized to provide.

## Run

From the repository root:

```sh
cd "Prism/swift version"
swift run -c release Prism
```

## Limits

Prism helps organize and think through information. It does not decide what a relationship means for you, and it is not a mental health diagnostic, treatment, or emergency service. Treat its answers as material for consideration and judge them against your own experience and the available evidence.

The project currently includes **42 automated regression tests** for safety judgment, model setup, conversation handling, and confirmation flows. Passing automated tests does not prove that a model will understand every real-world situation correctly.

## Source

- [SwiftUI application](Prism/swift%20version/Sources/Prism/)
- [Analysis and response rules](Prism/swift%20version/Sources/Prism/AgentPrompt.swift)
- [Data models](Prism/swift%20version/Sources/Prism/Models.swift)
- [MIT License](Prism/LICENSE)

[markbignews](https://github.com/markbignews)
