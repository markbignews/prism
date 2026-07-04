<p align="center">
  <img src="assets/icon.png" alt="稜鏡" width="120" style="border-radius: 22px;"/>
</p>

<p align="center">
  <strong>稜鏡 / Prism</strong><br>
  情感分析 Agent · Emotion Analysis Agent<br>
  <sub>Swift 6 · SwiftUI + AppKit · 零外部依賴</sub>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-SwiftUI-blue" alt="macOS"/>
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README_CN.md">简体中文</a> · <a href="README_ZH_HANT.md">繁體中文</a>
</p>

---

## 稜鏡是什麼？

稜鏡是一款**本地優先、尊重隱私**的 AI 情感分析 Agent，基於 DeepSeek 大語言模型。對話資料與使用者設定保存在本地（可選 iCloud Drive），無遙測、無分析。AI 推理透過 DeepSeek API 完成。它分析你的個人敘事、追蹤情緒變化、發現你可能忽略的認知盲點。

**它是分析工具，不是陪伴，不是醫生。** 品質守護系統主動防止情感迎合，確保分析立足於可觀察的事實。

---

## 它能做什麼

- **情緒追蹤** — 每輪對話自動標註情緒狀態，構建情緒變化時間線
- **敘事模式分析** — 檢測重複出現的主題、解釋循環和行為模式
- **盲點發現** — 發現意圖與行動之間的落差；標記你過度描述他人而忽略自己的時候
- **多視角分析** — 當故事結構完整時，提供同一事件的不同解讀
- **跨對話記憶** — 將過往對話提煉為可搜尋的知識庫
- **語義搜尋** — 關鍵詞 + Flash 重新排序，用不同措辭也能找到相關內容
- **安全干預** — 程式碼強制執行，檢測到危機訊號時自動跳出並提供專業求助指引

---

## 技術棧

| 層級 | 技術 |
|---|---|
| 語言 | Swift 6 |
| UI | SwiftUI + AppKit 混合（`NSViewRepresentable`、`NSTextView`、`NSOpenPanel`、`NSPasteboard`） |
| 併發 | `async/await`、`Task`、`Task.detached`、`@MainActor` |
| 狀態管理 | `ObservableObject` / `@Published` / `@StateObject` / `@EnvironmentObject` |
| 網路 | `URLSession.shared.bytes(for:)`（SSE 串流）、`URLSession.shared.data(for:)`（非串流） |
| 持久化 | `JSONEncoder` / `JSONDecoder` → 本地 `.json` 檔案 + `UserDefaults`（安全危機狀態） |
| 構建 | Swift Package Manager（`Package.swift`，swift-tools-version 6.0）— 無需 Xcode |
| 最低要求 | macOS 15.0（Sequoia）、Apple Silicon（arm64） |

**零外部依賴。** Markdown 渲染器、語義搜尋、MCP 工具註冊表、JSON 持久化、同義詞擴展 — 全部基於 Apple 框架（`SwiftUI`、`AppKit`、`Foundation`、`Combine`、`Observation`）手寫。

---

## 架構

```
SwiftUI 層 (ContentView、SidebarView、ChatView、SettingsView、OnboardingView、MemoryPanelView)
       │
       │  @EnvironmentObject / @Published
       ▼
ChatStore（ObservableObject 外觀層）
       │
       ▼
ChatAgent（@MainActor — 核心商業邏輯）
       │
       ├── DeepSeekClient        HTTP 客戶端：SSE 串流 + 非串流歸納
       ├── ToolRegistry          5 個 MCP 工具定義與本地執行器
       ├── AgentPrompt           所有模式的系統提示詞 + 歸納 + 重新排序
       ├── StoryMemory           基於章節的本地對話記憶
       ├── PrePipeline           單次統一 Flash 呼叫：守護 + 情緒 + 人物 + 盲點
       └── SearchExpander        ~40 組同義詞擴展
```

**設計模式 — Agent-Facade：** `ChatStore` 是一個薄 `ObservableObject`，橋接 SwiftUI 和 `ChatAgent`。它暴露 `@Published` 屬性並將所有呼叫委託給 Agent。串流傳輸期間，`append()` 將每個 token delta 直接寫入記憶體中的 `Conversation` 模型並呼叫 `agentStateDidChange()` — SwiftUI 在每個 token 到達時重渲染訊息氣泡，無中間緩衝層。

---

## 工作原理

每條使用者訊息觸發以下管線：

```
使用者發送訊息
  │
  ▼
1. StoryMemory.ingest()
   按段落拆分文字 → 建立或更新本地章節
   每個章節包含：標題、摘要、關鍵詞、訊息 ID 引用
   │
  ▼
2. PrePipeline（Flash 模型，非串流，thinking 禁用）
   首輪對話跳過（尚無助手回覆可供 ingratiation 檢測）
   發送最近 10 條 user+assistant 訊息 + 已知人物列表 + 歷史盲點記錄
   │
   一次 Flash API 呼叫返回結構化 JSON，同時完成：
   ├── 6 維度品質守護：
   │     reality（現實感）— 可觀察事實 vs 主觀解釋比例（>2.5:1 時告警）
   │     spiral（情緒漩渦）— 情緒停滯，多輪無位移
   │     blindspots（盲點）— 解釋循環、迴避自我、意圖-行動差距
   │     ingratiation（迎合）— 助手過度贊同/情感迎合/鏡像無分析
   │     action_hollow（空談）— 當前意圖匹配歷史盲點模式
   │     safety（安全）— 自傷、暴力/虐待、精神錯亂、未成年人受害、明確求助
   ├── 情緒標註：1-3 個片段，含 emotion + intensity（0.0-1.0）
   ├── 人物提取：真實姓名 + 角色，支援別名去重解析
   └── 盲點發現：pattern + evidence + counter_question + severity（new|recurring|persistent）
   │
  ▼
3. 安全檢查
   若 safety.flag == "crisis":
     → 構建本地化安全回應（中/英文）
     → 逐字元串流輸出到 UI（每 8 字元 yield 一次）
     → 將危機狀態持久化至 UserDefaults，供下一輪 PrePipeline 上下文使用
     → 完全跳過主模型
   若 safety.flag == "ok" 且上一輪為危機狀態 → 自動清除危機標記
   │
  ▼
4. 主模型（DeepSeek v4-pro，串流 + thinking 模式）
   │
   API 請求結構（DeepSeekClient.stream）:
     POST {baseURL}/chat/completions
     Body:
       model: 使用者配置（預設 deepseek-v4-pro）
       messages:
         - system: AgentPrompt.system(語言, 模式, 回覆長度)
         - system: "[監督者方向]\n{守護提示}"  （若有告警維度）
         - system: 記憶上下文 + 跨對話記憶（若有）
         - 最近 500 條對話訊息（非最後一條 assistant 的 tool_calls 被清除）
         - role:"tool" 訊息（待處理的工具結果）
       temperature: 0.1（理性）/ 0.35（平衡）/ 0.6（溫情）
       top_p: 0.8（理性）/ 0.9（平衡）/ 0.95（溫情）
       max_tokens: 8192
       thinking: {type: "enabled"} + reasoning_effort（使用者可配，預設 high）
       stream: true
       tools: ToolRegistry.definitions（5 個工具）
       timeout: 300s
   │
   SSE 解析迴圈（URLSession.shared.bytes）:
     逐行讀取回應:
       "data: [DONE]" → 結束
       "data: {...}" → JSONDecode → 提取 delta:
         reasoning_content → 追加到推理內容，發送 .reasoning(token)
         content → 追加到正文，發送 .content(token)
         tool_calls[] → 按 index 累積（id、function.name、function.arguments 片段）
   │
   上下文視窗策略（buildWindowedMessages）:
     ≤60 條訊息 → 全文發送 + 注入章節索引
     >60 條訊息 → 保留最後 40 條全文，舊內容壓縮為章節摘要
     章節索引作為 system 訊息注入，讓 Agent 知道哪些內容可透過工具檢索
   │
   工具迴圈（最多 3 輪）:
     若模型返回 tool_calls:
       1. 將 tool_calls 持久化到 assistant 訊息（API 下一輪呼叫所需）
       2. UI 顯示 "🔧 正在查詢…" 佔位符
       3. 透過 ToolRegistry 本地執行每個工具:
            track_person       → 讀取 person_archive.json，模糊名稱匹配
            emotion_timeline   → 返回最近 N 條記錄，含 ISO8601 日期
            search_chapters    → 關鍵詞打分 → 前 15 候選 → Flash 語義重排序 → 返回前 K
            fetch_chapter_messages → 返回某章節最多 12 條訊息（1-based 索引）
            search_memory      → 關鍵詞 + 同義詞擴展 → Flash 語義重排序 → 返回前 K
       4. 清除佔位符
       5. 將結果作為 role:"tool" 訊息注入
       6. 重建視窗訊息，再次呼叫 API
     若模型返回正文且無 tool_calls → 完成
     迴圈結束後: 清除 assistant 訊息的 tool_calls（防止下輪 API 報錯）
   │
  ▼
5. 後處理（Flash 模型，非串流，thinking 禁用）
   │
   ├── 應用 PrePipeline 結果到存檔（分離、非阻塞）:
   │     合併情緒（上限 200）、人物（上限 200，按 lastMentionedAt 排序）、
   │     盲點（上限 300，按 createdAt 排序）
   │
   ├── 歸納總結（按對話輪數觸發，間隔可配置）:
   │     增量歸納（Flash，max_tokens: 1024，超時 120s）:
   │       發送 lastSummaryMessageIndex 之後的新訊息 + 最近 3 個章節
   │       解析 JSON: {title, summary, keywords}
   │       追加 1 個章節，同步到跨對話記憶庫
   │     全量重掃（Flash，max_tokens: 8192，超時 180s）:
   │       發送完整對話記錄（帶 [序號][角色] 標記）+ 存檔上下文
   │       解析 JSON 陣列: [{title, summary, keywords, startIndex, endIndex}]
   │       替換全部章節，重置 incrementalChapterCount
   │     混合策略: 每 3 次增量歸納 → 自動觸發 1 次全量重掃
   │     壓縮儲存（trimConversation）:
   │       已被章節覆蓋的訊息 → 替換為 "[已歸納: 第N章「標題」]"
   │       未被覆蓋的訊息 → 截斷至 200 字元
   │       章節摘要 → 截斷至 600 字元
   │       始終保留最後 40 條訊息全文
   │
   ├── 標題更新（Flash 模型）:
   │     首條訊息或章節變化時觸發
   │     發送全部章節摘要 → Flash 生成 ≤40 字元標題
   │
   └── 持久化至 ~/Documents/Prism/conversations.json（原子寫入）
```

---

## 專案結構

```
macOS Version/
├── Package.swift                # SPM 清單（swift-tools-version: 6.0）
├── Sources/
│   └── Prism/
│       ├── PrismApp.swift       # @main 入口，WindowGroup，引導頁，Cmd+N 快捷鍵
│       ├── ContentView.swift    # NavigationSplitView，GlassBackground 修飾器，SidebarView，
│       │                        #   ChatView，MessageBubble（推理展開器），ComposerView，
│       │                        #   MacEditor（NSViewRepresentable 包裝 IntrinsicTextView），
│       │                        #   MemoryPanelView（人物存檔、情緒時間線、盲點、洞察）
│       ├── ChatStore.swift      # ObservableObject 外觀層 → ChatAgent，響應 agentStateDidChange
│       ├── ChatAgent.swift      # 核心編排器：send()、視窗訊息、工具迴圈、
│       │                        #   歸納（增量+全量）、智慧搜尋、記憶搜尋、
│       │                        #   語義重排序（Flash）、存檔管理、JSON 持久化
│       ├── DeepSeekClient.swift # HTTP 客戶端：stream() SSE 解析、summarize()/fullSummarize()
│       │                        #   非串流、ChatRequest/APIMessage/ThinkingConfig 模型
│       ├── Models.swift         # Conversation、ChatMessage、StoryChapter、EmotionEntry、
│       │                        #   PersonRecord、BlindspotRecord、MemoryEntry、
│       │                        #   ToolCall（自訂 Codable）、ToolResult
│       ├── Tools.swift          # ToolRegistry，5 個工具：track_person、emotion_timeline、
│       │                        #   search_chapters、fetch_chapter_messages、search_memory
│       │                        #   ToolDef schema 含 FunctionDef/Parameters/Property
│       ├── MarkdownText.swift   # 自訂 Markdown 解析器 → MarkdownBlock 列舉樹，
│       │                        #   SwiftUI 渲染器（標題、列表、程式碼區塊、表格 via Grid）
│       ├── StoryMemory.swift    # 按段落提取章節，relevantContext() 檢索
│       ├── PrePipeline.swift    # 單次 Flash 呼叫：100+ 行系統提示詞，嚴格 JSON 輸出模式，
│       │                        #   JSON 提取（處理 ```json 標記），安全危機狀態機
│       ├── AgentPrompt.swift    # 理性/溫情/平衡系統提示詞，歸納提示詞，
│       │                        #   標題更新提示詞，搜尋重排序提示詞
│       ├── L10n.swift           # 190+ 本地化字串（簡中 / 繁中 / 英文）
│       ├── SettingsView.swift   # API Key、Base URL、模型選擇、thinking 開關、推理強度、
│       │                        #   語言、對話模式、回覆長度、iCloud、資料路徑
│       ├── OnboardingView.swift # 8 頁流程：歡迎 → 用途 → 功能 → UI 導覽 → API Key →
│       │                        #   模式選擇 → iCloud → 資料與隱私
│       └── SearchExpander.swift # ~40 組同義詞：情緒、家庭、愛情、職場、內心模式
└── Prism.app/                   # 構建產物（arm64）
```

---

## 截圖

| 對話 | 跨對話記憶 | 人物記憶 |
|---|---|---|
| <img src="assets/1.png" width="240" style="border-radius: 16px;"/> | <img src="assets/2.png" width="240" style="border-radius: 16px;"/> | <img src="assets/3.png" width="240" style="border-radius: 16px;"/> |

---

## 核心功能

### 預處理管線（Flash 守護模型）

每次主模型回覆前，一次 Flash API 呼叫同時完成所有維度的分析。接收最近 10 條 user+assistant 訊息、已知人物列表和歷史盲點記錄作為上下文，返回單個 JSON 物件 — 無多次呼叫開銷。

管線**跳過首輪對話**（尚無助手回覆可供 ingratiation 檢測，無 spiral 歷史，無 blindspot 基線）。

| 維度 | 檢測邏輯 | 告警閾值 |
|---|---|---|
| `reality`（現實感） | 統計解釋性語言（「我覺得」「應該是」「意味著」…）vs 具體事實（時間/地點/人名/引述原話） | 解釋:事實 > 2.5:1 |
| `spiral`（情緒漩渦） | 比較多輪的情緒多樣性和強度趨勢 | 相同情緒 + 相同話題 + 無位移 |
| `blindspots`（盲點） | 三項子檢查：解釋循環（換措辭重複同一事件）、迴避自我（大量描述他人忽略自己）、意圖-行動差距（有意圖無行動描述） | 任一子項陽性 |
| `ingratiation`（迎合） | 僅掃描最近一條助手回覆：過度贊同、迴避挑戰、鏡像無分析、過度稱讚 | 嚴格標準 — 正常共情不算 |
| `action_hollow`（空談） | 將當前使用者意圖與歷史盲點模式交叉比對 | 意圖匹配持續盲點 |
| `safety`（安全） | 自傷、暴力/虐待、精神錯亂、未成年人受害、明確求助 — **最高優先級** | 任何明確訊號 → crisis，接管主模型 |

**安全危機狀態機：** 危機狀態持久化到 `UserDefaults`（按對話 ID 隔離）。下一輪 PrePipeline 重新注入危機上下文。當 Flash 對之前處於危機的對話返回 `safety.flag == "ok"` 時，自動清除危機狀態。

### JSON 輸出格式

PrePipeline 返回嚴格 JSON（解析器處理 ````json` 標記和周圍文字）：

```json
{
  "guard": {
    "reality":    {"flag":"ok|warning", "ratio":0.0, "interpretive_count":0, "concrete_count":0, "hint":""},
    "spiral":     {"flag":"ok|warning", "emotion_diversity":0, "intensity_trend":"stable|rising|falling", "hint":""},
    "blindspots": {"flag":"ok|warning", "findings":[{...}], "hint":""},
    "ingratiation":{"flag":"ok|warning", "signals":["..."], "hint":""},
    "action_hollow":{"flag":"ok|warning", "matched_count":0, "persistent_count":0, "hint":""},
    "safety":     {"flag":"ok|crisis", "signals":["..."], "suggest":"", "resources":""}
  },
  "emotions": [{"segment":"...", "emotion":"憤怒", "intensity":0.8}],
  "persons": [{"name":"張偉", "role":"ex-partner"}]
}
```

守護告警以 `[監督者方向]` 系統訊息的形式注入到主系統提示詞和對話歷史之間，給 Pro 模型結構化指導而不覆蓋其判斷。

### 5 個檢索工具（MCP 風格）

所有工具**本地執行** — 讀取磁碟 JSON 存檔，不呼叫外部 API。每個工具返回 JSON 字串給模型。

當 `settings` 可用時，`search_chapters` 和 `search_memory` 使用**兩階段語義管線**：關鍵詞預篩選（前 15）→ Flash 重排序（按語義相關性打分排序，返回前 K）。

| 工具 | 觸發條件 | 資料來源 | 返回內容 |
|---|---|---|---|
| `track_person` | 使用者提及具體人名/身份 | `person_archive.json` | 完整 `PersonRecord` JSON 或 `{"found":false}` |
| `emotion_timeline` | 模型需要情緒上下文 | `emotion_timeline.json` | 最近 N 條：`{emotion, intensity, date (ISO8601), segment}` |
| `search_chapters` | 使用者提及過往話題/事件 | 當前對話章節 | 最佳匹配：`{title, summary (200字元), keywords}` |
| `fetch_chapter_messages` | `search_chapters` 摘要不夠詳細 | 當前對話訊息 | 該章節最多 12 條訊息：`{role, content}` |
| `search_memory` | 需要跨對話上下文 | `memory.json` | 匹配的記憶：`{content, keywords, sourceChapter, recallCount}` |

### 對話模式

| 模式 | 系統提示詞風格 | Temperature | Top-P |
|---|---|---|---|
| **理性之鏡** | 分析性、證據驅動、挑戰認知扭曲、要求具體事實 | 0.1 | 0.8 |
| **平衡之鏡**（預設） | 敘事分析 + 適度挑戰，平衡共情與嚴謹 | 0.35 | 0.9 |
| **溫情之鏡** | 共情、溫和探索、情感驗證 | 0.6 | 0.95 |

所有模式共享相同的 thinking 配置（`thinking: enabled`，`reasoning_effort` 使用者可配，預設 `high`）和 `max_tokens: 8192`。

### 上下文視窗策略

稜鏡充分利用 DeepSeek 1M token 上下文視窗：

| 對話長度 | 策略 |
|---|---|
| ≤60 條訊息（30 輪） | **全文發送** — 所有訊息 + 章節索引作為 system 訊息注入，讓 Agent 知道哪些內容可透過工具檢索 |
| >60 條訊息 | **視窗模式** — 保留最後 40 條全文，舊訊息壓縮為章節摘要。Agent 可呼叫 `search_chapters` / `fetch_chapter_messages` 獲取完整原文 |

**語義壓縮（trimConversation）：** 儲存時，已被章節覆蓋的訊息替換為 `[已歸納: 第N章「標題」]` 引用 — 比盲目截斷更具語義價值。未被覆蓋的訊息截斷至 200 字元。章節摘要上限 600 字元。最後 40 條訊息始終保留全文。

### 自動歸納

按對話輪數觸發（user+assistant 對），間隔可在設定中配置。

| 類型 | 模型 | Max Tokens | 超時 | Thinking |
|---|---|---|---|---|
| **增量歸納** | Flash | 1024 | 120s | 禁用 |
| **全量重掃** | Flash | 8192 | 180s | 禁用 |

**混合策略：** 每 3 次增量歸納自動觸發 1 次全量重掃，保持章節風格和粒度一致。

全量重掃增強上下文：近期情緒軌跡（最近 5 條）、關鍵人物（提及次數前 5）、活躍盲點模式（最近 5 條）。所有章節重新生成，JSON 回應中的 `startIndex`/`endIndex` 映射回實際訊息 ID。

**跨對話記憶：** 每次歸納後，章節 upsert 到 `memory.json`（按標題 + 對話 ID 去重）。記憶庫上限 500 條，溢出時裁剪至 300。

### 智慧搜尋

多關鍵詞非重疊出現次數統計，覆蓋標題、訊息和章節：

- **標題匹配**：完整查詢 → +10，關鍵詞命中 → +5/個
- **訊息匹配**：關鍵詞出現 → +2/次，完整查詢 → +5
- **章節匹配**：標題關鍵詞 → +3，摘要關鍵詞 → +1，完整查詢 → +3-5
- **上下文摘錄**：匹配位置周圍 50 字元半徑提取，20 字元內去重
- **同義詞擴展**：~40 組（中英文），覆蓋情緒、家庭、愛情、職場、內心模式

### 語義重排序器

用於 `search_chapters` 和 `search_memory` 工具呼叫：

1. **關鍵詞預篩選**：本地搜尋返回前 15 候選
2. **Flash 重排序**：發送 `{查詢, 候選[index] 標題 — 摘要}` → Flash 返回 `[3,1,5,2,4]`（排序後的索引）
3. **回退**：Flash 失敗時直接返回關鍵詞排序結果

### Liquid Glass 介面

macOS 原生玻璃效果（macOS 26+ `NSGlassWindowBackground`），低版本回退至 `.ultraThinMaterial`。側邊欄和對話面板採用半透明深度層次材質。訊息輸入框透過 `NSViewRepresentable` 包裝 `NSTextView`，實現原生文字編輯體驗（自動增高、Enter 發送、Shift+Enter 換行）。

---

## 快速開始

```bash
cd "macOS Version" && swift build -c release
open Prism.app
```

需要 macOS 15.0+、Swift 6.0+、DeepSeek API Key（[platform.deepseek.com](https://platform.deepseek.com)）。

首次啟動時，8 頁新手引導帶你完成：歡迎 → 用途 → 功能（4 卡片）→ UI 導覽 → API Key 配置 → 對話模式（3 模式卡片）→ iCloud 儲存 → 資料與隱私。

---

## 資料與隱私

```
~/Documents/Prism/               （或自訂路徑，或 iCloud Drive）
├── conversations.json           # 所有對話和訊息
├── config.json                  # 應用設定與 API Key
└── Data/
    ├── person_archive.json      # 人物記錄（上限 200，按 lastMentionedAt 排序）
    ├── emotion_timeline.json    # 情緒條目（上限 200）
    ├── blindspots.json          # 盲點記錄（上限 300）
    └── memory.json              # 跨對話記憶（上限 500，溢出裁剪至 300）
```

- **100% 本地儲存** — 純 JSON，任意文字編輯器可讀
- **僅當前對話上下文發送至 DeepSeek API** — 無持久化伺服器端儲存
- **無遙測、無分析、無帳號**
- **可選 iCloud Drive** 多 Mac 同步（設定中開啟）
- **舊版遷移** — 自動將舊 bundle 旁位置存檔遷移至統一資料目錄

---

## 合規聲明

> 本產品係情感分析 Agent，不屬於《人工智能擬人化互動服務管理暫行辦法》(2026.7.15施行) 所規定的「擬人化互動服務」。本產品不提供持續性情感陪伴、不模擬自然人人格、不替代專業心理健康服務。未滿14周歲請在監護人陪同下使用。

---

## 授權

[MIT](LICENSE)
