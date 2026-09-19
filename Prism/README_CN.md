<p align="center">
  <img src="assets/icon.png" alt="棱镜" width="128" style="border-radius: 24px;"/>
</p>

<h1 align="center">棱镜 / Prism</h1>

<p align="center">
  一个用于理解个人叙事、情绪和反复出现模式的工作空间，数据保存在本地，模型在远程运行。
</p>

<p align="center">
  <strong>本地数据存储 · 远程模型推理</strong><br>
  SwiftUI · macOS 15+ · Apple Silicon
</p>

<p align="center">
  <img src="https://img.shields.io/badge/status-active%20development-6f42c1" alt="Active development"/>
  <img src="https://img.shields.io/badge/macOS-SwiftUI-blue" alt="macOS SwiftUI"/>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README_CN.md">简体中文</a>
</p>

---

## 棱镜是什么？

棱镜是一个**本地数据存储、远程模型推理的叙事分析工具**，通过兼容 DeepSeek 的 API 工作。它帮助你回看自己写下的内容，观察情绪变化，按照事件实际发生的时间整理经历，并发现当下容易忽略的模式。

棱镜不是离线模型。对话、索引和分析档案会保存在本地，但每次依赖模型的功能运行时，所需的对话上下文和相关本地检索结果都会发送到你配置的 API 端点。

棱镜并不是一个持续陪伴型产品。它更像一个分析工作空间：会追问缺失的事实、挑战未经验证的解释，并提示可能存在的盲点，而不是简单地附和你。

> 棱镜不是心理治疗师、医生、急救服务，也不能替代专业帮助。

## 棱镜包含的能力

棱镜将以下能力整合在一起：

- 面向 Apple Silicon Mac 的原生 SwiftUI 客户端
- 情绪追踪、叙事时间轴、章节、人物、记忆和盲点
- 理性、平衡、温情三种回应方式：共用同一事实判断与安全边界，只改变表达
- 检测到危机信号时可以中断常规模型流程的本地安全守护
- 需要研究依据时的心理学联网检索：仅调用 DeepSeek 官方搜索，不接入第三方搜索服务
- 本地 SQLite 持久化，不内置遥测、分析或账号系统

## 核心亮点

### 看见故事的结构，而不只是最新一条消息

棱镜会把长对话整理成章节，并为重要内容建立可搜索索引。当你后来提到过去的事件时，它可以检索相关上下文。

### 区分叙事时间和消息时间

只有当事件的日期或时间段来自你的叙述时，棱镜才会把它放入叙事时间轴。你发送消息的时间不会被悄悄当成事件发生时间。

### 用证据发现模式

质量守护会检查解释循环、情绪漩涡、意图与行动的落差、过度迎合以及具体事实不足等情况。告警会以结构化指导的形式传给主模型，帮助回答保持有依据，而不会替代模型本身的判断。

### 按需查找心理学依据

当问题明确需要心理学研究、概念解释或专业资料时，主模型可以调用 `search_psychology`。棱镜会先限制查询范围并去掉邮箱、链接和长数字，再通过 DeepSeek 的官方 Anthropic Web Search 接口检索；不使用 Semantic Scholar、Brave 或自建搜索代理。普通关系分析不会自动联网，安全危机模式也不会搜索。返回结果会带来源链接，并要求模型区分研究发现、来源陈述和结合用户处境的推断。

### 标记人物的疑似行为模式

当当前对话中有具体行为证据时，棱镜可以把人物关联到“控制或限制自主”“回避沟通或冷处理”“边界被忽视”“愧疚施压”等行为模式，并同时保存证据片段、依据强度和单次/重复范围。所有结果都标为“疑似·待确认”，不输出人格、心理疾病或依恋类型诊断。

人物归档会结合当前上下文处理自然出现的昵称、关系称呼、简称和代词变化：完全相同的已有名称或别名可跨对话归并，模型也必须有充分证据才会自动归并；证据不足但存在合理候选时，会在归纳完成后的对话区和记忆面板显示依据，并由你选择“是同一人”或“保留为不同的人”。只有用户明确把人物说成“我/自己”时才标记为用户本人。

### 在设备上建立记忆

章节、人物、情绪、盲点和跨对话记忆都会保存在本地 SQLite 数据库中。你可以选择本地数据目录。

### 分工明确，证据收窄

棱镜不会让一个分析提示词同时生成章节、解析人物和推断用户画像。短小的同步监督器只处理安全与回答质量信号；可见回复完成后，人物 Worker 才根据用户消息和人物索引归并别名；章节落库后，画像 Worker 才提取有依据的明确偏好、目标、稳定背景或沟通偏好。章节归纳只读取原始对话和前序章节，暂定的人物或画像结果不会反向改写故事摘要。

### 原生 macOS 工作空间

棱镜是面向 Apple Silicon Mac 的原生 SwiftUI 应用。界面、本地存储与打包应用统一由这一套 macOS 实现维护。

### 需要时添加图片或文本上下文

输入框支持点击 **+** 按钮或直接将文件拖入输入区域。JPEG、PNG、GIF 和 WebP 图片会显示为缩略图；常见文本和代码文件会作为文本块读取。每个附件都会显示名称、类型和体积，发送前可以删除。每条回复最多添加 5 个附件：单张图片不超过 10 MB，单个文本/代码文件不超过 1 MB，合计不超过 20 MB。附件只随本次回复发送，并只在当前 App 会话中保留预览。

当前打包版本为 `v1.0.16`。更新后的源码构建默认使用原生支持视觉的 **DeepSeek V4.1 Flash**（API 模型 ID：`deepseek-flash`），因此棱镜可以通过你配置的 DeepSeek 兼容端点识别和理解图片输入。可以参考 DeepSeek 的[官方更新日志](https://api-docs.deepseek.com/updates/)、[视觉 API 指南](https://api-docs.deepseek.com/guides/vision)和[Files API 文档](https://api-docs.deepseek.com/guides/files_api)了解服务端限制。PDF 不会被直接发送：当前 Files API 只接受图片，因此 PDF 文本提取或页面转图暂未集成到棱镜中。

## 截图

| 对话 | 跨对话记忆 | 人物与洞察 |
| --- | --- | --- |
| <img src="assets/1.png" width="260" alt="棱镜对话界面"/> | <img src="assets/2.png" width="260" alt="棱镜记忆界面"/> | <img src="assets/3.png" width="260" alt="棱镜人物与洞察界面"/> |

## 一条消息如何被处理

1. 棱镜在本地保存消息，并更新当前章节。
2. 轻量 Flash 监督器检查安全、回答质量、情绪和盲点。
3. 如果消息可以继续处理，主模型按统一的事实、关系和安全规则生成回复；所选回应方式只调整表达语气与组织。
4. 回复完成后，人物 Worker 更新别名和证据，不阻塞当前对话。
5. 到达章节边界时，章节 Worker 归纳原始对话；画像 Worker 随后只记录有依据的明确用户信息。
6. 当回复需要上下文时，本地工具可以检索章节、记忆、人物、情绪或叙事时间节点。
7. 当回复明确需要心理学研究依据时，主模型可以调用 DeepSeek 官方联网搜索；危机模式不会调用搜索。

安全路径优先于普通回复路径。检测到危机信号时，棱镜会提供本地化安全回应，不会让主模型按普通对话流程继续。

## 回应方式

三种回应方式共用同一套事实判断、关系建议、工具条件与安全引导。信息不足时也会提出同一个关键澄清问题；它们只改变措辞、共情句的位置和信息呈现顺序。

| 回应方式 | 表达差异 |
| --- | --- |
| **理性** | 更直接、克制地表达同一结论 |
| **平衡**（默认） | 更清晰、平和地表达同一结论 |
| **温情** | 先简短承认体验，再以更有共情的语气表达同一结论 |

## 支持的平台

| 客户端 | 运行环境 | 能力概览 |
| --- | --- | --- |
| SwiftUI | macOS 15+、Apple Silicon | 原生客户端；打包应用位于 `release/Prism-SwiftUI-macOS.app` |

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

## 本地数据与隐私

棱镜默认把数据保存到：

~~~
~/Documents/Prism/
├── prism.sqlite3
├── config.json
└── conversations.json.pre-sqlite.bak  # 旧数据首次导入时生成
~~~

- 对话历史和索引保存在一个本地 SQLite 数据库中，启用 WAL 日志和陈旧写入检测。
- 本次更新后的首次启动会将每个已导入的旧 JSON 复制为相邻的 `.pre-sqlite.bak`；原 JSON 文件保持不变。
- 没有内置遥测、分析或棱镜账号。
- 附件只会在当前请求期间保留在内存中，不会写入数据库。发送附件时，其内容会传输到你配置的 API 端点：图片作为图片数据，文本/代码文件作为文本内容。
- 棱镜虽然在本地保留副本，但对话内容以及由此形成的用户画像数据（包括人物、疑似行为模式、情绪、记忆、盲点和叙事时间轴记录）会在模型功能运行时，通过你配置的 API Key 和端点上传到 DeepSeek。
- 人物特征、盲点、画像和洞察都标注为暂定的模型观察，并显示证据。用户可在记忆面板逐条移除不接受的记录；移除不会删除原始对话。
- 可以选择其他本地存储目录。内置 iCloud 存储与同步已移除；检测到旧 iCloud 目录时，应用会复制到本地导入目录，原目录不改动。
- 删除对话时，也会删除与之关联的本地归档记录。

你需要自行负责所选择的 API 提供商、端点、保留策略和凭据。棱镜无法控制 DeepSeek 对数据的处理、存储、保留、训练或删除政策。不要把密钥放进截图、导出日志或受版本控制的文件中。

## 数据使用授权与免责声明

当你填写 API Key 并使用依赖模型的功能时，即表示你授权棱镜通过已配置的 API 端点，将对话内容、你主动发送的附件以及由此形成的用户画像数据传输给 DeepSeek。这些数据可能包括消息、图片数据、文本/代码文件内容、人物、疑似行为模式、情绪、记忆、盲点、叙事时间轴记录、摘要和搜索上下文。

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
├── assets/                        # 图标和截图
├── release/Prism-SwiftUI-macOS.app # 打包的 macOS 应用
├── README.md
└── README_CN.md
~~~

棱镜使用 Swift Package Manager 和 Apple 框架构建。

## 重要信息

- 棱镜需要访问已配置的 LLM 端点，不是离线模型。
- 本地保存不等于本地推理：每次依赖模型的请求都可能再次把所需上下文和检索记录发送给你配置的服务商。
- 模型输出、分类结果和检索上下文可能不完美，请自行复核重要结论。
- 棱镜不是医疗或急救产品。如果存在即时伤害风险，请联系当地急救服务或专业人员。

## 近期更新 — 2026-09-12

- 项目已收敛为原生 SwiftUI macOS 客户端及其正式应用包。
- SwiftUI 客户端已统一使用本地 SQLite 主存储。
- 首次导入旧 JSON 时会生成相邻备份；请求上下文裁剪不会再改写或截断原始对话。
- 已移除内置 iCloud 存储与同步。发现旧 iCloud 目录时，会导入到本地目录，原目录保持不变。
- 切换目录时若目标已有数据库会直接拒绝，避免覆盖；并发写入过期时会明确提示冲突。
- 衍生记忆会记录来源消息 ID 和证据状态。提示规则要求保留更正、否定、不确定性与时间范围；这提高了可追溯性，但不能保证模型分析永远正确。

## 今晚更新 — 2026-09-17

- 三种回应方式现在共用同一套事实核验、关系建议、工具条件和安全守护；理性、平衡、温情只改变表达语气、共情位置和组织顺序，并使用一致的采样参数，减少同一事实因切换方式而出现不同判断。
- 章节归纳、人物归纳和用户画像已经拆成相互衔接的 Worker：监督器先处理安全与回答质量信号；人物 Worker 处理名称、别名、关系称呼和证据；章节 Worker 只读取原始对话与既有章节；画像 Worker 只记录有明确证据的用户信息。
- 不确定的人物别名不会静默合并。系统会保留候选、依据和“同一人/分开”决定；只有用户明确说“我”或“自己”时才归为用户本人。
- 对话模型收敛为 `deepseek-flash` 与 `deepseek-v4-pro`：Flash 为默认模型并支持原生图片输入，Pro 保留为纯文本模型；旧模型 ID 会迁移到受支持的模型。
- SQLite 作为唯一主存储后，导入旧 JSON 会保留相邻备份；写入使用事务和 WAL，并检测陈旧写入，切换数据目录时不会覆盖已有数据库。
- 附件二进制只在当前请求期间保留；消息和文件名会写入本地记录，重新打开 App 后需要重新选择原文件。附件内容只会发送到用户配置的 API 端点。

## 本次更新 — 2026-09-19

- 增加按需的 `search_psychology` 工具：仅在问题需要心理学研究依据时调用 DeepSeek 官方联网搜索，不接入第三方搜索服务；自定义兼容端点或安全危机模式下不会启用。
- 安全回应改为受约束的动态措辞，保留固定模板兜底；安全检查失败时暂停普通关系分析，并持久化危机状态供下一轮复核。
- 重新构建并签名 `release/Prism-SwiftUI-macOS.app`，构建与 ad-hoc 签名验证已通过；真实 API 搜索尚未做在线 smoke test。

## 后续方向

棱镜的本地数据模型和原生 macOS 使用体验会继续完善，后续将集中在：

- 更可靠的导入和导出流程
- 更完善的本地归档备份与恢复控制
- 更可靠的 macOS 打包和发布流程
- 更透明地展示检索证据和模型上下文

## 许可证

棱镜使用 [MIT License](LICENSE) 发布。版权持有人：`markbignews`。

## 作者

棱镜由 [markbignews](https://github.com/markbignews) 创建和维护。


### DeepSeek API catalog — 2026-09-12

- `deepseek-flash`：DeepSeek V4.1 Flash，默认模型；原生图片输入。
- `deepseek-v4-pro`：DeepSeek V4 Pro，保留为纯文本模型。输入区会明确提示此限制，并阻止带图片的 Pro 请求。
- Prism 只保留这两个受维护的对话模型。已保存的退役或自定义对话模型 ID 会迁移到 Flash；官方的 `deepseek-v4-flash` 与 `deepseek-v4-flash-vision-exp` 也会迁移到 `deepseek-flash`。
- Chat Completions and the base URL remain unchanged. Thinking uses explicit enabled/disabled and low/high/max effort. Tool-enabled history retains assistant reasoning, including final answers. Older archives that already lost reasoning cannot be reconstructed.
- The launch announcement planned Pro retirement on September 14, but the current API guide and pricing page explicitly retain Pro. No timed Pro remapping is implemented. No undocumented `deepseek-v4.1-flash` or future Pro ID is added.

Sources checked: [API guide](https://api-docs.deepseek.com/), [model catalog](https://api-docs.deepseek.com/quick_start/pricing/), [thinking compatibility](https://api-docs.deepseek.com/guides/thinking_mode/), [September 10 announcement](https://deepseek.com/news/deepseek-v4-1-flash/).
