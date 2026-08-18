# Prism Windows 版本

这是 Prism 面向 Windows 11 及更高版本的独立 Tauri 工程。Windows 配置直接位于 `src-tauri/tauri.conf.json`，不依赖 macOS 配置覆盖文件。前端与 Rust 核心已和 `Tauri Version` 主工程同步；平台差异只保留在窗口、存储路径、云存储能力和安装包配置中。

## 与 macOS Tauri 的对齐范围

- 相同的对话、思维链、章节、人物画像、情绪时间轴、叙事时间轴、搜索和日志导出功能
- 叙事时间轴按用户故事中事件实际发生或持续的时间排序，支持时间段、具体日期或混合节点；消息发送时间只作为回复时机和画像参考，不自动当作事件时间
- 相同的输入框模式切换、发送后置顶、回到最新对话和工具栏交互
- 相同的 V4 Flash 默认模型、默认高思考强度和设置迁移逻辑
- 相同的 1M Token 上下文估算与详情：55% 只提醒，75% 压缩发送请求，85% 加强保护
- 相同的输入/输出 Token、缓存命中和用户 ID 统计字段

Windows 专属行为：

- 使用 Windows 11 原生不透明标题栏，不启用 macOS Overlay 或 iCloud 控件
- 默认数据目录为 `%USERPROFILE%\Documents\Prism`
- 存储路径指针保存在 `%APPDATA%\Prism\storage_path`
- 使用 NSIS 当前用户安装模式；缺少 WebView2 时由安装程序下载引导程序

## 环境要求

- Windows 11 或更高版本
- Rust MSVC 工具链（`x86_64-pc-windows-msvc`）
- Visual Studio Build Tools，安装“使用 C++ 的桌面开发”
- WebView2 Runtime
- Tauri CLI 2：`cargo install tauri-cli --version '^2'`

## 开发与构建

在 PowerShell 中执行：

```powershell
cd "Windows Version"
cargo tauri dev
cargo tauri build
```

安装包输出到 `src-tauri/target/release/bundle/nsis/`。

Windows 版本默认将数据保存到：

- 文档目录：`%USERPROFILE%\Documents\Prism`
- 存储路径配置：`%APPDATA%\Prism\storage_path`

## Windows 客户端

Windows 版本使用原生 Windows 11 窗口、WebView2 和 NSIS 当前用户安装模式，并将用户数据保存在用户自己的 Prism 数据目录中。
