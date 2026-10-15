# Prism / 棱镜

[English](README.md)

很多关系问题不是“给我一个答案”就能解决的。发生了什么、什么时候发生、你怎么理解、模型又推测了什么，混在一起时，很容易把希望或猜测当成事实。

我做 Prism，就是想把这些东西理清楚。你可以持续整理一段关系和相关经历，让模型回看对话、时间线和已有依据，帮你比较不同解释。它可以指出你忽略的地方，也应该把反例讲出来。最后怎么判断，还是由你自己决定。

## 它能做什么

- 对话按章节整理，旧内容会保留摘要，需要时再找相关上下文。
- 人物和别名单独记录。名字对不上或身份不确定时，可以先让你确认。
- 事情发生的时间和情绪变化分开记录。“今天说起”不代表“今天发生”。
- 分析可以关联回原消息，方便你检查它到底依据了什么。
- 关键信息缺失时，模型可以追问。你可以选一个答案，也可以自己写。
- 回答可以有不同语气，但事实标准不跟着语气变。

## 我希望 Prism 怎样判断

我不想让模型为了让人舒服，就说“肯定会好起来”；也不想让它为了显得客观，只盯着最坏的结果。能不能乐观，要看事实。事实不支持的，就别保证；还有可能、也有能做的事，就把它们说清楚。

所以 Prism 要分清事实、你的理解和模型的推测。行为不能直接证明动机，重复一遍的推测也不会变成证据。时间线要看事情发生的时间，不只看消息发送的时间。判断一个人或一段关系时，要讲依据，也要看反例。信息不够，就承认不够。

这是我对 Prism 的要求，不代表模型永远做得到。它可能漏看上下文，也可能判断错。Prism 不能读心，更不能替你决定一段关系到底意味着什么。

## 当前版本

这个仓库目前只有 **Swift 版本**：使用 SwiftUI 编写的原生 macOS 应用。需要 macOS 15 或更高版本；源码使用 Swift 6，编译需 Xcode 26 或更新版本及其 macOS SDK；仓库中的应用包面向 Apple Silicon。

Prism 通过你配置的模型服务生成回答，默认使用 DeepSeek 端点和 `deepseek-flash`。首次设置时填写 API Key、端点和模型；设置页可以读取或手动刷新模型列表，也可以直接填写模型 ID。Prism 不附带 API Key 或离线模型。

对话及结构化记录保存在本地 SQLite 数据库中。API Key 保存到系统 Keychain，配置文件只保留凭据引用。设置页支持会话和档案快照导出、导入，导入前会自动备份现有数据库。发送请求时，应用会把完成当前任务所需的对话、你主动添加的附件，以及相关分析或检索内容发送给所配置的服务商。请只提供你有权分享的信息。

## 运行

在仓库根目录执行：

```sh
python3 Prism/scripts/build_app.py --run
```

## 打包应用

在仓库根目录执行：

```sh
python3 Prism/scripts/package_app.py --sync-release
```

版本号从 [Prism/VERSION](Prism/VERSION) 读取，生成并验证 arm64 的 `Prism/swift version/Prism.app`，并同步同一份应用到 `Prism/release/Prism-SwiftUI-macOS.app`。旧包保留在 `~/Documents/Prism-build-backups`，可通过 `--backup-dir` 改位置。`--help` 查看 Developer ID 签名与公证选项；`--digest` 可复核应用包内的源码摘要。摘要覆盖 Sources、Resources、Package.swift、VERSION 和两个构建脚本，不含 Tests 与文档；用于核对构建输入，不代表不同工具链下的二进制逐字节一致。若受限宿主禁止 SwiftPM manifest 沙箱，可为构建/打包脚本设置 `PRISM_DISABLE_MANIFEST_SANDBOX=1`；普通构建与 CI 无需设置。

默认使用 **ad hoc 签名，未公证**。下载的应用可能需要按 [Apple 的说明](https://support.apple.com/zh-cn/102445)手动批准打开。仓库内 `Prism/release/` 已同步本轮修复。

GitHub Actions 已配置 macOS 26 与 Xcode 27 runner 的测试、构建和打包；要阻止失败的检查被合并，还需在分支保护中设置必需状态检查。实现与验证边界见[技术说明](Prism/swift%20version/TECHNICAL_SPEC.md)及[语义验收清单](Prism/swift%20version/SEMANTIC_ACCEPTANCE.md)。

## 使用边界

Prism 用来辅助整理和思考，不替你决定一段关系意味着什么，也不提供心理诊断、治疗或急救服务。建议把回答当作讨论材料，结合自己的经历和实际证据判断。

自动回归测试覆盖安全路由、模型配置、流式输出、确认流程、存储恢复、事务回滚、迁移与快照往返。在 Swift 包目录运行 `swift test -Xswiftc -warnings-as-errors`；自动化测试不能证明模型在每种真实情境下都能正确理解。

## 源码

- [SwiftUI 应用](Prism/swift%20version/Sources/Prism/)
- [分析与回答规则](Prism/swift%20version/Sources/Prism/AgentPrompt.swift)
- [数据模型](Prism/swift%20version/Sources/Prism/Models.swift)
- [MIT 许可证](Prism/LICENSE)

[markbignews](https://github.com/markbignews)
