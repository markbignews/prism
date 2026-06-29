import Foundation

enum L10n {
    static func text(_ key: Key, _ language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese:
            simplified[key] ?? key.rawValue
        case .traditionalChinese:
            traditional[key] ?? simplified[key] ?? key.rawValue
        case .english:
            english[key] ?? key.rawValue
        }
    }

    static func languageName(_ language: AppLanguage, in current: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese:
            return text(.languageSimplifiedChinese, current)
        case .traditionalChinese:
            return text(.languageTraditionalChinese, current)
        case .english:
            return text(.languageEnglish, current)
        }
    }

    enum Key: String {
        case newConversation
        case settings
        case delete
        case deletePairHint
        case rename
        case renameHint
        case save
        case cancel
        case reSummarize
        case summarizing
        case search
        case noResults
        case storage
        case dataPath
        case dataPathHint
        case choose
        case edit
        case regenerate
        case userName
        case assistantName
        case thinking
        case thinkingPlaceholder
        case deepSeek
        case apiKey
        case baseURL
        case model
        case proModel
        case flashModel
        case modelParameters
        case proParameters
        case flashParameters
        case temperature
        case topP
        case maxTokens
        case presencePenalty
        case frequencyPenalty
        case thinkingMode
        case reasoningEffort
        case high
        case max
        case interface
        case language
        case languageSimplifiedChinese
        case languageTraditionalChinese
        case languageEnglish
        case conversations
        case chapters
        case noChapters
        case newConversationTitle
        case openingMessage
        case openingReasoning
        case requestFailedMessage
        case requestFailedReasoning
        case requestCancelledMessage
        case requestCancelledReasoning
        case cancelledSuffix
        case fallbackReasoning
        case thinkingHint
        case modePrism
        case modePrismShort
        case autoSummarization
        case summaryInterval
        case autoSummaryHint
        case intervalOff
        case dialog2
        case dialog5
        case dialog10
        case chapterSynthesized
        case emptyMirrorTitle
        case emptyMirrorHint
        // Onboarding
        case onboardingWelcomeTitle
        case onboardingWelcomeBody
        case onboardingPurposeTitle
        case onboardingPurposeBody
        case onboardingFeaturesTitle
        case onboardingFeaturesBody
        case onboardingUITourTitle
        case onboardingUITourBody
        case onboardingAPIKeyTitle
        case onboardingAPIKeyBody
        case onboardingDataTitle
        case onboardingDataBody
        case onboardingContinue
        case onboardingSkip
        case onboardingGetStarted
        case onboardingBack
        case onboardingPageIndicator
        // Onboarding feature cards
        case featureNarrativeTitle
        case featureNarrativeDesc
        case featureBlindspotTitle
        case featureBlindspotDesc
        case featurePerspectiveTitle
        case featurePerspectiveDesc
        case featureChapterTitle
        case featureChapterDesc
        // Onboarding UI tour cards
        case uiSidebarTitle
        case uiSidebarDesc
        case uiChatTitle
        case uiChatDesc
        case uiInputTitle
        case uiInputDesc
        case uiToolbarTitle
        case uiToolbarDesc
        // Onboarding data cards
        case dataStorageTitle
        case dataStorageDesc
        case dataConfigTitle
        case dataConfigDesc
        case dataPrivacyTitle
        case dataPrivacyDesc
        case dataArchiveTitle
        case dataArchiveDesc
        // Reset
        case reset
        case resetTitle
        case resetMessage
        case resetButton

        // Memory panel
        case memory
        case memoryPeople
        case memoryEmotions
        case memoryBlindspots
        case memoryInsights
        case memoryEmptyTitle
        case memoryEmptyHint
        case memoryMentions
        case memoryPersistent
        case memoryRecurring
        case memoryNew
        case memoryCounterQuestion
        case memoryRecall
        case memoryTimes

        // Conversation mode
        case conversationMode
        case conversationModeHint
        case modeRational
        case modeBalanced
        case modeWarm
        case conversationModel
        case modeRationalDesc
        case modeBalancedDesc
        case modeWarmDesc
        case responseLength
        case responseLengthHint
        case modeBrief
        case modeStandard
        case modeDetailed
        case aiLabelDisclaimer
        case onboardingModeTitle
        case onboardingModeBody

        // iCloud
        case useiCloud
        case iCloudActive
        case iCloudUnavailable

        // Actions
        case jumpToSource
        case copy
        case findInPage
    }

    private static let simplified: [Key: String] = [
        .newConversation: "新对话",
        .settings: "设置",
        .delete: "删除",
        .deletePairHint: "后面的助手回复也将被删除。",
        .rename: "重命名",
        .renameHint: "输入新名称",
        .save: "保存",
        .cancel: "取消",
        .reSummarize: "重新归纳",
        .summarizing: "正在归纳...",
        .search: "搜索...",
        .noResults: "无匹配结果",
        .storage: "存储",
        .dataPath: "数据路径",
        .dataPathHint: "更改后需重启应用生效",
        .choose: "选择...",
        .edit: "编辑",
        .regenerate: "重新生成",
        .userName: "你",
        .assistantName: "棱镜",
        .thinking: "思考链",
        .thinkingPlaceholder: "模型未返回 reasoning_content。",
        .deepSeek: "DeepSeek",
        .apiKey: "API Key",
        .baseURL: "Base URL",
        .model: "模型",
        .proModel: "Pro 模型",
        .flashModel: "Flash 模型",
        .modelParameters: "模型参数",
        .proParameters: "Pro 参数",
        .flashParameters: "Flash 参数",
        .temperature: "Temperature",
        .topP: "Top P",
        .maxTokens: "Max Tokens",
        .presencePenalty: "Presence Penalty",
        .frequencyPenalty: "Frequency Penalty",
        .thinkingMode: "深度思考",
        .reasoningEffort: "推理强度",
        .high: "高",
        .max: "最大",
        .interface: "界面",
        .language: "语言",
        .languageSimplifiedChinese: "简体中文",
        .languageTraditionalChinese: "繁体中文",
        .languageEnglish: "English",
        .conversations: "对话",
        .chapters: "章节",
        .noChapters: "继续对话，每次归纳时将自动生成章节",
        .newConversationTitle: "新对话",
        .openingMessage: "从一个具体场景开始。我会帮你拆分事实与解释、梳理感受，并在故事足够完整时提供多个可能的叙事视角。",
        .openingReasoning: "初始引导：邀请用户从一个具体场景开始叙述，不急于判断。",
        .requestFailedMessage: "暂时无法连接模型。请检查 API Key、模型名称和网络设置。",
        .requestFailedReasoning: "请求失败",
        .requestCancelledMessage: "对话已取消",
        .requestCancelledReasoning: "生成已取消",
        .cancelledSuffix: "已取消",
        .fallbackReasoning: "API 未返回 reasoning_content。当前显示为客户端占位：\n- 用户叙事已接收，保持中立优先。\n- 下一步应拆分事实、解释、情绪和缺失信息。\n- 对单一结论保持低到中等置信度，寻找替代视角。",
        .thinkingHint: "将 DeepSeek 的 reasoning_content 直接展示在助手回复上方。",
        .modePrism: "棱镜",
        .modePrismShort: "棱镜",
        .autoSummarization: "自动归纳",
        .summaryInterval: "归纳频率",
        .autoSummaryHint: "每完成设定轮数的对话后自动归纳生成章节。切换对话时也会归纳未处理的内容。",
        .intervalOff: "关闭",
        .dialog2: "每 2 轮",
        .dialog5: "每 5 轮",
        .dialog10: "每 10 轮",
        .chapterSynthesized: "章节已更新",
        .emptyMirrorTitle: "棱镜",
        .emptyMirrorHint: "从一个具体场景开始。我会帮你拆分事实与解释、梳理感受，并在故事足够完整时提供多个可能的叙事视角。",
        // Onboarding
        .onboardingWelcomeTitle: "欢迎使用棱镜",
        .onboardingWelcomeBody: "棱镜是你的叙事反思伴侣。它帮助你讲述故事、看清盲点、找到出口——不是诊断，不是治疗，只是陪你走一段。",
        .onboardingPurposeTitle: "棱镜能做什么",
        .onboardingPurposeBody: "棱镜基于 DeepSeek 大语言模型，通过对话帮你梳理叙事中的事实、解释、情绪和未知信息。它不是心理医生，而是一面镜子。",
        .onboardingFeaturesTitle: "核心特性",
        .onboardingFeaturesBody: "棱镜提供多种方式帮你审视自己的故事：",
        .onboardingUITourTitle: "界面导览",
        .onboardingUITourBody: "了解棱镜的主要界面布局，快速上手：",
        .onboardingAPIKeyTitle: "配置 DeepSeek API",
        .onboardingAPIKeyBody: "棱镜需要连接 DeepSeek 模型才能工作。请在下方输入你的 API Key，或稍后在设置中配置。",
        .onboardingDataTitle: "数据与隐私",
        .onboardingDataBody: "你的所有数据都存储在本地，不会上传到任何第三方服务器（除了你选择的模型 API）。",
        .onboardingContinue: "继续",
        .onboardingSkip: "跳过引导",
        .onboardingGetStarted: "开始使用",
        .onboardingBack: "返回",
        .onboardingPageIndicator: "第 %d 页，共 %d 页",
        // Feature cards
        .featureNarrativeTitle: "叙事梳理",
        .featureNarrativeDesc: "帮你拆分事实与解释，区分「发生了什么」和「你怎么看」",
        .featureBlindspotTitle: "盲点识别",
        .featureBlindspotDesc: "识别思维螺旋、认知偏差和叙事中的缺失视角",
        .featurePerspectiveTitle: "多视角叙事",
        .featurePerspectiveDesc: "当故事足够完整时，提供多个可能的叙事版本供你参考",
        .featureChapterTitle: "章节归纳",
        .featureChapterDesc: "自动将长对话归纳为带标题、摘要和关键词的章节",
        // UI tour cards
        .uiSidebarTitle: "侧边栏",
        .uiSidebarDesc: "左侧边栏显示对话列表和已归纳的章节。右键可重命名或删除对话，点击信息按钮查看章节详情。",
        .uiChatTitle: "对话区域",
        .uiChatDesc: "中央区域显示你与棱镜的对话。每条助手消息上方可展开「思考链」查看模型的推理过程。",
        .uiInputTitle: "输入框",
        .uiInputDesc: "底部输入框支持多行输入。按 Return 发送，Shift+Return 换行。消息下方有编辑、重新生成和删除按钮。",
        .uiToolbarTitle: "工具栏",
        .uiToolbarDesc: "右上角工具栏：📝 新建对话，⚙️ 打开设置，可配置模型参数、API Key、归纳频率、界面语言等。",
        // Data cards
        .dataStorageTitle: "对话数据",
        .dataStorageDesc: "对话内容保存在 ~/Documents/Prism/conversations.json，可通过设置更改存储路径。",
        .dataConfigTitle: "配置文件",
        .dataConfigDesc: "API Key、模型参数、语言偏好等设置保存在 config.json 中，与对话数据在同一目录。",
        .dataPrivacyTitle: "隐私优先",
        .dataPrivacyDesc: "所有数据 100% 本地存储。发送给 DeepSeek API 的仅限当前对话上下文，不会上传历史记录。",
        .dataArchiveTitle: "分析档案",
        .dataArchiveDesc: "人物档案、情绪时间线和盲点记录保存在数据目录的 Data 子文件夹中，用于跨对话检索。",
        // Reset
        .reset: "还原",
        .resetTitle: "还原所有设置和内容",
        .resetMessage: "此操作将删除所有对话记录、章节归纳、分析档案和 API Key 等设置，恢复为初始状态。应用需要重启。确定继续？",
        .resetButton: "还原并退出",
        .memory: "记忆",
        .memoryPeople: "人物",
        .memoryEmotions: "情绪轨迹",
        .memoryBlindspots: "叙事盲点",
        .memoryInsights: "洞察",
        .memoryEmptyTitle: "暂无记忆数据",
        .memoryEmptyHint: "当 v4-pro 调用 scan_blindspots 或归纳生成章节后，记忆会在这里呈现。",
        .memoryMentions: "提及",
        .memoryPersistent: "持续",
        .memoryRecurring: "反复",
        .memoryNew: "新发现",
        .memoryCounterQuestion: "反问",
        .memoryRecall: "回想",
        .memoryTimes: "次",
        .jumpToSource: "跳转至原文",
        .copy: "复制",
        .findInPage: "在对话中查找",
        .conversationMode: "对话模式",
        .conversationModel: "对话模型",
        .conversationModeHint: "理性模式更冷静分析，温情模式更注重共情。",
        .modeRational: "理性",
        .modeBalanced: "平衡",
        .modeWarm: "温情",
        .modeRationalDesc: "冷静分析，聚焦事实和逻辑结构",
        .modeBalancedDesc: "平衡共情与分析，适合大多数情况",
        .modeWarmDesc: "温暖陪伴，注重理解和情感支持",
        .responseLength: "回复长度",
        .responseLengthHint: "标准模式平衡清晰度与效率，简洁模式更直接，详细模式展开更多分析。",
        .modeBrief: "简洁",
        .modeStandard: "标准",
        .modeDetailed: "详细",
        .aiLabelDisclaimer: "对话内容由AI生成，有概率出错，仅供参考",
        .onboardingModeTitle: "选择对话模式",
        .onboardingModeBody: "棱镜提供三种对话模式，你可以随时在设置中切换：",
        .useiCloud: "使用 iCloud 存储",
        .iCloudActive: "数据存储在 iCloud Drive 中，所有设备自动同步",
        .iCloudUnavailable: "当前未登录 iCloud 或 iCloud 不可用",
    ]

    private static let traditional: [Key: String] = [
        .newConversation: "新對話",
        .settings: "設定",
        .delete: "刪除",
        .deletePairHint: "後面的助手回覆也將被刪除。",
        .rename: "重新命名",
        .renameHint: "輸入新名稱",
        .save: "儲存",
        .cancel: "取消",
        .reSummarize: "重新歸納",
        .summarizing: "正在歸納...",
        .search: "搜尋...",
        .noResults: "無匹配結果",
        .storage: "儲存",
        .dataPath: "資料路徑",
        .dataPathHint: "更改後需重啟應用生效",
        .choose: "選擇...",
        .edit: "編輯",
        .regenerate: "重新生成",
        .userName: "你",
        .assistantName: "稜鏡",
        .thinking: "思考鏈",
        .thinkingPlaceholder: "模型未返回 reasoning_content。",
        .deepSeek: "DeepSeek",
        .apiKey: "API Key",
        .baseURL: "Base URL",
        .model: "模型",
        .proModel: "Pro 模型",
        .flashModel: "Flash 模型",
        .modelParameters: "模型參數",
        .proParameters: "Pro 參數",
        .flashParameters: "Flash 參數",
        .temperature: "Temperature",
        .topP: "Top P",
        .maxTokens: "Max Tokens",
        .presencePenalty: "Presence Penalty",
        .frequencyPenalty: "Frequency Penalty",
        .thinkingMode: "深度思考",
        .reasoningEffort: "推理強度",
        .high: "高",
        .max: "最大",
        .interface: "介面",
        .language: "語言",
        .languageSimplifiedChinese: "简体中文",
        .languageTraditionalChinese: "繁體中文",
        .languageEnglish: "English",
        .conversations: "對話",
        .chapters: "章節",
        .noChapters: "繼續對話，每次歸納時將自動生成章節",
        .newConversationTitle: "新對話",
        .openingMessage: "從一個具體場景開始。我會幫你拆分事實與解釋、梳理感受，並在故事足夠完整時提供多個可能的敘事視角。",
        .openingReasoning: "初始引導：邀請使用者從一個具體場景開始敘述，不急於判斷。",
        .requestFailedMessage: "暫時無法連線模型。請檢查 API Key、模型名稱和網路設定。",
        .requestFailedReasoning: "請求失敗",
        .requestCancelledMessage: "對話已取消",
        .requestCancelledReasoning: "生成已取消",
        .cancelledSuffix: "已取消",
        .fallbackReasoning: "API 未返回 reasoning_content。當前顯示為用戶端占位：\n- 使用者敘事已接收，保持中立優先。\n- 下一步應拆分事實、解釋、情緒和缺失資訊。\n- 對單一結論保持低到中等置信度，尋找替代視角。",
        .thinkingHint: "將 DeepSeek 的 reasoning_content 直接展示在助手回覆上方。",
        .modePrism: "稜鏡",
        .modePrismShort: "稜鏡",
        .autoSummarization: "自動歸納",
        .summaryInterval: "歸納頻率",
        .autoSummaryHint: "每完成設定輪數的對話後自動歸納生成章節。切換對話時也會歸納未處理的內容。",
        .intervalOff: "關閉",
        .dialog2: "每 2 輪",
        .dialog5: "每 5 輪",
        .dialog10: "每 10 輪",
        .chapterSynthesized: "章節已更新",
        .emptyMirrorTitle: "稜鏡",
        .emptyMirrorHint: "從一個具體場景開始。我會幫你拆分事實與解釋、梳理感受，並在故事足夠完整時提供多個可能的敘事視角。",
        // Onboarding
        .onboardingWelcomeTitle: "歡迎使用稜鏡",
        .onboardingWelcomeBody: "稜鏡是你的敘事反思伴侶。它幫助你講述故事、看清盲點、找到出口——不是診斷，不是治療，只是陪你走一段。",
        .onboardingPurposeTitle: "稜鏡能做什麼",
        .onboardingPurposeBody: "稜鏡基於 DeepSeek 大語言模型，透過對話幫你梳理敘事中的事實、解釋、情緒和未知資訊。它不是心理醫生，而是一面鏡子。",
        .onboardingFeaturesTitle: "核心特性",
        .onboardingFeaturesBody: "稜鏡提供多種方式幫你審視自己的故事：",
        .onboardingUITourTitle: "介面導覽",
        .onboardingUITourBody: "了解稜鏡的主要介面佈局，快速上手：",
        .onboardingAPIKeyTitle: "設定 DeepSeek API",
        .onboardingAPIKeyBody: "稜鏡需要連接 DeepSeek 模型才能運作。請在下方輸入你的 API Key，或稍後在設定中配置。",
        .onboardingDataTitle: "資料與隱私",
        .onboardingDataBody: "你的所有資料都儲存在本機，不會上傳到任何第三方伺服器（除了你選擇的模型 API）。",
        .onboardingContinue: "繼續",
        .onboardingSkip: "跳過引導",
        .onboardingGetStarted: "開始使用",
        .onboardingBack: "返回",
        .onboardingPageIndicator: "第 %d 頁，共 %d 頁",
        // Feature cards
        .featureNarrativeTitle: "敘事梳理",
        .featureNarrativeDesc: "幫你拆分事實與解釋，區分「發生了什麼」和「你怎麼看」",
        .featureBlindspotTitle: "盲點識別",
        .featureBlindspotDesc: "識別思維螺旋、認知偏差和敘事中的缺失視角",
        .featurePerspectiveTitle: "多視角敘事",
        .featurePerspectiveDesc: "當故事足夠完整時，提供多個可能的敘事版本供你參考",
        .featureChapterTitle: "章節歸納",
        .featureChapterDesc: "自動將長對話歸納為帶標題、摘要和關鍵詞的章節",
        // UI tour cards
        .uiSidebarTitle: "側邊欄",
        .uiSidebarDesc: "左側側邊欄顯示對話列表和已歸納的章節。右鍵可重新命名或刪除對話，點擊資訊按鈕查看章節詳情。",
        .uiChatTitle: "對話區域",
        .uiChatDesc: "中央區域顯示你與稜鏡的對話。每條助手訊息上方可展開「思考鏈」檢視模型的推理過程。",
        .uiInputTitle: "輸入框",
        .uiInputDesc: "底部輸入框支援多行輸入。按 Return 發送，Shift+Return 換行。訊息下方有編輯、重新生成和刪除按鈕。",
        .uiToolbarTitle: "工具列",
        .uiToolbarDesc: "右上角工具列：📝 新增對話，⚙️ 開啟設定，可配置模型參數、API Key、歸納頻率、介面語言等。",
        // Data cards
        .dataStorageTitle: "對話資料",
        .dataStorageDesc: "對話內容儲存在 ~/Documents/Prism/conversations.json，可透過設定更改儲存路徑。",
        .dataConfigTitle: "設定檔",
        .dataConfigDesc: "API Key、模型參數、語言偏好等設定儲存在 config.json 中，與對話資料在同一目錄。",
        .dataPrivacyTitle: "隱私優先",
        .dataPrivacyDesc: "所有資料 100% 本機儲存。發送給 DeepSeek API 的僅限當前對話上下文，不會上傳歷史記錄。",
        .dataArchiveTitle: "分析檔案",
        .dataArchiveDesc: "人物檔案、情緒時間線和盲點記錄儲存在資料目錄的 Data 子資料夾中，用於跨對話檢索。",
        // Reset
        .reset: "還原",
        .resetTitle: "還原所有設定和內容",
        .resetMessage: "此操作將刪除所有對話記錄、章節歸納、分析檔案和 API Key 等設定，恢復為初始狀態。應用需要重啟。確定繼續？",
        .resetButton: "還原並退出",
        .memory: "記憶",
        .memoryPeople: "人物",
        .memoryEmotions: "情緒軌跡",
        .memoryBlindspots: "敘事盲點",
        .memoryInsights: "洞察",
        .memoryEmptyTitle: "暫無記憶資料",
        .memoryEmptyHint: "當 v4-pro 調用 scan_blindspots 或歸納生成章節後，記憶會在這裡呈現。",
        .memoryMentions: "提及",
        .memoryPersistent: "持續",
        .memoryRecurring: "反覆",
        .memoryNew: "新發現",
        .memoryCounterQuestion: "反問",
        .memoryRecall: "回想",
        .memoryTimes: "次",
        .jumpToSource: "跳轉至原文",
        .copy: "複製",
        .findInPage: "在對話中搜尋",
        .conversationMode: "對話模式",
        .conversationModel: "對話模型",
        .conversationModeHint: "理性模式更冷靜分析，溫情模式更注重共情。",
        .modeRational: "理性",
        .modeBalanced: "平衡",
        .modeWarm: "溫情",
        .modeRationalDesc: "冷靜分析，聚焦事實和邏輯結構",
        .modeBalancedDesc: "平衡共情與分析，適合大多數情況",
        .modeWarmDesc: "溫暖陪伴，注重理解和情感支持",
        .responseLength: "回覆長度",
        .responseLengthHint: "標準模式平衡清晰度與效率，簡潔模式更直接，詳細模式展開更多分析。",
        .modeBrief: "簡潔",
        .modeStandard: "標準",
        .modeDetailed: "詳細",
        .aiLabelDisclaimer: "對話內容由AI生成，有概率出錯，僅供參考",
        .onboardingModeTitle: "選擇對話模式",
        .onboardingModeBody: "稜鏡提供三種對話模式，你可以隨時在設定中切換：",
        .useiCloud: "使用 iCloud 儲存",
        .iCloudActive: "資料儲存在 iCloud Drive 中，所有裝置自動同步",
        .iCloudUnavailable: "目前未登入 iCloud 或 iCloud 不可用",
    ]

    private static let english: [Key: String] = [
        .newConversation: "New Chat",
        .settings: "Settings",
        .delete: "Delete",
        .deletePairHint: "The following assistant reply will also be deleted.",
        .rename: "Rename",
        .renameHint: "Enter new name",
        .save: "Save",
        .cancel: "Cancel",
        .reSummarize: "Re-synthesize",
        .summarizing: "Synthesizing...",
        .search: "Search...",
        .noResults: "No results",
        .storage: "Storage",
        .dataPath: "Data Path",
        .dataPathHint: "Restart app after changing",
        .choose: "Choose...",
        .edit: "Edit",
        .regenerate: "Regenerate",
        .userName: "You",
        .assistantName: "Prism",
        .thinking: "Reasoning",
        .thinkingPlaceholder: "The model did not return reasoning_content.",
        .deepSeek: "DeepSeek",
        .apiKey: "API Key",
        .baseURL: "Base URL",
        .model: "Model",
        .proModel: "Pro Model",
        .flashModel: "Flash Model",
        .modelParameters: "Model Parameters",
        .proParameters: "Pro Parameters",
        .flashParameters: "Flash Parameters",
        .temperature: "Temperature",
        .topP: "Top P",
        .maxTokens: "Max Tokens",
        .presencePenalty: "Presence Penalty",
        .frequencyPenalty: "Frequency Penalty",
        .thinkingMode: "Deep Thinking",
        .reasoningEffort: "Reasoning Effort",
        .high: "High",
        .max: "Max",
        .interface: "Interface",
        .language: "Language",
        .languageSimplifiedChinese: "简体中文",
        .languageTraditionalChinese: "繁體中文",
        .languageEnglish: "English",
        .conversations: "Conversations",
        .chapters: "Chapters",
        .noChapters: "Continue chatting; chapters are auto-generated during synthesis",
        .newConversationTitle: "New Chat",
        .openingMessage: "Start with a concrete moment. I'll help you separate facts from interpretations, trace feelings, and — when the story is complete — offer multiple narrative perspectives.",
        .openingReasoning: "Initial guide: invite a concrete scene; do not rush to judge.",
        .requestFailedMessage: "Unable to reach the model. Please check your API key, model name, and network.",
        .requestFailedReasoning: "Request failed",
        .requestCancelledMessage: "Response cancelled",
        .requestCancelledReasoning: "Generation was cancelled by user",
        .cancelledSuffix: "Cancelled",
        .fallbackReasoning: "API returned no reasoning_content. Client placeholder:\n- User narrative received; remain neutral.\n- Next: separate facts, interpretations, emotions, and unknowns.\n- Keep confidence low-to-medium for any single conclusion; seek alternative perspectives.",
        .thinkingHint: "DeepSeek reasoning_content displayed inline above the assistant response.",
        .modePrism: "Prism",
        .modePrismShort: "Prism",
        .autoSummarization: "Auto-Synthesis",
        .summaryInterval: "Synthesis Interval",
        .autoSummaryHint: "Chapters are auto-synthesized after the chosen number of dialog turns, and when switching conversations.",
        .intervalOff: "Off",
        .dialog2: "Every 2 turns",
        .dialog5: "Every 5 turns",
        .dialog10: "Every 10 turns",
        .chapterSynthesized: "Chapter synthesized",
        .emptyMirrorTitle: "Prism",
        .emptyMirrorHint: "Start with a concrete moment. I'll help you separate facts from interpretations, trace feelings, and — when the story is complete — offer multiple narrative perspectives.",
        // Onboarding
        .onboardingWelcomeTitle: "Welcome to Prism",
        .onboardingWelcomeBody: "Prism is your narrative reflection companion. It helps you tell your story fully, see blind spots, and find a way forward — not diagnosis, not therapy, just walking alongside you.",
        .onboardingPurposeTitle: "What Prism Does",
        .onboardingPurposeBody: "Powered by DeepSeek, Prism helps you separate facts from interpretations, trace emotions, and identify what's unknown in your narrative. It's not a therapist — it's a mirror.",
        .onboardingFeaturesTitle: "Core Features",
        .onboardingFeaturesBody: "Prism gives you multiple ways to examine your story:",
        .onboardingUITourTitle: "Interface Tour",
        .onboardingUITourBody: "A quick walkthrough of Prism's main interface:",
        .onboardingAPIKeyTitle: "Configure DeepSeek API",
        .onboardingAPIKeyBody: "Prism needs a DeepSeek API key to function. Enter your key below, or configure it later in Settings.",
        .onboardingDataTitle: "Data & Privacy",
        .onboardingDataBody: "All your data is stored locally. Nothing is uploaded to any third-party server except the model API you configure.",
        .onboardingContinue: "Continue",
        .onboardingSkip: "Skip Setup",
        .onboardingGetStarted: "Get Started",
        .onboardingBack: "Back",
        .onboardingPageIndicator: "Page %d of %d",
        // Feature cards
        .featureNarrativeTitle: "Narrative Mapping",
        .featureNarrativeDesc: "Separates facts from interpretations — what happened vs. how you see it",
        .featureBlindspotTitle: "Blind Spot Detection",
        .featureBlindspotDesc: "Identifies thought spirals, cognitive biases, and missing perspectives",
        .featurePerspectiveTitle: "Multi-Perspective Narratives",
        .featurePerspectiveDesc: "When the story is complete, offers alternative narrative versions for your consideration",
        .featureChapterTitle: "Chapter Synthesis",
        .featureChapterDesc: "Auto-summarizes long conversations into chapters with titles, summaries, and keywords",
        // UI tour cards
        .uiSidebarTitle: "Sidebar",
        .uiSidebarDesc: "The left sidebar shows your conversations and synthesized chapters. Right-click to rename or delete conversations; click the info button to view chapter details.",
        .uiChatTitle: "Chat Area",
        .uiChatDesc: "The central area displays your conversation with Prism. Above each assistant message, expand the «Reasoning» panel to see the model's thought process.",
        .uiInputTitle: "Input Bar",
        .uiInputDesc: "The bottom input area supports multi-line text. Press Return to send, Shift+Return for a new line. Use the edit, regenerate, and delete buttons below each message.",
        .uiToolbarTitle: "Toolbar",
        .uiToolbarDesc: "Top-right toolbar: 📝 New Conversation, ⚙️ Settings — configure model parameters, API key, synthesis frequency, and interface language.",
        // Data cards
        .dataStorageTitle: "Conversation Data",
        .dataStorageDesc: "Conversations are saved to ~/Documents/Prism/conversations.json. You can change the storage path in Settings.",
        .dataConfigTitle: "Configuration",
        .dataConfigDesc: "API key, model parameters, and language preferences are stored in config.json, in the same directory as your conversations.",
        .dataPrivacyTitle: "Privacy First",
        .dataPrivacyDesc: "All data is 100% local. Only the current conversation context is sent to the DeepSeek API — no history is ever uploaded.",
        .dataArchiveTitle: "Analysis Archive",
        .dataArchiveDesc: "Person records, emotion timelines, and blind spot logs are stored in the Data subfolder within your data directory, enabling cross-conversation retrieval.",
        // Reset
        .reset: "Reset",
        .resetTitle: "Reset All Settings & Content",
        .resetMessage: "This will delete all conversations, chapter summaries, analysis archives, API key, and other settings — restoring the app to its initial state. A restart is required. Continue?",
        .resetButton: "Reset & Quit",
        .memory: "Memory",
        .memoryPeople: "People",
        .memoryEmotions: "Emotions",
        .memoryBlindspots: "Blindspots",
        .memoryInsights: "Insights",
        .memoryEmptyTitle: "No Memory Data",
        .memoryEmptyHint: "Memory entries appear here when v4-pro runs scan_blindspots or when chapters are summarized.",
        .memoryMentions: "mentioned",
        .memoryPersistent: "persistent",
        .memoryRecurring: "recurring",
        .memoryNew: "new",
        .memoryCounterQuestion: "Ask",
        .memoryRecall: "recall",
        .memoryTimes: "×",
        .jumpToSource: "Jump to Source",
        .copy: "Copy",
        .findInPage: "Find in Conversation",
        .conversationMode: "Conversation Mode",
        .conversationModel: "Conversation Model",
        .conversationModeHint: "Rational is more analytical. Warm is more empathetic.",
        .modeRational: "Rational",
        .modeBalanced: "Balanced",
        .modeWarm: "Warm",
        .modeRationalDesc: "Analytical and logic-focused, minimal empathy",
        .modeBalancedDesc: "Balanced empathy and analysis, suitable for most situations",
        .modeWarmDesc: "Warm companionship with emotional support",
        .responseLength: "Response Length",
        .responseLengthHint: "Standard balances clarity with efficiency. Brief is more direct. Detailed provides thorough analysis.",
        .modeBrief: "Brief",
        .modeStandard: "Standard",
        .modeDetailed: "Detailed",
        .aiLabelDisclaimer: "AI-generated content may contain errors. For reference only.",
        .onboardingModeTitle: "Choose Conversation Mode",
        .onboardingModeBody: "Prism offers three conversation modes. You can switch at any time in Settings:",
        .useiCloud: "Use iCloud Storage",
        .iCloudActive: "Data stored in iCloud Drive, synced across all devices",
        .iCloudUnavailable: "iCloud not available or not signed in",
    ]
}
