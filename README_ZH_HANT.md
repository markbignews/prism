<p align="center">
  <img src="assets/icon.png" alt="稜鏡" width="120" style="border-radius: 22px;"/>
</p>

<p align="center">
  <strong>稜鏡 / Prism</strong><br>
  敘事反思伴侶 · 幫你看清盲點，找到出口<br>
  <em>A narrative reflection companion. See blind spots, find a way forward.</em>
</p>

<p align="center">
  基於 <strong>Swift</strong> 的 vibe coding 項目 · macOS 桌面端應用 + CLI 命令列版本 · 支援 macOS / Linux / Windows
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README_CN.md">简体中文</a> · <a href="README_ZH_HANT.md">繁體中文</a>
</p>

---

稜鏡是一款**本地優先、尊重隱私**的 AI 對話工具，基於 DeepSeek 大語言模型。它分析你的敘事模式、追蹤情緒變化、發現你可能忽略的盲點。為反思而設計。

---

### 截圖

| 對話 | 跨對話記憶 | 人物記憶 |
|---|---|---|
| <img src="assets/1.png" width="240" style="border-radius: 16px;"/> | <img src="assets/2.png" width="240" style="border-radius: 16px;"/> | <img src="assets/3.png" width="240" style="border-radius: 16px;"/> |

---

## 功能

- **串流對話** — DeepSeek v4-pro（thinking 模式）+ 5 個檢索工具
- **思考鏈可見** — 生成時自動滾動顯示推理過程
- **三種對話模式** — 理性 / 平衡（預設）/ 溫情
- **品質守護** — Flash 預處理每輪檢測 6 個維度
- **安全干預** — 自殺/自傷/暴力/虐待檢測跳過主模型
- **跨對話記憶** — 歸納時自動生成，任意對話可檢索
- **自動歸納** — 增量 + 全量重掃混合策略
- **預處理管線** — 每輪 1 次 Flash 呼叫
- **語意搜尋** — 關鍵詞 + Flash 重新排序
- **情緒追蹤** — 每輪自動標註
- **人物追蹤** — 自動提取，別名解析

---

## 處理流程

```
使用者訊息
  │
  ├── Flash 預處理（~500ms）
  │     reality / spiral / blindspots / ingratiation / action_hollow / safety
  │     emotions → emotion_timeline.json
  │     persons → person_archive.json
  │
  ├── [安全覆寫] safety == "crisis" → 跳過主模型
  │
  ├── v4-pro 主模型 + 5 個檢索工具
  │
  └── 歸檔更新（非同步）
```

---

## 品質守護

| 維度 | 說明 |
|---|---|
| `reality` | 事實 vs 解釋比例 |
| `spiral` | 情緒無位移 |
| `blindspots` | 解釋循環、迴避自我、意圖差距 |
| `ingratiation` | 迎合傾向 |
| `action_hollow` | 空頭承諾 |
| `safety` | 安全訊號，**覆蓋主模型** |

---

## 檢索工具（5 個）

全部本機執行，零 API 成本。搜尋工具可選 Flash 重新排序。

`track_person` · `emotion_timeline` · `search_chapters` · `fetch_chapter_messages` · `search_memory`

---

## 快速開始

```bash
# GUI
cd GUI && swift build -c release
cp .build/arm64-apple-macosx/release/Prism Prism.app/Contents/MacOS/Prism
open Prism.app

# CLI
cd CLI && swift build -c release
./.build/arm64-apple-macosx/release/prism
```

---

## 授權

[MIT](LICENSE)

---

*稜鏡不是來留住你的，是來幫你離開的。*
