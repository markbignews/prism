<p align="center">
  <img src="assets/icon.png" alt="Prism" width="128" style="border-radius: 24px;"/>
</p>

<h1 align="center">Prism / 棱镜</h1>

<p align="center">
  A workspace for understanding personal narratives, emotions, and recurring patterns, with local data storage and remote model inference.
</p>

<p align="center">
  <strong>Local data storage · Remote LLM inference</strong><br>
  SwiftUI · macOS 15+ · Apple Silicon
</p>

<p align="center">
  <img src="https://img.shields.io/badge/status-active%20development-6f42c1" alt="Active development"/>
  <img src="https://img.shields.io/badge/macOS-SwiftUI-blue" alt="macOS SwiftUI"/>
</p>

<p align="center">
  <a href="README_CN.md">简体中文</a> ·
  <a href="README.md">English</a>
</p>

---

## What is Prism?

Prism is a **narrative analysis tool with local data storage and remote model inference**, powered by a DeepSeek-compatible API. It helps you look back at what you have written, notice emotional movement, organize events by the time they actually happened, and examine patterns that are easy to miss in the moment.

Prism is not an offline model. Conversations, indexes, and analysis records are stored locally, while model-backed features send the required conversation context and relevant local retrieval results to the API endpoint you configure for each request.

Prism is deliberately not designed as an always-on companion. It is an analytical workspace: it can challenge an interpretation, ask for missing facts, and surface a possible blind spot instead of simply agreeing with you.

> Prism is not a therapist, doctor, emergency service, or a substitute for professional care.

## What Prism includes

Prism brings together:

- A native SwiftUI client for Apple Silicon Macs
- Emotion tracking, narrative timelines, chapters, people, memories, and blindspots
- Three response styles: Rational, Balanced, and Warm; they share facts and safety boundaries and change presentation only
- A local safety guard that can interrupt the normal model flow when a crisis signal is detected
- Local SQLite persistence with no built-in telemetry, analytics, or account system

## Highlights

### See the shape of a story, not only the latest message

Prism turns long conversations into chapters and keeps a searchable index of the important parts. It can retrieve earlier context when a later message refers to an old event.

### Keep narrative time separate from message time

An event is placed on the narrative timeline only when its date or period comes from your story. The time at which you sent a message is never silently treated as the time an event happened.

### Find patterns with evidence

The quality guard checks for explanation loops, emotional spirals, intent–action gaps, over-agreement, and missing concrete facts. Warnings are passed to the main model as structured guidance, so the response can stay grounded without replacing the model's judgment.

### Mark tentative behavior patterns for people

When the current conversation contains concrete behavior evidence, Prism can associate a person with patterns such as control or restricted autonomy, communication withdrawal, ignored boundaries, or guilt-based pressure. It stores the evidence snippet, evidence strength, and whether the observation is isolated or repeated. Every result is shown as **suspected · review**; Prism does not output personality, psychiatric, or attachment-style diagnoses.

Person records resolve natural changes in nicknames, relationship terms, short forms, and pronouns from context. Exact existing names or aliases can be joined across conversations; a model link needs strong evidence before it is joined automatically. A plausible but uncertain link shows an explicit clarification in the chat and Memory panel after analysis, with its evidence and **Same person** / **Keep separate** choices. A record is marked as the user only when the conversation explicitly identifies the person as “I” or “myself.”

### Build memory on your device

Chapters, people, emotions, blindspots, and cross-conversation memories are stored in a local SQLite database. You can choose a local data directory.

### Separate workers, narrow evidence

Prism does not ask one analysis prompt to build chapters, resolve people, and infer a user profile at once. A small synchronous supervisor handles safety and reply-quality signals. After the visible reply, a people worker resolves aliases from user messages and the entity index. Only after a chapter is stored does a profile worker extract explicit preferences, goals, stable context, or communication preferences with supporting evidence. Chapter summaries use the transcript and earlier chapters only, so a tentative person or profile observation cannot rewrite the story summary.

### A native macOS workspace

Prism is a native SwiftUI application for Apple Silicon Macs. Its interface, local storage, and packaged application are maintained as one macOS implementation.

### Add visual or text context when you need it

The composer accepts attachments through the **+** button or by dragging files into the input area. JPEG, PNG, GIF, and WebP images are shown as thumbnails; common text and code files are read as text blocks. Each attachment shows its name, type, and size, and can be removed before sending. Up to five attachments are allowed per reply: 10 MB per image, 1 MB per text/code file, and 20 MB in total. Attachments are sent only with that reply and remain visible only for the active app session.

The current packaged release is `v1.0.16`. Updated source builds use **DeepSeek V4.1 Flash** with native vision by default (`deepseek-flash` in the API), so Prism can recognize and understand image input through the configured DeepSeek-compatible endpoint. See DeepSeek's [official change log](https://api-docs.deepseek.com/updates/), [Vision API guide](https://api-docs.deepseek.com/guides/vision), and [Files API documentation](https://api-docs.deepseek.com/guides/files_api) for the provider-side limits. PDF files are not sent directly: the current Files API accepts images only, so PDF extraction or page rendering is not yet part of Prism.

## Screenshots

| Conversation | Cross-conversation memory | People and insights |
| --- | --- | --- |
| <img src="assets/1.png" width="260" alt="Prism conversation view"/> | <img src="assets/2.png" width="260" alt="Prism memory view"/> | <img src="assets/3.png" width="260" alt="Prism people and insights view"/> |

## How a message is processed

1. Prism stores the message locally and updates the current chapter.
2. A lightweight Flash supervisor checks safety, response-quality signals, emotions, and blindspots.
3. If the message is safe to continue, the main model uses one shared fact, relationship, and safety policy; the selected response style changes only wording and organization.
4. After the reply, the people worker updates aliases and evidence without delaying the conversation.
5. At the chapter boundary, the chapter worker summarizes the transcript; the profile worker then records only evidence-backed explicit user context.
6. Local tools can retrieve chapters, memories, people, emotions, or narrative-time events when the response needs them.

The safety path has priority over the normal response path. When a crisis signal is detected, Prism provides a localized safety response and does not ask the main model to continue the conversation as usual.

## Response styles

All three styles share the same fact assessment, relationship guidance, tool conditions, and safety guidance. When information is missing, each asks the same decisive clarification; only wording, empathy placement, and presentation order change.

| Style | Presentation difference |
| --- | --- |
| **Rational** | The same conclusion in a direct, restrained tone |
| **Balanced** *(default)* | The same conclusion in a clear, even tone |
| **Warm** | A brief acknowledgement of the experience, then the same conclusion in a more empathetic tone |

## Supported platforms

| Client | Runtime | Highlights |
| --- | --- | --- |
| SwiftUI | macOS 15+, Apple Silicon | Native client; packaged app: `release/Prism-SwiftUI-macOS.app` |

## Quick start

### 1. Configure an API endpoint

On first launch, use the onboarding flow or Settings to enter:

- A DeepSeek API key
- A DeepSeek-compatible base URL, if you are not using the default
- The model to use for the main response and auxiliary analysis

Prism does not include an API key. Requests are sent to the endpoint you configure.

### 2. Run the SwiftUI client on macOS

Requirements: macOS 15 or later, Apple Silicon, and Swift 6.

From the Prism directory:

~~~
cd "swift version"
swift run -c release
~~~

The packaged application, when present, is `release/Prism-SwiftUI-macOS.app`. Building with Swift Package Manager does not install the app into `/Applications`.

## Local data and privacy

By default, Prism stores its data under:

~~~
~/Documents/Prism/
├── prism.sqlite3
├── config.json
└── conversations.json.pre-sqlite.bak  # created during legacy import
~~~

- Conversation history and indexes are stored in a single local SQLite database with WAL journaling and stale-writer detection.
- On first launch after this update, each imported legacy JSON file is copied to a neighbouring `.pre-sqlite.bak` file; the original JSON is left untouched.
- There is no built-in telemetry, analytics, or Prism account.
- Attachments are kept in memory for the active request and are not written into the database. When you send an attachment, its contents are transmitted to the configured API endpoint: images as image data and text/code files as text content.
- Prism keeps local copies, but conversation content and user-profile data derived from it—including people, tentative behavior patterns, emotions, memories, blindspots, and narrative timeline records—are sent to DeepSeek through the API key and endpoint you configure whenever model-backed features run.
- Person traits, blind spots, profiles, and insights are labelled as tentative model observations and show supporting evidence. You can remove an item from the Memory panel without deleting its source conversation.
- You can choose another local storage directory. Built-in iCloud storage and sync have been removed; a legacy iCloud folder is copied into a local import folder without changing the original.
- Deleting a conversation also removes its associated local archive entries.

You remain responsible for the API provider, endpoint, retention policy, and credentials you choose. Prism does not control DeepSeek's processing, storage, retention, training, or deletion policies. Do not place secrets in screenshots, exported logs, or source-controlled files.

## Data-use authorization and disclaimer

By entering an API key and using model-backed features, you authorize Prism to transmit your conversation content, attachments you choose to send, and derived user-profile data to DeepSeek through the configured API endpoint. This may include messages, image data, text/code file contents, people, tentative behavior patterns, emotions, memories, blindspots, narrative timeline records, summaries, and search context.

If you replace the default base URL with another compatible provider, the same data is sent to that provider instead.

You are responsible for ensuring that you have the right to upload this information and that your use complies with applicable law, workplace rules, and any consent obligations. Review the [DeepSeek Privacy Policy](https://cdn.deepseek.com/policies/en-US/deepseek-privacy-policy.html) and [DeepSeek Open Platform Terms of Service](https://cdn.deepseek.com/policies/en-US/deepseek-open-platform-terms-of-service.html) before using real or sensitive data.

Prism provides informational analysis. Its classifications, summaries, safety responses, and suggestions may be incomplete or incorrect. They are not medical, mental-health, legal, financial, or emergency advice. You use Prism and any connected API at your own risk; the project author is not responsible for decisions made from model output or for the handling of data by the configured provider. This notice is not legal advice.

## Project layout

~~~
Prism/
├── swift version/                 # Native SwiftUI client
│   ├── Package.swift
│   ├── Sources/Prism/
│   └── Prism.app
├── assets/                        # Icon and screenshots
├── release/Prism-SwiftUI-macOS.app # Packaged macOS application
├── README.md
└── README_CN.md
~~~

Prism is built with Swift Package Manager and Apple frameworks.

## Important information

- Prism requires access to a configured LLM endpoint; it is not an offline model.
- Local storage does not mean local inference: each model-backed request may send the required context and retrieved records to the configured provider again.
- Model output, classification, and retrieved context can be imperfect. Review important conclusions yourself.
- Prism is not a medical or emergency product. If there is an immediate risk of harm, contact local emergency services or a qualified professional.

## Recent changes — 2026-09-12

- Consolidated the project around the native SwiftUI macOS client and its release application.
- Replaced the primary JSON store with local SQLite persistence for the SwiftUI client.
- Legacy JSON is imported once with a neighbouring backup, and the original files are never overwritten or shortened during request-context preparation.
- Removed built-in iCloud storage and sync. A legacy iCloud location is imported into a local folder while its original contents remain untouched.
- Storage moves reject an existing database instead of overwriting it, and concurrent stale saves are surfaced as a conflict.
- Derived memories now retain their source-message IDs and evidence status. Prompt rules require the model to preserve corrections, negation, uncertainty, and time scope; this improves traceability but does not make generated analysis infallible.

## Tonight's changes — 2026-09-17

- All three response styles now share one fact assessment, relationship guidance, tool policy, and safety guard. Rational, Balanced, and Warm change only wording, empathy placement, and organization, with consistent sampling parameters to reduce different judgments for the same facts.
- Chapter summarization, people summarization, and user profiling now run as separate, connected workers: a supervisor handles safety and response-quality signals; the people worker resolves names, aliases, relationship terms, and evidence; the chapter worker reads only the transcript and prior chapters; the profile worker records only explicit, evidence-backed user context.
- Uncertain person aliases are never merged silently. The candidate, evidence, and **Same person** / **Keep separate** decision remain visible; a person is marked as the user only when the conversation explicitly says “I” or “myself.”
- Conversation models are limited to `deepseek-flash` and `deepseek-v4-pro`. Flash is the default with native image input; Pro remains text-only. Retired model IDs migrate to a supported model.
- SQLite is now the single primary store. Legacy JSON imports keep neighbouring backups; writes use transactions and WAL with stale-writer detection, and changing the data directory never overwrites an existing database.
- Attachment binaries are kept only for the current request. The message and file name remain in the local record, while reopening the app requires selecting the original file again. Attachment contents are sent only to the API endpoint configured by the user.

## Roadmap

Prism's local data model and native macOS experience will continue to evolve through:

- More robust import and export workflows
- Better backup and restore controls for local archives
- More reliable macOS packaging and release automation
- More transparent inspection of retrieved evidence and model context

## License

Prism is released under the [MIT License](LICENSE). Copyright holder: `markbignews`.

## Author

Prism is created and maintained by [markbignews](https://github.com/markbignews).


### DeepSeek API catalog — 2026-09-12

- `deepseek-flash`: DeepSeek V4.1 Flash, the default; native image input.
- `deepseek-v4-pro`: DeepSeek V4 Pro, retained as a text-only alternative. Prism shows this limit in the composer and prevents sending an image with Pro.
- Prism keeps these two maintained conversation selections. Saved retired or custom conversation-model IDs migrate to Flash; saved official `deepseek-v4-flash` and `deepseek-v4-flash-vision-exp` IDs also migrate to `deepseek-flash`.
- Chat Completions and the base URL remain unchanged. Thinking uses explicit enabled/disabled and low/high/max effort. Tool-enabled history retains assistant reasoning, including final answers. Older archives that already lost reasoning cannot be reconstructed.
- The launch announcement planned Pro retirement on September 14, but the current API guide and pricing page explicitly retain Pro. No timed Pro remapping is implemented. No undocumented `deepseek-v4.1-flash` or future Pro ID is added.

Sources checked: [API guide](https://api-docs.deepseek.com/), [model catalog](https://api-docs.deepseek.com/quick_start/pricing/), [thinking compatibility](https://api-docs.deepseek.com/guides/thinking_mode/), [September 10 announcement](https://deepseek.com/news/deepseek-v4-1-flash/).
