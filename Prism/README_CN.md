<p align="center">
  <img src="assets/icon.png" alt="棱镜" width="128" style="border-radius: 24px;"/>
</p>

<h1 align="center">棱镜 / Prism</h1>

<p align="center">
  一个本地优先的工作空间，用来理解个人叙事、情绪和反复出现的模式。
</p>

<p align="center">
  <strong>本地优先的叙事分析工作空间</strong><br>
  SwiftUI + Tauri · macOS 15+ · Windows 11+
</p>

<p align="center">
  <img src="https://img.shields.io/badge/status-active%20development-6f42c1" alt="Active development"/>
  <img src="https://img.shields.io/badge/macOS-SwiftUI-blue" alt="macOS SwiftUI"/>
  <img src="https://img.shields.io/badge/Tauri-2-24C8DB" alt="Tauri 2"/>
  <img src="https://img.shields.io/badge/Windows-11%2B-0078D4" alt="Windows 11 或更高版本"/>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README_CN.md">简体中文</a>
</p>

---

## 棱镜是什么？

棱镜是一个**本地优先的叙事分析工具**，通过兼容 DeepSeek 的 API 工作。它帮助你回看自己写下的内容，观察情绪变化，按照事件实际发生的时间整理经历，并发现当下容易忽略的模式。

棱镜并不是一个持续陪伴型产品。它更像一个分析工作空间：会追问缺失的事实、挑战未经验证的解释，并提示可能存在的盲点，而不是简单地附和你。

> 棱镜不是心理治疗师、医生、急救服务，也不能替代专业帮助。

## 棱镜包含的能力

棱镜将以下能力整合在一起：

- 面向 Apple Silicon Mac 的原生 SwiftUI 客户端
- macOS Tauri 客户端
- 面向 Windows 11 及更高版本的独立 Tauri 工程
- 情绪追踪、叙事时间轴、章节、人物、记忆和盲点
- 理性、平衡、温情三种对话模式
- 检测到危机信号时可以中断常规模型流程的本地安全守护
- 本地 JSON 持久化，不内置遥测、分析或账号系统

## 核心亮点

### 看见故事的结构，而不只是最新一条消息

棱镜会把长对话整理成章节，并为重要内容建立可搜索索引。当你后来提到过去的事件时，它可以检索相关上下文。

### 区分叙事时间和消息时间

只有当事件的日期或时间段来自你的叙述时，棱镜才会把它放入叙事时间轴。你发送消息的时间不会被悄悄当成事件发生时间。

### 用证据发现模式

质量守护会检查解释循环、情绪漩涡、意图与行动的落差、过度迎合以及具体事实不足等情况。告警会以结构化指导的形式传给主模型，帮助回答保持有依据，而不会替代模型本身的判断。

### 在设备上建立记忆

章节、人物、情绪、盲点和跨对话记忆都会作为本地文件保存。你可以选择自定义数据目录，也可以在支持的 macOS 工作流中启用 iCloud Drive。

### 三个客户端共享同一产品思路

SwiftUI 和 Tauri 客户端共享核心行为，同时保留必要的平台差异：macOS 使用原生窗口和存储约定，Windows 使用原生标题栏、当前用户 NSIS 安装包和 WebView2。

## 截图

| 对话 | 跨对话记忆 | 人物与洞察 |
| --- | --- | --- |
| <img src="assets/1.png" width="260" alt="棱镜对话界面"/> | <img src="assets/2.png" width="260" alt="棱镜记忆界面"/> | <img src="assets/3.png" width="260" alt="棱镜人物与洞察界面"/> |

## 一条消息如何被处理

1. 棱镜在本地保存消息，并更新当前章节。
2. 轻量 Flash 分析检查情绪、人物、盲点、叙事上下文和安全信号。
3. 如果消息可以继续处理，所选对话模式会指导主模型流式生成回复。
4. 当回复需要上下文时，本地工具可以检索章节、记忆、人物、情绪或叙事时间节点。
5. 归纳和索引在本地更新，让后续对话可以找到相关内容。

安全路径优先于普通回复路径。检测到危机信号时，棱镜会提供本地化安全回应，不会让主模型按普通对话流程继续。

## 对话模式

| 模式 | 适合的体验 |
| --- | --- |
| **理性之镜** | 基于证据分析，明确区分事实和假设，更强地挑战认知扭曲 |
| **平衡之镜**（默认） | 在适度共情的同时进行叙事分析和实际追问 |
| **温情之镜** | 更温和地探索和验证情绪，同时保持分析有依据 |

## 支持的平台

| 客户端 | 运行环境 | 能力概览 |
| --- | --- | --- |
| SwiftUI | macOS 15+、Apple Silicon | 原生客户端；打包应用位于 `release/Prism-SwiftUI-macOS.app` |
| Tauri macOS | 按配置支持 macOS 12+ | 共享 HTML/CSS/JavaScript 前端和 Rust 核心；打包应用位于 `release/Prism-Tauri-macOS.app` |
| Tauri Windows | Windows 11+ | 独立 Tauri 工程，需要 MSVC 工具链和当前用户 NSIS 安装包 |

## 快速开始

### 1. 配置 API 端点

首次启动时，在引导流程或设置中填写：

- DeepSeek API Key
- DeepSeek 兼容的 Base URL（如果不使用默认地址）
- 用于主回复和辅助分析的模型

棱镜不附带 API Key，请求会发送到你配置的端点。

### 2. 在 macOS 上运行 SwiftUI 客户端

要求：macOS 15 或更高版本、Apple Silicon 和 Swift 6。

在 Prism 目录中执行：

~~~
cd "swift version"
swift run -c release
~~~

如果目录中提供了打包应用，它位于 `release/Prism-SwiftUI-macOS.app`。使用 Swift Package Manager 构建不会把应用安装到 `/Applications`。

### 3. 运行或打包 macOS Tauri 客户端

要求：Rust、Cargo 和 Tauri CLI 2。

~~~
cd "Tauri Version"
cargo tauri dev
~~~

创建 macOS 应用包：

~~~
cargo tauri build --bundles app
~~~

### 4. 构建 Windows 客户端

请使用 Windows 11 或更高版本，并准备：

- Rust MSVC 工具链（`x86_64-pc-windows-msvc`）
- 安装“使用 C++ 的桌面开发”的 Visual Studio Build Tools
- WebView2 Runtime
- Tauri CLI 2

在 PowerShell 中执行：

~~~
cd "Tauri Version\Windows Version"
cargo tauri build
~~~

NSIS 安装包会写入 `src-tauri\target\release\bundle\nsis`。Windows 工程使用自己的平台配置，不依赖 macOS 配置文件。

## 本地数据与隐私

棱镜默认把数据保存到：

~~~
~/Documents/Prism/
├── conversations.json
├── config.json
└── Data/
    ├── person_archive.json
    ├── emotion_timeline.json
    ├── narrative_timeline.json
    ├── blindspots.json
    └── memory.json
~~~

- 对话历史和索引是本地可读的 JSON 文件。
- 没有内置遥测、分析或棱镜账号。
- 棱镜虽然在本地保留副本，但对话内容以及由此形成的用户画像数据（包括人物、情绪、记忆、盲点和叙事时间轴记录）会在模型功能运行时，通过你配置的 API Key 和端点上传到 DeepSeek。
- 可以选择其他存储目录；支持的 macOS 工作流可以选择使用 iCloud Drive。
- Tauri 客户端删除对话时，也会删除与之关联的本地归档记录。

你需要自行负责所选择的 API 提供商、端点、保留策略和凭据。棱镜无法控制 DeepSeek 对数据的处理、存储、保留、训练或删除政策。不要把密钥放进截图、导出日志或受版本控制的文件中。

## 数据使用授权与免责声明

当你填写 API Key 并使用依赖模型的功能时，即表示你授权棱镜通过已配置的 API 端点，将对话内容和由此形成的用户画像数据传输给 DeepSeek。这些数据可能包括消息、人物、情绪、记忆、盲点、叙事时间轴记录、摘要和搜索上下文。

如果你把默认 Base URL 改成其他兼容服务商，同样的数据会发送给该服务商，而不是 DeepSeek。

你需要确认自己有权上传这些信息，并确保使用方式符合适用法律、工作场所规定以及必要的授权或同意要求。使用真实或敏感数据前，请阅读 [DeepSeek 隐私政策](https://cdn.deepseek.com/policies/zh-CN/deepseek-privacy-policy.html) 和 [DeepSeek 开放平台服务条款](https://cdn.deepseek.com/policies/en-US/deepseek-open-platform-terms-of-service.html)。

棱镜提供信息参考与叙事分析。分类、摘要、安全回应和建议可能不完整或不准确，不构成医疗、心理健康、法律、财务或紧急建议。你需要自行承担使用棱镜及其连接 API 的风险；项目作者不对基于模型输出作出的决定，或所配置服务商对数据的处理承担责任。本条款不构成法律意见。

## 项目结构

~~~
Prism/
├── swift version/                 # 原生 SwiftUI 客户端
│   ├── Package.swift
│   ├── Sources/Prism/
│   └── Prism.app
├── Tauri Version/                 # macOS Tauri 客户端
│   ├── src/
│   ├── src-tauri/
│   ├── macOS Version/Prism.app
│   └── Windows Version/           # 独立 Windows 11+ 工程
├── assets/                        # 图标和截图
├── release/                       # 打包的 macOS 应用
│   ├── Prism-SwiftUI-macOS.app
│   └── Prism-Tauri-macOS.app
├── README.md
└── README_CN.md
~~~

SwiftUI 版本使用 Swift Package Manager 和 Apple 框架构建。Tauri 版本使用 HTML/CSS/JavaScript 前端和 Rust 核心。各客户端保持产品行为一致，但窗口、存储路径和打包方式按平台分别处理。

## 重要信息

- 棱镜需要访问已配置的 LLM 端点，不是离线模型。
- 模型输出、分类结果和检索上下文可能不完美，请自行复核重要结论。
- 棱镜不是医疗或急救产品。如果存在即时伤害风险，请联系当地急救服务或专业人员。

## 后续方向

棱镜的本地数据模型以及 SwiftUI/Tauri 之间的共享行为会继续完善，后续将集中在：

- 更可靠的导入和导出流程
- 更完善的本地归档备份与恢复控制
- 更广泛的平台打包和自动化流程
- 更透明地展示检索证据和模型上下文
- 继续完善原生客户端与 Tauri 客户端之间的功能一致性

## 许可证

棱镜使用 [MIT License](LICENSE) 发布。版权持有人：`markbignews`。

## 作者

棱镜由 [markbignews](https://github.com/markbignews) 创建和维护。
