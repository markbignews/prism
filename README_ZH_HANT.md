<p align="center">
  <img src="assets/icon.png" alt="稜鏡" width="120" style="border-radius: 22px;"/>
</p>

<p align="center">
  <strong>稜鏡 / Prism</strong><br>
  情感分析 Agent · Emotion Analysis Agent<br>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-SwiftUI-blue" alt="macOS"/>
  <img src="https://img.shields.io/badge/Windows-WinUI_3_(開發中)-lightgrey" alt="Windows"/>
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README_CN.md">简体中文</a> · <a href="README_ZH_HANT.md">繁體中文</a>
</p>

---

## 稜鏡是什麼？

稜鏡是一款**本地優先、尊重隱私**的 AI 情感分析 Agent，基於 DeepSeek 大語言模型，完全運行在你的裝置上。它分析你的個人敘事、追蹤情緒變化、發現你可能忽略的認知盲點。

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

## 截圖

| 對話 | 跨對話記憶 | 人物記憶 |
|---|---|---|
| <img src="assets/1.png" width="240" style="border-radius: 16px;"/> | <img src="assets/2.png" width="240" style="border-radius: 16px;"/> | <img src="assets/3.png" width="240" style="border-radius: 16px;"/> |

---

## 核心功能

- DeepSeek v4-pro 串流對話（thinking 模式）+ 5 個檢索工具
- 三種對話模式：理性 / 平衡（預設）/ 溫情
- Flash 預處理管線：6 維度品質守護 + 情緒標註 + 人物提取
- 自動歸納：增量 + 全量重掃，生成結構化章節
- 29 組同義詞擴展（中英文），覆蓋情緒、關係、行為模式
- 100% 本地 JSON 儲存

---

## 快速開始

```bash
cd "macOS Version" && swift build -c release
open Prism.app
```

需要 macOS 15+、Swift 6.0+、DeepSeek API Key。

---

## 合規聲明

> 本產品係情感分析 Agent，不屬於《人工智能擬人化互動服務管理暫行辦法》(2026.7.15施行) 所規定的「擬人化互動服務」。本產品不提供持續性情感陪伴、不模擬自然人人格、不替代專業心理健康服務。未滿14周歲請在監護人陪同下使用。

---

## 隱私

100% 本地儲存 · 僅當前上下文發送至 API · 無遙測無追蹤

---

## 授權

[MIT](LICENSE)
