# Prism on Windows 11+

> 独立的 Windows 版本位于 [`Windows Version`](Windows%20Version/README.md)，可直接在该目录开发和打包。其前端和 Rust 核心与当前 Tauri 主工程保持同步；本文说明主工程通过平台配置构建 Windows 的方式。

The synchronized feature set includes both the emotion timeline and the narrative timeline. Narrative nodes use the event date or period stated in the user's story—not the message send time—and accept period, date, or mixed-time entries. If a later detail cannot be placed reliably, the agent asks one short clarification before writing it.

The Tauri build includes a Windows-specific configuration in
`src-tauri/tauri.windows.conf.json`. Tauri merges it automatically when the
target is Windows, so macOS keeps its overlay/transparent title bar while
Windows uses the native Windows 11 title bar and an opaque WebView surface.

## Prerequisites

- Windows 11 or later
- Rust stable with the `x86_64-pc-windows-msvc` target
- Visual Studio 2022 Build Tools with **Desktop development with C++** and the
  Windows 10/11 SDK
- WebView2 Runtime (included with Windows 11; the installer can bootstrap it
  when needed)
- Tauri CLI 2 (`cargo install tauri-cli --version '^2'`)

## Development

From this directory in PowerShell:

```powershell
cargo tauri dev
```

## Release installer

```powershell
cargo tauri build
```

The build produces a per-user NSIS installer under
`src-tauri/target/release/bundle/nsis/`. Prism stores its default data in
`%USERPROFILE%\Documents\Prism` and its storage pointer in
`%APPDATA%\Prism\storage_path`. A user-selected folder is preserved across
restarts.

The Windows overlay disables macOS-only iCloud controls during onboarding and
settings. Users can choose any local Windows folder instead.
