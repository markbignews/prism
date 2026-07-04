<p align="center">
  <img src="assets/icon.png" alt="棱镜" width="120" style="border-radius: 22px;"/>
</p>

<p align="center">
  <strong>棱镜 / Prism</strong><br>
  情感分析 Agent · Emotion Analysis Agent<br>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-SwiftUI-blue" alt="macOS"/>
  <img src="https://img.shields.io/badge/Windows-WinUI_3_(开发中)-lightgrey" alt="Windows"/>
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README_ZH_HANT.md">繁體中文</a> · <a href="README_CN.md">简体中文</a>
</p>

---

## 棱镜是什么？

棱镜是一款**本地优先、尊重隐私**的 AI 情感分析 Agent，基于 DeepSeek 大语言模型，完全运行在你的设备上。它分析你的个人叙事、追踪情绪变化、发现你可能忽略的认知盲点。

**它是分析工具，不是陪伴，不是医生。** 质量守护系统主动防止情感迎合，确保分析立足于可观察的事实。

---

## 它能做什么

- **情绪追踪** — 每轮对话自动标注情绪状态，构建情绪变化时间线
- **叙事模式分析** — 检测重复出现的主题、解释循环和行为模式
- **盲点发现** — 发现意图与行动之间的落差；标记你过度描述他人而忽略自己的时候
- **多视角分析** — 当故事结构完整时，提供同一事件的不同解读
- **跨对话记忆** — 将过往对话提炼为可搜索的知识库
- **语义搜索** — 关键词 + Flash 重排序，用不同措辞也能找到相关内容
- **安全干预** — 代码强制执行，检测到危机信号时自动跳出并提供专业求助指引

---

## 截图

| 对话 | 跨对话记忆 | 人物记忆 |
|---|---|---|
| <img src="assets/1.png" width="240" style="border-radius: 16px;"/> | <img src="assets/2.png" width="240" style="border-radius: 16px;"/> | <img src="assets/3.png" width="240" style="border-radius: 16px;"/> |

---

## 核心功能

- DeepSeek v4-pro 流式对话（thinking 模式）+ 5 个检索工具
- 三种对话模式：理性 / 平衡（默认）/ 温情
- Flash 预处理管线：6 维度质量守护 + 情绪标注 + 人物提取
- 自动归纳：增量 + 全量重扫，生成结构化章节
- 29 组同义词扩展（中英文），覆盖情绪、关系、行为模式
- 100% 本地 JSON 存储

---

## 快速开始

```bash
cd "macOS Version" && swift build -c release
open Prism.app
```

需要 macOS 15+、Swift 6.0+、DeepSeek API Key。

---

## 合规声明

> 本产品系情感分析 Agent，不属于《人工智能拟人化互动服务管理暂行办法》(2026.7.15施行) 所规定的"拟人化互动服务"。本产品不提供持续性情感陪伴、不模拟自然人人格、不替代专业心理健康服务。未满14周岁请在监护人陪同下使用。

---

## 隐私

100% 本地存储 · 仅当前上下文发送至 API · 无遥测无追踪

---

## 许可证

[MIT](LICENSE)
