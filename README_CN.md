<p align="center">
  <img src="assets/icon.png" alt="棱镜" width="120" style="border-radius: 22px;"/>
</p>

<p align="center">
  <strong>棱镜 / Prism</strong><br>
  叙事分析 Agent · Narrative Analysis Agent<br>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS_Version-SwiftUI-blue" alt="macOS"/>
  <img src="https://img.shields.io/badge/Windows_Version-WinUI_3-blue" alt="Windows"/>
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README_ZH_HANT.md">繁體中文</a> · <a href="README_CN.md">简体中文</a>
</p>

---

棱镜是一款**本地优先、尊重隐私**的叙事分析 Agent，基于 DeepSeek 大语言模型。它识别叙事模式、追踪情绪变化、发现盲点。

> 本产品系叙事分析 Agent，不属于《人工智能拟人化互动服务管理暂行办法》(2026.7.15施行) 所规定的"拟人化互动服务"。不提供持续性情感陪伴。未满14周岁请在监护人陪同下使用。

---

### 截图

| 对话 | 跨对话记忆 | 人物记忆 |
|---|---|---|
| <img src="assets/1.png" width="240" style="border-radius: 16px;"/> | <img src="assets/2.png" width="240" style="border-radius: 16px;"/> | <img src="assets/3.png" width="240" style="border-radius: 16px;"/> |

---

## 版本

| 版本 | 平台 | 技术栈 |
|---|---|---|
| **macOS Version** | macOS 15+ | SwiftUI + Swift Agent (嵌入式) |
| **Windows Version** | Windows 10+ | WinUI 3 + C# Agent (嵌入式) |

---

## 功能

- **流式对话** — DeepSeek v4-pro（thinking 模式）+ 5 个检索工具
- **思考链可见** — 生成时自动滚动显示推理过程
- **三种对话模式** — 理性 / 平衡（默认）/ 温情
- **质量守护系统** — Flash 预处理管线每轮检测 6 个维度
- **安全干预** — 自杀/自伤/暴力/虐待检测跳过主模型
- **跨对话记忆** — 归纳时自动生成，任意对话中可检索
- **自动归纳** — 增量 + 全量重扫混合策略
- **预处理管线** — 每轮 1 次 Flash 调用
- **语义搜索** — 关键词 + Flash 语义重排序
- **情绪追踪** — 每轮自动标注，支持时间线回顾
- **人物追踪** — 自动提取，别名解析
- **盲点扫描** — 解释循环、回避自我、意图-行动差距

---

## 构建

```bash
cd "macOS Version" && swift build -c release
```

零第三方依赖，仅需 Swift 6.0+。

---

## 隐私

100% 本地存储 · 仅当前上下文发 API · 无遥测

---

## 许可证

[MIT](LICENSE)

---

*棱镜不是来留住你的，是来帮你离开的。*
