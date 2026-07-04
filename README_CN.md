<p align="center">
  <img src="assets/icon.png" alt="棱镜" width="120" style="border-radius: 22px;"/>
</p>

<p align="center">
  <strong>棱镜 / Prism</strong><br>
  情感分析 Agent · Emotion Analysis Agent<br>
  <sub>Swift 6 · SwiftUI + AppKit · 零外部依赖</sub>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-SwiftUI-blue" alt="macOS"/>
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README_ZH_HANT.md">繁體中文</a> · <a href="README_CN.md">简体中文</a>
</p>

---

## 棱镜是什么？

棱镜是一款**本地优先、尊重隐私**的 AI 情感分析 Agent，基于 DeepSeek 大语言模型。对话数据与用户设置保存在本地（可选 iCloud Drive），无遥测、无分析。AI 推理通过 DeepSeek API 完成。它分析你的个人叙事、追踪情绪变化、发现你可能忽略的认知盲点。

**它是分析工具，不是陪伴，不是医生。** 质量守护系统主动防止情感迎合，确保分析立足于可观察的事实。

---

## 它能做什么

- **情绪追踪** — 每轮对话自动标注情绪状态，构建情绪变化时间线
- **叙事模式分析** — 检测重复出现的主题、解释循环和行为模式
- **盲点发现** — 发现意图与行动之间的落差；标记你过度描述他人而忽略自己的时候
- **多视角分析** — 当故事结构完整时，提供同一事件的不同解读
- **跨对话记忆** — 将过往对话提炼为可搜索的知识库
- **语义搜索** — 关键词 + Flash 重排序，用不同措辞也能找到相关内容
- **安全干预** — 代码强制执行，检测到危机信号时自动跳出并提供专业求助指引

---

## 技术栈

| 层级 | 技术 |
|---|---|
| 语言 | Swift 6 |
| UI | SwiftUI + AppKit 混合（`NSViewRepresentable`、`NSTextView`、`NSOpenPanel`、`NSPasteboard`） |
| 并发 | `async/await`、`Task`、`Task.detached`、`@MainActor` |
| 状态管理 | `ObservableObject` / `@Published` / `@StateObject` / `@EnvironmentObject` |
| 网络 | `URLSession.shared.bytes(for:)`（SSE 流式）、`URLSession.shared.data(for:)`（非流式） |
| 持久化 | `JSONEncoder` / `JSONDecoder` → 本地 `.json` 文件 + `UserDefaults`（安全危机状态） |
| 构建 | Swift Package Manager（`Package.swift`，swift-tools-version 6.0）— 无需 Xcode |
| 最低要求 | macOS 15.0（Sequoia）、Apple Silicon（arm64） |

**零外部依赖。** Markdown 渲染器、语义搜索、MCP 工具注册表、JSON 持久化、同义词扩展 — 全部基于 Apple 框架（`SwiftUI`、`AppKit`、`Foundation`、`Combine`、`Observation`）手写。

---

## 架构

```
SwiftUI 层 (ContentView、SidebarView、ChatView、SettingsView、OnboardingView、MemoryPanelView)
       │
       │  @EnvironmentObject / @Published
       ▼
ChatStore（ObservableObject 外观层）
       │
       ▼
ChatAgent（@MainActor — 核心业务逻辑）
       │
       ├── DeepSeekClient        HTTP 客户端：SSE 流式 + 非流式归纳
       ├── ToolRegistry          5 个 MCP 工具定义与本地执行器
       ├── AgentPrompt           所有模式的系统提示词 + 归纳 + 重排序
       ├── StoryMemory           基于章节的本地对话记忆
       ├── PrePipeline           单次统一 Flash 调用：守护 + 情绪 + 人物 + 盲点
       └── SearchExpander        ~40 组同义词扩展
```

**设计模式 — Agent-Facade：** `ChatStore` 是一个薄 `ObservableObject`，桥接 SwiftUI 和 `ChatAgent`。它暴露 `@Published` 属性并将所有调用委托给 Agent。流式传输期间，`append()` 将每个 token delta 直接写入内存中的 `Conversation` 模型并调用 `agentStateDidChange()` — SwiftUI 在每个 token 到达时重渲染消息气泡，无中间缓冲层。

---

## 工作原理

每条用户消息触发以下管线：

```
用户发送消息
  │
  ▼
1. StoryMemory.ingest()
   按段落拆分文本 → 创建或更新本地章节
   每个章节包含：标题、摘要、关键词、消息 ID 引用
   │
  ▼
2. PrePipeline（Flash 模型，非流式，thinking 禁用）
   首轮对话跳过（尚无助手回复可供 ingratiation 检测）
   发送最近 10 条 user+assistant 消息 + 已知人物列表 + 历史盲点记录
   │
   一次 Flash API 调用返回结构化 JSON，同时完成：
   ├── 6 维度质量守护：
   │     reality（现实感）— 可观察事实 vs 主观解释比例（>2.5:1 时告警）
   │     spiral（情绪漩涡）— 情绪停滞，多轮无位移
   │     blindspots（盲点）— 解释循环、回避自我、意图-行动差距
   │     ingratiation（迎合）— 助手过度赞同/情感迎合/镜像无分析
   │     action_hollow（空谈）— 当前意图匹配历史盲点模式
   │     safety（安全）— 自伤、暴力/虐待、精神错乱、未成年人受害、明确求助
   ├── 情绪标注：1-3 个片段，含 emotion + intensity（0.0-1.0）
   ├── 人物提取：真实姓名 + 角色，支持别名去重解析
   └── 盲点发现：pattern + evidence + counter_question + severity（new|recurring|persistent）
   │
  ▼
3. 安全检查
   若 safety.flag == "crisis":
     → 构建本地化安全回应（中/英文）
     → 逐字符流式输出到 UI（每 8 字符 yield 一次）
     → 将危机状态持久化至 UserDefaults，供下一轮 PrePipeline 上下文使用
     → 完全跳过主模型
   若 safety.flag == "ok" 且上一轮为危机状态 → 自动清除危机标记
   │
  ▼
4. 主模型（DeepSeek v4-pro，流式 + thinking 模式）
   │
   API 请求结构（DeepSeekClient.stream）:
     POST {baseURL}/chat/completions
     Body:
       model: 用户配置（默认 deepseek-v4-pro）
       messages:
         - system: AgentPrompt.system(语言, 模式, 回复长度)
         - system: "[监督者方向]\n{守护提示}"  （若有告警维度）
         - system: 记忆上下文 + 跨对话记忆（若有）
         - 最近 500 条对话消息（非最后一条 assistant 的 tool_calls 被清除）
         - role:"tool" 消息（待处理的工具结果）
       temperature: 0.1（理性）/ 0.35（平衡）/ 0.6（温情）
       top_p: 0.8（理性）/ 0.9（平衡）/ 0.95（温情）
       max_tokens: 8192
       thinking: {type: "enabled"} + reasoning_effort（用户可配，默认 high）
       stream: true
       tools: ToolRegistry.definitions（5 个工具）
       timeout: 300s
   │
   SSE 解析循环（URLSession.shared.bytes）:
     逐行读取响应:
       "data: [DONE]" → 结束
       "data: {...}" → JSONDecode → 提取 delta:
         reasoning_content → 追加到推理内容，发送 .reasoning(token)
         content → 追加到正文，发送 .content(token)
         tool_calls[] → 按 index 累积（id、function.name、function.arguments 片段）
   │
   上下文窗口策略（buildWindowedMessages）:
     ≤60 条消息 → 全文发送 + 注入章节索引
     >60 条消息 → 保留最后 40 条全文，旧内容压缩为章节摘要
     章节索引作为 system 消息注入，让 Agent 知道哪些内容可通过工具检索
   │
   工具循环（最多 3 轮）:
     若模型返回 tool_calls:
       1. 将 tool_calls 持久化到 assistant 消息（API 下一轮调用所需）
       2. UI 显示 "🔧 正在查询…" 占位符
       3. 通过 ToolRegistry 本地执行每个工具:
            track_person       → 读取 person_archive.json，模糊名称匹配
            emotion_timeline   → 返回最近 N 条记录，含 ISO8601 日期
            search_chapters    → 关键词打分 → 前 15 候选 → Flash 语义重排序 → 返回前 K
            fetch_chapter_messages → 返回某章节最多 12 条消息（1-based 索引）
            search_memory      → 关键词 + 同义词扩展 → Flash 语义重排序 → 返回前 K
       4. 清除占位符
       5. 将结果作为 role:"tool" 消息注入
       6. 重建窗口消息，再次调用 API
     若模型返回正文且无 tool_calls → 完成
     循环结束后: 清除 assistant 消息的 tool_calls（防止下轮 API 报错）
   │
  ▼
5. 后处理（Flash 模型，非流式，thinking 禁用）
   │
   ├── 应用 PrePipeline 结果到存档（分离、非阻塞）:
   │     合并情绪（上限 200）、人物（上限 200，按 lastMentionedAt 排序）、
   │     盲点（上限 300，按 createdAt 排序）
   │
   ├── 归纳总结（按对话轮数触发，间隔可配置）:
   │     增量归纳（Flash，max_tokens: 1024，超时 120s）:
   │       发送 lastSummaryMessageIndex 之后的新消息 + 最近 3 个章节
   │       解析 JSON: {title, summary, keywords}
   │       追加 1 个章节，同步到跨对话记忆库
   │     全量重扫（Flash，max_tokens: 8192，超时 180s）:
   │       发送完整对话记录（带 [序号][角色] 标记）+ 存档上下文
   │       解析 JSON 数组: [{title, summary, keywords, startIndex, endIndex}]
   │       替换全部章节，重置 incrementalChapterCount
   │     混合策略: 每 3 次增量归纳 → 自动触发 1 次全量重扫
   │     压缩存储（trimConversation）:
   │       已被章节覆盖的消息 → 替换为 "[已归纳: 第N章「标题」]"
   │       未被覆盖的消息 → 截断至 200 字符
   │       章节摘要 → 截断至 600 字符
   │       始终保留最后 40 条消息全文
   │
   ├── 标题更新（Flash 模型）:
   │     首条消息或章节变化时触发
   │     发送全部章节摘要 → Flash 生成 ≤40 字符标题
   │
   └── 持久化至 ~/Documents/Prism/conversations.json（原子写入）
```

---

## 项目结构

```
macOS Version/
├── Package.swift                # SPM 清单（swift-tools-version: 6.0）
├── Sources/
│   └── Prism/
│       ├── PrismApp.swift       # @main 入口，WindowGroup，引导页，Cmd+N 快捷键
│       ├── ContentView.swift    # NavigationSplitView，GlassBackground 修饰器，SidebarView，
│       │                        #   ChatView，MessageBubble（推理展开器），ComposerView，
│       │                        #   MacEditor（NSViewRepresentable 包装 IntrinsicTextView），
│       │                        #   MemoryPanelView（人物存档、情绪时间线、盲点、洞察）
│       ├── ChatStore.swift      # ObservableObject 外观层 → ChatAgent，响应 agentStateDidChange
│       ├── ChatAgent.swift      # 核心编排器：send()、窗口消息、工具循环、
│       │                        #   归纳（增量+全量）、智能搜索、记忆搜索、
│       │                        #   语义重排序（Flash）、存档管理、JSON 持久化
│       ├── DeepSeekClient.swift # HTTP 客户端：stream() SSE 解析、summarize()/fullSummarize()
│       │                        #   非流式、ChatRequest/APIMessage/ThinkingConfig 模型
│       ├── Models.swift         # Conversation、ChatMessage、StoryChapter、EmotionEntry、
│       │                        #   PersonRecord、BlindspotRecord、MemoryEntry、
│       │                        #   ToolCall（自定义 Codable）、ToolResult
│       ├── Tools.swift          # ToolRegistry，5 个工具：track_person、emotion_timeline、
│       │                        #   search_chapters、fetch_chapter_messages、search_memory
│       │                        #   ToolDef schema 含 FunctionDef/Parameters/Property
│       ├── MarkdownText.swift   # 自定义 Markdown 解析器 → MarkdownBlock 枚举树，
│       │                        #   SwiftUI 渲染器（标题、列表、代码块、表格 via Grid）
│       ├── StoryMemory.swift    # 按段落提取章节，relevantContext() 检索
│       ├── PrePipeline.swift    # 单次 Flash 调用：100+ 行系统提示词，严格 JSON 输出模式，
│       │                        #   JSON 提取（处理 ```json 标记），安全危机状态机
│       ├── AgentPrompt.swift    # 理性/温情/平衡系统提示词，归纳提示词，
│       │                        #   标题更新提示词，搜索重排序提示词
│       ├── L10n.swift           # 190+ 本地化字符串（简中 / 繁中 / 英文）
│       ├── SettingsView.swift   # API Key、Base URL、模型选择、thinking 开关、推理强度、
│       │                        #   语言、对话模式、回复长度、iCloud、数据路径
│       ├── OnboardingView.swift # 8 页流程：欢迎 → 用途 → 功能 → UI 导览 → API Key →
│       │                        #   模式选择 → iCloud → 数据与隐私
│       └── SearchExpander.swift # ~40 组同义词：情绪、家庭、爱情、职场、内心模式
└── Prism.app/                   # 构建产物（arm64）
```

---

## 截图

| 对话 | 跨对话记忆 | 人物记忆 |
|---|---|---|
| <img src="assets/1.png" width="240" style="border-radius: 16px;"/> | <img src="assets/2.png" width="240" style="border-radius: 16px;"/> | <img src="assets/3.png" width="240" style="border-radius: 16px;"/> |

---

## 核心功能

### 预处理管线（Flash 守护模型）

每次主模型回复前，一次 Flash API 调用同时完成所有维度的分析。接收最近 10 条 user+assistant 消息、已知人物列表和历史盲点记录作为上下文，返回单个 JSON 对象 — 无多次调用开销。

管线**跳过首轮对话**（尚无助手回复可供 ingratiation 检测，无 spiral 历史，无 blindspot 基线）。

| 维度 | 检测逻辑 | 告警阈值 |
|---|---|---|
| `reality`（现实感） | 统计解释性语言（"我觉得""应该是""意味着"…）vs 具体事实（时间/地点/人名/引述原话） | 解释:事实 > 2.5:1 |
| `spiral`（情绪漩涡） | 比较多轮的情绪多样性和强度趋势 | 相同情绪 + 相同话题 + 无位移 |
| `blindspots`（盲点） | 三项子检查：解释循环（换措辞重复同一事件）、回避自我（大量描述他人忽略自己）、意图-行动差距（有意图无行动描述） | 任一子项阳性 |
| `ingratiation`（迎合） | 仅扫描最近一条助手回复：过度赞同、回避挑战、镜像无分析、过度称赞 | 严格标准 — 正常共情不算 |
| `action_hollow`（空谈） | 将当前用户意图与历史盲点模式交叉比对 | 意图匹配持续盲点 |
| `safety`（安全） | 自伤、暴力/虐待、精神错乱、未成年人受害、明确求助 — **最高优先级** | 任何明确信号 → crisis，接管主模型 |

**安全危机状态机：** 危机状态持久化到 `UserDefaults`（按对话 ID 隔离）。下一轮 PrePipeline 重新注入危机上下文。当 Flash 对之前处于危机的对话返回 `safety.flag == "ok"` 时，自动清除危机状态。

### JSON 输出格式

PrePipeline 返回严格 JSON（解析器处理 ````json` 标记和周围文本）：

```json
{
  "guard": {
    "reality":    {"flag":"ok|warning", "ratio":0.0, "interpretive_count":0, "concrete_count":0, "hint":""},
    "spiral":     {"flag":"ok|warning", "emotion_diversity":0, "intensity_trend":"stable|rising|falling", "hint":""},
    "blindspots": {"flag":"ok|warning", "findings":[{...}], "hint":""},
    "ingratiation":{"flag":"ok|warning", "signals":["..."], "hint":""},
    "action_hollow":{"flag":"ok|warning", "matched_count":0, "persistent_count":0, "hint":""},
    "safety":     {"flag":"ok|crisis", "signals":["..."], "suggest":"", "resources":""}
  },
  "emotions": [{"segment":"...", "emotion":"愤怒", "intensity":0.8}],
  "persons": [{"name":"张伟", "role":"ex-partner"}]
}
```

守护告警以 `[监督者方向]` 系统消息的形式注入到主系统提示词和对话历史之间，给 Pro 模型结构化指导而不覆盖其判断。

### 5 个检索工具（MCP 风格）

所有工具**本地执行** — 读取磁盘 JSON 存档，不调用外部 API。每个工具返回 JSON 字符串给模型。

当 `settings` 可用时，`search_chapters` 和 `search_memory` 使用**两阶段语义管线**：关键词预筛选（前 15）→ Flash 重排序（按语义相关性打分排序，返回前 K）。

| 工具 | 触发条件 | 数据来源 | 返回内容 |
|---|---|---|---|
| `track_person` | 用户提及具体人名/身份 | `person_archive.json` | 完整 `PersonRecord` JSON 或 `{"found":false}` |
| `emotion_timeline` | 模型需要情绪上下文 | `emotion_timeline.json` | 最近 N 条：`{emotion, intensity, date (ISO8601), segment}` |
| `search_chapters` | 用户提及过往话题/事件 | 当前对话章节 | 最佳匹配：`{title, summary (200字符), keywords}` |
| `fetch_chapter_messages` | `search_chapters` 摘要不够详细 | 当前对话消息 | 该章节最多 12 条消息：`{role, content}` |
| `search_memory` | 需要跨对话上下文 | `memory.json` | 匹配的记忆：`{content, keywords, sourceChapter, recallCount}` |

### 对话模式

| 模式 | 系统提示词风格 | Temperature | Top-P |
|---|---|---|---|
| **理性之镜** | 分析性、证据驱动、挑战认知扭曲、要求具体事实 | 0.1 | 0.8 |
| **平衡之镜**（默认） | 叙事分析 + 适度挑战，平衡共情与严谨 | 0.35 | 0.9 |
| **温情之镜** | 共情、温和探索、情感验证 | 0.6 | 0.95 |

所有模式共享相同的 thinking 配置（`thinking: enabled`，`reasoning_effort` 用户可配，默认 `high`）和 `max_tokens: 8192`。

### 上下文窗口策略

棱镜充分利用 DeepSeek 1M token 上下文窗口：

| 对话长度 | 策略 |
|---|---|
| ≤60 条消息（30 轮） | **全文发送** — 所有消息 + 章节索引作为 system 消息注入，让 Agent 知道哪些内容可通过工具检索 |
| >60 条消息 | **窗口模式** — 保留最后 40 条全文，旧消息压缩为章节摘要。Agent 可调用 `search_chapters` / `fetch_chapter_messages` 获取完整原文 |

**语义压缩（trimConversation）：** 保存时，已被章节覆盖的消息替换为 `[已归纳: 第N章「标题」]` 引用 — 比盲目截断更具语义价值。未被覆盖的消息截断至 200 字符。章节摘要上限 600 字符。最后 40 条消息始终保留全文。

### 自动归纳

按对话轮数触发（user+assistant 对），间隔可在设置中配置。

| 类型 | 模型 | Max Tokens | 超时 | Thinking |
|---|---|---|---|---|
| **增量归纳** | Flash | 1024 | 120s | 禁用 |
| **全量重扫** | Flash | 8192 | 180s | 禁用 |

**混合策略：** 每 3 次增量归纳自动触发 1 次全量重扫，保持章节风格和粒度一致。

全量重扫增强上下文：近期情绪轨迹（最近 5 条）、关键人物（提及次数前 5）、活跃盲点模式（最近 5 条）。所有章节重新生成，JSON 响应中的 `startIndex`/`endIndex` 映射回实际消息 ID。

**跨对话记忆：** 每次归纳后，章节 upsert 到 `memory.json`（按标题 + 对话 ID 去重）。记忆库上限 500 条，溢出时裁剪至 300。

### 智能搜索

多关键词非重叠出现次数统计，覆盖标题、消息和章节：

- **标题匹配**：完整查询 → +10，关键词命中 → +5/个
- **消息匹配**：关键词出现 → +2/次，完整查询 → +5
- **章节匹配**：标题关键词 → +3，摘要关键词 → +1，完整查询 → +3-5
- **上下文摘录**：匹配位置周围 50 字符半径提取，20 字符内去重
- **同义词扩展**：~40 组（中英文），覆盖情绪、家庭、爱情、职场、内心模式

### 语义重排序器

用于 `search_chapters` 和 `search_memory` 工具调用：

1. **关键词预筛选**：本地搜索返回前 15 候选
2. **Flash 重排序**：发送 `{查询, 候选[index] 标题 — 摘要}` → Flash 返回 `[3,1,5,2,4]`（排序后的索引）
3. **回退**：Flash 失败时直接返回关键词排序结果

### Liquid Glass 界面

macOS 原生玻璃效果（macOS 26+ `NSGlassWindowBackground`），低版本回退至 `.ultraThinMaterial`。侧边栏和对话面板采用半透明深度层次材质。消息输入框通过 `NSViewRepresentable` 包装 `NSTextView`，实现原生文本编辑体验（自动增高、回车发送、Shift+回车换行）。

---

## 快速开始

```bash
cd "macOS Version" && swift build -c release
open Prism.app
```

需要 macOS 15.0+、Swift 6.0+、DeepSeek API Key（[platform.deepseek.com](https://platform.deepseek.com)）。

首次启动时，8 页新手引导带你完成：欢迎 → 用途 → 功能（4 卡片）→ UI 导览 → API Key 配置 → 对话模式（3 模式卡片）→ iCloud 存储 → 数据与隐私。

---

## 数据与隐私

```
~/Documents/Prism/               （或自定义路径，或 iCloud Drive）
├── conversations.json           # 所有对话和消息
├── config.json                  # 应用设置与 API Key
└── Data/
    ├── person_archive.json      # 人物记录（上限 200，按 lastMentionedAt 排序）
    ├── emotion_timeline.json    # 情绪条目（上限 200）
    ├── blindspots.json          # 盲点记录（上限 300）
    └── memory.json              # 跨对话记忆（上限 500，溢出裁剪至 300）
```

- **100% 本地存储** — 纯 JSON，任意文本编辑器可读
- **仅当前对话上下文发送至 DeepSeek API** — 无持久化服务器端存储
- **无遥测、无分析、无账号**
- **可选 iCloud Drive** 多 Mac 同步（设置中开启）
- **旧版迁移** — 自动将旧 bundle 旁位置存档迁移至统一数据目录

---

## 合规声明

> 本产品系情感分析 Agent，不属于《人工智能拟人化互动服务管理暂行办法》(2026.7.15施行) 所规定的"拟人化互动服务"。本产品不提供持续性情感陪伴、不模拟自然人人格、不诱导情感依赖、不替代专业心理健康服务。未满14周岁请在监护人陪同下使用。

---

## 许可证

[MIT](LICENSE)
