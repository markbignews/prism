# Prism / 棱镜

> 一个本地优先的个人叙事分析工作空间，用来整理对话、情绪、人物、记忆、盲点与事件时间轴。

Prism 面向需要回看自己经历的人：它把长对话整理成可检索的章节，把情绪变化和故事事件分成两条时间线，并通过结构化分析帮助用户区分事实、解释、感受和反复出现的模式。项目提供 SwiftUI 原生 macOS 客户端，以及基于 Tauri 2 的 macOS 和 Windows 客户端。

Prism 是分析工作空间，不是持续陪伴型产品，也不是心理治疗、医疗或急救服务。模型输出需要结合原始事实自行判断。

## 内容导航

- [项目定位](#项目定位)
- [当前版本与平台矩阵](#当前版本与平台矩阵)
- [功能总览](#功能总览)
- [时间轴：叙事时间与情绪时间分开](#时间轴叙事时间与情绪时间分开)
- [一次对话的处理流程](#一次对话的处理流程)
- [本地工具与运行时边界](#本地工具与运行时边界)
- [本地数据与隐私](#本地数据与隐私)
- [快速开始](#快速开始)
- [构建与打包](#构建与打包)
- [项目结构](#项目结构)
- [开发约定与路线图](#开发约定与路线图)
- [补充文档](#补充文档)
- [许可证与作者](#许可证与作者)

## 项目定位

### Prism 解决什么问题

普通聊天记录通常只能回答“刚才说了什么”，很难回答以下问题：

- 这件事在故事中究竟发生于什么时候？
- 某种情绪是一次性的，还是在多个章节反复出现？
- 某个人物、关系或冲突是否在不同对话中重复出现？
- 哪些内容是用户明确说过的事实，哪些只是当下的推测？
- 一段建议是否真正落到了可执行行动上？

Prism 围绕这些问题建立本地数据模型。对话是入口，章节是组织方式，记忆和人物是跨对话索引，情绪和叙事时间轴则是用来观察变化的结构化视图。

### 产品原则

1. **本地优先**：对话、索引、人物、记忆和时间轴默认保存在用户设备上。
2. **事实优先**：故事事件的时间来自叙述内容；不把消息发送时间悄悄当成事件发生时间。
3. **证据优先**：检索结果和分析提示用于支持判断，不把模型猜测包装成确定事实。
4. **工具可解释**：模型只能通过项目内定义的函数调用工具请求检索或写入，工具执行由本地运行时完成。
5. **平台一致、实现分层**：SwiftUI 与 Tauri 客户端共享产品行为，但窗口、文件路径和安装方式按平台处理。

## 当前版本与平台矩阵

以下信息来自当前仓库中的构建配置。应用版本、框架版本和操作系统要求是三个不同概念，使用时请分别看对应列。

| 客户端 | 运行环境 | 框架与工具链 | 当前配置版本 | 主要用途 |
| --- | --- | --- | --- | --- |
| SwiftUI | macOS 15+、Apple Silicon | Swift 6 / Swift Package Manager | 以 `Package.swift` 为准 | 原生 macOS 客户端 |
| Tauri macOS | macOS 12+（由 Tauri bundle 配置声明） | Tauri 2 / HTML/CSS/JavaScript / Rust | 应用配置 `1.0.14` | 跨平台前端与 Rust 核心的 macOS 客户端 |
| Tauri Windows | Windows 11+ | Tauri 2 / Rust MSVC / WebView2 / NSIS | 应用配置 `1.0.14` | 独立 Windows 工程与当前用户安装包 |

版本来源：

- SwiftUI 的 Swift 工具版本为 `6.0`，最低平台为 macOS 15，定义在 [`Prism/swift version/Package.swift`](Prism/swift%20version/Package.swift)。
- Tauri 客户端使用 Tauri 2；应用配置版本为 `1.0.14`，定义在各客户端的 `src-tauri/tauri.conf.json`。
- Windows 客户端是 `Prism/Tauri Version/Windows Version` 下的独立工程，使用 Windows 自己的 Tauri 配置，不把 macOS 配置当作 Windows 配置。
- 当前文档整理日期：**2026-08-18**。后续以仓库中的配置文件和提交记录为准。

## 功能总览

### 1. 对话与章节

- 按章节保存长对话，而不是只保留一条扁平消息流。
- 自动生成章节摘要和标题，方便之后回看。
- 删除对话时同步清理关联的本地归档记录。
- 保留原始消息，使摘要、检索和模型回答可以回到具体上下文。

### 2. 人物与关系

- 从对话中记录人物、关系和相关事实。
- 支持跨章节检索人物，观察某个关系在不同叙事中的变化。
- 人物信息是分析辅助数据，不等同于对现实人物的客观定论。

### 3. 记忆与检索

- 跨对话保存用户主动表达过的记忆、偏好和重要背景。
- 章节、消息和记忆可以按关键词及语义相关性检索。
- 检索上下文被注入当前分析前，会保留来源类别，便于区分章节、记忆、人物和时间轴节点。

### 4. 情绪分析

- 记录情绪类别、强度、变化片段和相关章节。
- 将“当前消息的情绪判断”和“跨章节的情绪趋势”分开处理。
- 情绪数据用于辅助回顾，不能替代临床评估或专业诊断。

### 5. 盲点与质量守护

本地质量守护会在主模型处理前后检查常见风险：

- **现实性**：是否把假设、愿望或推测当成事实。
- **情绪漩涡**：是否持续重复同一情绪而没有新增信息。
- **盲点**：是否忽略了叙述中已经出现的反例或限制条件。
- **过度迎合**：回答是否只顺着用户的当前解释，没有进行必要核对。
- **行动落差**：建议是否听起来正确，却没有转化为下一步行动。
- **安全信号**：是否需要优先提供安全相关回应。

安全路径的优先级高于普通回复路径；检测到需要优先处理的信号时，应用会切换到安全回应流程。

### 6. 三种对话模式

| 模式 | 主要风格 | 适合场景 |
| --- | --- | --- |
| 理性之镜 | 更强调证据、事实与假设的区分 | 想拆解认知偏差或检查推断时 |
| 平衡之镜（默认） | 在适度共情和分析追问之间保持平衡 | 日常叙事回顾与复盘 |
| 温情之镜 | 更温和地探索情绪，同时保留事实核对 | 需要低压力地整理感受时 |

## 时间轴：叙事时间与情绪时间分开

时间轴是 Prism 的核心数据模型之一，包含两个互不替代的视图。

### 叙事时间轴 `narrative_timeline.json`

叙事时间轴描述“故事里的事件何时发生”，而不是“用户何时发送了消息”。它可以记录：

- 明确日期，例如 `2025-04-12`；
- 日期范围，例如 `2025 年春季至夏季`；
- 相对时期，例如“大学毕业后”“去年冬天”；
- 只知道顺序但不知道日期的事件，例如“搬家之后、换工作之前”；
- 事件标题、摘要、人物、章节来源和补充说明。

时间判断规则：

1. 只有故事本身提供了日期或时期线索，才创建对应的叙事时间节点。
2. 如果日期不明确，保留不确定性或使用时期描述，不强行生成精确日期。
3. 消息的发送时间只属于对话元数据，不会自动写入事件发生时间。
4. 用户补充或纠正日期后，允许更新、合并或删除节点。

叙事时间轴由本地函数调用工具 `manage_narrative_timeline` 管理，数据保存在 `Data/narrative_timeline.json`。

### 情绪时间线 `emotion_timeline.json`

情绪时间线描述“情绪如何变化”，例如某一章节中的紧张、疲惫、期待或释然，以及这些情绪的强度和持续片段。它回答的是“情绪趋势是什么”，不是“事件发生于哪一天”。

将两个文件分开可以避免把推断出来的情绪时间，误写成用户经历的客观事件时间。

## 一次对话的处理流程

```text
用户输入
   │
   ├─ 1. 本地保存消息，并确定当前章节
   │
   ├─ 2. 轻量分析：情绪、人物、盲点、叙事线索、安全信号
   │
   ├─ 3. 选择对话模式，构造主模型上下文
   │
   ├─ 4. 主模型流式生成；需要上下文时调用本地检索工具
   │
   ├─ 5. 质量守护检查回答，必要时调整回答路径
   │
   └─ 6. 本地更新摘要、标题、人物、记忆、情绪和时间轴
```

更具体地说：

1. 消息首先写入本地存储，并与当前章节关联。
2. Flash 级别的轻量分析提取可用于本轮处理的情绪、人物、盲点和安全信号。
3. 主模型根据理性、平衡或温情模式生成流式回答。
4. 如果回答需要过去的上下文，模型请求本地工具检索章节、消息、记忆、人物或时间轴节点。
5. 主流程完成后，本地运行时更新章节摘要、搜索索引和结构化数据。
6. 若安全守护判定需要优先处理风险，普通对话路径会被安全回应替代。

## 本地工具与运行时边界

Prism 使用模型的 **function-calling 工具定义**，并由应用内的 `ToolRegistry` 执行。这里的“工具”是项目内部的本地函数调用，不是外部工具服务器，也不要求用户单独启动工具服务。

当前主要工具包括：

| 工具 | 作用 | 数据方向 |
| --- | --- | --- |
| `track_person` | 创建或更新人物及关系信息 | 读写本地人物归档 |
| `emotion_timeline` | 记录和查询情绪时间线 | 读写 `emotion_timeline.json` |
| `search_chapters` | 查找相关章节和摘要 | 读取本地章节索引 |
| `fetch_chapter_messages` | 获取章节内的原始消息 | 读取本地对话存储 |
| `search_memory` | 查询跨对话记忆 | 读取本地记忆索引 |
| `manage_narrative_timeline` | 创建、更新、删除叙事时间节点 | 读写 `narrative_timeline.json` |

工具执行遵循以下边界：

- 工具的读写目标是 Prism 的本地数据目录。
- 搜索工具先在本地筛选和排序，再把必要的上下文交给模型。
- 模型可以请求工具，但不能绕过工具协议直接改写本地文件。
- API 请求只在模型功能运行时发生；没有内置的 Prism 账号、广告或遥测系统。

## 本地数据与隐私

### 默认数据目录

在 macOS 上，默认目录为 `~/Documents/Prism/`：

```text
~/Documents/Prism/
├── conversations.json           # 对话和章节消息
├── config.json                  # API 端点、模型等用户配置
└── Data/
    ├── person_archive.json      # 人物与关系
    ├── emotion_timeline.json    # 情绪时间线
    ├── narrative_timeline.json  # 叙事事件时间轴
    ├── blindspots.json          # 盲点与质量提示
    └── memory.json              # 跨对话记忆
```

Windows 客户端将应用数据写入当前用户目录下的 Prism 存储位置，具体路径由 Windows 工程的 Rust 配置决定，默认使用 `%USERPROFILE%\Documents\Prism` 及 `%APPDATA%\Prism` 相关目录。

### 哪些数据会离开设备

Prism 默认不提供离线大模型。用户配置 API Key、Base URL 和模型后，依赖模型的功能会向该端点发送请求。根据当前功能，上传范围可能包括：

- 当前对话消息和必要的历史上下文；
- 章节摘要、搜索结果和消息片段；
- 人物、情绪、记忆、盲点和叙事时间轴记录；
- 为生成回答而整理的用户画像、检索上下文和分析提示。

如果把默认 Base URL 改成其他兼容服务商，上述数据会发送给新的服务商，而不是默认服务商。服务商的日志、保留、训练和删除政策由服务商决定，Prism 无法替用户控制。

使用前请确认：

1. 你有权上传这些对话和相关人物信息；
2. API Key 不会出现在截图、日志、提交或导出的文件中；
3. 你已经阅读所选服务商的隐私政策和服务条款；
4. 对真实或敏感数据采取了符合自身风险承受能力的保护措施。

### 免责声明

Prism 的分类、摘要、检索和建议可能不完整或不准确，不构成医疗、心理健康、法律、财务或紧急建议。遇到即时伤害风险或其他紧急情况，请直接联系当地急救服务和专业人员，不要等待应用或模型回复。

## 快速开始

### 运行前准备

根据目标客户端准备对应环境：

- **SwiftUI macOS**：macOS 15+、Apple Silicon、Swift 6。
- **Tauri macOS**：Rust、Cargo、Tauri CLI 2，以及 macOS 开发工具链。
- **Tauri Windows**：Windows 11+、Rust MSVC 工具链、Visual Studio Build Tools（含“使用 C++ 的桌面开发”）、WebView2 Runtime、Tauri CLI 2。

Prism 不附带 API Key。首次启动后，在设置或引导流程中填写：

1. API Key；
2. DeepSeek 兼容的 Base URL；
3. 主回复模型和辅助分析模型（如果界面分别提供）。

### 在 macOS 上运行 SwiftUI

```bash
cd "Prism/swift version"
swift run -c release
```

如果仓库中已有打包应用，可直接打开 `Prism/release/Prism-SwiftUI-macOS.app`。

### 运行或打包 macOS Tauri

```bash
cd "Prism/Tauri Version"
cargo tauri dev
```

构建 macOS 应用包：

```bash
cargo tauri build --bundles app
```

打包应用通常位于 `Prism/release/Prism-Tauri-macOS.app`，或位于 Tauri 的标准 bundle 输出目录。

### 运行或打包 Windows Tauri

Windows 工程目录为 `Prism/Tauri Version/Windows Version`。在 PowerShell 中执行：

```powershell
cd "Prism\Tauri Version\Windows Version"
cargo tauri dev
```

构建当前用户 NSIS 安装包：

```powershell
cargo tauri build
```

安装包输出目录为：

```text
src-tauri\target\release\bundle\nsis\
```

Windows 工程使用自己的 `src-tauri/tauri.conf.json`，包含窗口、图标、WebView2 和 NSIS 当前用户安装模式配置。

## 构建与打包

### 客户端与产物

| 目标 | 构建入口 | 产物类型 |
| --- | --- | --- |
| SwiftUI macOS | `Prism/swift version/Package.swift` | macOS 原生可执行文件或 `.app` |
| Tauri macOS | `Prism/Tauri Version/src-tauri/tauri.conf.json` | `.app` 及其他 macOS bundle |
| Tauri Windows | `Prism/Tauri Version/Windows Version/src-tauri/tauri.conf.json` | NSIS 当前用户安装包 |

### 平台差异

- SwiftUI 使用原生 macOS 窗口和 Apple 框架。
- Tauri macOS 使用 HTML/CSS/JavaScript 前端与 Rust 核心，最低 macOS 版本由 bundle 配置声明。
- Tauri Windows 使用独立工程、Windows 原生窗口配置、WebView2 和 NSIS 当前用户安装模式。
- 三个客户端共享产品数据模型和分析目标，但不把某个平台的安装包当作另一个平台的安装包。

## 项目结构

```text
.
├── .github/
│   └── workflows/
│       └── build-windows.yml        # Windows 构建工作流
├── Prism/
│   ├── swift version/               # SwiftUI macOS 客户端
│   │   ├── Package.swift
│   │   ├── Sources/Prism/
│   │   └── TECHNICAL_SPEC.md
│   ├── Tauri Version/               # Tauri macOS 客户端
│   │   ├── src/                     # HTML/CSS/JavaScript 前端
│   │   ├── src-tauri/               # Rust 核心与 macOS 配置
│   │   └── Windows Version/         # 独立 Windows 11+ 工程
│   ├── assets/                      # 图标和界面资源
│   ├── release/                     # 已生成的 macOS 应用（如存在）
│   ├── README.md                    # 产品与平台完整说明
│   ├── README_CN.md                 # 简体中文说明
│   └── LICENSE                       # MIT 许可证
├── README.md                        # 仓库首页说明
├── README_CN.md                     # 中文入口副本
└── .gitignore
```

源码分层如下：

```text
界面层：SwiftUI / Tauri Web 前端
             │
运行时层：会话、流式输出、质量守护、ToolRegistry
             │
数据层：章节、消息、人物、记忆、盲点、情绪与叙事时间轴
             │
外部服务：用户主动配置的模型 API 端点
```

## 开发约定与路线图

### 开发约定

- 新增结构化数据时，明确它属于事实记录、模型推断还是用户偏好。
- 叙事事件的日期必须能够追溯到用户故事或用户的后续确认。
- 新工具要声明读写范围，并通过 `ToolRegistry` 暴露，不在模型提示中伪造执行结果。
- 影响隐私的字段、API 请求或第三方服务必须同步更新 README 的数据说明。
- SwiftUI、Tauri macOS 和 Tauri Windows 的用户可见行为保持一致；平台特有功能单独标注。

### 后续方向

- 更可靠的导入、导出、备份和恢复。
- 更透明地展示检索证据、来源章节和模型上下文。
- 继续完善原生客户端与 Tauri 客户端的功能一致性。
- 扩展跨平台打包和自动化构建流程。
- 提供更细粒度的数据删除、导出和隐私控制。

## 补充文档

本页已经包含项目的完整公共概览。以下文档只用于深入实现细节：

- [Prism 产品与平台说明](Prism/README.md)
- [Prism 简体中文详细说明](Prism/README_CN.md)
- [Tauri macOS/Windows 迁移说明](Prism/Tauri%20Version/README_WINDOWS.md)
- [Windows 独立工程说明](Prism/Tauri%20Version/Windows%20Version/README.md)
- [SwiftUI 技术规格](Prism/swift%20version/TECHNICAL_SPEC.md)

## 许可证与作者

Prism 使用 [MIT License](Prism/LICENSE) 发布。项目由 [`markbignews`](https://github.com/markbignews) 创建和维护。
