# 棱镜 / Prism

> 叙事反思伴侣 · 帮你看清盲点，找到出口
>
> A narrative reflection companion. See blind spots, find a way forward.

**[简体中文](README_CN.md) · [English](README.md) · [繁體中文](README_ZH_HANT.md)**

棱镜是一款**本地优先、尊重隐私**的 AI 对话工具，基于 DeepSeek 大语言模型。它帮助你讲出自己的故事、识别叙事盲点、探索替代视角，最终不再需要它。

**不是心理医生，只是一面镜子。**

和大多数追求"有用"的 AI 聊天不同，棱镜追求的是**诚实**。它会挑战你的解释、指出你不断重复的模式、拒绝只附和你的观点。它的目标不是留住你，是帮你走到不需要再打开它的那一天。

---

## 功能特性

### 核心

- **流式对话** — DeepSeek v4-pro（thinking 模式）+ 5 个检索工具
- **思考链可见** — 生成时自动滚动显示推理过程
- **三种对话模式** — 理性、平衡（默认）、温情
- **质量守护系统** — Flash 预处理管线每轮自动检测 6 个维度（代码强制执行）
- **安全干预** — 自杀/自伤/暴力/虐待检测跳过主模型，输出热线引导
- **跨对话记忆** — 归纳时自动生成，任意对话中可检索
- **自动归纳** — 增量 + 全量重扫混合策略，生成结构化章节
- **预处理管线** — 每轮 1 次 Flash 调用覆盖 guard + 情绪 + 人物 + 盲点（~500ms）
- **上下文窗口** — ≤60 条全文，>60 条自动压缩为章节摘要
- **语义搜索** — 关键词预筛选 + Flash 语义重排序

### MCP 检索工具（5 个）

| 工具 | 用途 | AI？ |
|------|------|------|
| `search_chapters` | 语义搜索历史章节，返回标题/摘要/关键词 | ✅ keyword + Flash |
| `fetch_chapter_messages` | 按序号获取章节原文 | ❌ |
| `search_memory` | 语义搜索跨对话记忆 | ✅ keyword + Flash |
| `track_person` | 跨对话人物追踪（含别名解析） | ❌ |
| `emotion_timeline` | 原始情绪序列（模型自行判断趋势） | ❌ |

质量守护（reality / spiral / blindspots / ingratiation / action_hollow / safety）由预处理管线自动运行，不暴露为工具。

### 数据与隐私

- 100% 本地存储：`~/Documents/Prism/`（可自定义）
- 仅当前对话上下文发送至 DeepSeek API
- 无遥测、无追踪、无分析 SDK
- 可选 iCloud Drive 同步（macOS 独有，默认关闭）
- 所有归档为纯 JSON，可读可迁移

### GUI / CLI

| GUI（macOS 15+） | CLI（macOS / Linux / Windows） |
|---|---|
| SwiftUI + AppKit，Liquid Glass 设计 | ANSI 终端流式输出 |
| Markdown 渲染，侧边栏章节导航 | 完整对话管理，`/config` 实时设置 |
| 6 页首次引导向导 | `/help` 查看所有命令 |

---

## 消息处理流程

```
用户消息
  │
  ├── [1] Flash 预处理管线（代码强制执行，~500ms）
  │     └─ 统一一次调用：
  │          reality — 事实 vs 解释比例
  │          spiral — 情绪漩涡检测
  │          blindspots — 解释循环/回避自我/意图-行动差距
  │          ingratiation — 助手迎合倾向检测
  │          action_hollow — 历史空头承诺比对
  │          safety — 安全信号（最高优先级）
  │          emotions — 情绪标注 → emotion_timeline.json
  │          persons — 人物提取（含别名解析）→ person_archive.json
  │
  ├── [安全覆写] safety == "crisis" → 跳过主模型，返回安全引导
  │
  ├── [2] v4-pro 主模型（thinking，流式）+ 5 个 MCP 工具
  │     └─ guard 提示通过 [监督者方向] 系统消息注入
  │
  └── [3] 归档更新（异步，不阻塞主对话）
```

---

## 质量守护系统

| 维度 | 检测什么 | warning 时 |
|---|---|---|
| `reality` | 解释性语言远多于具体事实 | 温和拉回事实层 |
| `spiral` | 同一话题无情绪位移重复 | 从分析切换到出口引导 |
| `blindspots` | 解释循环、回避自我、意图-行动差距 | 自然地提示盲点 |
| `ingratiation` | 上轮回复有迎合倾向 | 回复更独立 |
| `action_hollow` | 历史上出现过的空头承诺 | 温和提醒过去模式 |
| `safety` | 自杀/自伤/暴力/虐待 | **覆盖主模型，输出热线** |

---

## 设计决策

**为什么预处理在主模型之前？**
guard 信号在主模型生成回复前就可用，自然融入回复，不生硬转折。延迟成本约 500ms。

**为什么 Agent + MCP 检索？**
模型需要理解上下文才能决定搜什么。检索工具纯本地执行（零 API 成本），模型自主决策何时调用。

**为什么上下文窗口阈值设 60 条？**
DeepSeek Pro 有 1M token 上下文。60 条以内全量发送，超过则压缩——但模型仍可通过工具检索任何压缩内容。

**为什么归纳用混合策略？**
每次都全量重扫浪费 token，纯增量导致章节风格不一致。3 次增量 + 1 次重扫 = 平衡效率和一致性。归纳时附带预处理管线数据，章节更有洞察。

**为什么搜索用 keyword + Flash 两步式？**
纯关键词搜不到语义匹配（"被PUA"找不到"精神控制"），纯 embedding 需要额外 API。两步式：keyword 微秒级过滤 → Flash 语义重排序 ~300ms，失败时降级。

**为什么人物提取要解析别名？**
用户对同一人的称呼会变（"我男朋友"→"张伟"→"前任"）。预处理时传入已知人物列表，要求复用标准名称，避免同一人分裂为多条记录。

**为什么 searchChapters 不返回原文？**
10 结果 × 8 条消息 = 80 条非必要上下文。现在只返回标题/摘要/关键词，需原文时单独调 fetch_chapter_messages。

---

## 快速开始

```bash
# GUI
cd GUI && swift build -c release
cp .build/arm64-apple-macosx/release/Prism Prism.app/Contents/MacOS/Prism
open Prism.app

# CLI
cd CLI && swift build -c release
./.build/arm64-apple-macosx/release/prism
```

首次启动配置 API Key。CLI 中直接打字对话，`/help` 查看命令。

---

## CLI 命令

导航：`/help`, `/new`, `/list`, `/switch <n>`, `/delete <n>`, `/rename <n>`
消息：`/history [n]`, `/delmsg <n>`, `/find <关键词>`
搜索：`/chapters`, `/chapter <n>`, `/search <关键词>`
信息：`/info`, `/settings`
归纳：`/summarize`
配置：`/config <键> <值>`
其他：`/thinking`, `/lang zh|tw|en`, `/reset --confirm`, `/exit`

配置键：`apikey`, `model`, `mode`, `response`, `thinking`, `effort`, `summary`, `icloud`, `datapath`, `lang`

---

## 项目结构

```
chatbot/
├── CLI/Sources/       — 12 个源文件（含 main.swift、PrePipeline.swift、SearchExpander.swift）
├── GUI/Sources/Prism/ — 同一套核心文件 + UI 专有文件
├── README.md          — 英文说明
└── README_CN.md       — 中文说明（本文档）
```

---

## 构建

```bash
# 零第三方依赖，仅需 Swift 6.0+
cd CLI  && swift build -c release
cd GUI  && swift build -c release
```

---

## 许可证

待定。

---

*棱镜不是来留住你的，是来帮你离开的。*
