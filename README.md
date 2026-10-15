# Prism

[简体中文](README_CN.md)

Prism is a macOS chat app I am building to help people make sense of complex relationships and personal stories. It should help you see things more clearly, not read someone's mind or make decisions for you.

I want it to follow one simple rule: **a conclusion should not go further than the evidence.**

## How I want it to respond

- Keep reported events, the user's interpretation, and the model's inference separate. A user's account is not independently verified fact.
- Behavior alone does not prove motive. Contact, silence, or closeness can have different explanations; say when the evidence is not enough.
- Repeating a guess does not make it evidence, and message time is not the same as event time.
- Discuss behavior patterns without turning them into personality or clinical labels. Include counterevidence when it matters.
- Be cautiously optimistic without pretending things are better than they are. Face problems honestly, keep hope grounded in facts and actions within the user's control, and do not promise an outcome.

These are product requirements, not a guarantee that a model is always right. Prism cannot read minds. **When it does not know, it should say so.**

## What I fixed today

- **Long drafts no longer turn the composer into a huge text box.** It grows to about six lines, then scrolls inside with a mouse wheel or trackpad. Return sends; Shift+Return adds a line.
- **Generating a reply no longer makes the whole window churn through updates.** Streaming refreshes are batched and kept separate from rendering the full conversation history.
- **Tool calls no longer replace earlier reasoning.** Reasoning from each tool round is retained; the final “write the reply now” request no longer overwrites it.
- **The title bar now shows the conversation title and a short note.** It says the content is AI-generated, for reference, and should be judged independently.
- **Long API keys no longer stretch the settings field.** The key field stays on one line and scrolls horizontally. First-run setup checks the key after typing stops and only completes after a successful check.
- **Provider errors are explained in plain language.** Common authentication, rate-limit, network, and service errors include a readable cause and next step instead of dumping raw provider text.
- **The model list can refresh automatically or on demand.** Settings reads the provider's model list, puts Flash models first, and supports manual refresh and model IDs. Chat and auxiliary models can be chosen separately.
- **Confirmation cards remain usable when the window is resized or maximized.** Long timeline and person descriptions can scroll while the action buttons stay visible.
- **The model can ask for a missing detail with answer choices.** A compact inline card offers a few options and a free-text field. Submit a choice, custom text, or both; the answer joins the conversation and the model continues.
- **Every response style follows the same cautious optimism.** Evidence determines the judgment. A warmer tone does not change the conclusion, and keywords do not trigger a canned crisis response.

## Current version

This repository currently contains **only the Swift version**: a native SwiftUI macOS app. Other client versions are not provided or maintained here.

Prism organizes conversations into chapters and stores people and aliases, narrative-event and emotion timelines, and references to relevant messages. Conversations and structured records are stored in a local SQLite database. Those references help review the basis for an analysis; they do not guarantee that an interpretation is correct.

## Run

Requirements: macOS 15 or later and a Swift 6 toolchain with the macOS SDK. The bundled app targets Apple Silicon.

From the repository root:

```sh
cd "Prism/swift version"
swift run -c release Prism
```

On first launch, enter an API key, provider endpoint, and model in Settings. The default uses the DeepSeek endpoint and `deepseek-flash`. Prism does not include an API key or an offline model.

First-run setup checks the key after typing stops and reads the model list. This does not send chat content or generate a reply. You can refresh the list later in Settings. A successful list request does not prove that every model is available to your account; actual access depends on the provider.

## Limits

Requests send the conversation needed for the current task, attachments you choose to add, and relevant analysis or retrieved context to the configured provider. Only send information you are authorized to share. Model output may be incomplete or wrong; Prism is not therapy, diagnosis, or emergency care.

The Swift source includes **42 automated regression tests** for safety judgment, model discovery, input and streaming updates, reasoning across tool calls, credential checks, and the clarification flow. Automated tests do not replace end-to-end checks with a live provider.

## Source

- [SwiftUI application](Prism/swift%20version/Sources/Prism/)
- [Analysis and response rules](Prism/swift%20version/Sources/Prism/AgentPrompt.swift)
- [Data models](Prism/swift%20version/Sources/Prism/Models.swift)
- [MIT License](Prism/LICENSE)

[markbignews](https://github.com/markbignews)
