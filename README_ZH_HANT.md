<p align="center">
  <img src="1.png" alt="Prism Screenshot" width="180" style="border-radius: 28px;"/>
</p>

<p align="center">
  <strong>稜鏡 / Prism</strong><br>
  敘事反思伴侶 · 幫你看清盲點，找到出口<br>
  <em>A narrative reflection companion. See blind spots, find a way forward.</em>
</p>

<p align="center">
  基於 <strong>Swift</strong> 的 vibe coding 項目 · macOS 桌面端應用
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README_CN.md">简体中文</a> · <a href="README_ZH_HANT.md">繁體中文</a>
</p>

---

| 對話 | 跨對話記憶 | 人物記憶 |
|---|---|---|
| <img src="1.png" width="240" style="border-radius: 16px;"/> | <img src="2.png" width="240" style="border-radius: 16px;"/> | <img src="3.png" width="240" style="border-radius: 16px;"/> |

---

稜鏡是一款**本地優先、尊重隱私**的 AI 對話工具，基於 DeepSeek 大語言模型。它幫助你講出自己的故事、識別敘事盲點、探索替代視角，最終不再需要它。

**不是心理醫生，只是一面鏡子。**

---

## 功能特性

### 核心

- **串流對話** — DeepSeek v4-pro（thinking 模式）+ 5 個檢索工具
- **思考鏈可見** — 生成時自動滾動顯示推理過程
- **三種對話模式** — 理性、平衡（預設）、溫情
- **品質守護系統** — Flash 預處理管線每輪自動檢測 6 個維度（程式碼強制執行）
- **安全干預** — 自殺/自傷/暴力/虐待檢測跳過主模型，輸出熱線引導
- **跨對話記憶** — 歸納時自動生成，任意對話中可檢索
- **自動歸納** — 增量 + 全量重掃混合策略，生成結構化章節
- **預處理管線** — 每輪 1 次 Flash 呼叫覆蓋 guard + 情緒 + 人物 + 盲點（~500ms）
- **上下文視窗** — ≤60 條全文，>60 條自動壓縮為章節摘要
- **語意搜尋** — 關鍵詞預篩選 + Flash 語意重新排序

### 檢索工具（5 個）

| 工具 | 用途 | AI？ |
|------|------|------|
| `search_chapters` | 語意搜尋歷史章節，返回標題/摘要/關鍵詞 | ✅ keyword + Flash |
| `fetch_chapter_messages` | 按序號取得章節原文 | ❌ |
| `search_memory` | 語意搜尋跨對話記憶 | ✅ keyword + Flash |
| `track_person` | 跨對話人物追蹤（含別名解析） | ❌ |
| `emotion_timeline` | 原始情緒序列（模型自行判斷趨勢） | ❌ |

品質守護（reality / spiral / blindspots / ingratiation / action_hollow / safety）由預處理管線自動運行，不暴露為工具。

### 資料與隱私

- 100% 本地儲存：`~/Documents/Prism/`（可自訂）
- 僅當前對話上下文發送至 DeepSeek API
- 無遙測、無追蹤、無分析 SDK
- 可選 iCloud Drive 同步（macOS 獨有，預設關閉）
- 所有歸檔為純 JSON，可讀可遷移

### GUI / CLI

| GUI（macOS 15+） | CLI（macOS / Linux / Windows） |
|---|---|
| SwiftUI + AppKit，Liquid Glass 設計 | ANSI 終端串流輸出 |
| Markdown 渲染，側邊欄章節導航 | 完整對話管理，`/config` 即時設定 |
| 6 頁首次引導向導 | `/help` 檢視所有指令 |

---

## 訊息處理流程

```
使用者訊息
  │
  ├── [1] Flash 預處理管線（程式碼強制執行，~500ms）
  │     └─ 統一一次呼叫：
  │          reality — 事實 vs 解釋比例
  │          spiral — 情緒漩渦檢測
  │          blindspots — 解釋循環/迴避自我/意圖-行動差距
  │          ingratiation — 助手迎合傾向檢測
  │          action_hollow — 歷史空頭承諾比對
  │          safety — 安全訊號（最高優先順序）
  │          emotions — 情緒標註 → emotion_timeline.json
  │          persons — 人物提取（含別名解析）→ person_archive.json
  │
  ├── [安全覆寫] safety == "crisis" → 跳過主模型，返回安全引導
  │
  ├── [2] v4-pro 主模型（thinking，串流）+ 5 個工具
  │     └─ guard 提示透過 [監督者方向] 系統訊息注入
  │
  └── [3] 歸檔更新（非同步，不阻塞主對話）
```

---

## 品質守護系統

| 維度 | 檢測什麼 | warning 時 |
|---|---|---|
| `reality` | 解釋性語言遠多於具體事實 | 溫和拉回事實層 |
| `spiral` | 同一話題無情緒位移重複 | 從分析切換到出口引導 |
| `blindspots` | 解釋循環、迴避自我、意圖-行動差距 | 自然地提示盲點 |
| `ingratiation` | 上輪回覆有迎合傾向 | 回覆更獨立 |
| `action_hollow` | 歷史上出現過的空頭承諾 | 溫和提醒過去模式 |
| `safety` | 自殺/自傷/暴力/虐待 | **覆蓋主模型，輸出熱線** |

---

## 設計決策

**為什麼預處理在主模型之前？**
guard 訊號在主模型生成回覆前就可用，自然融入回覆，不生硬轉折。延遲成本約 500ms。

**為什麼 Agent + 工具檢索？**
模型需要理解上下文才能決定搜什麼。檢索工具純本機執行（零 API 成本），模型自主決策何時呼叫。

**為什麼上下文視窗閾值設 60 條？**
DeepSeek Pro 有 1M token 上下文。60 條以內全量發送，超過則壓縮——但模型仍可透過工具檢索任何壓縮內容。

**為什麼歸納用混合策略？**
每次都全量重掃浪費 token，純增量導致章節風格不一致。3 次增量 + 1 次重掃 = 平衡效率和一致性。歸納時附帶預處理管線資料，章節更有洞察。

**為什麼搜尋用 keyword + Flash 兩步式？**
純關鍵詞搜不到語意匹配（"被PUA"找不到"精神控制"），純 embedding 需要額外 API。兩步式：keyword 微秒級過濾 → Flash 語意重新排序 ~300ms，失敗時降級。

**為什麼人物提取要解析別名？**
使用者對同一人的稱呼會變（"我男朋友"→"張偉"→"前任"）。預處理時傳入已知人物列表，要求使用標準名稱，避免同一人分裂為多條記錄。

**為什麼 searchChapters 不回傳原文？**
10 結果 × 8 條訊息 = 80 條非必要上下文。現在只回傳標題/摘要/關鍵詞，需原文時單獨呼叫 fetch_chapter_messages。

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

首次啟動設定 API Key。CLI 中直接打字對話，`/help` 檢視指令。

---

## CLI 指令

導航：`/help`, `/new`, `/list`, `/switch <n>`, `/delete <n>`, `/rename <n>`
訊息：`/history [n]`, `/delmsg <n>`, `/find <關鍵詞>`
搜尋：`/chapters`, `/chapter <n>`, `/search <關鍵詞>`
資訊：`/info`, `/settings`
歸納：`/summarize`
設定：`/config <鍵> <值>`
其他：`/thinking`, `/lang zh|tw|en`, `/reset --confirm`, `/exit`

設定鍵：`apikey`, `model`, `mode`, `response`, `thinking`, `effort`, `summary`, `icloud`, `datapath`, `lang`

---

## 專案結構

```
chatbot/
├── CLI/Sources/       — 12 個原始檔（含 main.swift、PrePipeline.swift、SearchExpander.swift）
├── GUI/Sources/Prism/ — 同一套核心檔案 + UI 專屬檔案
├── README.md          — 英文說明
├── README_CN.md       — 簡體中文說明
└── README_ZH_HANT.md  — 繁體中文說明（本文檔）
```

---

## 建置

```bash
# 零第三方依賴，僅需 Swift 6.0+
cd CLI  && swift build -c release
cd GUI  && swift build -c release
```

---

## 授權

[MIT](LICENSE)

---

*稜鏡不是來留住你的，是來幫你離開的。*
