# Prism / 棱镜

Prism 是一个面向个人叙事的情绪分析与认知反思实验项目。它把 SwiftUI 和 Tauri 作为跨平台界面外壳，把对话、记忆、人物、盲点、情绪与叙事时间轴组织到同一套本地优先的数据模型中。

## 当前版本

| 版本 | 平台 | 说明 |
|---|---|---|
| SwiftUI | macOS 15+、Apple Silicon | 原生 macOS 客户端 |
| Tauri macOS | macOS（按配置） | HTML/CSS/JavaScript 前端 + Rust 核心 |
| Tauri Windows | Windows 11+ | 独立工程，MSVC 工具链，NSIS 当前用户安装包 |

Windows 工程位于 [`Prism/Tauri Version/Windows Version`](Prism/Tauri%20Version/Windows%20Version/README.md)，不是旧版 WinUI 工程。macOS 与 Windows 的最终安装包必须分别在对应平台验证；macOS 构建不能证明 Windows `.exe` 或 NSIS 安装包可用。

Tauri 客户端基于 **Tauri 2**；当前应用配置版本为 `1.0.14`。

## 核心能力

- **叙事时间轴**：记录用户故事中事件实际发生或持续的日期、时期和时间段；消息发送时间不会被自动当成事件发生时间。
- **情绪时间线**：记录对话分析得到的情绪、强度和片段。它与叙事时间轴是两个不同的数据集。
- 章节、人物、跨对话记忆、盲点和本地 JSON 存档。
- SwiftUI 与 Tauri 客户端的功能对齐，以及 Windows 11 的独立路径、窗口和安装配置。

## 工具边界

Prism 使用模型的**函数调用工具定义**，由本地 `ToolRegistry` 执行检索和时间轴读写；不依赖外部工具服务器，默认只读写本地 Prism 数据目录。

## 项目入口

- [完整英文说明](Prism/README.md)
- [完整简体中文说明](Prism/README_CN.md)
- [Tauri Windows 说明](Prism/Tauri%20Version/README_WINDOWS.md)
- [Windows 独立工程说明](Prism/Tauri%20Version/Windows%20Version/README.md)
- [SwiftUI 技术规格](Prism/swift%20version/TECHNICAL_SPEC.md)

## 目录

```text
Prism/
├── swift version/                 # SwiftUI macOS 客户端
├── Tauri Version/                 # Tauri macOS 客户端
│   └── Windows Version/           # 独立 Tauri Windows 11+ 工程
├── release/                       # 已构建的 macOS 应用（如存在）
└── README*.md                     # 产品与平台文档
```

这是实验性测试项目，不把本地 macOS 检查包装成已验证的 Windows 发布物，也不把产品描述成陪伴或医疗服务。
