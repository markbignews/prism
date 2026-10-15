# Prism SwiftUI 技术说明

本文描述当前源码。版本号唯一来源为 `../VERSION`；打包脚本读取该文件。仓库内应用包通过 `--sync-release` 同步；单独修改源码不会自动更新二进制。

## 运行与构建

- 原生 SwiftUI + AppKit，Swift 6，运行最低 macOS 15。
- 编译需要 Xcode 26 或更新的 macOS SDK，因为源码使用受 availability 保护的 macOS 26 Liquid Glass API；较早系统运行时使用 material 回退。
- SwiftPM manifest 仅声明包。`scripts/build_app.py` 与打包入口通过 `xcrun --sdk macosx --show-sdk-version` 查询实际 SDK 并传给链接器，修正 Swift Build 把 SDK 错记为 deployment target 的行为；SDK 缺失或过旧时明确报错，不伪造 SDK 版本。
- 没有第三方依赖；`CSQLite` 是系统 SQLite 的模块映射，Security 是系统 Keychain 框架。
- 当前打包目标为 Apple Silicon arm64；Intel 未列入本轮支持范围。

```sh
cd "Prism/swift version"
swift test -Xswiftc -warnings-as-errors
swift run -c release Prism
```

受限环境可把 `CLANG_MODULE_CACHE_PATH`、`SWIFTPM_MODULECACHE_OVERRIDE` 和 SwiftPM `--cache-path` 指向可写临时目录。`--disable-sandbox` 仅关闭 SwiftPM manifest sandbox；宿主权限仍可能影响 dSYM 生成。不能把宿主拒绝访问当成测试失败。

## 编排与产品约束

`ChatStore` 提供 SwiftUI observable 外观；`ChatAgent` 在 MainActor 上维护业务状态。`DeepSeekClient` 处理 HTTP、SSE 和工具历史。`PrePipeline` 做辅助上下文检查；独立的 `PeoplePipeline` 和 `ProfilePipeline` 整理人物和用户观察。

`AgentPrompt.swift` 的证据纪律、事实/用户解释/模型推断边界和共同判断标准保持不变。三种回应风格不改变结论标准。安全路径仍由 `SafetyAssessment.requiresIntervention` 的三个条件共同决定：`flag=crisis`、`immediate_danger=true`、非空 evidence。辅助请求不可用或语义不确定不自动触发危机模式。当前轮监督提示重申既有否定与证据规则，并以反例提醒模型不要把否定扩写成隐藏危机或未经陈述的情绪强度；没有增加关键词分类或改变干预触发条件。

这些是程序和提示词约束，不能代替真实模型语义验收。验收入口及未完成项目见 `REGRESSION_CHECKLIST.md` 与 `SEMANTIC_ACCEPTANCE.md`。

## 工具与调用轮次

`Tools.swift` 注册八个工具：

| 工具 | 职责 |
| --- | --- |
| `track_person` | 读取人物与别名档案 |
| `emotion_timeline` | 读取情绪记录 |
| `search_chapters` | 关键词与同义词扩展检索章节 |
| `fetch_chapter_messages` | 读取章节原消息 |
| `search_memory` | 检索跨会话记忆 |
| `search_psychology` | DeepSeek 官方搜索；自定义端点不暴露该工具 |
| `manage_narrative_timeline` | 读取时间线或生成待用户确认的预览 |
| `request_user_input` | 结构化追问 |

检索不额外调用模型重排。发送流程最多执行两轮工具调用，再保留一轮不带工具的最终合成。每轮可以包含多个工具调用。新对话第一轮只提供时间线提案与追问工具。保存时间线仍须点击原生确认按钮，模型参数不构成授权。

## 上下文与流式展示

上下文按估算 token 阈值管理，不再按 60/40 条消息截断：

| 原文估算 token | 行为 |
| --- | --- |
| 550,000 | 显示容量提醒，不改变发送原文 |
| 750,000 | 压缩请求中的旧上下文，近期目标保留 200,000 tokens |
| 850,000 | 加强压缩保护，近期目标保留 150,000 tokens |

当前模型容量常量为 1,000,000 tokens，不是自定义服务商能力探测。估算值不是服务端实际用量；单条消息超过近期预算时仍保留该条，不能视为严格的请求长度上限。本地原消息不会因压缩而物理替换或删除。旧 `contextWindow` 配置字段被忽略，设置页保留有效阈值说明。

流式首帧立即显示，后续片段按 50ms 合并，优先通知当前消息 observable；完成时冲刷缓冲并发布最终历史。工具查询占位使用不持久化的 `isToolPlaceholder` 状态，不依赖中文文案比较。章节解析拒绝越界起始索引，并约束结束索引与摘要长度。

## 存储、写入与故障恢复

默认目录为 `~/Documents/Prism`，可在设置中更换本地目录：

- `prism.sqlite3`：会话及七类结构化档案。
- `config.json`：非敏感设置与 Keychain 条目 ID。
- `usage_stats.json`、可选 `prism.log`：用量统计和日志。
- `Data/*.json`、`*.pre-sqlite.bak`：旧版本数据及迁移备份，仅兼容导入；后续写入以 SQLite 为准。

SQLite schema 保持 `user_version=1`，不改变现有 record payload 结构。历史 Rust schema 注释不再承诺当前跨客户端兼容。启用 WAL 和 `synchronous=FULL`；不支持直接将活跃数据库放入 iCloud。

`StorageWriter` 使用独立串行队列完成快照编码与数据库 IO。业务操作标记 dirty collection，约 500ms 防抖合并；按版本记录确认成功的 dirty 状态，旧写入完成不会清除新改动。SQLite 连接由递归锁保护，串行写入与同步 flush 不并发使用连接。

一个 batch 的所有集合共享 `BEGIN IMMEDIATE` 事务，失败同时回滚 SQL 数据与缓存 revision。仍需扫描/编码被标记集合，并非按消息增量落盘；SQLite 仅更新有变化的 record。没有实施按会话拆文件。

删除会话会清理其时间线、记忆、盲点、画像与提案，人物仅清理引用、保留本体。会话和关联档案一起提交；提交失败时保留窗口中的待保存改动和错误状态，磁盘保持事务之前的数据。

切换目录、导入前、删除时、应用失去 active 状态与退出前强制 flush。正常退出遇到保存失败可导出快照后退出、取消退出，或明确选择不保存退出。强制终止进程/断电仍可能丢失尚未提交的防抖窗口内容。

- 单次占锁等待上限 250ms；写入队列仅对 SQLITE_BUSY（含扩展码）额外自动重试两次，退避 250ms、750ms，持续占锁约 1.75 秒后上报。冲突、SQLITE_LOCKED、磁盘满、IO/权限故障不自动重放；保留 dirty，条件恢复后点击“重试保存”。
- revision 冲突阻止盲目重试覆盖其他窗口：先导出当前窗口，确认后丢弃未保存改动并重新加载。
- 格式损坏或新版本数据库拒绝写入；不把加载失败得到的空列表作为正常数据覆盖磁盘。

只有所有集合完整加载成功后才做启动孤儿对账。清理不存在会话的引用时，把会话 revision 也纳入同一事务校验；保留人物本体和旧版本无 scope 的人物。成功清理记录数量无关的简短日志，不输出档案原文。

`history` 每条 record 保留最近五版，总计最多 10,000 条、32MiB 历史 payload；启动与写入事务都会裁剪旧历史。该上限不包括活跃数据、索引、空闲页和 WAL，不能称为数据库物理文件上限。需要回收旧空闲页时，退出应用后运行 `../scripts/storage_maintenance.py --help`；脚本默认只报告统计，写入前先备份。

## 密钥与迁移

API Key 使用系统 Keychain generic password，设置文件只保存条目 ID，不启用 iCloud Keychain 同步。迁移旧 `config.json`、`settings.json` 或 UserDefaults 时先写 Keychain、读回确认，再原子保存去掉明文的配置并清理旧字段。Keychain 失败时保留原配置，允许重试；禁止因为读失败把旧 Key 当空值删除。

已存在的系统备份/同步盘副本不会被程序追溯擦除。数据目录迁移保留同一 credential ID；复制快照到其他机器需重新设置该机器的 Key。Keychain 的系统权限提示与签名身份稳定性需要真实应用升级验收。

## 导出、导入与备份

设置页可打开数据目录、导出当前窗口 JSON 快照、导入完整快照。导出不包含 API Key；加载不完整的窗口会被标记为不完整，不能当作完整快照导入。快照可能包含敏感对话，应由用户自行保存。

导入与目录切换会更新数据代次，旧后台人物/画像结果会丢弃；人物处理绑定原用户消息，画像还要求原章节未被替换。导入前校验版本、所有集合和模型解码，先通过 SQLite backup API 生成 `pre-import-<UUID>.sqlite3`，再原子替换所有集合。解析或事务失败不会部分替换旧数据。复制活跃数据库应使用 backup API，不能只复制 `.sqlite3` 而遗漏 WAL。

## 测试、CI 与打包

测试覆盖存储锁恢复、跨集合回滚、旧数据备份、history 收敛、孤儿对账、快照往返、500 条消息与合并写入、人物/画像解析合并、章节边界、流式与确认流程。默认测试仅用临时目录、模拟凭据与 mock HTTP，不读取真实 Keychain 或调用真实模型。

`.github/workflows/swift.yml` 在 `macos-26` 和 `xcode-27` runner 上测试、release 编译及打包。工作流入库不代表 GitHub 已实际运行；要阻止合并，还须将两个检查配置为分支必需状态检查。

从仓库根目录一条命令打包：

```sh
python3 Prism/scripts/package_app.py --sync-release
```

默认生成 `swift version/Prism.app`；`--sync-release` 同步 `release/Prism-SwiftUI-macOS.app`。替换前把旧包移到仓库外 `~/Documents/Prism-build-backups`，可用 `--backup-dir` 指定。`../VERSION` 生成两个 bundle version 字段。源码摘要算法固定为按相对路径排序，对路径、NUL、文件字节、NUL 依次做 SHA-256；包括 Sources、Resources、Package.swift、VERSION、build_app.py 与 package_app.py；Tests 和文档不参与摘要。`--digest` 可复核。

受限宿主若禁止 SwiftPM manifest 沙箱，可给构建/打包入口设置 `PRISM_DISABLE_MANIFEST_SANDBOX=1`；普通构建与 CI 无需此开关。

这是来源摘要，不承诺不同工具链下的二进制逐字节相同。打包命令始终运行构建，前后核对源码摘要，并验证二进制的 arm64、最低 macOS 与实际 SDK 记录。

默认 ad hoc 签名，未做 Developer ID 公证；Apple Silicon 的支持范围不因签名改变。可用 `--identity` 和已有 `--notary-profile` 完成正式签名、公证和 stapling。仓库不存证书、私钥或公证凭据。`codesign --verify`、`stapler validate` 与干净 Mac 首次打开是不同验收项目。
