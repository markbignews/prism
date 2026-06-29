<p align="center">
  <img src="../1.png" alt="Prism Screenshot" width="180" style="border-radius: 28px;"/>
</p>

<p align="center">
  <strong>Prism / 棱镜</strong><br>
  叙事反思伴侣 · 帮你看清盲点，找到出口<br>
  <em>A narrative reflection companion. See blind spots, find a way forward.</em>
</p>

<p align="center">
  基于 <strong>Swift</strong> 的 vibe coding 项目 · macOS 桌面端应用
</p>

---

## 截图

| 对话 | 跨对话记忆 | 人物记忆 |
|---|---|---|
| <img src="../1.png" width="240" style="border-radius: 16px;"/> | <img src="../2.png" width="240" style="border-radius: 16px;"/> | <img src="../3.png" width="240" style="border-radius: 16px;"/> |

---

## 特性

- **流式对话** — DeepSeek v4-pro（thinking 模式）+ 5 个检索工具
- **思考链可见** — 生成时实时展示推理过程
- **质量守护系统** — 预处理管线自动检测 6 个维度
- **安全干预** — 自杀/自伤/暴力/虐待检测，自动输出热线引导
- **跨对话记忆** — 归纳时自动生成，任意对话可检索
- **语义搜索** — 关键词 + Flash 语义重排序
- **三种对话模式** — 理性 / 平衡 / 温情
- **自动归纳** — 混合策略，生成结构化章节
- **情绪追踪** — 每轮自动标注情绪，支持时间线回顾
- **人物追踪** — 自动提取人物，支持别名解析
- **盲点扫描** — 检测叙事盲点：解释循环、回避自我、意图-行动差距

## 界面

- 原生 SwiftUI + AppKit
- Liquid Glass 设计风格
- Markdown 渲染
- 侧边栏：对话列表、章节导航、搜索、记忆面板
- 章节详情弹窗，蓝色跳转原文
- 消息气泡：复制 / 编辑 / 重新生成 / 删除
- 配对删除：删任意边自动删配对问答
- 6 页首次引导向导
- 设置：API Key、模型、模式、数据路径、iCloud

## 系统要求

- macOS 15+
- Swift 6.0+（构建需要）
- DeepSeek API Key

## 构建

```bash
swift build -c release
cp .build/arm64-apple-macosx/release/Prism Prism.app/Contents/MacOS/Prism
open Prism.app
```

## 隐私

100% 本地存储 · 仅当前对话上下文发送 API · 无遥测无追踪

---

<p align="center"><em>棱镜不是来留住你的，是来帮你离开的。</em></p>
