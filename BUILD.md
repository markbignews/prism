# 构建与打包指南 (Build & Package)

## 目录位置

```
chatbot/
├── GUI/
│   ├── Sources/Prism/         ← GUI 源码（改这里）
│   ├── Prism.app/             ← GUI 编译产物（项目内存档）
│   │   └── Contents/
│   │       ├── MacOS/Prism    ← GUI release 二进制
│   │       ├── Resources/AppIcon.icns
│   │       └── Resources/AppIcon.png
│   └── .build/                ← Swift 构建缓存（git ignored）
│
├── CLI/
│   ├── Sources/               ← CLI 源码（改这里）
│   ├── prism                  ← CLI release 二进制（项目内存档）
│   └── .build/                ← Swift 构建缓存（git ignored）
│
├── GUI/Prism.app/             → 复制 → /Applications/Prism.app（发布包）
└── GUI/Sources/Prism/Tools.swift
    CLI/Sources/Tools.swift    ← 两处同步修改
```

## 构建命令

### CLI

```bash
cd /Users/loong/Documents/chatbot/CLI
swift build -c release                    # 产物在 .build/arm64-apple-macosx/release/prism

# 复制到项目目录内存档
cp .build/arm64-apple-macosx/release/prism /Users/loong/Documents/chatbot/CLI/prism
```

### GUI

```bash
cd /Users/loong/Documents/chatbot/GUI
swift build -c release                    # 产物在 .build/arm64-apple-macosx/release/Prism

# 复制到项目目录内 .app bundle
cp .build/arm64-apple-macosx/release/Prism /Users/loong/Documents/chatbot/GUI/Prism.app/Contents/MacOS/Prism
```

## 部署

### 复制到 /Applications（发布）

```bash
rm -rf /Applications/Prism.app
cp -R /Users/loong/Documents/chatbot/GUI/Prism.app /Applications/Prism.app
```

### 注册 Launch Services（让 Finder/macOS 识别新版本）

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Prism.app
```

## 同步注意事项

- CLI 和 GUI 共享 `Tools.swift`、`ChatStore.swift`、`AgentPrompt.swift`、`DeepSeekClient.swift`、`Models.swift`、`AppSettings.swift`、`StoryMemory.swift`、`L10n.swift`
- **修改任一共享文件后，必须同步复制到另一个目录**：
  ```bash
  cp CLI/Sources/X.swift GUI/Sources/Prism/X.swift
  ```
- 唯一差异：GUI 的 `ChatStore.swift` 需要额外 `import Combine` 和 `ObservableObject` 适配
- GUI 独有的文件：`PrismApp.swift`、`ContentView.swift`、`OnboardingView.swift`、`SettingsView.swift`、`MarkdownText.swift`
- CLI 独有的文件：`main.swift`、`Terminal.swift`

## 验证清单

| 检查项 | 命令 |
|---|---|
| CLI 编译 | `cd CLI && swift build -c release` |
| GUI 编译 | `cd GUI && swift build -c release` |
| 二进制已复制 | `ls -la GUI/Prism.app/Contents/MacOS/Prism` |
| /Applications 已更新 | `ls -la /Applications/Prism.app/Contents/MacOS/Prism` |
| Launch Services 注册 | `lsregister -f /Applications/Prism.app` |
| CLI 项目内存档 | `ls -la CLI/prism` |
