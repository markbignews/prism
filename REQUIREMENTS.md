# 棱镜 / Prism — 需求文档

## 1. 产品概述

**棱镜 (Prism)** 是一款基于 DeepSeek 大语言模型的叙事反思工具。它作为对话伙伴，帮助用户讲述个人故事、识别叙事盲点、看到替代视角，最终找到出口。

### 核心理念

- 不是心理医生，不做诊断，不贴心理标签
- 终极目标：帮用户走到不再需要打开棱镜的那一天
- 一面镜子，而非一个权威

### 两种形态

| | GUI (Prism.app) | CLI (prism) |
|---|---|---|
| **平台** | macOS 15+ | macOS / Linux / Windows |
| **技术栈** | SwiftUI + AppKit | Swift + Foundation |
| **体验** | 桌面原生、Liquid Glass、Markdown | 终端 ANSI 流式输出 |
| **适用** | 日常桌面使用 | 服务器、SSH、CI 环境 |

---

## 2. 目标用户

- 经历复杂人际关系、需要梳理叙事的人
- 对自身认知偏差有觉察意愿的人
- 需要安全倾诉空间但尚未准备好寻求专业帮助的人
- 重视隐私、希望数据留在本地的用户

**不是目标用户：**
- 需要临床诊断或治疗的人（棱镜明确不做诊断）
- 处于危机状态的人（棱镜有安全模式，但不能替代危机热线）

---

## 3. 功能需求

### 3.1 核心对话

| 功能 | GUI | CLI | 说明 |
|---|---|---|---|
| 流式对话 | ✅ | ✅ | DeepSeek API SSE 流式传输 |
| 思考链显示 | ✅ | ✅ | reasoning_content 可见，生成时自动滚动 |
| 对话管理 | ✅ | ✅ | 新建/切换/删除/重命名 |
| 对话记忆 | ✅ | ✅ | 重启恢复上次对话 + 滚动到底部 |
| 消息编辑 | ✅ | ❌ | 编辑后重新发送 |
| 重新生成 | ✅ | ❌ | 重新生成助手回复 |
| 单消息删除 | ✅ | ✅ | GUI 气泡按钮 / CLI `/delmsg` |
| Markdown 渲染 | ✅ | ❌ | 标题/列表/表格/代码块 |
| 页内查找 | ❌ | ✅ | CLI `/find` 当前对话内搜索 |

### 3.2 叙事分析

| 功能 | 说明 |
|---|---|
| **事实/解释分离** | 区分「可观察事实」「用户解释」「情绪体验」「推测」「未知信息」 |
| **多视角叙事** | 故事结构完整时提供 2-3 个替代叙事版本 |
| **阶段感知** | 倾听→清创→缝合→放下，根据用户所处阶段调整回应策略 |
| **安全模式** | 检测自杀/自伤/暴力/虐待/精神异常/未成年人受害 → 暂停叙事分析，仅危机干预 |
| **迎合检测** | `detect_ingratiation` 每轮检测是否过度赞同、回避挑战、镜像叙述无分析 |

### 3.3 对话模式（三种）

| 模式 | 温度 | Top P | 风格 |
|---|---|---|---|
| **理性 (Rational)** | 0.1 | 0.8 | 冷静克制，直奔结论，不共情不安慰 |
| **平衡 (Balanced)** | 0.35 | 0.9 | 默认，共情+分析，叙事多版本拆解 |
| **温情 (Warm)** | 0.6 | 0.95 | 先共情再引导，温暖但不讨好，保持独立判断 |

温度/Top P 由系统内置，用户无需手动调整。首次使用时在引导页选择模式，后续可在设置中切换。


### 3.4 MCP 工具体系（10 个）

所有工具本地执行，0 API 成本，Pro Agent 自主调用（最多 3 轮 tool loop）。

**检索工具：**

| 工具 | 功能 |
|---|---|
| `search_chapters` | 相关度打分搜索历史章节，返回标题、摘要、关键词和原文消息（top 10） |
| `fetch_chapter_messages` | 按章节序号获取全部原文消息（深层检索） |
| `search_memory` | 搜索跨对话记忆库，返回相关叙事摘要和洞察 |

**人物与情绪工具：**

| 工具 | 功能 | Guard 条件 |
|---|---|---|
| `track_person` | 跨对话人物档案追踪 | — |
| `emotion_timeline` | 最近 N 轮情绪趋势 + 恶化检测 | 恶化时 `guard_flag: warning` |

**守卫工具（检测叙事风险）：**

| 工具 | 功能 | Guard 条件 |
|---|---|---|
| `reality_check` | 事实 vs 解释性语言比例（中英文） | 比例 > 2.5 → `warning` |
| `action_check` | 历史意图 vs 实际行动一致性 | 识别自我欺骗式重复 → `warning` |
| `spiral_detect` | 话题是否陷入无位移重复 | 单一情绪 + 强度不降 → `warning` |
| `scan_blindspots` | 扫描解释循环/回避自我/意图-行动差距 | 检测到模式 → `warning` |
| `detect_ingratiation` | **每轮必须调用**：检测上一轮回复是否迎合用户 | 过度赞同/无挑战/镜像无分析 → `warning` |

### 3.5 章节归纳

**触发机制：**
- 自动归纳：每完成 N 轮对话后触发（可配置 2/5/10/关闭）
- 切换对话：自动归纳未处理的新内容
- 手动归纳：侧边栏按钮触发完整重扫
- 休眠保护：对话无新消息时跳过

**混合策略：**
- 默认增量归纳（仅处理上次归纳后的新消息，追加单章）
- 每积累 3 个增量章节后自动完整重扫，统一章节风格和粒度
- 手动触发始终走完整重扫

**章节结构：**
- 标题（≤15 字）、摘要（200-400 字）、关键词（3-6 个）、消息范围
- 完整重扫：3-10 章；增量：每批 1 章
- 归纳成功自动写入跨对话记忆（`memory.json`）

**反馈机制：**
- GUI：蓝色胶囊 `✓ 章节已更新` 2.5s 自动消失；失败弹窗提示原因
- CLI：显示 "已生成 N 个章节" 或失败原因

**存储优化：**
- 超过 40 条的消息：有章节覆盖的替换为 `[已归纳: 第X章「标题」]`，无覆盖的截断 200 字
- 章节摘要自动截断至 600 字

### 3.6 事后流水线（Post-pipeline）

每轮对话后异步执行，`Task.detached` 不阻塞主对话：

1. **情绪标注** (v4-flash) — 提取情绪段及其强度（1-3 个显著情绪）
2. **人物更新** (v4-flash) — 从对话中提取新人，更新已有档案

> 盲点扫描已移至 MCP 工具 `scan_blindspots`，由 v4-pro 自主调用，不再作为后台流水线。

优化措施：
- 2 个调用并行发射（延迟 = 单次调用）
- 短消息跳过：用户最近一条消息 < 5 字不触发（"嗯""好的"等）
- 输入截断：每个 Flash 调用最多读取 `userText.prefix(2000)`
- 失败追踪：错误写入 `postPipelineErrors`，GUI 可观测

### 3.7 跨对话记忆系统

- 归纳生成章节时自动写入 `memory.json`
- 去重：同标题+同对话的章节自动更新而非重复
- 上限：500 条，超出后裁剪为 300 条
- 每次对话检索 top 3 相关记忆注入 System Prompt
- GUI 工具栏按钮打开记忆面板（独立窗口），结构化展示：人物/情绪轨迹/叙事盲点/洞察
- 情绪轨迹按类型去重，强度归一化为百分比（总和 100%）

### 3.8 搜索系统

**GUI 侧边栏搜索**：搜索章节标题和摘要（跨所有对话），点击结果跳转到对应对话并打开章节详情。

**CLI 搜索**：
- `/search <关键词>` — 跨对话章节搜索（相关度打分，top 15）
- `/find <关键词>` — 当前对话页内搜索，`/find` 跳下一个匹配

### 3.9 数据管理

- **数据路径迁移**：GUI 设置页/CLI `/config datapath` 更改路径，自动迁移原有文件到新路径
- **消息删除**：删用户消息自动删配对助手回复（反之亦然），同步清理章节引用、重算归纳书签、调整对话计数
- **启动清理**：自动移除末尾空内容的助手消息残留（崩溃/中断保护）

### 3.10 UI/UX（GUI 特定）

- **强调色**：统一蓝色（除对话气泡外）
- **对话气泡**：用户蓝色底白字（iMessage 风格），助手灰色底
- **气泡操作按钮**：在气泡下方外侧，用户右对齐/助手左对齐，与气泡边框留 4px 间距
  - 用户气泡：复制 + 编辑
  - 助手气泡：复制 + 重新生成 + 删除
- **输入框**：毛玻璃 Liquid Glass 效果，圆角 18（与气泡一致）
- **发送按钮**：`arrow.up.circle.fill` 24pt，蓝色，输入框内右侧居中
- **停止按钮**：`stop.circle.fill` 24pt，红色，同位置替换
- **跳到底部按钮**：圆角 18，毛玻璃
- **章节列表**：蓝色跳转原文按钮 + 信息按钮打开详情
- **章节详情**：标题旁蓝色胶囊 "→ 跳转至原文"，点击关闭弹窗并滚动到源消息
- **折叠箭头**：22×22px 点击区域
- **侧边栏对话图标**：书籍图标

### 3.11 设置与配置

| 配置项 | 默认值 | 说明 |
|---|---|---|
| DeepSeek API Key | — | 必填 |
| Base URL | `https://api.deepseek.com` | 可自定义 |
| 对话模型 | `deepseek-v4-pro` | V4 Pro / V4 Flash 二选一 |
| 回复长度 | 标准 | 简洁/标准/详细 三段，注入 System Prompt |
| 深度思考 | 开启 | Pro: 默认开；Flash: 默认开（归纳需要） |
| 推理强度 | high | high / max |
| 归纳频率 | 每 5 轮 | 0/2/5/10 |
| 对话模式 | 平衡 | 理性/平衡/温情（引导页选择，设置不可见） |
| iCloud 存储 | 关闭 | 开启后数据存 iCloud Drive（仅 macOS），关闭为本地 |
| 界面语言 | 简体中文 | 简/繁/英 |
| 数据路径 | 平台自适应 | macOS: `~/Documents/Prism`; Linux: `~/.local/share/prism`; Windows: `%APPDATA%/Prism` |

> 温度/Top P/Presence Penalty/Frequency Penalty/Max Tokens 由系统内置，用户界面不暴露。

### 3.12 合规

- **安全红线**：System Prompt 级安全规则（自杀/自伤/虐待红线）
- **边界声明**：不诊断、不贴心理标签、不冒充医生或治疗师

---

## 4. 非功能需求

### 4.1 数据与隐私

- 所有对话数据 100% 本地存储
- 仅当前对话上下文发送给 DeepSeek API
- 不收集遥测、不上传历史记录
- 跨对话记忆本地存储，检索不调额外 API
- 数据目录结构（macOS 示例）：

```
~/Documents/Prism/                      # macOS（与 GUI 共享）
~/.local/share/prism/                   # Linux
%APPDATA%/Prism/                        # Windows
├── config.json                         # API Key、模型参数、模式、iCloud
├── conversations.json                  # 对话、消息、章节
└── Data/
    ├── person_archive.json             # 人物档案
    ├── emotion_timeline.json           # 情绪时间线
    ├── blindspots.json                 # 盲点记录
    └── memory.json                     # 跨对话记忆
```

### 4.2 性能

- 流式输出延迟 < 500ms 首 token
- 归纳分析（Flash 模型）< 30s
- Post-pipeline 2 个 Flash 调用并行
- 存储：旧消息语义压缩为章节引用
- 窗口化：对话 ≤60 条享完整上下文，超长对话才触发压缩
- GUI 消息列表 LazyVStack + 发送中无节流自动滚动
- MCP 工具执行间 `Task.yield()` 保持 UI 响应

### 4.3 可靠性

- API 错误友好提示
- 归纳失败不影响对话功能
- 事后流水线各步骤独立运行，互不影响，失败写入 `postPipelineErrors`
- `saveConfig` 记录写入错误日志
- 所有归纳 guard 失败均有 `lastSummaryStatus` 反馈
- `isSummarizing` 卡住自动恢复

### 4.4 多语言

| 语言 | GUI | CLI |
|---|---|---|
| 简体中文 | ✅ | ✅ |
| 繁體中文 | ✅ | ✅ |
| English | ✅ | ✅ |

所有 UI 文案（按钮、标签、提示）均通过 L10n 系统三语适配。

---

## 5. 系统架构

```
┌──────────────────────────────────────────────────────────┐
│                      PrismApp (GUI)                      │
├──────────────────────────────────────────────────────────┤
│  ContentView / SidebarView / ChatView / ComposerView     │
│  MessageBubble / ChapterRow / ChapterDetailView          │
│  MemoryPanelView / SettingsView / OnboardingView         │
│  MarkdownText / GlassBackground (Liquid Glass)           │
├──────────────────────────────────────────────────────────┤
│              ChatStore (核心状态管理)                      │
│  对话 CRUD / send() / Agent Loop / 归纳 / Post-pipeline   │
│  buildWindowedMessages / trimConversation                 │
│  smartSearch / searchMemory / upsertMemory                │
│  deleteMessage (配对删除) / reloadStorage / selectConversation│
├──────────────┬───────────────────────────────────────────┤
│ DeepSeekClient│  ToolRegistry (10 MCP 工具)              │
│ stream()     │  检索: search_chapters / fetch_chapter    │
│ summarize()  │  人物: track_person / emotion_timeline     │
│ fullSummarize│  守卫: reality / action / spiral           │
│ (mode-aware) │        scan_blindspots / detect_ingratiation│
│              │  记忆: search_memory                       │
├──────────────┴───────────────────────────────────────────┤
│  Models.swift / AgentPrompt (3 模式) / StoryMemory       │
│  AppSettings / L10n (三语)                               │
└──────────────────────────────────────────────────────────┘
```

**Agent 层（2 模型，6 场景）：**

| 模型 | 场景 | 职责 |
|---|---|---|
| **v4-pro** | 主对话 | 流式对话 + 10 个 MCP 工具自主调用（最多 3 轮） |
| | 模式适配 | 根据理性/平衡/温情调整温度、Top P 和 System Prompt |
| **v4-flash** | 增量归纳 | performSummarization：新消息 → 单章 |
| | 全量归纳 | fullReSummarize：重扫全部 → 3-10 章 |
| | 标题更新 | updateConversationTitle：根据章节生成标题 |
| | 情绪标注 | Post-pipeline：情绪维度和强度 |
| | 人物更新 | Post-pipeline：人物档案更新 |

**上下文策略：**
- 对话 ≤60 条 → 全文发送 + 章节索引 + 跨对话记忆（top 3）
- 对话 >60 条 → 最近 40 条全文 + 历史压缩为章节摘要
- Agent 可通过 `search_chapters` / `fetch_chapter_messages` 检索被压缩的原文

**归纳策略：**
- 增量为主（>3 次增量后自动完整重扫统一风格）
- 休眠保护（无新消息不重复归纳）
- 手动始终完整重扫
- 归纳成功自动写入 `memory.json`（跨对话记忆，不额外调 API）

---

## 6. CLI 命令参考

```
/help                    显示帮助
/new                     新建对话
/list                    列出所有对话（含摘要）
/switch <n>              切换到第 n 个对话
/delete <n>              删除第 n 个对话
/delmsg <n>              删除当前对话第 n 条消息（配对删除）
/rename <n> <x>          重命名第 n 个对话
/search <keyword>         跨对话章节搜索（相关度排序）
/find <keyword>           当前对话页内搜索（/find 跳下一个）
/info                    查看当前对话摘要（章节/人物/情绪）
/history [n]              查看最近 n 条消息（含序号，默认 10）
/chapters                列出当前对话章节
/chapter <n>             查看第 n 个章节详情
/thinking                切换思考链显示
/settings                查看当前设置
/summarize               手动归纳当前对话
/config <k> <v>          修改设置项（含 mode/datapath）
/lang zh|zh-hant|en      切换语言
/reset                   还原所有数据（需 --confirm）
/exit                    退出
```

---

## 7. 安全与边界

### 系统提示词核心规则

1. 承认感受，不自动承认用户的解释是事实
2. 区分「可观察事实」「用户解释」「情绪体验」「推测」「未知信息」
3. 先判断用户阶段：需要被听见 / 需要理清 / 需要完整回看 / 需要放下
4. 情绪强烈但叙述碎片化 → 先共情止血，只问一个关键问题
5. 故事结构完整时帮用户看见自己走过的路
6. 有些遗憾就是遗憾，不需要说成「最好的安排」
7. 不诊断、不贴心理标签、不冒充医生或治疗师、不替用户做决定
8. 出现安全红线 → 立即切换安全干预模式，暂停叙事分析

### 多叙事版本触发条件

全部满足才触发：
- 用户提供了具体事件、关键人物、大致时间线
- 描述了双方行为（不是仅对方）
- 表达了感受和困惑
- 不是首次倾诉阶段

触发后提供 2-3 个版本：用户当前解释 / 对用户不利但需面对的 / 中立观察者视角。

### 迎合检测（detect_ingratiation）

每轮对话强制调用，检测信号：
- 过度赞同（"你说得对" 等 ≥2 次）
- 无挑战性提问（>100 字但无"不过""换个角度"等转折）
- 镜像叙述无分析（"你感到""你经历" ≥3 次且无"背后可能是"）
- 过度称赞（"你很棒""你勇敢" ≥2 次）

`guard_flag: warning` 时要求模型更独立、引入不同视角、适当挑战用户。

---

## 8. 项目信息

- **仓库位置**：`~/Documents/chatbot/`
- **当前版本**：1.0 (2026-06-29)
- **GUI 构建**：`cd GUI && swift build -c release` → 复制 `Prism.app/Contents/MacOS/Prism`
- **CLI 构建**：`cd CLI && swift build -c release` → `CLI/prism`
- **语言**：Swift 6.0+
- **依赖**：零第三方
- **文件编码**：UTF-8
- **换行符**：LF
