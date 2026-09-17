---
name: directory-storage
description: Prism 的 SwiftUI 目录结构、打包产物与应用图标规范。处理 Swift 重新构建、图标生成、产物同步、签名或运行时验收时使用；.app 必须保留在项目版本目录，禁止安装到 /Applications，禁止把新 bundle 合并覆盖到旧 bundle。
---

# 目录存放规范（Prism 项目）

> Prism 维护一个原生 SwiftUI macOS 客户端。

## 1. 当前目录结构

```
Prism/
├── swift version/                  # SwiftUI 源码与正式构建产物
│   ├── Package.swift
│   ├── Sources/Prism/
│   ├── Resources/Prism.icns
│   └── Prism.app                   # ← 本地正式应用包
├── assets/
│   └── ture icon.icon/Assets/image.png # 图标源图
├── release/
│   └── Prism-SwiftUI-macOS.app     # 可分发的正式应用包
└── README.md / README_CN.md
```

## 2. 产物存放要求

1. 构建应用包保留在 `swift version/Prism.app`；可分发副本保留在 `release/Prism-SwiftUI-macOS.app`。不要安装或复制到 `/Applications`。
2. 替换现有 bundle 时，先将旧包移动到明确的临时备份位置，再复制新包到一个不存在的最终路径。不能将新包合并覆盖旧包。
3. 发现其他同 Bundle ID 的 Prism.app 时，不覆盖或从那里启动；报告位置，只有用户明确授权后才处理。
4. 运行验证使用最终产物的绝对路径，避免系统启动旧副本。

## 3. Swift 打包流程

```bash
cd "swift version"
swift build -c release -Xswiftc -warnings-as-errors
```

将 release 二进制组装到 `Prism.app/Contents/MacOS/prism` 后，整体替换 `swift version/Prism.app`，再复制到 `release/Prism-SwiftUI-macOS.app`。两个应用包均使用 ad-hoc 签名：

```bash
codesign --force --sign - "Prism.app"
codesign --verify --deep --strict --verbose=2 "Prism.app"
```

## 4. 图标

- 图标源为 `assets/ture icon.icon/Assets/image.png`。
- 使用 `sips` 生成完整 iconset，再通过 `iconutil -c icns` 写入 `swift version/Resources/Prism.icns`。
- 新包中的 `Contents/Resources/Prism.icns` 必须与上述资源一致；未经用户明确要求，不单独重绘某个尺寸或替换源图。

## 5. 打包后验收

1. `Info.plist` 中的 Bundle ID、版本号、`CFBundleIconFile` 与目标应用一致。
2. `Contents/Resources/Prism.icns` 存在，并包含 16、32、128、256、512、1024 尺寸。
3. `codesign --verify --deep --strict --verbose=2 <正式 Prism.app>` 通过。
4. 从正式产物绝对路径启动，确认没有复用其他同名应用进程。
5. README 中仅描述当前 SwiftUI/macOS 实现及实际完成的验证。

## 6. 记录约定

- 代码、目录或打包变动同步更新 `README.md` 与 `README_CN.md` 的「Recent changes / 近期更新」。
- 最终回复链接项目中的正式产物，并区分已完成的构建检查与尚未进行的 Finder、Dock 或真实 API 运行验证。
