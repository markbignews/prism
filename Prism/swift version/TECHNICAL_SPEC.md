# Prism (macOS SwiftUI Version) - 本地叙事反思与认知守护伴侣
## 技术文档与核心代码规范 (Technical Specifications & Code Architecture)

---

## 一、 项目概述与设计愿景 (Project Overview & Vision)

**Prism (棱镜)** 是一款运行于 macOS 原生平台（SwiftUI + AppKit）的**本地优先、尊重隐私的情感分析与认知反思 Agent**。

区别于传统的迎合型或伴侣型 AI，Prism 定位于用户**“思维的镜子”**。它通过追踪个人叙事、审查认知扭曲、捕获情绪轨迹和发现逻辑盲点，引导用户客观审视自身叙事。项目严格遵循**技术中立与数据本地化**设计，数据以纯文本 JSON 格式安全存放于用户本地（或 iCloud Drive），通过高保真 **Liquid Glass (毛玻璃)** 视觉与三阶智能分析管线，实现苹果生态下的极致体验。

---

## 二、 架构模式与数据流设计 (Architecture & Data Flow)

Prism 采用 **Agent-Facade 设计模式** 组织数据与 UI 绑定：

```
[ SwiftUI 视图层 ] (ContentView / SidebarView / ChatView / SettingsView / OnboardingView)
       │
       │ @EnvironmentObject / @Published
       ▼
[ ChatStore (ObservableObject 外观层) ] ──(agentStateDidChange)──▶ 触发 SwiftUI 重绘
       │
       ▼
[ ChatAgent (@MainActor — 核心业务逻辑编排) ]
       ├── DeepSeekClient        # HTTP 客户端：SSE 流式解析 + 非流式归纳
       ├── ToolRegistry          # 6 个 MCP 风格本地工具 schema 注册与原生执行
       ├── AgentPrompt           # 系统提示词 (三种镜模式) + 归纳 + 重排序
       ├── StoryMemory           # 基于章节的本地上下文记忆与关键词提取
       ├── PrePipeline           # 单次统一 Flash JSON 调用 (守护+情绪+人物+盲点)
       └── SearchExpander        # ~40 组中英文情绪/爱情/职场同义词语义扩展
```

* **Token 流式渲染**：`ChatStore` 作为一个轻量外观层（Facade），将所有操作委托给 `ChatAgent`。在 DeepSeek-R1 流式传输期间，解析出的 token 直接追加到内存 `Conversation` 模型中并同步调用 `agentStateDidChange()`，使 SwiftUI 气泡在 token 到达时以 120Hz 刷新，不设任何中间缓冲。

---

## 三、 三阶对话生命周期管线 (Three-Stage Pipeline)

每一次用户发送消息，均会在后台启动一轮闭环的流水线分析：

```
                      【 用户发送消息 (trimmedText) 】
                                     │
                                     ▼
 ┌───────────────────────────────────────────────────────────────────────┐
 │ 1. 记忆写入与提取 (StoryMemory)                                         │
 │    - 按段落拆分输入，实时创建或追加本地 `StoryChapter`                   │
 └───────────────────────────────────┬───────────────────────────────────┘
                                     │
                                     ▼
 ┌───────────────────────────────────────────────────────────────────────┐
 │ 2. 前置守护分析 (Pre-Pipeline - 单次 Flash API JSON 调用)               │
 │    - 6 维度守护监控 (Reality / Spiral / Ingratiation 等)                │
 │    - 提取情绪及人物实体 (Emotion & Person)                             │
 │    - 盲点审计与自杀/危机干预拦截 (Safety Crisis Override)                │
 └───────────────────────────────────┬───────────────────────────────────┘
                                     │
                      ┌──────────────┴──────────────┐
                      ▼ (safety.flag == "ok")        ▼ (safety.flag == "crisis")
 ┌──────────────────────────────────────────┐   ┌────────────────────────┐
 │ 3. 主模型对话周期 (DeepSeek R1 Stream)    │   │  4. 触发硬性危机干预    │
 │    - 注入 [监督者方向] 守护提示          │   │  - 暂停主模型分析       │
 │    - 注入 Context 本地检索与跨对话记忆    │   │  - 强制流式打出本地援助  │
 │    - 激活 MCP 工具循环 (最多 3 轮)        │   │  - 状态写入 UserDefaults│
 └────────────────────┬─────────────────────┘   └────────────────────────┘
                      │
                      ▼
 ┌───────────────────────────────────────────────────────────────────────┐
 │ 5. 后处理归纳管道 (Post-Pipeline)                                      │
 │    - 将 PrePipeline 结果异步合并入本地 JSON 存档库                      │
 │    - 周期性触发自动总结 (每 3 次增量归纳 ➡️ 自动触发 1 次全量重扫)          │
 │    - 更新会话大标题并原子写入 conversations.json                         │
 └───────────────────────────────────────────────────────────────────────┘
```

---

## 四、 核心技术模块规范

### 1. 预处理管线与守护模式限制 (Pre-Pipeline Guarding)
在发送主对话前，程序发送最近 10 条消息、已知人物列表和历史盲点至 Flash 模型，要求其返回严格 JSON。**首轮对话跳过此管线**（因为尚无助手回复可供 ingratiation 评估）。

| 维度 | 检测逻辑 | 告警/警告阈值 |
| :--- | :--- | :--- |
| `reality` (现实感) | 统计解释性词汇（"我觉得""这意味着"）与可观察事实（具体人名/时间/引述原话）的比例。 | 解释 : 事实 ＞ 2.5:1 |
| `spiral` (情绪漩涡) | 比较多轮的情绪变化和话题走向。 | 相同情绪 + 相同话题 + 持续多轮无认知位移 |
| `blindspots` (认知盲点) | 三项检查：解释循环、回避自我（大量描述他人忽略自己）、意图与行动落差。 | 任一子项为阳性 |
| `ingratiation` (迎合) | 扫描上一条助手消息是否存在过度赞同、情感迎合、回避合理挑战、镜像重复。 | 严格过滤，防范大模型情感谄媚 |
| `action_hollow` (空谈) | 用户的当前意图匹配历史持续存在的盲点模式。 | 匹配已记录的 persistent 盲点 |
| `safety` (安全危机) | 检测自残、自杀、精神错乱、暴力侵害、未成年人受害或直接求助。 | 任何明确信号 ➡️ 标记为 "crisis" 并强制接管主模型 |

* **危机干预状态机**：当 safety 变为 `crisis` 时，主程序暂停叙事，直接将本地安全回复（中/英文）以每 8 字符一挂起（`Task.yield()`）的速度模拟打字打在 UI 上。危机标记写入 `UserDefaults`，供下一轮重新注入。直到 Flash 返回 `safety.flag == "ok"` 时才自动清除该状态。

---

### 2. 本地工具 (7 MCP-style Tools)
Prism 注册了 6 个本地工具供模型按需调度。工具本身不请求任何云端接口，只读写本地数据：

| 工具名 | 数据来源 | 返回内容规范 |
| :--- | :--- | :--- |
| `track_person` | `person_archive.json` | 匹配特定人名，返回人物的身份角色、提及次数、情感变化弧线及历史记事。 |
| `emotion_timeline` | `emotion_timeline.json` | 返回最近 N 条情绪条目：`{emotion, intensity, date, segment}`。 |
| `search_chapters` | 当前对话章节 `StoryChapter` | 模糊搜索匹配章节，返回 `{title, summary, keywords}`。 |
| `fetch_chapter_messages` | 当前会话消息 `ChatMessage` | 基于 1-based 索引，返回该章节覆盖的最多 12 条对话明细。 |
| `search_memory` | 跨对话归档 `memory.json` | 返回包含同义词扩展和重排序后相关的跨对话核心记忆。 |
| `manage_narrative_timeline` | `narrative_timeline.json` | 按用户故事中事件实际发生或持续的时间列出、添加或修正节点；支持时间段、日期及混合节点，归属不清时先向用户澄清。 |

* **两阶段语义检索与重排序器 (Semantic Re-ranker)**：
  在执行 `search_chapters` 和 `search_memory` 时，首先在本地利用关键词和同义词进行快速初筛（前 15 候选），随后将候选发送给 Flash 模型进行**语义重排序（Re-ranking）**，由模型返回最优排序索引，若 Flash 异常则自动降级回退至本地关键词排序。

---

### 3. 上下文窗口与自动归纳语义压缩策略 (Context Window & Trimming)
为了最大化利用长上下文窗口并控制 API 成本，Prism 采用分段压缩机制：
* **≤60 条消息**：全文发送，并在 system 提示词中注入章节索引，明确提示 Agent 哪些过往记忆可以用工具精确调取。
* **>60 条消息 (窗口模式)**：仅保留最后 40 条消息的全文。其余更旧的历史消息执行**语义压缩（`trimConversation`）**：
  * 被章节覆盖的消息在保存时物理替换为 `[已归纳: 第N章「标题」]`。
  * 未被章节覆盖的其余消息文本截断至 200 字符。
  * 章节摘要截断至 600 字符。

---

### 4. 自动归纳混合策略 (Summary Mechanics)
对话在达到特定轮数时（于后台 Deselect 或轮数满额）异步触发章节归纳。

* **增量归纳 (Incremental Summarization)**：使用 Flash 模型，读取最近 3 个章节及最新消息，返回增量 `{title, summary, keywords}` 追加到章节队列，同步写入跨对话记忆。
* **全量重扫 (Full Re-Summarize)**：每执行 **3 次增量归纳，自动触发 1 次全量重扫**。向模型发送完整对话历史、最近情绪轨迹（前 5 条）、高频人物（前 5 人）及活跃盲点。模型重构整个章节列表，返回包含 `startIndex` 与 `endIndex` 的 JSON 数组，映射并重置消息 ID 引用，保持全文章节风格和粒度完全一致。

---

## 五、 本地存储模型与目录规范 (Persistence & Folder Tree)

所有本地数据一律存放于 `~/Documents/Prism/` 中（可通过设置面板自定义至 iCloud Drive 实现多端同步）：

```
~/Documents/Prism/
├── conversations.json           # 核心会话数据库（原子写入，防断电文件损坏）
├── config.json                  # 应用设置、配置参数及 API Key
└── Data/                        # 后置分析数据库文件夹
    ├── person_archive.json      # 人物归档记录（上限 200 条，按 lastMentionedAt 排序）
    ├── emotion_timeline.json    # 情绪时间轴数据（上限 200 条）
    ├── narrative_timeline.json  # 按故事内实际发生时间排列的叙事事件
    ├── blindspots.json          # 认知盲点历史记录（上限 300 条）
    └── memory.json              # 跨会话核心知识库记忆（上限 500 条，溢出自动裁剪至 300 条）
```

### 5.1 性能优化计划（写盘节流，2026-07）

**现状瓶颈**（`ChatAgent.swift` 事实）：

| 问题 | 现状 |
|---|---|
| 全量同步写盘 | `save()` 每次对全部会话 `JSONEncoder().encode` + `data.write(.atomic)`，运行在 `@MainActor` 上，操作时阻塞 UI |
| 调用点过多 | `save()` 调用点 16 处（发送、工具调用、删除、改名、摘要等每阶段一次），每次全量写 |
| 启动同步加载 | `load()` 启动时同步 decode 整个 `conversations.json` |

**优化方案**：

1. **写盘节流合并**：`save()` 改为置 dirty 标记 + 取消上一个 pending 写 + 调度延迟约 500ms 的合并写；连续操作只写最后一次；IO 写盘移至后台队列（encode 留在主线程，纯 CPU 开销可接受）；
2. **退出前 flush**（正确性关键）：`scenePhase` 转后台 / `willTerminate` 时同步写一次并取消 pending，防止节流导致退出丢数据；保留 `atomic` 写与 `trimConversation` 语义；
3. **启动加载异步化**（可选）：`load()` 改为后台 decode、完成后主线程应用，注意 init 时序。

**范围边界**：不改数据格式、不改 agent 逻辑、不做 SwiftData/SQLite 迁移、不做备份导出与检索增强。

**工作量**：核心（1+2）约 2 天；加启动异步约 3 天。

### 5.2 数据一致性：删除与孤儿清理

> 参考来源：note/ARCHITECTURE.md「删除一致性」设计（唯一删除入口 + 启动对账孤儿清扫），此处仅取其适用于 Prism JSON 架构的部分。

**现状问题**：`conversations.json` 与 `Data/` 存档（person/emotion/blindspots/memory）之间无参照关系；删除会话后，存档中引用该会话的记录成为孤儿数据，长期累积会污染记忆召回与搜索。

**改进**：

1. **统一删除入口**：所有删除操作（删除会话、resetAll）经由单一方法，按会话 ID 级联清理存档：
   - `emotion_timeline.json`：删除 `conversationID` 匹配项；
   - `blindspots.json`：删除 `conversationID` 匹配项；
   - `memory.json`：删除 `sourceConversationID` 匹配项；
   - `person_archive.json`：只清理 `notes` 中引用该会话的增量，保留人物本体；
2. **启动对账**（轻量）：启动时扫描存档中不存在的 `conversationID` 并删除孤儿条目，与 5.1 的加载流程合并执行，不增加启动耗时。

### 5.3 消息模型演进参考（暂不实施）

note 架构的教训：消息若作为整包 blob 持久化，每次追加都会全量重写（长对话 O(n²) 写入放大）。Prism 当前 `conversations.json` 全量存储即属此类，5.1 的节流合并已缓解写频率；若未来会话量或单会话规模持续增长，可按会话拆分为独立文件（`Data/conversations/<id>.json`），只写变更的会话。当前不实施。

---

## 六、 命名及界面代码规范 (`Package.swift` 结构)

1. **状态更新通知机制**：`ChatAgent` 执行的所有更新都必须在 `@MainActor` 中执行，并通过 `delegate?.agentStateDidChange()` 让 UI 状态外观层 `ChatStore` 发送 `objectWillChange.send()`。
2. **原生 Markdown 渲染 (`MarkdownText.swift`)**：不依赖第三方包。手动解析 markdown 到 `MarkdownBlock` 抽象语法树，利用 SwiftUI `Grid` 渲染高保真表格，使用原生的 `Text` 组装粗体、斜体、链接、代码块及列表。
3. **输入框弹性排版 (`MacEditor.swift`)**：利用 `NSViewRepresentable` 封装 AppKit 的 `NSTextView`，以便完美控制 macOS 下的回车直接发送、`Shift + Enter` 换行以及输入框随内容自动拉伸的布局。
4. **磨砂微透效果实现 (`GlassBackground.swift`)**：
   * 原生支持 macOS 26 `glassEffect(Glass.regular)`。
   * 对于低版本自适应降级：使用 `.ultraThinMaterial` 模拟磨砂度，外层套两圈不同透明度的 Stroke 边框，并在左上角使用 mask 混合遮罩，在老系统上也能完美折射光泽感。
