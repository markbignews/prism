---
name: directory-storage
description: Prism 项目目录结构、打包产物与应用图标规范。处理 Swift/Tauri 重新构建、图标生成、产物同步、签名或运行时验收时使用；.app 必须放在各自版本目录，禁止安装到 /Applications，禁止把新 bundle 合并覆盖到旧 bundle；两版图标统一使用 assets/ture icon.icon。
---

# 目录存放规范（Prism 项目）

> 本 Skill 记录 Prism 项目的目录结构、打包产物存放要求与相关约定。
> 处理本仓库的任何 AI / 工具请先阅读并遵守。

## 1. 当前目录结构

```
Prism/
├── Tauri Version/            # Tauri 版（项目源码 + 双平台构建）
│   ├── Windows Version/      #   Tauri Windows 11+ 独立工程
│   ├── macOS Version/        #   Tauri macOS 版构建目录
│   │   └── Prism.app         #     ← Tauri macOS 打包产物放这里
│   ├── src/                  #   Tauri 前端（JS/HTML）
│   └── src-tauri/            #   Rust 后端 + icons/
├── swift version/            # Swift 版（源码 + 打包产物）
│   ├── Prism.app             #   ← Swift 打包产物放这里
│   ├── Sources/Prism/        #   Swift 源码
│   ├── Resources/Prism.icns  #   打包图标（由 assets/ture icon.icon 生成）
│   └── Package.swift
├── assets/
│   └── ture icon.icon/       # 两版共用的 App 图标源（Assets/image.png, 1254×1254）
└── README.md / README_CN.md
```

## 2. 打包产物存放要求（核心规则，务必遵守）

1. **打包好的 .app 一律放在各自版本目录内，禁止安装或复制到 /Applications**：
   - Swift 版 → `swift version/Prism.app`
   - Tauri 版 macOS → `Tauri Version/macOS Version/Prism.app`
   - Tauri 版 Windows → `Tauri Version/Windows Version/`
2. 打包产物不常驻源码树；需要时直接重新打包并放回对应目录（无需打包脚本）。
3. 打包产物应加入 `.gitignore`，不提交到 git。
4. 不得为了“方便测试”创建第二个同 Bundle ID 的 Prism.app。发现 `/Applications/Prism.app` 或其他重复副本时，不要覆盖或从那里启动；报告其位置，只有获得用户授权后才能移到废纸篓。
5. 运行验证必须使用产物的绝对路径，不能只按显示名称 `Prism` 启动，否则系统可能打开旧副本。

## 3. 打包方式（Swift 版）

```bash
cd "swift version"
swift build --disable-sandbox          # 或 swift build -c release 出 release 包
# 组装 Prism.app：
#   Contents/MacOS/prism               ← .build/debug/Prism（或 release 产物）
#   Contents/Info.plist                ← CFBundleIdentifier=com.prism.chatclient,
#                                         CFBundleShortVersionString=1.0.0,
#                                         CFBundleIconFile=Prism.icns,
#                                         LSMinimumSystemVersion=12.0
#   Contents/Resources/Prism.icns      ← 最新图标（见第 4 节）
codesign --force --sign - Prism.app    # ad-hoc 签名（与历史包一致）
```

## 4. 图标（统一来源）

- 两版 App 图标**统一**使用 `assets/ture icon.icon/Assets/image.png`。
- Swift 打包前：用 `sips` 把源图缩放到全尺寸 iconset（16/32/64/128/256/512/1024 @1x/@2x），再 `iconutil -c icns` 生成 `swift version/Resources/Prism.icns`。
- Tauri 图标目录：`Tauri Version/src-tauri/icons/`（`icon.png` 1024、`icon.icns`、多尺寸 png、Windows `icon.ico`）。从 `Tauri Version/src-tauri` 执行：

```bash
cargo tauri icon '../../assets/ture icon.icon/Assets/image.png' --output icons
```

- 引导页使用的 `Tauri Version/src/app-icon.png` 必须同步自同一源图或新生成的 `src-tauri/icons/icon.png`；不能只更新 bundle 图标而遗漏应用内图标。
- 未经用户明确要求，不得单独重绘某一尺寸或替换统一源图。当前源图整体偏亮，在 16px 列表视图中可能显得很淡；这属于小尺寸辨识度问题，不等同于图标资源缺失。

## 5. Tauri macOS 打包流程（必须按顺序）

1. 检查 `tauri.conf.json > bundle.icon` 是否包含 `icons/icon.icns`，并确认不存在将要参与验证的重复 Prism.app。
2. 图标或源图变化后，先按第 4 节重新生成图标，再执行：

```bash
cd "Tauri Version"
node --check src/app.js
cargo fmt --check --manifest-path src-tauri/Cargo.toml
cargo test --manifest-path src-tauri/Cargo.toml
cargo tauri build --bundles app
```

3. 构建源为 `src-tauri/target/release/bundle/macos/Prism.app`，最终位置为 `macOS Version/Prism.app`。
4. **整体替换 bundle，禁止合并覆盖**：不要对一个已存在的 `macOS Version/Prism.app` 直接执行 `ditto 新包 旧包`。`ditto` 会合并目录并保留新包中不存在的旧资源。
5. 安全替换方式：先把旧 bundle 移到明确的临时备份位置，再将新 bundle 复制到一个不存在的最终路径；成功后重新 ad-hoc 签名。不要用宽泛路径或递归删除清理旧包。
6. 新包启动前先退出旧 Prism 进程，再使用最终产物绝对路径启动。

## 6. 打包后验收（不得只看构建成功）

依次完成以下检查：

1. `Info.plist`：`CFBundleIconFile` 指向 `icon.icns`，Bundle ID 与目标版本一致。
2. 资源：`Contents/Resources/icon.icns` 存在，且与 `src-tauri/icons/icon.icns` 哈希一致。
3. 图层：用 `iconutil -c iconset` 解包 `.icns`，确认包含 16、32、128、256、512、1024 对应图层。
4. 签名：执行 `codesign --verify --deep --strict --verbose=2 <最终 Prism.app>`。
5. Finder：实际打开最终目录，在“图标视图”确认图标存在；再检查列表视图。若大图正常而 16px 很淡，应报告为源图小尺寸对比度问题，不要误判为丢失。
6. 运行时：从最终绝对路径启动，确认不是旧进程或其他同名副本。
7. 引导页：确认 `src/app-icon.png` 已被前端引用并进入最终构建。需要验证首次引导时使用隔离的测试数据，不要重置用户真实设置。

常见症状与定位：

- Finder 显示通用应用图标：先查 `CFBundleIconFile`、`.icns` 是否进入 bundle、签名及重复 Bundle ID 副本。
- Finder 图标视图正常、列表视图近乎空白：统一源图在小尺寸下对比度不足。
- Dock/Finder 与引导页表现不一致：bundle 图标和 `src/app-icon.png` 没有同步。
- 修改已打包但界面仍旧：旧进程未退出，或启动了另一个同名 Prism.app。
- 新包出现旧资源：曾把新 bundle 合并覆盖到旧 bundle，应重新整体替换。

## 7. 命名约定（避免混淆）

- `swift version` = Swift 源码目录（曾用名 `macOS Version`，已改名）。
- `Tauri Version/macOS Version` = **Tauri 版**的 macOS 构建目录，**不是** Swift 版。

## 8. 文档约定

- README（`README.md` / `README_CN.md` 双语）同步说明 Windows 11+ 独立工程及其验证边界；macOS 上的源码检查不能表述为已产出或验证 Windows 安装包。
- 代码 / 目录 / 打包相关的改动，记录到 README 的「最近更新 / Recent Changes」章节（注明日期）。
- 最终回复只链接各版本目录中的正式产物，不提供 `/Applications` 路径，并明确区分“静态/构建检查”与“Finder、Dock、引导页的实际运行验证”。
