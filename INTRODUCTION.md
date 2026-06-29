# 棱镜 Prism — 系统介绍

## 是什么

棱镜是叙事反思工具。它基于 DeepSeek 大语言模型，通过对话帮你把故事讲完整、看见盲点、找到出口。

不是心理医生，不做诊断，不贴标签。是一面棱镜。

## 架构概览

```
用户输入 → buildWindowedMessages → Flash 预处理 → Pro Agent (MCP 工具) → 归纳
                 │                       │              │              │
           智能窗口化            1次Flash统一检测      5个MCP检索    混合策略
           ≤60全文              guard+情绪+人物       工具可选       增量+定期重扫
```

### 质量守护系统（Flash 预处理管线）

**位置**：在主模型之前运行，不阻塞流式输出。

**触发**：每轮对话自动执行（代码强制，非模型决策），首次对话跳过（无助手回复可分析）。

**API 调用**：1 次 Flash，覆盖全部任务。

```
用户消息
  │
  ├── [阻塞] Flash 预处理 (~500ms)
  │       └─ 统一分析：
  │            reality（事实vs解释比例）
  │            spiral（情绪漩涡检测）
  │            blindspots（叙事盲点：解释循环/回避自我/意图-行动差距）
  │            ingratiation（助手迎合倾向检测）
  │            action_hollow（历史空头承诺比对）
  │            safety（安全信号：自杀/自伤/暴力/虐待，代码强制优先）
  │            emotions（情绪标注，写入 emotion_timeline.json）
  │            persons（人物提取，含别名解析，写入 person_archive.json）
  │
  ├── [安全覆写] safety == "crisis" → 跳过主模型，直接返回安全引导（含热线）
  │               上轮安全 → 正常注入 supervisorHint
  │
  ├── [阻塞] 主模型回复（guard hint 通过 supervisorHint 参数注入，
  │         自然融入回复，不生硬转折）
  │
  └── [异步] 归档更新（情绪/人物/盲点写入本地 JSON）
```

**降级保护**：Flash 调用失败时 guard 全部默认 `flag: "ok"`，不影响对话。

### Agent 层（2 个 Agent + 1 条管线）

| Agent | 模型 | 是什么 | 请求次数/轮 |
|---|---|---|---|
| **主对话 Agent** | Pro | 流式对话，可调用 5 个 MCP 检索工具 | 1 次 |
| **章节归纳 Agent** | Flash | 将对话压缩为带标题/摘要/关键词的章节 | 0-1 次 |
| **预处理管线** | Flash | guard + 情绪 + 人物 + 盲点统一检测 | 1 次（从第二轮起） |

正常一轮：1 次 Flash + 1 次 Pro。完整一轮：1 Flash + 1 Pro + 1 归纳。

### MCP 检索工具（5 个）

Agent 可以自主调用以下工具。所有工具本地执行，不产生 API 费用。

| 工具 | 场景 | 返回 | 是否调用 AI |
|---|---|---|---|
| `search_chapters` | 用户提到过去话题 | 标题、摘要、关键词（不含原文） | keyword 本地 + Flash 语义重排序 |
| `fetch_chapter_messages` | 摘要不够详细，需要阅读完整原文 | 指定章节前 12 条消息 | ❌ 纯本地 |
| `track_person` | 查某人是否在历史对话中出现过 | 跨对话人物档案（含别名解析） | ❌ 纯本地 |
| `emotion_timeline` | 了解近期情绪状态 | 原始情绪序列（模型自行判断趋势） | ❌ 纯本地 |
| `search_memory` | 跨对话记忆检索 | 相关记忆条目 | keyword 本地 + Flash 语义重排序 |

**注意**：质量守护由预处理管线自动完成，不暴露为 MCP 工具。Agent 无需自行决策何时调用 guard。

### 上下文窗口策略

DeepSeek Pro 提供 1M token 上下文。棱镜的策略：

| 对话长度 | 策略 |
|---|---|
| ≤ 60 条（30 轮） | 全文发送 + 章节索引（享完整上下文） |
| > 60 条 | 最近 40 条全文 + 历史压缩为章节摘要 |

压缩不是丢弃——Agent 可通过 `search_chapters` / `fetch_chapter_messages` 检索任何被压缩的原文。**信息可找回，token 不浪费。**

### 归纳系统

**触发：**
- 自动：每 N 轮对话后（默认 5，可配 2/5/10/关）
- 切换对话：自动归纳剩余未处理内容
- 手动：侧边栏按钮

**混合策略：**
- 增量为主：只处理上次归纳后的新消息，追加单章（省 token）
- 每 3 次增量 → 完整重扫：合并为 3-10 章统一风格
- 休眠保护：对话无新消息时跳过（不浪费 API）

**丰富上下文**：归纳 Flash 调用时会附带预处理管线产出的情绪轨迹、关键人物、盲点模式，帮助生成更有洞察力的章节摘要。

**存储：**
- 超过 40 条的消息：有章节覆盖 → 替换为 `[已归纳: 第X章「标题」]`
- 无覆盖 → 截断至 200 字

### 数据存储

```
~/Documents/Prism/                      # macOS（默认路径，平台自适应）
├── config.json                         # API Key、模型、模式、iCloud
├── conversations.json                  # 对话、消息、章节
└── Data/
    ├── person_archive.json   # 人物档案
    ├── emotion_timeline.json # 情绪时间线
    └── blindspots.json       # 盲点记录
```

100% 本地，不收集遥测，不上传历史。

**归档上限：**
| 存档 | 上限 | 裁剪策略 |
|---|---|---|
| `emotion_timeline.json` | 200 条 | 保留最新 |
| `person_archive.json` | 200 条 | 按最后提及时间保留 |
| `blindspots.json` | 300 条 | 按创建时间保留 |
| `memory.json` | 500 条 | 保留最新 |

## 项目结构

```
chatbot/
├── GUI/                     # macOS 桌面应用
│   ├── Sources/Prism/
│   │   ├── ContentView.swift    # 主 UI：气泡、输入框、章节详情
│   │   ├── ChatStore.swift      # 核心状态：send/工具循环/窗口化
│   │   ├── PrePipeline.swift    # 预处理管线（guard + 安全 + 搜索重排序）
│   │   ├── DeepSeekClient.swift # API 通信：stream / summarize
│   │   ├── Tools.swift          # 5 个 MCP 检索工具定义和执行
│   │   ├── AgentPrompt.swift    # 系统提示词 + 归纳提示词 + 重排序提示词
│   │   ├── SearchExpander.swift # 同义词扩展（30 组语义群）
│   │   ├── StoryMemory.swift    # 本地章节记忆和关键词检索
│   │   ├── MarkdownText.swift   # 自定义 Markdown 渲染
│   │   ├── Models.swift         # 数据模型
│   │   ├── AppSettings.swift    # 配置管理
│   │   ├── L10n.swift           # 三语本地化
│   │   ├── PrismApp.swift       # App 入口
│   │   ├── SettingsView.swift   # 设置界面
│   │   └── OnboardingView.swift # 首次使用引导
│   ├── Prism.app/               # 构建产物
│   └── Package.swift
├── CLI/                     # 命令行版本
├── REQUIREMENTS.md          # 需求文档
└── INTRODUCTION.md          # 本文档
```

## 设计决策

**为什么去掉本地守卫工具，改用 Flash 预处理？**
- 关键词匹配的 guard 对上下文理解不够，误报率高
- Flash 模型的一次调用即可覆盖全部 5 个 guard 维度 + 情绪/人物/盲点提取
- 合并后 API 调用次数不变（1 Flash + 1 Pro），但守卫精度质的提升
- 代码强制每轮执行，不依赖模型自觉性调用工具

**为什么预处理在主模型之前？**
- guard 信号在主模型生成回复前就可用，自然融入回复，不生硬转折
- 相比于异步轮询的无割裂感方案，延迟仅 +500ms

**为什么 Agent + MCP 混合？**
- 叙事反思需要上下文感知的检索——Agent 理解用户问什么才能决定查哪个章节
- 检索工具纯本地计算，不影响延迟和 API 成本
- Agent 自主决策 > 预先注入所有上下文

**为什么窗口化有阈值？**
- DeepSeek 1M 上下文是优势，不应为了省 token 牺牲体验
- 日常对话（≤60 条）完整保留，只有极端长对话才压缩
- 压缩不等于丢弃——MCP 工具可找回原文

**为什么归纳混合策略？**
- 每次都完整重扫浪费 token，纯增量会导致章节风格不统一
- 3 次增量 + 1 次重扫 = 平衡效率和一致性
- 归纳时附带预处理管线产出的情绪/人物/盲点数据，章节更有洞察

**为什么预处理管线用 Flash？**
- Flash 比 Pro 便宜几个数量级
- Flash 语义理解能力远超关键词匹配，且一次调用覆盖全部任务

**为什么搜索用 keyword + Flash 两步式？**
- 纯关键词慢且不准（"被PUA"搜不到"精神控制"），纯 embedding 需要额外 API
- 两步式：keyword 微秒级过滤出 top 15 → Flash 语义重排序 → 准确的 top 5
- Flash 仅在小候选集上运行，延迟可控（~300ms），失败时降级到关键词结果

**为什么人物提取要解析别名？**
- 用户对同一人的称呼会变："我男朋友"→"张伟"→"前任"
- Flash 预处理时传入已知人物列表，要求复用标准名称
- 避免同一人分裂为多条互不关联的档案记录

**为什么 emotion_timeline 不再返回趋势判断？**
- 3 个数据点的硬编码趋势判断（3 条全负 = deteriorating）统计上无意义
- 改为返回原始情绪序列，由主模型自行判断趋势——模型比硬编码阈值聪明得多

**为什么 searchChapters 不再返回原文消息？**
- 每次搜索返回 10 章 × 每章 8 条 = 80 条消息，模型需消化大量非必要上下文
- 如需原文，Agent 可单独调 fetch_chapter_messages
- 默认只返回标题 + 摘要 + 关键词，按需取原文

## 构建

```bash
# GUI (macOS)
cd GUI
swift build -c release
cp .build/arm64-apple-macosx/release/Prism Prism.app/Contents/MacOS/Prism

# CLI
cd CLI
swift build -c release
```
