# 棱镜 / Prism

> 叙事反思伴侣 · 帮你看清盲点，找到出口
>
> A narrative reflection companion. See blind spots, find a way forward.

棱镜是一款**本地优先、尊重隐私**的 AI 对话工具，基于 DeepSeek 大语言模型。它帮助你讲出自己的故事、识别叙事盲点、探索替代视角，最终找到出口。

不是心理医生，只是一面镜子。

---

## 功能

### 核心对话

- **流式对话**：DeepSeek v4-pro（thinking 模式）+ 5 个 MCP 检索工具
- **思考链可见**：生成时自动滚动显示推理过程
- **三种对话模式**：理性（冷静分析）/ 平衡（默认）/ 温情（共情优先）
- **质量守护系统**：Flash 预处理管线自动检测 5 个对话质量维度 + 安全信号（代码强制执行，不依赖模型自主调用）
- **安全干预**：检测到自杀/自伤/暴力/虐待等信号时，跳过主模型直接输出安全引导（含热线号码）
- **跨对话记忆**：归纳时自动生成，任意对话中可检索
- **自动归纳**：增量 + 全量重扫，生成结构化章节
- **预处理管线**：每轮对话前自动运行 guard + 情绪 + 人物 + 盲点检测（v4-flash，～500ms）
- **上下文窗口**：≤60 条全文发送（享 1M 上下文），>60 条自动压缩为章节摘要

### MCP 检索工具（5 个，本地执行，零 API 成本）

| 工具 | 用途 | AI? |
|------|------|------|
| `search_chapters` | 语义搜索历史章节（keyword + Flash 重排序），返回标题/摘要/关键词 | ✅ 关键词本地 + Flash 语义 |
| `fetch_chapter_messages` | 按序号获取章节原文 | ❌ |
| `search_memory` | 语义搜索跨对话记忆（keyword + Flash 重排序） | ✅ 关键词本地 + Flash 语义 |
| `track_person` | 跨对话人物追踪（含别名解析） | ❌ |
| `emotion_timeline` | 原始情绪序列（模型自行判断趋势） | ❌ |

**注意**：对话质量守护（reality / spiral / blindspots / ingratiation / action_hollow）由 Flash 预处理管线自动执行，每轮对话代码强制运行，不暴露为 MCP 工具。

### 数据与隐私

- **100% 本地存储**：平台自适应默认路径（可自定义）
  - macOS: `~/Documents/Prism/`
  - Linux: `~/.local/share/prism/`
  - Windows: `%APPDATA%/Prism/`
- 可选 iCloud Drive 同步（仅 macOS）
- 仅当前对话上下文发送至 DeepSeek API
- 无遥测、无追踪（iCloud 除外）
- 支持数据路径迁移，自动复制原有文件
- 记忆库、情绪数据、盲点记录全部本地落盘

### GUI（macOS 桌面应用）

- macOS 15+ 原生 SwiftUI + AppKit
- Liquid Glass 设计风格（Apple HIG）
- Markdown 渲染
- 侧边栏：对话列表、章节导航、搜索、记忆面板
- 章节详情弹窗 + 蓝色跳转原文按钮
- 消息气泡：复制/编辑/重新生成/删除，按钮在气泡外侧
- 配对删除：删任意一边自动删除配对的问答
- 跨对话章节搜索，点击结果直接跳转

### CLI（命令行）

- ANSI 终端流式输出
- 全部核心功能：对话、归纳、搜索、查找、删除消息
- `/config` 实时修改设置（模式、路径等）
- 跨平台（macOS / Linux / Windows）

---

## 快速开始

### 环境要求

- macOS 15+（GUI）/ macOS、Linux、Windows（CLI）
- Swift 6.0+
- [DeepSeek API Key](https://platform.deepseek.com)

### GUI

```bash
cd GUI
swift build -c release
cp .build/arm64-apple-macosx/release/Prism Prism.app/Contents/MacOS/Prism
open Prism.app
```

首次启动进入设置向导，配置 API Key 和偏好。

### CLI

```bash
cd CLI
swift build -c release
./.build/arm64-apple-macosx/release/prism
```

直接打字开始对话，`/help` 查看所有命令。

---

## 架构

```
用户消息
  │
  ├── Flash 预处理管线（代码强制执行，~500ms）
  │     └─ 统一一次调用：
  │          reality（事实vs解释比例）
  │          spiral（情绪漩涡检测）
  │          blindspots（叙事盲点扫描）
  │          ingratiation（迎合倾向检测）
  │          action_hollow（空头承诺比对）
  │          safety（安全信号：自杀/自伤/暴力/虐待）
  │          emotions（情绪标注，写入 emotion_timeline.json）
  │          persons（人物提取，含别名解析，写入 person_archive.json）
  │
  ├── [安全覆写] safety == "crisis" → 跳过主模型，直接输出安全引导（含热线）
  │
  ├── v4-pro（thinking，流式）+ 5 个 MCP 检索工具
  │     ├─ System Prompt（根据模式：理性/平衡/温情）
  │     ├─ guard hint（由预处理管线注入 supervisorHint）
  │     ├─ StoryMemory + 跨对话记忆（top 3 条）
  │     └─ 章节索引（长对话时提供检索入口）
  │
  └── 自动归档更新（Task.detached，不阻塞主对话）
        ├─ 情绪写入 emotion_timeline.json
        ├─ 人物写入 person_archive.json
        └─ 盲点写入 blindspots.json

自动归纳（v4-flash，按对话轮数触发）
  ├─ 增量归纳（新消息 → 1 章，附带预处理管线产出的情绪/人物/盲点上下文）
  └─ 全量重扫（每 3 次增量 → 3-10 章）
       └─ 自动写入跨对话记忆（不额外调 API）

数据流：100% 本地 JSON → API（仅上下文）→ 本地 JSON
```

**API 调用/轮**：1 次 Flash + 1 次 Pro（日常对话）。
首次对话跳过预处理管线（无助手回复可分析）。

---

## CLI 命令

```
/help                    显示帮助
/new                     新建对话
/list                    列出所有对话
/switch <n>              切换到第 n 个对话
/delete <n>              删除第 n 个对话
/delmsg <n>              删除当前对话第 n 条消息（配对删除）
/rename <n> <名称>       重命名第 n 个对话
/search <关键词>          跨对话章节搜索（相关度排序）
/find <关键词>            当前对话内搜索（/find 跳下一个匹配）
/history [n]              查看最近 n 条消息（含序号）
/info                    查看当前对话摘要
/chapters                列出当前对话章节
/chapter <n>             查看第 n 个章节详情
/thinking                切换思考链显示
/settings                查看当前设置
/summarize               手动归纳当前对话
/config <键> <值>         修改设置（apiKey/model/mode/datapath/...）
/lang zh|zh-hant|en      切换语言
/reset --confirm          还原所有数据
/exit                    退出
```

---

## 配置

| 键 | 默认值 | 说明 |
|-----|---------|------|
| `apiKey` | — | DeepSeek API Key（必填） |
| `baseURL` | `https://api.deepseek.com` | API 地址 |
| `model` | `deepseek-v4-pro` | 对话模型（`pro` / `flash`） |
| `response` | `standard` | 回复长度（`brief` / `standard` / `detailed`） |
| `thinking` | on | 深度思考 |
| `effort` | high | 推理强度（`high` / `max`） |
| `summary` | 5 | 归纳频率（0 关/2/5/10 轮） |
| `mode` | balanced | 对话模式（`rational` / `balanced` / `warm`） |
| `icloud` | off | iCloud 存储（仅 macOS） |
| `datapath` | 平台默认 | 数据存储路径 |
| `lang` | zh-Hans | 界面语言（`zh` / `tw` / `en`） |

---

## 隐私与合规

- **安全红线**：自杀/自伤/暴力/虐待场景触发安全干预模式
- **不做诊断**：明确不诊断、不贴心理标签、不冒充医疗专业人员
- **数据可迁移**：全部数据以 JSON 格式本地存储，可随时复制或迁移

---

## 项目结构

```
chatbot/
├── CLI/
│   ├── Package.swift
│   ├── Sources/
│   │   ├── main.swift           # CLI 入口 + 命令
│   │   ├── ChatStore.swift      # 核心状态管理（预处理管线/工具循环/归纳）
│   │   ├── DeepSeekClient.swift # API 客户端
│   │   ├── AgentPrompt.swift    # System Prompt（3 套模式）
│   │   ├── Tools.swift          # 5 个 MCP 检索工具
│   │   ├── Models.swift         # 数据模型
│   │   ├── AppSettings.swift    # 配置管理
│   │   ├── StoryMemory.swift    # 本地记忆匹配
│   │   ├── L10n.swift           # 多语言
│   │   └── Terminal.swift       # ANSI 终端引擎
│   └── prism                    # 发布二进制文件
├── GUI/
│   ├── Package.swift
│   ├── Sources/Prism/
│   │   ├── PrismApp.swift         # 应用入口
│   │   ├── ContentView.swift      # 主界面 + 所有子视图
│   │   ├── ChatStore.swift        # 核心状态（与 CLI 同源）
│   │   ├── DeepSeekClient.swift   # API 客户端（同源）
│   │   ├── AgentPrompt.swift      # 提示词（同源）
│   │   ├── Tools.swift            # MCP 工具（同源）
│   │   ├── Models.swift           # 数据模型（同源）
│   │   ├── AppSettings.swift      # 配置（同源）
│   │   ├── StoryMemory.swift      # 记忆（同源）
│   │   ├── L10n.swift             # 多语言
│   │   └── ...
│   └── Prism.app                  # App 包
├── INTRODUCTION.md
├── REQUIREMENTS.md
├── README.md
└── README_CN.md
```

---

## 构建

```bash
# 两个版本
cd CLI  && swift build -c release
cd GUI  && swift build -c release
```

零第三方依赖。仅需 Swift 6.0+ 标准库。

---

## 许可证

待定。

---

*棱镜不是来留住你的，是来帮你离开的。*
