// ─── Prism — Renderer App.js ─────────────────────────────────────────
// Complete renderer logic — calls invoke() via Tauri IPC

// ── Logger shorthand ──────────────────────────────────────────
var L = window.PrismLog || { d: function(){}, i: function(){}, w: function(){}, e: function(){} };

// Keep interface symbols in one visual language. Emoji vary by macOS version
// and font, so all actionable UI icons use the same lightweight SVG stroke.
var ICON_PATHS = {
  prism: '<path d="m12 2 3.4 6.6L22 12l-6.6 3.4L12 22l-3.4-6.6L2 12l6.6-3.4L12 2Z"/><circle cx="12" cy="12" r="2.2"/>',
  scale: '<path d="M5 5h14M12 5v14M7 19h10M5 5l-3 6a3 3 0 0 0 6 0L5 5ZM19 5l-3 6a3 3 0 0 0 6 0l-3-6Z"/>',
  bookmark: '<path d="M6 4.5A2.5 2.5 0 0 1 8.5 2h7A2.5 2.5 0 0 1 18 4.5V21l-6-3.5L6 21V4.5Z"/>',
  layers: '<path d="m12 3 9 5-9 5-9-5 9-5Z"/><path d="m3 12 9 5 9-5M3 16l9 5 9-5"/>',
  memory: '<path d="M9 5.5A3.5 3.5 0 0 0 5.5 9c0 .5.1 1 .3 1.4A3.5 3.5 0 0 0 7 17a3.5 3.5 0 0 0 3 2.2V6.5A3 3 0 0 0 9 5.5ZM15 5.5A3.5 3.5 0 0 1 18.5 9c0 .5-.1 1-.3 1.4A3.5 3.5 0 0 1 17 17a3.5 3.5 0 0 1-3 2.2V6.5a3 3 0 0 1 1-1Z"/><path d="M10 10H8M14 10h2M10 14H8M14 14h2"/>',
  refresh: '<path d="M20 11a8 8 0 0 0-14.9-4"/><path d="M4 4v5h5M4 13a8 8 0 0 0 14.9 4"/><path d="M20 20v-5h-5"/>',
  archive: '<path d="M5 4h14v16H5z"/><path d="M8 4v16M10.5 8h6M10.5 12h6M10.5 16h4"/>',
  messagePlus: '<path d="M5 5h14a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H9l-4 3v-3a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2Z"/><path d="M12 8v6M9 11h6"/>',
  chart: '<path d="M4 19V5M4 19h16M8 16v-4M12 16V8M16 16V5M20 16v-7"/>',
  search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
  brain: '<path d="M9 5.5A3.5 3.5 0 0 0 5.5 9c0 .5.1 1 .3 1.4A3.5 3.5 0 0 0 7 17a3.5 3.5 0 0 0 3 2.2V6.5A3 3 0 0 0 9 5.5ZM15 5.5A3.5 3.5 0 0 1 18.5 9c0 .5-.1 1-.3 1.4A3.5 3.5 0 0 1 17 17a3.5 3.5 0 0 1-3 2.2V6.5a3 3 0 0 1 1-1Z"/><path d="M10 10H8M14 10h2M10 14H8M14 14h2"/>',
  monitor: '<rect x="3" y="4" width="18" height="13" rx="2"/><path d="M8 21h8M12 17v4"/>',
  key: '<circle cx="8" cy="15" r="4"/><path d="m11 12 9-9M16 7l2 2M18 5l2 2"/>',
  folder: '<path d="M3 7.5A2.5 2.5 0 0 1 5.5 5H10l2 2h6.5A2.5 2.5 0 0 1 21 9.5v8A2.5 2.5 0 0 1 18.5 20h-13A2.5 2.5 0 0 1 3 17.5v-10Z"/>',
  cloud: '<path d="M7.5 18a5.5 5.5 0 1 1 1.7-10.7A6 6 0 0 1 20 10.5 3.5 3.5 0 0 1 18.5 18h-11Z"/>',
  shield: '<path d="M12 3 20 6v5c0 5-3.2 8.2-8 10-4.8-1.8-8-5-8-10V6l8-3Z"/><path d="m9 12 2 2 4-4"/>',
  users: '<path d="M16 20v-1.5a3.5 3.5 0 0 0-3.5-3.5h-5A3.5 3.5 0 0 0 4 18.5V20M10 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7ZM16 4.5a3.5 3.5 0 0 1 0 6.8M16 15h1.5a3.5 3.5 0 0 1 3.5 3.5V20"/>',
  activity: '<path d="M3 12h4l2-7 4 14 2-7h6"/>',
  eye: '<path d="M2.5 12s3.5-6 9.5-6 9.5 6 9.5 6-3.5 6-9.5 6-9.5-6-9.5-6Z"/><circle cx="12" cy="12" r="2.5"/>',
  bulb: '<path d="M9 18h6M10 21h4M8.5 14.5A6 6 0 1 1 15.5 15c-.8.7-1.3 1.4-1.5 3h-4c-.2-1.6-.7-2.3-1.5-3Z"/>',
  tool: '<path d="m14.5 6.5 3-3a5 5 0 0 0-6.6 6.6L4 17a2.1 2.1 0 1 0 3 3l6.1-6.9a5 5 0 0 0 6.6-6.6l-3 3-2.2-.3-.3-2.2Z"/>',
  settings: '<path d="M4 6h16M4 12h16M4 18h16"/><circle cx="8" cy="6" r="2"/><circle cx="16" cy="12" r="2"/><circle cx="10" cy="18" r="2"/>',
  gear: '<path d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 0 0 2.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 0 0 1.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 0 0-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 0 0-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 0 0-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 0 0-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 0 0 1.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065Z"/><path d="M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z"/>',
  x: '<path d="M6 6l12 12M18 6 6 18"/>',
  check: '<path d="m5 12 4 4L19 6"/>',
  wrench: '<path d="M14.5 6.5 17 4a5 5 0 0 0-6.6 6.6L4 17a2.1 2.1 0 1 0 3 3l6.1-6.9A5 5 0 0 0 19 6.5l-3 3-2.2-.3-.3-2.2Z"/>',
  wand: '<path d="m15 4 5 5M13 6l5 5M4 20 17 7M3 13l2 2M7 3v3M4 4h3"/>'
};
function iconSvg(name, className) {
  return '<svg class="' + (className || 'ui-icon') + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (ICON_PATHS[name] || ICON_PATHS.prism) + '</svg>';
}

// ── Invoke wrapper with logging ──────────────────────────────
function loggedInvoke(cmd, args) {
  L.d('IPC', 'invoke: ' + cmd, args || {});
  // Do not cache this function: the bridge can be injected after app.js is
  // evaluated, and a cached fallback makes every UI action permanently fail.
  return window.__TAURI_INVOKE__(cmd, args).catch(function(err) {
    L.e('IPC', 'invoke FAILED: ' + cmd, { error: String(err), args: args || {} });
    throw err;
  });
}
// ── API surface ──────────────────────────────────────────────
window.api = {
  createConversation: function(m) { return loggedInvoke('create_conversation', { mode: m || 'balanced' }); },
  deleteConversation: function(i) { return loggedInvoke('delete_conversation', { id: i }); },
  deleteMessagePair: function(c, m) { return loggedInvoke('delete_message_pair', { convId: c.toString(), msgId: m.toString() }); },
  truncateConversation: function(c, m) { return loggedInvoke('truncate_conversation', { convId: c.toString(), msgId: m.toString() }); },
  listConversations: function() { return loggedInvoke('list_conversations'); },
  getConversation: function(i) { return loggedInvoke('get_conversation', { id: i }); },
  getContextUsage: function(i) { return loggedInvoke('get_context_usage', { convId: i.toString() }); },
  setMode: function(c, m) { return loggedInvoke('set_mode', { convId: c.toString(), mode: m }); },
  setTitle: function(c, t) { return loggedInvoke('set_title', { convId: c.toString(), title: t }); },
  summarizeOnDeselect: function(c) { return loggedInvoke('summarize_deselect', { convId: c.toString() }); },
  fullReSummarize: function(c) { return loggedInvoke('re_summarize', { convId: c.toString() }); },
  sendMessage: function(c, t) { return loggedInvoke('send_message', { convId: c.toString(), text: t }); },
  startDragging: function() { return loggedInvoke('start_window_dragging'); },
  cancelMessage: function() { return loggedInvoke('cancel_message'); },
  getSettings: function() { return loggedInvoke('get_settings'); },
  saveSettings: function(s) { return loggedInvoke('save_settings', { settings: s }); },
  chooseDirectory: function() { return loggedInvoke('choose_directory'); },
  getStoragePaths: function() { return loggedInvoke('get_storage_paths'); },
  exportLogs: function() { return loggedInvoke('export_logs'); },
  resetAllSettings: function() { return loggedInvoke('reset_all_settings'); },
  queryEmotions: function() { return loggedInvoke('query_emotions'); },
  queryPersons: function() { return loggedInvoke('query_persons'); },
  queryPerson: function(n) { return loggedInvoke('query_person', { name: n }); },
  queryMemory: function(q) { return loggedInvoke('query_memory', { query: q || null }); },
  queryNarrativeEvents: function(c) { return loggedInvoke('query_narrative_events', { convId: c || null }); },
  getUsageStats: function() { return loggedInvoke('get_usage_stats'); },
  getUserBalance: function() { return loggedInvoke('get_user_balance'); },
  queryBlindspots: function() { return loggedInvoke('query_blindspots'); },
  getChapters: function(c) { return loggedInvoke('get_chapters', { convId: c.toString() }); },
  getChapterMessages: function(c, i) { return loggedInvoke('get_chapter_messages', { convId: c.toString(), index: i }); },
  searchChapters: function(c, q) { return loggedInvoke('search_chapters', { convId: c.toString(), query: q }); },
  getPlatform: function() { return window.__TAURI_PLATFORM__().then(function(p) { return p === 'darwin' ? 'darwin' : 'win32'; }); },
  getVersion: function() { return '1.0.15'; },
  getLogs: function() { return Promise.resolve(window.PrismLog ? window.PrismLog.getBuffer() : []); },
  validateApiKey: function(key, baseUrl) { return loggedInvoke('validate_api_key', { apiKey: key, baseUrl: baseUrl || 'https://api.deepseek.com' }); }
};

// ═══════════════════════════════════════════════════════════════════════
// LOCALIZATION
// ═══════════════════════════════════════════════════════════════════════
const I18N = {
  en: {
    search: 'Search...',
    conversations: 'Conversations',
    chapters: 'Chapters',
    newConversation: 'New Conversation',
    memory: 'Memory',
    settings: 'Settings',
    you: 'You',
    prism: 'Prism',
    reasoningChain: 'Reasoning Chain',
    copy: 'Copy',
    retry: 'Retry',
    delete: 'Delete',
    edit: 'Edit',
    cancel: 'Cancel',
    save: 'Save',
    typePlaceholder: 'Type your message...',
    aiDisclaimer: 'AI-generated content may contain errors. For reference only.',
    ready: 'Ready',
    thinking: 'Thinking...',
    thinkingNow: 'Thinking…',
    confirmDeleteConv: 'Are you sure you want to delete this conversation?',
    confirmDeleteMsg: 'This will delete the message pair (your message and the assistant\'s reply).',
    rename: 'Rename',
    noMessages: 'No messages yet',
    emptyTitle: 'Prism',
    emptyDesc: 'Start with a concrete moment. I\'ll help you separate facts from interpretations, trace feelings, and — when the story is complete — offer multiple narrative perspectives.',
    apiKeyTitle: 'API Key Required',
    apiKeyDesc: 'Prism uses DeepSeek\'s API for emotion analysis.\nEnter your API key to get started.',
    people: 'People',
    emotionTimeline: 'Emotion Timeline',
    conversationTimeline: 'Narrative Timeline',
    modelUsage: 'Model Usage',
    inputTokens: 'Input tokens',
    outputTokens: 'Output tokens',
    cacheHitRate: 'Cache hit rate',
    accountBalance: 'Account balance',
    balanceUnavailable: 'Balance unavailable',
    totalBalance: 'Total',
    grantedBalance: 'Granted',
    toppedUpBalance: 'Topped up',
    noNarrativeEvents: 'Narrated events with a clear period or date will appear here.',
    conversationStarted: 'Conversation started',
    firstMessage: 'First message',
    lastMessage: 'Latest message',
    elapsed: 'Elapsed',
    blindspots: 'Blind Spots',
    insights: 'Insights',
    memoryInsights: 'Insights & Memory',
    mentions: 'mentions',
    usingTool: 'Using tool: ',
    toolDone: 'Tool completed',
    error: 'Error',
    copied: 'Copied to clipboard',
    settingsSaved: 'Settings saved',
    apiKeySaved: 'API key saved',
    convCreated: 'New conversation created',
    convDeleted: 'Conversation deleted',
    rational: 'Rational',
    balanced: 'Balanced',
    warm: 'Warm',
    mode: 'Mode',
    apiConfig: 'API Configuration',
    apiKey: 'API Key',
    baseUrl: 'Base URL',
    models: 'Models',
    conversationModel: 'Conversation Model',
    flashModelOption: 'V4 Flash (default)',
    proModelOption: 'V4 Pro',
    flashModel: 'Flash Model',
    proModel: 'Pro Model',
    preferences: 'Preferences',
    language: 'Language',
    defaultMode: 'Default Mode',
    dataStorage: 'Data Storage',
    dataNote: 'All data stored locally. No data sent to third parties except DeepSeek API calls.',
    chapterDetail: 'Chapter Detail',
    summary: 'Summary',
    jumpToSource: 'Jump to Source',
    keywords: 'Keywords',
    originalMessages: 'Original Messages',
    noChapters: 'Chapters will appear here after several exchanges.',
    noPeople: 'People mentioned in your narratives will appear here.',
    noEmotions: 'Emotional observations will appear here as you converse.',
    noInsights: 'Insights will be generated as patterns emerge across conversations.',
    noBlindspots: 'Cognitive blind spots will appear here when detected.',
    refreshChapters: 'Re-summarize chapters',
    summaryInterval: 'Auto-Synthesis Interval',
    responseLength: 'Response Length',
    brief: 'Brief',
    standard: 'Standard',
    detailed: 'Detailed',
    contextWindow: 'Automatic Context Management',
    contextWindowHint: '55% only shows a capacity notice and does not change the request. Compression starts at 75%, with stronger protection at 85%. Local messages are never deleted.',
    proParams: 'Pro Parameters (Reasoner)',
    flashParams: 'Flash Parameters',
    deepThinking: 'Deep Thinking',
    reasoningEffort: 'Reasoning Effort',
    icloudSync: 'iCloud Storage Sync',
    storagePath: 'Storage Directory',
    changePath: 'Choose...',
    factoryReset: 'Factory Reset',
    confirmReset: 'Are you sure you want to reset all data? This cannot be undone.',
    resetMessage: 'This will permanently delete all conversations, archives, memories, and settings. Prism will close after reset.',
    resetTitle: 'Reset Prism',
    summarizing: 'Summarizing...',
    chapterSynthesized: 'Chapter Synthesized',
    enableLogging: 'Enable Debug Logging',
    loggingNote: 'Logs are stored in ~/Documents/Prism/prism.log. Disable to reduce disk usage.',
    exportLogs: 'Export Logs',
    exportLogsHint: 'Save a copy of the current diagnostic log.',
    noApiKeyError: 'No API key configured. Please set your DeepSeek API key in Settings to send messages.',
    apiKeyInvalid: 'API key validation failed. The key may be invalid or the service is unreachable.',
    apiKeyInvalidContinue: 'Do you want to continue anyway? You can change the key later in Settings.',
  },
  zh: {
    search: '搜索...',
    conversations: '对话',
    chapters: '章节',
    newConversation: '新对话',
    memory: '记忆',
    settings: '设置',
    you: '你',
    prism: 'Prism',
    reasoningChain: '思考链',
    copy: '复制',
    retry: '重试',
    delete: '删除',
    edit: '编辑',
    cancel: '取消',
    save: '保存',
    typePlaceholder: '输入消息...',
    aiDisclaimer: '对话内容由AI生成，有概率出错，仅供参考',
    ready: '就绪',
    thinking: '思考中...',
    thinkingNow: '正在思考…',
    confirmDeleteConv: '确定要删除这个对话吗？',
    confirmDeleteMsg: '这将删除这对消息（你的消息和助手的回复）。',
    rename: '重命名',
    noMessages: '暂无消息',
    emptyTitle: 'Prism',
    emptyDesc: '从一个具体场景开始。我会帮你拆分事实与解释、梳理感受，并在故事足够完整时提供多个可能的叙事视角。',
    apiKeyTitle: '需要 API 密钥',
    apiKeyDesc: 'Prism 使用 DeepSeek 的 API 进行情感分析。\n输入你的 API 密钥以开始使用。',
    people: '人物',
    emotionTimeline: '情绪轨迹',
    conversationTimeline: '叙事时间轴',
    modelUsage: '模型用量',
    inputTokens: '输入 Token',
    outputTokens: '输出 Token',
    cacheHitRate: '缓存命中率',
    accountBalance: '账户余额',
    balanceUnavailable: '余额暂不可用',
    totalBalance: '总余额',
    grantedBalance: '赠余额度',
    toppedUpBalance: '充值余额',
    noNarrativeEvents: '带有明确时期或日期的叙事事件会显示在这里。',
    conversationStarted: '对话发起',
    firstMessage: '第一条消息',
    lastMessage: '最近消息',
    elapsed: '已跨时长',
    blindspots: '认知盲点',
    insights: '洞察',
    memoryInsights: '洞察与记忆',
    mentions: '次提及',
    usingTool: '使用工具：',
    toolDone: '工具完成',
    error: '错误',
    copied: '已复制到剪贴板',
    settingsSaved: '设置已保存',
    apiKeySaved: 'API 密钥已保存',
    convCreated: '新对话已创建',
    convDeleted: '对话已删除',
    rational: '理性',
    balanced: '平衡',
    warm: '温暖',
    mode: '模式',
    apiConfig: 'API 配置',
    apiKey: 'API 密钥',
    baseUrl: '基础 URL',
    models: '模型',
    conversationModel: '对话模型',
    flashModelOption: 'V4 Flash（默认）',
    proModelOption: 'V4 Pro',
    flashModel: 'Flash 模型',
    proModel: 'Pro 模型',
    preferences: '偏好设置',
    language: '语言',
    defaultMode: '默认模式',
    dataStorage: '数据存储',
    dataNote: '所有数据存储在本地。除 DeepSeek API 调用外，不向第三方发送数据。',
    chapterDetail: '章节详情',
    summary: '摘要',
    jumpToSource: '定位原文',
    keywords: '关键词',
    originalMessages: '原始消息',
    noChapters: '章节将在多轮对话后出现。',
    noPeople: '叙述中提到的人物将显示在这里。',
    noEmotions: '随着对话进行，情绪观察将显示在这里。',
    noInsights: '随着对话模式的出现，洞察将被生成。',
    noBlindspots: '检测到的认知盲点将在此显示。',
    refreshChapters: '重新归纳章节',
    summaryInterval: '自动章节合成间隔',
    responseLength: '回复长度',
    brief: '简洁',
    standard: '正常',
    detailed: '偏长',
    contextWindow: '自动上下文管理',
    contextWindowHint: '55% 仅显示容量提醒且不改变发送内容，75% 才开始压缩，85% 加强保护；本地原始消息不会删除。',
    proParams: 'Pro 模型参数 (Reasoner)',
    flashParams: 'Flash 模型参数',
    deepThinking: '深度思考开关',
    reasoningEffort: '思考深度',
    icloudSync: 'iCloud 云同步存储',
    storagePath: '数据存储目录',
    changePath: '选择...',
    factoryReset: '恢复出厂设置',
    confirmReset: '确认重置所有数据？此操作不可撤销。',
    resetMessage: '这将永久删除所有对话、归档、记忆和设置。重置后 Prism 将退出运行。',
    resetTitle: '重置 Prism',
    summarizing: '归纳中...',
    chapterSynthesized: '章节已更新',
    enableLogging: '启用调试日志',
    loggingNote: '日志文件存储在 ~/Documents/Prism/prism.log。关闭可减少磁盘占用。',
    exportLogs: '导出日志',
    exportLogsHint: '保存一份当前诊断日志。',
    noApiKeyError: '未配置 API 密钥。请在设置中输入 DeepSeek API 密钥后再发送消息。',
    apiKeyInvalid: 'API 密钥验证失败。密钥可能无效或服务不可达。',
    apiKeyInvalidContinue: '是否继续？你可以稍后在设置中修改密钥。',
  },
  'zh-hant': {
    search: '搜尋...',
    conversations: '對話',
    chapters: '章節',
    newConversation: '新對話',
    memory: '記憶',
    settings: '設定',
    you: '你',
    prism: 'Prism',
    reasoningChain: '思考鏈',
    copy: '複製',
    retry: '重試',
    delete: '刪除',
    edit: '編輯',
    cancel: '取消',
    save: '儲存',
    typePlaceholder: '輸入訊息...',
    aiDisclaimer: '對話內容由AI生成，有機率出錯，僅供參考',
    ready: '就緒',
    thinking: '思考中...',
    thinkingNow: '正在思考…',
    confirmDeleteConv: '確定要刪除這個對話嗎？',
    confirmDeleteMsg: '這將刪除這對訊息（你的訊息和助手的回覆）。',
    rename: '重新命名',
    noMessages: '暫無訊息',
    emptyTitle: 'Prism',
    emptyDesc: '從一個具體場景開始。我會幫你拆分事實與解釋、梳理感受，並在故事足夠完整時提供多個可能的敘事視角。',
    apiKeyTitle: '需要 API 金鑰',
    apiKeyDesc: 'Prism 使用 DeepSeek 的 API 進行情感分析。\n輸入你的 API 金鑰以開始使用。',
    people: '人物',
    emotionTimeline: '情緒軌跡',
    conversationTimeline: '敘事時間軸',
    modelUsage: '模型用量',
    inputTokens: '輸入 Token',
    outputTokens: '輸出 Token',
    cacheHitRate: '快取命中率',
    accountBalance: '帳戶餘額',
    balanceUnavailable: '餘額暫不可用',
    totalBalance: '總餘額',
    grantedBalance: '贈送餘額',
    toppedUpBalance: '充值餘額',
    noNarrativeEvents: '帶有明確時期或日期的敘事事件會顯示在這裡。',
    conversationStarted: '對話發起',
    firstMessage: '第一則訊息',
    lastMessage: '最近訊息',
    elapsed: '已跨時長',
    blindspots: '認知盲點',
    insights: '洞察',
    memoryInsights: '洞察與記憶',
    mentions: '次提及',
    usingTool: '使用工具：',
    toolDone: '工具完成',
    error: '錯誤',
    copied: '已複製到剪貼簿',
    settingsSaved: '設定已儲存',
    apiKeySaved: 'API 金鑰已儲存',
    convCreated: '新對話已建立',
    convDeleted: '對話已刪除',
    rational: '理性',
    balanced: '平衡',
    warm: '溫慢',
    mode: '模式',
    apiConfig: 'API 設定',
    apiKey: 'API 金鑰',
    baseUrl: '基礎 URL',
    models: '模型',
    conversationModel: '對話模型',
    flashModelOption: 'V4 Flash（預設）',
    proModelOption: 'V4 Pro',
    flashModel: 'Flash 模型',
    proModel: 'Pro 模型',
    preferences: '偏好設定',
    language: '語言',
    defaultMode: '預設模式',
    dataStorage: '資料儲存',
    dataNote: '所有資料儲存在本地。除 DeepSeek API 呼叫外，不向第三方發送資料。',
    chapterDetail: '章節詳情',
    summary: '摘要',
    jumpToSource: '定位原文',
    keywords: '關鍵詞',
    originalMessages: '原始訊息',
    noChapters: '章節將在多輪對話後出現。',
    noPeople: '敘述中提到的人物將顯示在這裡。',
    noEmotions: '隨著對話進行，情緒觀察將顯示在這裡。',
    noInsights: '隨著對話模式的出現，洞察將被生成。',
    noBlindspots: '檢測到的認知盲點將在此顯示。',
    refreshChapters: '重新歸納章節',
    summaryInterval: '自動章節合成間隔',
    responseLength: '回覆長度',
    brief: '簡潔',
    standard: '正常',
    detailed: '偏長',
    contextWindow: '自動上下文管理',
    contextWindowHint: '55% 僅顯示容量提醒且不改變傳送內容，75% 才開始壓縮，85% 加強保護；本機原始訊息不會刪除。',
    proParams: 'Pro 模型參數 (Reasoner)',
    flashParams: 'Flash 模型參數',
    deepThinking: '深度思考開關',
    reasoningEffort: '思考深度',
    icloudSync: 'iCloud 雲同步儲存',
    storagePath: '資料儲存目錄',
    changePath: '選擇...',
    factoryReset: '恢復出廠設置',
    confirmReset: '確認重置所有數據？此操作不可撤銷。',
    resetMessage: '這將永久刪除所有對話、歸檔、記憶和設置。重置後 Prism 將退出運行。',
    resetTitle: '重置 Prism',
    summarizing: '歸納中...',
    chapterSynthesized: '章節已更新',
    enableLogging: '啟用除錯日誌',
    loggingNote: '日誌檔案存儲在 ~/Documents/Prism/prism.log。關閉可減少磁碟佔用。',
    exportLogs: '匯出日誌',
    exportLogsHint: '儲存一份目前的診斷日誌。',
    noApiKeyError: '未設定 API 金鑰。請在設定中輸入 DeepSeek API 金鑰後再發送訊息。',
    apiKeyInvalid: 'API 金鑰驗證失敗。金鑰可能無效或服務不可達。',
    apiKeyInvalidContinue: '是否繼續？你可以稍後在設定中修改金鑰。',
  }
};

// ═══════════════════════════════════════════════════════════════════════
// STATE
// ═══════════════════════════════════════════════════════════════════════
const S = {
  conversations: [],
  activeId: null,
  messages: [],
  mode: 'balanced',
  isProcessing: false,
  streamingMsgIdx: -1,
  streamingText: '',
  streamingReasoning: '',
  isStartingConversation: false,
  ctxConvId: null,
  apiKeySet: false,
  settings: null,
  lang: 'en',
  platform: 'windows',
  chapters: [],
  providerBalance: null,
  contextUsage: null,
  convSectionOpen: true,
  chapterSectionOpen: true,
  isAtBottom: true,
  // The user turn that owns the current viewport. Keep it pinned through
  // every streaming/final re-render; clear it only when changing chats.
  pinnedUserMsgIdx: null,
};

const MODES = ['rational', 'balanced', 'warm'];

function getLangKey(lang) {
  if (!lang) return 'en';
  const l = lang.toLowerCase();
  if (l.includes('hant')) return 'zh-hant';
  if (l.includes('zh') || l.includes('hans')) return 'zh';
  return 'en';
}

function t(key) {
  const lKey = getLangKey(S.lang);
  return I18N[lKey]?.[key] || I18N.en[key] || key;
}

function setThinkingStatus(active) {
  const indicator = document.getElementById('thinkingStatus');
  const label = document.getElementById('thinkingStatusLabel');
  if (!indicator) return;
  if (label) label.textContent = t('thinkingNow');
  indicator.hidden = !active;
}

function installNativeWindowDragging() {
  const regions = document.querySelectorAll('.window-drag-region, .chat-hdr, .hdr-center');
  const interactive = 'button, input, textarea, select, a, .mode-badge, .hdr-toolbar';
  regions.forEach(region => {
    region.addEventListener('mousedown', event => {
      if (event.button !== 0 || event.target.closest(interactive)) return;
      // Prevent the WebView from treating this as text selection; the native
      // command below owns the drag gesture.
      event.preventDefault();
      window.api.startDragging().catch(error => {
        L.w('Window', 'Native drag request failed', { error: errMsg(error) });
      });
    });
  });
  L.i('Window', 'Native drag regions installed', { count: regions.length });
}

// ═══════════════════════════════════════════════════════════════════════
// INITIALIZATION
// ═══════════════════════════════════════════════════════════════════════
document.addEventListener('DOMContentLoaded', async () => {
  // Older builds rendered a second, detached “Thinking…” pill above the
  // composer. Remove it if a WebView retained stale DOM and keep the only
  // visible status inside the active assistant bubble.
  document.querySelectorAll('#thinkingStatus, .thinking-status').forEach(el => el.remove());

  // Tauri may expose its global after DOMContentLoaded. Await the bridge so
  // every handler below is wired against the real IPC implementation.
  const bridgeReady = await (window.__TAURI_READY_PROMISE__ || Promise.resolve(window.__TAURI_READY__));
  // ── Tauri readiness check ──────────────────────────────
  if (!bridgeReady || !window.__TAURI_READY__) {
    L.e('Init', 'Tauri runtime NOT detected — app launched outside Tauri webview?');
    showErrorBanner('Tauri runtime not detected. Please run this app inside the Prism application.');
    setStatus('Error: Tauri not available');
    // Still allow the UI to render for debugging, but all invoke calls will fail.
  } else {
    L.i('Init', 'Tauri IPC bridge ready, starting app initialization');
  }

  try{
    var p = await window.__TAURI_PLATFORM__();
    S.platform = p;
    document.body.classList.add(p === 'darwin' ? 'mac' : 'win');
    L.i('Init', 'Platform detected: ' + p);
  } catch(e) {
    document.body.classList.add('win');
    L.w('Init', 'Platform detection failed, defaulting to win', { error: String(e) });
  }

  try{
    await window.__TAURI_LISTEN__('msg:event', function(event) {
      handleMsgEvent(event.payload);
    });
    L.i('Init', 'Event listener registered for msg:event');
  } catch(e) {
    L.e('Init', 'Failed to register msg:event listener', { error: String(e) });
  }

  // Wire up UI handlers
  document.getElementById('newChatBtn').onclick = newConv;
  document.getElementById('searchInput').oninput = filterConversations;
  document.getElementById('sendBtn').onclick = onSend;
  document.getElementById('msgInput').onkeydown = e => {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); onSend(); }
  };
  document.getElementById('msgInput').oninput = function() {
    autoResize(this);
    updateSendBtn();
  };
  installNativeWindowDragging();

  // Header buttons
  // Replace the old toolbar glyphs at runtime as well, so an installed app
  // cannot retain the previous brain/pencil/sliders artwork from cached HTML.
  document.getElementById('memBtn').innerHTML = iconSvg('memory');
  document.getElementById('refreshChaptersBtn').innerHTML = iconSvg('refresh');
  document.getElementById('newChatBtn').innerHTML = iconSvg('messagePlus');
  document.getElementById('settingsBtn').innerHTML = iconSvg('gear');
  const chapterSectionIcon = document.querySelector('#chapterSectionHdr .section-icon');
  if (chapterSectionIcon) chapterSectionIcon.innerHTML = iconSvg('bookmark');
  document.getElementById('settingsBtn').onclick = openSettings;
  document.getElementById('memBtn').onclick = openMemory;
  document.getElementById('modeBadge').onclick = cycleMode;
  document.getElementById('contextBadge').onclick = function(event) {
    event.stopPropagation();
    const popover = document.getElementById('contextPopover');
    const willOpen = popover.hidden;
    popover.hidden = !willOpen;
    this.classList.toggle('open', willOpen);
    this.setAttribute('aria-expanded', String(willOpen));
  };

  // Modal close buttons
  document.getElementById('closeSettings').onclick = closeSettings;
  document.getElementById('closeMem').onclick = closeMemory;
  document.getElementById('closeChDetail').onclick = closeChapterDetail;

  // Confirm dialog
  document.getElementById('confirmNo').onclick = closeConfirm;
  document.getElementById('confirmYes').onclick = confirmAction;

  // Context menu
  document.getElementById('ctxRename').onclick = doRename;
  document.getElementById('ctxDelete').onclick = doDelete;
  document.addEventListener('click', event => {
    closeCtxMenu();
    if (!event.target.closest('#contextPopover, #contextBadge')) closeContextPopover();
  });
  // Prism is a native desktop window, not a browser tab. Suppress the
  // WebView's default context menu (Reload/Inspect/etc.) everywhere except
  // conversation rows, which use Prism's own rename/delete menu.
  document.addEventListener('contextmenu', e => {
    if (!e.target.closest('.conv-item, .conv-menu-btn, .ctx-menu')) {
      e.preventDefault();
    }
  });

  // Sidebar sections
  document.getElementById('convSectionHdr').onclick = () => toggleSection('conv');
  document.getElementById('chapterSectionHdr').onclick = () => toggleSection('chapter');
  document.getElementById('refreshChaptersBtn').onclick = async e => {
    e.stopPropagation();
    if (!S.activeId || S.isProcessing) return;
    setChapterSummarizingState('summarizing');
    try {
      await window.api.fullReSummarize(S.activeId);
      setChapterSummarizingState('done');
      await loadChapters();
    } catch(err) {
      setStatus(t('error') + ': ' + err.message);
      setChapterSummarizingState('idle');
    }
  };

  // Scroll management
  const msgArea = document.getElementById('msgArea');
  msgArea.addEventListener('scroll', checkScrollPosition);
  document.getElementById('scrollBottomBtn').onclick = scrollToBottom;

  // Close overlays on backdrop click
  document.querySelectorAll('.overlay').forEach(overlay => {
    overlay.addEventListener('click', e => {
      // Setup is a transactional flow. Clicking outside the card must not
      // discard the in-memory choices and expose the main window as if they
      // were saved.
      if (e.target === overlay && overlay.id !== 'onboardingOverlay') {
        overlay.classList.remove('open');
      }
    });
  });

  // Keyboard shortcuts
  document.addEventListener('keydown', e => {
    if (e.key === 'Escape') {
      document.querySelectorAll('.overlay.open').forEach(o => {
        if (o.id !== 'onboardingOverlay') o.classList.remove('open');
      });
    }
  });

  // Load settings
  try {
    S.settings = await window.api.getSettings();
    L.i('Init', 'Settings loaded', { lang: S.settings.language, mode: S.settings.defaultMode, hasApiKey: !!S.settings.apiKey });
    if (S.settings.apiKey) {
      S.apiKeySet = true;
      // Account metadata is refreshed at launch without a model call. The
      // Memory panel reuses this value and refreshes on demand if needed.
      window.api.getUserBalance().then(balance => {
        S.providerBalance = balance;
      }).catch(error => {
        L.w('Init', 'Provider balance unavailable', { error: errMsg(error) });
      });
    }
    if (S.settings.defaultMode) {
      S.mode = S.settings.defaultMode;
    }
    if (S.settings.language) {
      S.lang = S.settings.language;
    }
    // Apply logging toggle
    if (S.settings.enableLogging === false) {
      if (window.PrismLog) window.PrismLog.disable();
      L.i('Init', 'Logging disabled per settings');
    } else {
      if (window.PrismLog) window.PrismLog.enable();
    }
    updateAllText();
    updateModeUI();

    if (!S.settings.onboardingCompleted) {
      L.i('Init', 'Onboarding not completed, starting wizard');
      startOnboarding();
    }
  } catch (e) {
    L.e('Init', 'Failed to load settings', { error: String(e) });
    console.error('Failed to load settings:', e);
  }

  // Load conversations
  await loadConversations();

  // Auto-select first if exists
  if (S.conversations.length > 0) {
    selectConv(S.conversations[0].id);
  } else {
    // Keep the chapter section visible even before the first conversation;
    // Swift shows the empty chapter state in the sidebar at all times.
    loadChapters();
  }
});

// ═══════════════════════════════════════════════════════════════════════
// LOCALIZATION — Update all static text
// ═══════════════════════════════════════════════════════════════════════
function updateAllText() {
  document.getElementById('searchInput').placeholder = t('search');
  document.getElementById('convSectionLabel').textContent = t('conversations');
  document.getElementById('chapterSectionLabel').textContent = t('chapters');
  document.getElementById('msgInput').placeholder = t('typePlaceholder');
  document.getElementById('hdrSubtitle').textContent = t('aiDisclaimer');
  const statusTxt = document.getElementById('statusTxt');
  if (statusTxt) statusTxt.textContent = t('ready');
  document.getElementById('ctxRenameLabel').textContent = t('rename');
  document.getElementById('ctxDeleteLabel').textContent = t('delete');
  document.getElementById('settingsTitle').innerHTML = iconSvg('settings') + '<span>' + esc(t('settings')) + '</span>';
  document.getElementById('memTitle').innerHTML = iconSvg('brain') + '<span>' + esc(t('memory')) + '</span>';
  document.getElementById('refreshChaptersBtn').title = t('refreshChapters');

  // Mode labels
  document.getElementById('modeLabel').textContent = t(S.mode);

  // Toolbar tooltips
  document.getElementById('memBtn').title = t('memory');
  document.getElementById('newChatBtn').title = t('newConversation');
  document.getElementById('settingsBtn').title = t('settings');

  // Confirm dialog
  document.getElementById('confirmNo').textContent = t('cancel');
  document.getElementById('confirmYes').textContent = t('delete');

  // Empty state
  const emptyState = document.getElementById('emptyState');
  emptyState.querySelector('h2').textContent = t('emptyTitle');
  emptyState.querySelector('p').innerHTML = t('emptyDesc').replace(/\n/g, '<br>');
  setThinkingStatus(S.isProcessing);
  renderContextUsage();
}

// ═══════════════════════════════════════════════════════════════════════
// IPC EVENT HANDLER (streaming from main process)
// ═══════════════════════════════════════════════════════════════════════
function handleMsgEvent(event) {
  switch (event.type) {
    case 'text':
      S.streamingText += event.content;
      if (S.streamingMsgIdx >= 0 && S.messages[S.streamingMsgIdx]) {
        S.messages[S.streamingMsgIdx].content = S.streamingText;
      }
      updateStreamingMsg();
      break;
    case 'reasoning':
      S.streamingReasoning += event.content;
      if (S.streamingMsgIdx >= 0 && S.messages[S.streamingMsgIdx]) {
        S.messages[S.streamingMsgIdx].reasoning = S.streamingReasoning;
      }
      updateStreamingMsg();
      break;
    case 'tool-call':
      L.d('Stream', 'Tool call: ' + event.name);
      setStatus(t('usingTool') + event.name);
      addToolCallBadge(event.name);
      break;
    case 'tool-result':
      L.d('Stream', 'Tool result: ' + (event.name || ''));
      setStatus(t('toolDone'));
      break;
    case 'error':
      L.e('Stream', 'Stream error', { error: event.error });
      showErrorBanner(event.error);
      finishStreaming();
      break;
    case 'done':
      L.i('Stream', 'Message stream completed', { convId: event.convId });
      finishStreaming();
      if (event.title) {
        const conv = S.conversations.find(c => c.id === event.convId);
        if (conv) { conv.title = event.title; renderSidebar(); }
        if (S.activeId === event.convId) {
          document.getElementById('hdrTitle').textContent = event.title;
        }
      }
      loadConversations();
      setStatus(t('ready'));
      break;
    case 'summarizing':
      L.i('Stream', 'Chapter summarization started', { convId: event.convId });
      if (S.activeId === event.convId) {
        setChapterSummarizingState('summarizing');
      }
      break;
    case 'chapters-updated':
      L.i('Stream', 'Chapters updated', { convId: event.convId });
      if (S.activeId === event.convId) {
        setChapterSummarizingState('done');
        loadChapters();
        refreshContextUsage();
      }
      break;
    case 'summarize-failed':
      L.w('Stream', 'Chapter summarization failed', { convId: event.convId });
      if (S.activeId === event.convId) {
        setChapterSummarizingState('idle');
      }
      break;
    case 'conv-created':
      L.i('Stream', 'Conversation created via stream', { convId: event.convId });
      S.activeId = event.convId;
      loadConversations();
      document.getElementById('modeBadge').style.display = 'flex';
      document.getElementById('contextBadge').style.display = 'block';
      document.getElementById('composerWrap').style.display = 'flex';
      document.getElementById('emptyState').classList.add('hidden');
      updateSendBtn();
      refreshContextUsage();
      break;
    case 'processing':
      if (event.processing) {
        S.isProcessing = true;
        setThinkingStatus(true);
        updateSendBtn();
      } else {
        // Processing(false) is the final fence even if a Done event was
        // swallowed by the WebView. Always clear the local streaming state.
        finishStreaming();
        setStatus(t('ready'));
      }
      break;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// CONVERSATIONS
// ═══════════════════════════════════════════════════════════════════════
async function loadConversations() {
  try {
    S.conversations = await window.api.listConversations();
  } catch(e) {
    S.conversations = [];
  }
  renderSidebar();
}

function renderSidebar() {
  const list = document.getElementById('convList');
  list.innerHTML = '';
  document.getElementById('convCount').textContent = S.conversations.length;

  S.conversations.forEach(c => {
    const div = document.createElement('div');
    div.className = 'conv-item' + (c.id === S.activeId ? ' active' : '');
    div.dataset.id = c.id;

    div.innerHTML = `
      <div class="conv-title">${esc(c.title || t('newConversation'))}</div>
      <div class="conv-time">${c.updatedAt ? formatTime(c.updatedAt) : ''}</div>
      <button class="conv-menu-btn" data-id="${c.id}">⋯</button>
    `;

    div.querySelector('.conv-menu-btn').onclick = e => {
      e.stopPropagation(); openCtxMenu(e, c.id);
    };
    div.onclick = () => selectConv(c.id);
    div.oncontextmenu = e => { e.preventDefault(); openCtxMenu(e, c.id); };
    list.appendChild(div);
  });
}

async function selectConv(id) {
  if (S.isProcessing) return;
  L.i('UI', 'Selecting conversation', { id: id });
  if (S.activeId && S.activeId !== id) {
    const previousId = S.activeId;
    window.api.summarizeOnDeselect(previousId)
      .then(() => {
        L.i('Chapters', 'Conversation summarized on deselect', { convId: previousId });
        if (S.activeId === previousId) loadChapters();
      })
      .catch(error => {
        L.w('Chapters', 'Deselect summarization failed', { convId: previousId, error: errMsg(error) });
      });
  }
  clearErrorBanner();
  S.pinnedUserMsgIdx = null;
  S.messages = [];
  renderMessages();
  S.activeId = id;
  setChapterSummarizingState('idle');

  document.querySelectorAll('.conv-item').forEach(el =>
    el.classList.toggle('active', el.dataset.id === id)
  );

  document.getElementById('modeBadge').style.display = 'flex';
  document.getElementById('contextBadge').style.display = 'block';
  document.getElementById('composerWrap').style.display = 'flex';

  try {
    const conv = await window.api.getConversation(id);
    if (conv) {
      document.getElementById('hdrTitle').textContent = conv.title || t('newConversation');
      S.messages = conv.messages || [];
      if (conv.mode) S.mode = conv.mode;
      updateModeUI();
    }
  } catch(e) {
    setStatus(t('error') + ': Failed to load conversation');
  }
  renderMessages();
  loadChapters();
  updateSendBtn();
  refreshContextUsage();

  // Focus the input
  setTimeout(() => document.getElementById('msgInput').focus(), 100);
}

async function newConv() {
  if (S.isProcessing) return;
  try {
    const id = await window.api.createConversation(S.mode);
    await loadConversations();
    selectConv(id);
    setStatus(t('convCreated'));
  } catch(e) {
    setStatus(t('error') + ': ' + e.message);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// CHAPTERS
// ═══════════════════════════════════════════════════════════════════════
let doneStateTimeout = null;

function setChapterSummarizingState(state) {
  const btn = document.getElementById('refreshChaptersBtn');
  const summarizingBadge = document.getElementById('chapterBadgeSummarizing');
  const doneBadge = document.getElementById('chapterBadgeDone');

  if (doneStateTimeout) {
    clearTimeout(doneStateTimeout);
    doneStateTimeout = null;
  }

  // Update label texts in current language dynamically
  document.getElementById('lblSummarizing').textContent = t('summarizing');
  document.getElementById('lblSynthesized').textContent = t('chapterSynthesized');

  if (state === 'summarizing') {
    btn.style.display = 'none';
    summarizingBadge.style.display = 'inline-flex';
    doneBadge.style.display = 'none';
  } else if (state === 'done') {
    btn.style.display = 'none';
    summarizingBadge.style.display = 'none';
    doneBadge.style.display = 'inline-flex';
    doneStateTimeout = setTimeout(() => {
      setChapterSummarizingState('idle');
    }, 2500);
  } else {
    btn.style.display = 'inline-block';
    summarizingBadge.style.display = 'none';
    doneBadge.style.display = 'none';
  }
}

async function loadChapters() {
  if (!S.activeId) {
    S.chapters = [];
    document.getElementById('chapterSectionHdr').style.display = 'flex';
    document.getElementById('chapterBody').style.display = 'block';
    renderChapters();
    return;
  }

  try {
    S.chapters = await window.api.getChapters(S.activeId) || [];
  } catch(e) {
    S.chapters = [];
  }

  document.getElementById('chapterSectionHdr').style.display = 'flex';
  document.getElementById('chapterBody').style.display = 'block';

  renderChapters();
}

function renderChapters() {
  const list = document.getElementById('chapterList');
  list.innerHTML = '';

  if (S.chapters.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'empty-chapters-placeholder';
    empty.style.padding = '10px 12px';
    empty.style.color = 'var(--text-tertiary)';
    empty.style.fontSize = '12px';
    empty.style.lineHeight = '1.4';
    empty.style.fontStyle = 'italic';
    empty.textContent = t('noChapters');
    list.appendChild(empty);
    return;
  }

  S.chapters.forEach((ch, i) => {
    const div = document.createElement('div');
    div.className = 'chapter-item';
    div.innerHTML = `
      <div class="chapter-num">${i + 1}. ${esc(ch.title || 'Untitled')}</div>
      <div class="chapter-summary">${esc(ch.summary || '')}</div>
      ${ch.keywords?.length ? `<div class="chapter-keywords">${ch.keywords.map(k => esc(k)).join(' · ')}</div>` : ''}
      <button class="chapter-info-btn" data-idx="${i}" title="Details">
        <svg viewBox="0 0 24 24" fill="currentColor" fill-rule="evenodd" clip-rule="evenodd">
          <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 14h-2v-6h2v6zm0-8h-2V7h2v2z"/>
        </svg>
      </button>
    `;
    div.querySelector('.chapter-info-btn').onclick = e => {
      e.stopPropagation();
      viewChapterDetail(i);
    };
    div.onclick = () => {
      let msgId;
      if (ch.messageIDs?.length) {
        msgId = ch.messageIDs[0];
      } else if (ch.messageIndices?.length) {
        const idx = ch.messageIndices[0];
        const row = document.querySelector(`#msgArea .msg-row[data-idx="${idx}"]`);
        if (row) row.scrollIntoView({ behavior: 'smooth', block: 'center' });
        return;
      }
      if (msgId) {
        const el = document.querySelector(`[data-msg-id="${msgId}"]`);
        if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }
    };
    list.appendChild(div);
  });
}

async function viewChapterDetail(index) {
  if (!S.activeId) return;
  try {
    const chapters = S.chapters;
    const ch = chapters?.[index];
    if (!ch) return;

    const msgs = await window.api.getChapterMessages(S.activeId, index) || [];

    document.getElementById('chDetailTitle').textContent =
      (t('chapterDetail') + ': ' + (ch.title || `#${index + 1}`));

    // Update Jump to Source button
    const jumpBtn = document.getElementById('chDetailJumpBtn');
    document.getElementById('jumpBtnText').textContent = t('jumpToSource');
    if (ch.messageIDs?.length || ch.messageIndices?.length) {
      jumpBtn.style.display = 'flex';
      jumpBtn.onclick = () => {
        closeChapterDetail();
        if (ch.messageIDs?.length) {
          const msgId = ch.messageIDs[0];
          const el = document.querySelector(`[data-msg-id="${msgId}"]`);
          if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' });
        } else if (ch.messageIndices?.length) {
          const idx = ch.messageIndices[0];
          const row = document.querySelector(`#msgArea .msg-row[data-idx="${idx}"]`);
          if (row) row.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }
      };
    } else {
      jumpBtn.style.display = 'none';
    }

    let html = '';

    // Summary
    if (ch.summary) {
      html += `<div class="ch-summary">${esc(ch.summary)}</div>`;
    }

    // Keywords
    if (ch.keywords?.length) {
      html += '<div class="ch-keywords">';
      ch.keywords.forEach(k => {
        html += `<span class="ch-keyword">${esc(k)}</span>`;
      });
      html += '</div>';
    }

    // Original messages
    if (msgs.length) {
      html += `<div class="ch-messages-title">${t('originalMessages')}</div>`;
      msgs.forEach(m => {
        if (m.role === 'tool' || m.role === 'system') return;
        const isUser = m.role === 'user';
        html += `<div class="ch-msg ${isUser ? 'user-msg' : 'asst-msg'}">${md(m.content || '')}</div>`;
      });
    }

    document.getElementById('chDetailBody').innerHTML = html;
    document.getElementById('chDetailOverlay').classList.add('open');
  } catch(e) {
    setStatus(t('error') + ': ' + e.message);
  }
}

function closeChapterDetail() {
  document.getElementById('chDetailOverlay').classList.remove('open');
}

// ═══════════════════════════════════════════════════════════════════════
// SIDEBAR SECTIONS
// ═══════════════════════════════════════════════════════════════════════
function toggleSection(name) {
  if (name === 'conv') {
    S.convSectionOpen = !S.convSectionOpen;
    document.getElementById('convArrow').classList.toggle('collapsed', !S.convSectionOpen);
    document.getElementById('convBody').classList.toggle('collapsed', !S.convSectionOpen);
  } else if (name === 'chapter') {
    S.chapterSectionOpen = !S.chapterSectionOpen;
    document.getElementById('chapterArrow').classList.toggle('collapsed', !S.chapterSectionOpen);
    document.getElementById('chapterBody').classList.toggle('collapsed', !S.chapterSectionOpen);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// MESSAGES
// ═══════════════════════════════════════════════════════════════════════
function renderMessages({ pinIndex = S.pinnedUserMsgIdx } = {}) {
  const container = document.getElementById('msgArea');
  const empty = document.getElementById('emptyState');

  while (container.firstChild) container.removeChild(container.firstChild);
  container.appendChild(empty);

  if (!S.messages.length) {
    empty.classList.remove('hidden');
    return;
  }
  empty.classList.add('hidden');

  S.messages.forEach((msg, i) => {
    if (msg.role === 'tool' || msg.role === 'system') return;
    // Skip tool-round scaffolding persisted by older builds: empty assistant
    // messages that only carry tool_calls. They would render as phantom
    // empty bubbles; the real reply follows separately.
    if (msg.role === 'assistant' && !msg.content && msg.toolCalls && msg.toolCalls.length) return;
    const isMsgStreaming = (i === S.streamingMsgIdx && S.isProcessing);
    container.appendChild(createMsgEl(msg, i, isMsgStreaming));
  });

  if (Number.isInteger(pinIndex)) {
    // Keep enough scrollable space after the latest turn for its user message
    // to sit at the top while the assistant response grows underneath it.
    // Size it from the live viewport; percentage flex heights are unreliable
    // in WKWebView when the message stack is shorter than the viewport.
    const runway = document.createElement('div');
    runway.className = 'message-runway';
    runway.style.height = `${Math.max(140, container.clientHeight - 90)}px`;
    runway.setAttribute('aria-hidden', 'true');
    container.appendChild(runway);
    pinMessageToTop(pinIndex);
  } else {
    scrollToBottom();
  }
}

function createMsgEl(msg, index, isStreaming) {
  const isUser = msg.role === 'user';
  const row = document.createElement('div');
  row.className = 'msg-row ' + (isUser ? 'user' : 'assistant');
  row.dataset.idx = index;
  if (msg.id) row.dataset.msgId = msg.id;

  const hasReasoning = !!msg.reasoning;
  const hasContent = !!msg.content;
  const isReasoningOpen = hasReasoning && !hasContent; // Auto-collapse when real content starts flowing
  const rid = 'reason_' + index;

  const roleLabel = isUser ? t('you') : t('prism');

  let html = `<div class="msg-role">${esc(roleLabel)}</div>`;
  html += `<div class="msg-bubble ${isUser ? 'user' : 'assistant'}">`;

  // Keep a visible, lightweight status while the assistant is still working,
  // including the reasoning phase before the first text token arrives.
  if (!isUser && isStreaming && !hasContent && !hasReasoning) {
    html += `
      <div class="thinking-indicator" aria-live="polite">
        <span>${esc(t('thinkingNow'))}</span>
        <span class="thinking-track"><span class="thinking-thumb"></span></span>
      </div>
    `;
  }

  // Reasoning (assistant only)
  if (!isUser && hasReasoning) {
    html += `
      <div class="reasoning">
        <div class="reasoning-hdr" onclick="toggleReasoning('${rid}')">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>
          <span class="reasoning-label">${t('reasoningChain')}</span>
          <span class="reasoning-chevron ${isReasoningOpen ? 'open' : ''}" id="chevron_${rid}">›</span>
        </div>
        <div class="reasoning-body ${isReasoningOpen ? 'open' : ''}" id="${rid}">${esc(msg.reasoning)}</div>
      </div>
    `;
  }

  // Content
  const content = msg.content || '';
  if (content) {
    html += `<div class="msg-content">${md(content)}</div>`;
  }

  // Tool call badge
  if (msg.toolCalls?.length) {
    html += `<div class="tool-badge">${iconSvg('wrench')}<span>${t('usingTool')}${msg.toolCalls.map(tc => tc.name || '').join(', ')}</span></div>`;
  }

  html += '</div>'; // close bubble

  if (!isStreaming) {
    html += '<div class="msg-actions">';
    if (isUser) {
      html += `
        <button class="msg-action-btn" onclick="copyMessage(${index})" title="${t('copy')}">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
        </button>
        <button class="msg-action-btn" onclick="editMessage(${index})" title="${t('edit')}">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/></svg>
        </button>
      `;
    } else {
      html += `
        <button class="msg-action-btn" onclick="copyMessage(${index})" title="${t('copy')}">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
        </button>
        <button class="msg-action-btn" onclick="retryMessage(${index})" title="${t('retry')}">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/></svg>
        </button>
        <button class="msg-action-btn danger" onclick="deleteMessagePair(${index})" title="${t('delete')}">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/></svg>
        </button>
      `;
    }
    html += '</div>';
  }

  row.innerHTML = html;
  return row;
}

function updateStreamingMsg() {
  const idx = S.streamingMsgIdx;
  if (idx < 0) return;

  const container = document.getElementById('msgArea');
  const old = container.querySelector(`[data-idx="${idx}"]`);
  if (!old) return;

  const msg = S.messages[idx];
  if (!msg) return;

  const newEl = createMsgEl(msg, idx, true);
  old.replaceWith(newEl);

  if (S.isAtBottom) {
    scrollToBottom();
  } else {
    requestAnimationFrame(() => updateScrollBottomButton(container));
  }
}

function toggleReasoning(id) {
  const el = document.getElementById(id);
  const chevron = document.getElementById('chevron_' + id);
  if (!el) return;
  el.classList.toggle('open');
  if (chevron) chevron.classList.toggle('open');
}

// ═══════════════════════════════════════════════════════════════════════
// MESSAGE ACTIONS
// ═══════════════════════════════════════════════════════════════════════
function copyMessage(index) {
  const msg = S.messages[index];
  if (!msg) return;
  navigator.clipboard.writeText(msg.content || '').then(() => {
    showToast(t('copied'));
  }).catch(() => {});
}

function editMessage(index) {
  const msg = S.messages[index];
  if (!msg || msg.role !== 'user' || S.isProcessing) return;

  const input = document.getElementById('msgInput');
  input.value = msg.content || '';
  autoResize(input);
  input.focus();

  // Persist the truncation before allowing a replacement. Otherwise the
  // edited branch remains in model context and the UI/backend diverge.
  window.api.truncateConversation(S.activeId, msg.id).then(() => {
    S.messages = S.messages.slice(0, index);
    renderMessages();
  }).catch(e => setStatus(t('error') + ': ' + errMsg(e)));
}

function retryMessage(index) {
  if (S.isProcessing || !S.activeId) return;

  let userMsgIdx = -1;
  for (let i = index - 1; i >= 0; i--) {
    if (S.messages[i].role === 'user') {
      userMsgIdx = i;
      break;
    }
  }
  if (userMsgIdx < 0) return;

  const userMsg = S.messages[userMsgIdx];
  const userText = userMsg.content;

  if (!userMsg.id) return;
  window.api.truncateConversation(S.activeId, userMsg.id).then(() => {
    S.messages = S.messages.slice(0, userMsgIdx);
    startMessageRequest(userText);
  }).catch(e => setStatus(t('error') + ': ' + errMsg(e)));
}

function startMessageRequest(text) {
  if (!S.activeId || S.isProcessing) return;

  S.streamingText = '';
  S.streamingReasoning = '';

  const userMsg = { role: 'user', content: text, createdAt: new Date().toISOString() };
  const asstMsg = { role: 'assistant', content: '', reasoning: '', createdAt: new Date().toISOString() };
  S.messages.push(userMsg);
  S.messages.push(asstMsg);
  S.streamingMsgIdx = S.messages.length - 1;
  S.pinnedUserMsgIdx = S.messages.length - 2;
  S.isProcessing = true;
  setThinkingStatus(true);
  renderMessages();
  updateSendBtn();
  setStatus(t('thinking'));

  // The event stream normally clears processing on `done`. Keep the IPC
  // promise as a second completion fence so a dropped/missed final event can
  // never leave the composer stuck showing the red stop button.
  window.api.sendMessage(S.activeId, text)
    .then(() => {
      if (S.isProcessing) {
        L.w('UI', 'IPC completed without a final stream event; finishing locally');
        finishStreaming();
      }
    })
    .catch(handleSendFailure);
}

function deleteMessagePair(index) {
  if (S.isProcessing || !S.activeId) return;

  let userIdx = index;
  if (S.messages[index]?.role === 'assistant') {
    for (let i = index - 1; i >= 0; i--) {
      if (S.messages[i].role === 'user') {
        userIdx = i;
        break;
      }
    }
  }

  const userMsg = S.messages[userIdx];
  if (!userMsg || !userMsg.id) return;

  pendingConfirmAction = () => {
    window.api.deleteMessagePair(S.activeId, userMsg.id).then(() => {
      window.api.getConversation(S.activeId).then(conv => {
        if (conv) {
          S.messages = conv.messages || [];
          renderMessages();
        }
      });
    }).catch(e => setStatus(t('error') + ': ' + e.message));
  };

  document.getElementById('confirmMsg').textContent = t('confirmDeleteMsg');
  document.getElementById('confirmOverlay').classList.add('open');
}

// ═══════════════════════════════════════════════════════════════════════
// SENDING
// ═══════════════════════════════════════════════════════════════════════
function onSend() {
  if (S.isProcessing) {
    window.api.cancelMessage().catch(e => setStatus(t('error') + ': ' + errMsg(e)));
    return;
  }
  if (S.isStartingConversation) return;

  const input = document.getElementById('msgInput');
  const text = input.value.trim();
  if (!text) return;

  // ── API key check ─────────────────────────────────────
  if (!S.apiKeySet && !(S.settings && S.settings.apiKey)) {
    showErrorBanner(t('noApiKeyError'));
    L.e('UI', 'Cannot send: no API key configured');
    return;
  }

  // A fresh install has no selected conversation yet. The old flow called
  // startMessageRequest() with a null id, which returned immediately and
  // silently discarded the text. Create/select the first conversation before
  // clearing the composer so a failed IPC call never loses user input.
  (async () => {
    S.isStartingConversation = !S.activeId;
    try {
      if (!S.activeId) {
        const id = await window.api.createConversation(S.mode);
        // Do not await the full selectConv() path here. It performs several
        // secondary IPC reads (conversation/chapter loading), and a failure
        // or stalled read used to prevent the actual send_message invoke from
        // ever being reached. The new conversation is empty, so activate it
        // locally first and let the normal send path proceed immediately.
        S.activeId = id;
        // Refresh the sidebar independently; it must never block the send
        // request or make the composer lose the current text.
        loadConversations().catch(error => {
          L.w('UI', 'Conversation list refresh failed after creation', { error: errMsg(error) });
        });
        S.messages = [];
        document.getElementById('modeBadge').style.display = 'flex';
        document.getElementById('contextBadge').style.display = 'block';
        document.getElementById('composerWrap').style.display = 'flex';
        document.getElementById('emptyState').classList.add('hidden');
        renderMessages();
        loadChapters();
        updateSendBtn();
      }
      if (!S.activeId) throw new Error('Unable to create a conversation');

      L.i('UI', 'Sending message', { convId: S.activeId, textLen: text.length });
      clearErrorBanner();
      input.value = '';
      input.style.height = 'auto';

      startMessageRequest(text);

      const conv = S.conversations.find(c => c.id === S.activeId);
      if (conv) {
        conv.preview = text.substring(0, 60);
        renderSidebar();
      }
    } catch (error) {
      handleSendFailure(error);
    } finally {
      S.isStartingConversation = false;
      updateSendBtn();
    }
  })();
}

function handleSendFailure(error) {
  const message = errMsg(error);
  L.e('UI', 'Message request failed', { error: message });
  showErrorBanner(message);
  setStatus(t('error') + ': ' + message);
  finishStreaming();
}

function finishStreaming() {
  const wasStreaming = S.isProcessing || S.streamingMsgIdx >= 0;
  S.isProcessing = false;
  setThinkingStatus(false);
  S.streamingMsgIdx = -1;
  S.streamingText = '';
  S.streamingReasoning = '';
  updateSendBtn();
  // Re-render immediately so the in-bubble thinking indicator cannot linger
  // while the persisted conversation is being fetched from the backend.
  if (S.messages.length) renderMessages();

  if (!wasStreaming) return;

  if (S.activeId) {
    window.api.getConversation(S.activeId).then(conv => {
      if (conv) {
        S.messages = conv.messages || [];
        renderMessages();
      }
    }).catch(() => {});

    loadChapters();
    refreshContextUsage();
  }
}

function updateSendBtn() {
  const btn = document.getElementById('sendBtn');
  const input = document.getElementById('msgInput');
  if (S.isProcessing) {
    btn.className = 'send-btn stop';
    btn.innerHTML = `<svg viewBox="0 0 24 24" fill="currentColor" fill-rule="evenodd" clip-rule="evenodd">
      <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-4 6h8v8H8V8z" />
    </svg>`;
  } else {
    const hasText = input.value.trim().length > 0;
    btn.className = 'send-btn' + (hasText ? '' : ' disabled');
    btn.innerHTML = `<svg viewBox="0 0 24 24" fill="currentColor" fill-rule="evenodd" clip-rule="evenodd">
      <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 5l5 5h-4v5h-2v-5H7l5-5z"/>
    </svg>`;
  }
}

function addToolCallBadge(name) {
  const container = document.getElementById('msgArea');
  const row = container.querySelector(`[data-idx="${S.streamingMsgIdx}"]`);
  if (!row) return;
  const bubble = row.querySelector('.msg-bubble');
  if (!bubble) return;
  const existing = bubble.querySelector('.tool-badge');
  if (!existing) {
    const badge = document.createElement('div');
    badge.className = 'tool-badge';
    badge.innerHTML = iconSvg('wrench') + '<span>' + esc(name) + '</span>';
    bubble.appendChild(badge);
  } else {
    existing.innerHTML = iconSvg('wrench') + '<span>' + esc(name) + '</span>';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// MODE
// ═══════════════════════════════════════════════════════════════════════
function cycleMode() {
  const idx = MODES.indexOf(S.mode);
  S.mode = MODES[(idx + 1) % MODES.length];
  updateModeUI();
  if (S.activeId) window.api.setMode(S.activeId, S.mode);
  showToast(t('mode') + ': ' + t(S.mode));
}

function updateModeUI() {
  document.getElementById('modeLabel').textContent = t(S.mode);
  document.getElementById('modeDot').className = 'mode-dot ' + S.mode;
  const badge = document.getElementById('modeBadge');
  const accessibleLabel = t('mode') + ': ' + t(S.mode);
  badge.title = accessibleLabel;
  badge.setAttribute('aria-label', accessibleLabel);
}

// ═══════════════════════════════════════════════════════════════════════
// CURRENT-CONVERSATION CONTEXT USAGE
// ═══════════════════════════════════════════════════════════════════════
function contextCopy() {
  const lang = getLangKey(S.lang);
  if (lang === 'zh-hant') return {
    title: '目前對話上下文（估算）', tokens: '估算輸入 Token', before: '壓縮前估算', reserve: '回覆預留', messages: '本對話訊息數',
    active: s => `已達到 75%：傳送時壓縮舊內容，保留最近約 ${s.retainedRecentTokens.toLocaleString()} Token 原文；本機記錄不刪除。`,
    preparing: s => `目前佔用已超過 55%。這只是容量提醒，傳送內容不會變化；達到 75% 後才會壓縮舊內容，還差約 ${s.tokensUntilCompression.toLocaleString()} Token。`,
    pending: s => `達到 55% 時只顯示容量提醒，不會改變傳送內容（還差約 ${s.tokensUntilPreparation.toLocaleString()} Token）；達到 75% 後才會壓縮舊內容。`,
    summary: s => s.summaryInterval > 0 ? `章節約每 ${s.summaryInterval} 輪更新；距下次歸納約 ${s.dialogsUntilSummary} 輪。` : '自動章節歸納已停用。',
    normal: 'Prism 按 Token 佔用管理上下文；章節歸納不會提前刪除或替換原始對話。',
    high: '佔用升高會增加延遲與輸入成本；正式壓縮前，原始對話仍完整傳送。',
    critical: '未壓縮內容已超過 85%。Prism 會強制壓縮請求，避免截斷、失敗或擠佔回覆空間。'
  };
  if (lang === 'zh') return {
    title: '当前会话上下文（估算）', tokens: '估算输入 Token', before: '压缩前估算', reserve: '回复预留', messages: '本会话消息数',
    active: s => `已达到 75%：发送时压缩旧内容，保留最近约 ${s.retainedRecentTokens.toLocaleString()} Token 原文；本地记录不删除。`,
    preparing: s => `当前占用已超过 55%。这只是容量提醒，发送内容不会变化；达到 75% 后才会压缩旧内容，还差约 ${s.tokensUntilCompression.toLocaleString()} Token。`,
    pending: s => `达到 55% 时仅显示容量提醒，不会改变发送内容（还差约 ${s.tokensUntilPreparation.toLocaleString()} Token）；达到 75% 后才会压缩旧内容。`,
    summary: s => s.summaryInterval > 0 ? `章节约每 ${s.summaryInterval} 轮更新；距下次归纳约 ${s.dialogsUntilSummary} 轮。` : '自动章节归纳已停用。',
    normal: 'Prism 按 Token 占用管理上下文；章节归纳不会提前删除或替换原始对话。',
    high: '占用升高会增加延迟与输入成本；正式压缩前，原始对话仍完整发送。',
    critical: '未压缩内容已超过 85%。Prism 会强制压缩请求，避免截断、失败或挤占回复空间。'
  };
  return {
    title: 'Current conversation context (estimated)', tokens: 'Estimated input tokens', before: 'Before compression', reserve: 'Reserved for reply', messages: 'Messages in this chat',
    active: s => `At 75%: older request context is compressed while about ${s.retainedRecentTokens.toLocaleString()} recent tokens stay verbatim; local history is untouched.`,
    preparing: s => `Usage is above 55%. This is only a capacity notice and does not change the request; older context is compressed at 75%, about ${s.tokensUntilCompression.toLocaleString()} tokens away.`,
    pending: s => `At 55%, Prism only shows a capacity notice and does not change the request (about ${s.tokensUntilPreparation.toLocaleString()} tokens away); older context is compressed at 75%.`,
    summary: s => s.summaryInterval > 0 ? `Chapters update about every ${s.summaryInterval} turns; roughly ${s.dialogsUntilSummary} turns until the next synthesis.` : 'Automatic chapter synthesis is disabled.',
    normal: 'Prism manages context by token usage; chapter synthesis does not prematurely replace the raw conversation.',
    high: 'Higher usage increases latency and input cost; the raw transcript remains intact until formal compression.',
    critical: 'Uncompressed context is above 85%. Prism compacts the request to avoid truncation, failure, or crowding out the reply.'
  };
}

function contextPercent(snapshot) {
  if (!snapshot || !snapshot.capacityTokens) return 0;
  return Math.min(100, snapshot.estimatedTokens / snapshot.capacityTokens * 100);
}

function contextPercentLabel(snapshot) {
  const percent = contextPercent(snapshot);
  if (snapshot && snapshot.estimatedTokens > 0 && percent < 0.1) return '<0.1%';
  return percent.toFixed(1) + '%';
}

function closeContextPopover() {
  const popover = document.getElementById('contextPopover');
  const badge = document.getElementById('contextBadge');
  if (popover) popover.hidden = true;
  if (badge) {
    badge.classList.remove('open');
    badge.setAttribute('aria-expanded', 'false');
  }
}

function renderContextUsage() {
  const badge = document.getElementById('contextBadge');
  const popover = document.getElementById('contextPopover');
  if (!badge || !popover) return;
  const snapshot = S.contextUsage;
  if (!snapshot || !S.activeId) {
    badge.textContent = '--%';
    badge.style.display = 'none';
    closeContextPopover();
    return;
  }
  const copy = contextCopy();
  const percent = contextPercent(snapshot);
  const level = snapshot.critical ? 'critical' : snapshot.compressionActive ? 'warn' : snapshot.preparationActive ? 'prepare' : '';
  badge.style.display = 'block';
  badge.textContent = contextPercentLabel(snapshot);
  badge.title = copy.title;
  badge.setAttribute('aria-label', copy.title + ': ' + contextPercentLabel(snapshot));
  badge.classList.remove('prepare', 'warn', 'critical');
  if (level) badge.classList.add(level);
  const fmt = new Intl.NumberFormat(getLangKey(S.lang) === 'en' ? 'en' : 'zh-CN');
  const risk = level === 'critical' ? copy.critical : (snapshot.preparationActive ? copy.high : copy.normal);
  const compressionNote = snapshot.compressionActive
    ? copy.active(snapshot)
    : snapshot.preparationActive ? copy.preparing(snapshot) : copy.pending(snapshot);
  popover.innerHTML = `
    <div class="context-popover-hdr"><span>${esc(copy.title)}</span><strong>${esc(contextPercentLabel(snapshot))}</strong></div>
    <div class="context-meter"><div class="context-meter-fill" style="width:${percent}%"></div></div>
    <div class="context-detail-row"><span>${esc(copy.tokens)}</span><span>${fmt.format(snapshot.estimatedTokens)} / ${fmt.format(snapshot.capacityTokens)}</span></div>
    ${snapshot.compressionActive ? `<div class="context-detail-row"><span>${esc(copy.before)}</span><span>${fmt.format(snapshot.uncompressedEstimatedTokens)}</span></div>` : ''}
    <div class="context-detail-row"><span>${esc(copy.reserve)}</span><span>${fmt.format(snapshot.reservedOutputTokens)}</span></div>
    <div class="context-detail-row"><span>${esc(copy.messages)}</span><span>${fmt.format(snapshot.messageCount)}</span></div>
    <div class="context-divider"></div>
    <div class="context-note">${esc(compressionNote)}</div>
    <div class="context-note">${esc(copy.summary(snapshot))}</div>
    <div class="context-risk ${level}">${esc(risk)}</div>`;
}

async function refreshContextUsage() {
  const requestedId = S.activeId;
  if (!requestedId) {
    S.contextUsage = null;
    renderContextUsage();
    return;
  }
  try {
    const snapshot = await window.api.getContextUsage(requestedId);
    if (S.activeId !== requestedId) return;
    S.contextUsage = snapshot;
    renderContextUsage();
  } catch (error) {
    L.w('Context', 'Context usage unavailable', { error: errMsg(error) });
  }
}

// ═══════════════════════════════════════════════════════════════════════
// CONTEXT MENU
// ═══════════════════════════════════════════════════════════════════════
function openCtxMenu(e, id) {
  S.ctxConvId = id;
  const menu = document.getElementById('ctxMenu');
  menu.style.left = Math.min(e.clientX, window.innerWidth - 160) + 'px';
  menu.style.top = Math.min(e.clientY, window.innerHeight - 80) + 'px';
  menu.classList.add('open');
}

function closeCtxMenu() {
  document.getElementById('ctxMenu').classList.remove('open');
}

function doRename() {
  closeCtxMenu();
  if (!S.ctxConvId) return;

  const convEl = document.querySelector(`.conv-item[data-id="${S.ctxConvId}"]`);
  if (!convEl) return;

  const titleEl = convEl.querySelector('.conv-title');
  const conv = S.conversations.find(c => c.id === S.ctxConvId);
  if (!titleEl || !conv) return;

  const oldTitle = conv.title || '';

  const input = document.createElement('input');
  input.className = 'rename-input';
  input.value = oldTitle;
  input.type = 'text';

  titleEl.replaceWith(input);
  input.focus();
  input.select();

  const finishRename = () => {
    const name = input.value.trim();
    if (name && name !== oldTitle) {
      conv.title = name;
      window.api.setTitle(conv.id, name);
      if (S.activeId === conv.id) document.getElementById('hdrTitle').textContent = name;
    }
    renderSidebar();
  };

  input.onblur = finishRename;
  input.onkeydown = e => {
    if (e.key === 'Enter') { e.preventDefault(); input.blur(); }
    if (e.key === 'Escape') { input.value = oldTitle; input.blur(); }
  };
}

let pendingConfirmAction = null;

function doDelete() {
  closeCtxMenu();
  if (!S.ctxConvId) return;

  pendingConfirmAction = async () => {
    const id = S.ctxConvId;
    try {
      await window.api.deleteConversation(id);
      S.conversations = S.conversations.filter(c => c.id !== id);
      renderSidebar();
      if (S.activeId === id) {
        S.activeId = null;
        S.messages = [];
        S.chapters = [];
        document.getElementById('hdrTitle').textContent = '';
        document.getElementById('hdrSubtitle').textContent = t('aiDisclaimer');
        document.getElementById('modeBadge').style.display = 'none';
        document.getElementById('contextBadge').style.display = 'none';
        S.contextUsage = null;
        closeContextPopover();
        document.getElementById('chapterSectionHdr').style.display = 'none';
        document.getElementById('chapterBody').style.display = 'none';
        renderMessages();
      }
      setStatus(t('convDeleted'));
    } catch(e) {
      setStatus(t('error') + ': ' + e.message);
    }
  };

  document.getElementById('confirmMsg').textContent = t('confirmDeleteConv');
  document.getElementById('confirmOverlay').classList.add('open');
}

function closeConfirm() {
  document.getElementById('confirmOverlay').classList.remove('open');
  pendingConfirmAction = null;
}

function confirmAction() {
  document.getElementById('confirmOverlay').classList.remove('open');
  if (pendingConfirmAction) {
    pendingConfirmAction();
    pendingConfirmAction = null;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SETTINGS MODAL
// ═══════════════════════════════════════════════════════════════════════
async function openSettings() {
  const body = document.getElementById('settingsBody');
  const s = S.settings || {};
  const cloudSupported = S.platform === 'darwin';
  const cloudEnabled = cloudSupported && (s.iCloudSync ?? s.icloudSync ?? false);
  let storagePaths = {
    localPath: s.dataPath || '~/Documents/Prism',
    iCloudPath: null
  };
  try {
    storagePaths = await window.api.getStoragePaths();
  } catch (error) {
    L.w('Settings', 'Could not resolve storage paths', { error: errMsg(error) });
  }
  let localStoragePath = cloudEnabled ? storagePaths.localPath : (s.dataPath || storagePaths.localPath);

  body.innerHTML = `
    <div class="set-grp">
      <div class="set-lbl">${t('apiConfig')}</div>
      <div class="set-field"><label>${t('apiKey')}</label><input type="password" id="sApiKey" value="${esc(s.apiKey || '')}"></div>
      <div class="set-field"><label>${t('baseUrl')}</label><input type="text" id="sBaseUrl" value="${esc(s.baseUrl || 'https://api.deepseek.com')}"></div>
    </div>

    <div class="set-grp">
      <div class="set-lbl">${t('models')}</div>
      <div class="set-field">
        <label>${t('conversationModel')}</label>
        <select id="sConversationModel">
          <option value="flash" ${(s.conversationModel || 'flash') === 'flash' ? 'selected' : ''}>${t('flashModelOption')}</option>
          <option value="pro" ${s.conversationModel === 'pro' ? 'selected' : ''}>${t('proModelOption')}</option>
        </select>
      </div>
      <div class="set-row-2">
        <div class="set-field"><label>${t('flashModel')}</label><input type="text" id="sFlash" value="${esc(s.flashModel || 'deepseek-v4-flash')}"></div>
        <div class="set-field"><label>${t('proModel')}</label><input type="text" id="sPro" value="${esc(s.proModel || 'deepseek-v4-pro')}"></div>
      </div>
    </div>

    <div class="set-grp">
      <div class="set-lbl">${t('proParams')}</div>
      <div class="set-field toggle">
        <label>${t('deepThinking')}</label>
        <input type="checkbox" id="sProThinking" ${s.proThinkingEnabled !== false ? 'checked' : ''}>
      </div>
      <div class="set-field">
        <label>${t('reasoningEffort')}</label>
        <select id="sProEffort">
          <option value="high" ${s.proReasoningEffort === 'high' || !s.proReasoningEffort ? 'selected' : ''}>High (Deep)</option>
          <option value="max" ${s.proReasoningEffort === 'max' ? 'selected' : ''}>Max</option>
        </select>
      </div>
    </div>

    <div class="set-grp">
      <div class="set-lbl">${t('flashParams')}</div>
      <div class="set-field toggle">
        <label>${t('deepThinking')}</label>
        <input type="checkbox" id="sFlashThinking" ${s.flashThinkingEnabled !== false ? 'checked' : ''}>
      </div>
      <div class="set-field">
        <label>${t('reasoningEffort')}</label>
        <select id="sFlashEffort">
          <option value="high" ${s.flashReasoningEffort === 'high' || !s.flashReasoningEffort ? 'selected' : ''}>High</option>
          <option value="max" ${s.flashReasoningEffort === 'max' ? 'selected' : ''}>Max</option>
        </select>
      </div>
    </div>

    <div class="set-grp">
      <div class="set-lbl">${t('preferences')}</div>
      <div class="set-field">
        <label>${t('language')}</label>
        <select id="sLang">
          <option value="en" ${s.language === 'en' ? 'selected' : ''}>English</option>
          <option value="zh" ${s.language === 'zh' ? 'selected' : ''}>简体中文</option>
          <option value="zh-hant" ${s.language === 'zh-hant' ? 'selected' : ''}>繁體中文</option>
        </select>
      </div>
      <div class="set-field">
        <label>${t('defaultMode')}</label>
        <div class="seg-picker" id="sModePicker">
          <button class="seg-btn ${s.defaultMode === 'rational' ? 'active' : ''}" data-val="rational">${t('rational')}</button>
          <button class="seg-btn ${s.defaultMode === 'balanced' || !s.defaultMode ? 'active' : ''}" data-val="balanced">${t('balanced')}</button>
          <button class="seg-btn ${s.defaultMode === 'warm' ? 'active' : ''}" data-val="warm">${t('warm')}</button>
        </div>
      </div>
      <div class="set-field">
        <label>${t('responseLength')}</label>
        <div class="seg-picker" id="sLengthPicker">
          <button class="seg-btn ${s.responseLength === 'brief' ? 'active' : ''}" data-val="brief">${t('brief')}</button>
          <button class="seg-btn ${s.responseLength === 'standard' || !s.responseLength ? 'active' : ''}" data-val="standard">${t('standard')}</button>
          <button class="seg-btn ${s.responseLength === 'detailed' ? 'active' : ''}" data-val="detailed">${t('detailed')}</button>
        </div>
      </div>
      <div class="set-field">
        <label>${t('summaryInterval')}</label>
        <select id="sSummaryInterval">
          <option value="0" ${s.summaryInterval === 0 ? 'selected' : ''}>Off</option>
          <option value="2" ${s.summaryInterval === 2 ? 'selected' : ''}>Every 2 turns</option>
          <option value="5" ${s.summaryInterval === 5 || !s.summaryInterval ? 'selected' : ''}>Every 5 turns</option>
          <option value="10" ${s.summaryInterval === 10 ? 'selected' : ''}>Every 10 turns</option>
        </select>
      </div>
      <div class="set-field">
        <label>${t('contextWindow')}</label>
        <span class="set-value">55% · 75% · 85%</span>
      </div>
      <div class="set-note">${t('contextWindowHint')}</div>
      <div class="set-field toggle">
        <label>${t('enableLogging')}</label>
        <input type="checkbox" id="sEnableLogging" ${s.enableLogging !== false ? 'checked' : ''}>
      </div>
      <div class="set-note">${t('loggingNote')}</div>
    </div>

    <div class="set-grp">
      <div class="set-lbl">${t('dataStorage')}</div>
      ${cloudSupported ? `
        <div class="set-field toggle">
          <label>${t('icloudSync')}</label>
          <input type="checkbox" id="sICloud" ${cloudEnabled ? 'checked' : ''}>
        </div>
      ` : ''}
      <div class="set-field">
        <label>${t('storagePath')}</label>
        <div class="choose-path-row">
          <span id="sDataPathDisplay">${esc(cloudEnabled ? (storagePaths.iCloudPath || s.dataPath || '') : localStoragePath)}</span>
          <button class="choose-path-btn" onclick="chooseStoragePath()">${t('changePath')}</button>
        </div>
      </div>
      <div class="set-note">${t('dataNote')}</div>
    </div>

    <div class="set-grp">
      <div class="set-lbl">${t('exportLogs')}</div>
      <div class="set-field" style="border:none;padding-top:0">
        <button class="choose-path-btn" onclick="exportLogs()">${t('exportLogs')}</button>
      </div>
      <div class="set-note">${t('exportLogsHint')}</div>
    </div>

    <div class="set-grp">
      <div class="set-lbl">${t('factoryReset')}</div>
      <div class="set-field" style="border:none;padding-top:0">
        <button class="choose-path-btn" onclick="triggerReset()" style="background:var(--danger);color:white;border:none;font-weight:500">${t('resetTitle')}</button>
      </div>
      <div class="set-note">${t('resetMessage')}</div>
    </div>

    <button class="set-save-btn" onclick="saveSettings()">${t('save')}</button>
  `;

  // Segment picker behaviors
  document.querySelectorAll('#sModePicker .seg-btn').forEach(btn => {
    btn.onclick = function() {
      document.querySelectorAll('#sModePicker .seg-btn').forEach(b => b.classList.remove('active'));
      this.classList.add('active');
    };
  });
  document.querySelectorAll('#sLengthPicker .seg-btn').forEach(btn => {
    btn.onclick = function() {
      document.querySelectorAll('#sLengthPicker .seg-btn').forEach(b => b.classList.remove('active'));
      this.classList.add('active');
    };
  });

  const icloudCheckbox = document.getElementById('sICloud');
  const dataPathDisplay = document.getElementById('sDataPathDisplay');
  const changePathBtn = document.querySelector('.choose-path-row button');

  const updatePathDisplay = async (useCloud) => {
    if (useCloud) {
      if (!storagePaths.iCloudPath) {
        if (icloudCheckbox) icloudCheckbox.checked = false;
        alert(getObText('icloudUnavailable') || 'iCloud Drive is unavailable on this Mac.');
        return false;
      }
      if (!localStoragePath || localStoragePath === storagePaths.iCloudPath) {
        localStoragePath = storagePaths.localPath;
      }
      if (dataPathDisplay) dataPathDisplay.textContent = storagePaths.iCloudPath;
      if (changePathBtn) changePathBtn.style.display = 'none';
      return true;
    } else {
      if (dataPathDisplay) dataPathDisplay.textContent = localStoragePath || storagePaths.localPath;
      if (changePathBtn) changePathBtn.style.display = 'block';
      return true;
    }
  };

  if (icloudCheckbox) {
    icloudCheckbox.onchange = async function() {
      const enabled = this.checked;
      if (!enabled) {
        await updatePathDisplay(false);
        return;
      }
      const previousPath = dataPathDisplay?.textContent;
      if (previousPath && previousPath !== storagePaths.iCloudPath) {
        localStoragePath = previousPath;
      }
      await updatePathDisplay(true);
    };
    updatePathDisplay(icloudCheckbox.checked);
  }

  document.getElementById('settingsOverlay').classList.add('open');
}

function closeSettings() {
  document.getElementById('settingsOverlay').classList.remove('open');
}

async function exportLogs() {
  try {
    const path = await window.api.exportLogs();
    if (path) setStatus(t('exportLogs'));
  } catch (error) {
    setStatus(t('error') + ': ' + errMsg(error));
  }
}

function triggerReset() {
  closeSettings();
  pendingConfirmAction = async () => {
    try {
      await window.api.resetAllSettings();
    } catch (e) {
      setStatus(t('error') + ': ' + e.message);
    }
  };
  document.getElementById('confirmMsg').textContent = t('confirmReset');
  document.getElementById('confirmOverlay').classList.add('open');
}

async function chooseStoragePath() {
  try {
    const path = await window.api.chooseDirectory();
    if (path) {
      document.getElementById('sDataPathDisplay').textContent = path;
    }
  } catch(e) {
    console.error(e);
  }
}

async function saveSettings() {
  const activeModeBtn = document.querySelector('#sModePicker .seg-btn.active');
  const activeLengthBtn = document.querySelector('#sLengthPicker .seg-btn.active');

  const settings = {
    apiKey: document.getElementById('sApiKey')?.value || '',
    baseUrl: document.getElementById('sBaseUrl')?.value || 'https://api.deepseek.com',
    flashModel: document.getElementById('sFlash')?.value || 'deepseek-v4-flash',
    proModel: document.getElementById('sPro')?.value || 'deepseek-v4-pro',
    conversationModel: document.getElementById('sConversationModel')?.value || 'flash',
    language: document.getElementById('sLang')?.value || 'en',
    defaultMode: activeModeBtn ? activeModeBtn.dataset.val : 'balanced',
    responseLength: activeLengthBtn ? activeLengthBtn.dataset.val : 'standard',
    summaryInterval: parseInt(document.getElementById('sSummaryInterval').value, 10),
    // Retain the legacy field for settings-file compatibility. Context
    // compaction itself is now token-based and no longer reads this value.
    contextWindow: S.settings.contextWindow || 60,
    proThinkingEnabled: document.getElementById('sProThinking').checked,
    proReasoningEffort: document.getElementById('sProEffort').value,
    flashThinkingEnabled: document.getElementById('sFlashThinking').checked,
    flashReasoningEffort: document.getElementById('sFlashEffort').value,
    // Rust serializes this as `icloudSync`; keep the renderer's historical
    // spelling out of the persistence contract.
    icloudSync: document.getElementById('sICloud')?.checked ?? false,
    dataPath: document.getElementById('sDataPathDisplay').textContent,
    onboardingCompleted: true,
    enableLogging: document.getElementById('sEnableLogging')?.checked ?? true
  };

  // Apply logging toggle immediately
  if (settings.enableLogging) {
    if (window.PrismLog) window.PrismLog.enable();
  } else {
    if (window.PrismLog) window.PrismLog.disable();
  }

  try {
    await window.api.saveSettings(settings);
    L.i('Settings', 'Settings saved', { lang: settings.language, mode: settings.defaultMode });
    S.settings = settings;
    if (settings.apiKey) S.apiKeySet = true;
    S.lang = settings.language;
    updateAllText();
    showToast(t('settingsSaved'));
    closeSettings();
  } catch(e) {
    const msg = errMsg(e);
    L.e('Settings', 'Failed to save settings', { error: msg });
    setStatus(t('error') + ': ' + msg);
    alert(t('error') + ': ' + msg);
  }
}

// Onboarding State
let obCurrentPage = 0;
const obTotalPages = 8;
let obTempSettings = {};
let obApiValidation = { status: 'idle', message: '' };
let obSaving = false;

function startOnboarding() {
  obCurrentPage = 0;
  obApiValidation = { status: 'idle', message: '' };
  obSaving = false;
  const cloudEnabled = S.platform === 'darwin' && (S.settings.iCloudSync ?? S.settings.icloudSync ?? false);
  obTempSettings = {
    apiKey: S.settings.apiKey || '',
    baseUrl: S.settings.baseUrl || 'https://api.deepseek.com',
    flashModel: S.settings.flashModel || 'deepseek-v4-flash',
    proModel: S.settings.proModel || 'deepseek-v4-pro',
    conversationModel: S.settings.conversationModel || 'flash',
    language: S.settings.language || S.lang || 'en',
    defaultMode: S.settings.defaultMode || 'balanced',
    responseLength: S.settings.responseLength || 'standard',
    iCloudSync: cloudEnabled,
    dataPath: S.settings.dataPath || '',
    localDataPath: cloudEnabled ? '' : (S.settings.dataPath || ''),
    contextWindow: S.settings.contextWindow || 60,
    summaryInterval: S.settings.summaryInterval === undefined ? 5 : S.settings.summaryInterval,
    proThinkingEnabled: S.settings.proThinkingEnabled !== undefined ? S.settings.proThinkingEnabled : true,
    proReasoningEffort: S.settings.proReasoningEffort || 'high',
    flashThinkingEnabled: S.settings.flashThinkingEnabled !== undefined ? S.settings.flashThinkingEnabled : true,
    flashReasoningEffort: S.settings.flashReasoningEffort || 'high',
    enableLogging: S.settings.enableLogging !== undefined ? S.settings.enableLogging : true,
    onboardingCompleted: false
  };

  // Wire up footer buttons
  document.getElementById('onboardingSkipBtn').onclick = () => finishOnboarding(true);
  document.getElementById('onboardingBackBtn').onclick = () => {
    if (obCurrentPage > 0) {
      obCurrentPage--;
      renderOnboarding();
    }
  };
  document.getElementById('onboardingNextBtn').onclick = async () => {
    if (obCurrentPage === 4) {
      const keyInput = document.getElementById('onboardingApiKeyInput');
      const key = keyInput ? keyInput.value.trim() : '';
      if (!key) {
        obApiValidation = { status: 'error', message: getObText('apiKeyRequired') };
        renderOnboarding();
        return;
      }
      obTempSettings.apiKey = key;
      if (obApiValidation.status === 'error') {
        // Validation is surfaced, but it must not make the entire setup
        // impossible (offline use, a custom endpoint, or a temporary outage
        // are all valid reasons to finish setup and fix the key later).
        if (!window.confirm(getObText('apiKeyInvalidContinue'))) return;
      } else if (obApiValidation.status !== 'success') {
        obApiValidation = { status: 'checking', message: getObText('apiKeyChecking') };
        renderOnboarding();
        document.getElementById('onboardingNextBtn').disabled = true;
        L.i('Onboarding', 'Validating API key', { baseUrl: obTempSettings.baseUrl });
        try {
          await window.api.validateApiKey(key, obTempSettings.baseUrl);
          obApiValidation = { status: 'success', message: getObText('apiKeyValid') };
          L.i('Onboarding', 'API key validation succeeded');
          showToast(getObText('apiKeyValid'));
          document.getElementById('onboardingNextBtn').disabled = false;
        } catch (error) {
          const message = errMsg(error);
          obApiValidation = { status: 'error', message: getObText('apiKeyInvalid') + ' ' + message };
          L.e('Onboarding', 'API key validation failed', { baseUrl: obTempSettings.baseUrl, error: message });
          renderOnboarding();
          return;
        }
      }
    }
    if (obCurrentPage < obTotalPages - 1) {
      obCurrentPage++;
      renderOnboarding();
    } else {
      finishOnboarding(false);
    }
  };

  document.getElementById('onboardingOverlay').classList.add('open');
  renderOnboarding();
}

function errMsg(e) { return typeof e === 'string' ? e : (e && e.message) || String(e); }

async function finishOnboarding(skipped) {
  if (obSaving) return;
  obSaving = true;
  obTempSettings.onboardingCompleted = true;
  const nextBtn = document.getElementById('onboardingNextBtn');
  // Keep the final action visually active. `obSaving` prevents duplicate
  // submissions while still making it obvious that Setup has not failed.
  nextBtn.disabled = false;
  nextBtn.dataset.saving = 'true';
  nextBtn.textContent = getObText('saving');

  try {
    const settingsToSave = { ...obTempSettings };
    settingsToSave.icloudSync = !!settingsToSave.iCloudSync;
    delete settingsToSave.iCloudSync;
    delete settingsToSave.localDataPath;
    L.i('Onboarding', 'Saving completed setup', {
      dataPath: settingsToSave.dataPath,
      iCloud: settingsToSave.icloudSync,
      skipped: !!skipped
    });
    await Promise.race([
      window.api.saveSettings(settingsToSave),
      new Promise((_, reject) => setTimeout(() => reject(new Error(getObText('saveTimeout'))), 30000))
    ]);
    S.settings = settingsToSave;
    S.apiKeySet = !!S.settings.apiKey;
    if (S.settings.language) {
      S.lang = S.settings.language;
      updateAllText();
    }
    document.getElementById('onboardingOverlay').classList.remove('open');
    showToast(t('settingsSaved'));
  } catch (e) {
    const message = errMsg(e);
    L.e('Onboarding', 'Failed to save onboarding settings', { error: message });
    nextBtn.disabled = false;
    alert(t('error') + ': ' + message);
  } finally {
    obSaving = false;
    nextBtn.dataset.saving = 'false';
    if (document.getElementById('onboardingOverlay').classList.contains('open')) {
      renderOnboarding();
    }
  }
}

// Onboarding translations mapping based on current selected language (obTempSettings.language)
function getObText(key) {
  const translations = {
    en: {
      welcomeTitle: "Welcome to Prism",
      welcomeBody: "Prism is a narrative analysis Agent powered by DeepSeek. It identifies narrative patterns, tracks emotional changes, and surfaces blindspots.",
      purposeTitle: "What Prism Does",
      purposeBody: "Prism helps you separate facts from interpretations, trace emotions, and identify what's unknown in your narrative.",
      featuresTitle: "Core Features",
      featuresBody: "Prism gives you multiple ways to examine your story:",
      featNarrativeTitle: "Narrative Mapping",
      featNarrativeDesc: "Separates facts from interpretations — what happened vs. how you see it",
      featBlindspotTitle: "Blind Spot Detection",
      featBlindspotDesc: "Identifies thought spirals, cognitive biases, and missing perspectives",
      featPerspectiveTitle: "Multi-Perspective Narratives",
      featPerspectiveDesc: "When the story is complete, offers alternative narrative versions for your consideration",
      featChapterTitle: "Chapter Synthesis",
      featChapterDesc: "Auto-summarizes long conversations into chapters with titles, summaries, and keywords",
      tourTitle: "Interface Tour",
      tourBody: "A quick walkthrough of Prism's main interface:",
      tourSidebarTitle: "Sidebar",
      tourSidebarDesc: "The left sidebar shows your conversations and synthesized chapters. Right-click to rename/delete; click info for details.",
      tourChatTitle: "Chat Area",
      tourChatDesc: "The central area displays your conversation with Prism. Expand the «Reasoning» panel to see the model's thoughts.",
      tourInputTitle: "Input Bar",
      tourInputDesc: "The bottom input area supports multi-line text. Press Return to send, Shift+Return for a new line.",
      tourToolbarTitle: "Toolbar",
      tourToolbarDesc: "Top-right toolbar: New Conversation and Settings — configure model parameters, API key, and language.",
      apiKeyTitle: "Configure DeepSeek API",
      apiKeyBody: "Prism needs a DeepSeek API key to function. Enter your key below, or configure it later in Settings.",
      apiKeyPlaceholder: "Paste your API key here...",
      apiKeyHelp: "Go to platform.deepseek.com, create an account, and generate a new API key. New users typically receive free credits.",
      modeTitle: "Choose Conversation Mode",
      modeBody: "Prism offers three conversation modes. You can switch at any time in Settings:",
      modeRational: "Rational",
      modeRationalDesc: "Analytical and logic-focused, minimal empathy",
      modeBalanced: "Balanced",
      modeBalancedDesc: "Balanced empathy and analysis, suitable for most situations",
      modeWarm: "Warm",
      modeWarmDesc: "Warm, empathetic analysis with emotional awareness",
      responseLength: "Response Length",
      modeBrief: "Brief",
      modeStandard: "Standard",
      modeDetailed: "Detailed",
      icloudTitle: "Cloud Sync & Storage",
      icloudBody: "Sync your conversations and memory logs securely across devices or store locally.",
      localStorageTitle: "Local Storage",
      localStorageBody: "Choose where Prism stores your conversations and memory logs on this PC.",
      useICloud: "Use iCloud Storage",
      icloudActive: "Data stored in iCloud Drive, synced across all devices",
      icloudUnavailable: "iCloud Drive is unavailable on this Mac. Turn on iCloud Drive in System Settings first.",
      choosePath: "Choose Local Folder...",
      privacyTitle: "Privacy First",
      privacyBody: "All your data is stored locally. Nothing is uploaded to any third-party server except the model API you configure.",
      getStarted: "Get Started",
      saving: "Saving…",
      saveTimeout: "Saving setup timed out. Check the selected folder and try again.",
      back: "Back",
      next: "Next",
      skip: "Skip Setup",
      done: "Done",
      apiKeyInvalid: "API key validation failed. The key may be invalid or the service is unreachable.",
      apiKeyInvalidContinue: "Do you want to continue anyway? You can change the key later in Settings.",
      apiKeyRequired: "Enter an API key to continue.",
      apiKeyChecking: "Verifying API key…",
      apiKeyValid: "API key verified successfully."
    },
    zh: {
      welcomeTitle: "欢迎使用 Prism",
      welcomeBody: "Prism 是基于 DeepSeek 的情感分析 Agent。它识别你的叙事模式、追踪情绪变化、发现盲点。",
      purposeTitle: "Prism 能做什么",
      purposeBody: "Prism 基于 DeepSeek 大语言模型，通过对话帮你梳理叙事中的事实、解释、情绪和未知信息。",
      featuresTitle: "核心特性",
      featuresBody: "Prism 提供多种方式帮你审视自己的故事：",
      featNarrativeTitle: "叙事梳理",
      featNarrativeDesc: "帮你拆分事实与解释，区分「发生了什么」和「你怎么看」",
      featBlindspotTitle: "盲点识别",
      featBlindspotDesc: "识别思维螺旋、认知偏差和叙事中的缺失视角",
      featPerspectiveTitle: "多视角叙事",
      featPerspectiveDesc: "当故事足够完整时，提供多个可能的叙事版本供你参考",
      featChapterTitle: "章节归纳",
      featChapterDesc: "自动将长对话归纳为带标题、摘要和关键词的章节",
      tourTitle: "界面导览",
      tourBody: "了解 Prism 的主要界面布局，快速上手：",
      tourSidebarTitle: "侧边栏",
      tourSidebarDesc: "左侧边栏显示对话列表和已归纳的章节。右键可重命名或删除对话，点击信息按钮查看详情。",
      tourChatTitle: "对话区域",
      tourChatDesc: "中央区域显示你与 Prism 的对话。每条助手消息上方可展开「思考链」查看模型的推理过程。",
      tourInputTitle: "输入框",
      tourInputDesc: "底部输入框支持多行输入。按 Return 发送，Shift+Return 换行。",
      tourToolbarTitle: "工具栏",
      tourToolbarDesc: "右上角工具栏：新建对话和设置，可配置模型参数、API Key、归纳频率等。",
      apiKeyTitle: "配置 DeepSeek API",
      apiKeyBody: "Prism 需要连接 DeepSeek 模型才能工作。请在下方输入你的 API Key，或稍后在设置中配置。",
      apiKeyPlaceholder: "在此粘贴你的 API 密钥...",
      apiKeyHelp: "前往 platform.deepseek.com 注册账号，在「API Keys」页面创建一个新的 Key。DeepSeek 新用户通常会有免费额度。",
      modeTitle: "选择对话模式",
      modeBody: "Prism 提供三种对话模式，你可以随时在设置中切换：",
      modeRational: "理性",
      modeRationalDesc: "冷静分析，聚焦事实和逻辑结构",
      modeBalanced: "平衡",
      modeBalancedDesc: "平衡共情与分析，适合大多数情况",
      modeWarm: "温情",
      modeWarmDesc: "温暖陪伴，注重理解和情感支持",
      responseLength: "回复长度",
      modeBrief: "简洁",
      modeStandard: "标准",
      modeDetailed: "详细",
      icloudTitle: "云同步与存储",
      icloudBody: "将你的聊天记录和情感分析档案保存在 iCloud，以便跨设备自动同步；或存储在本地。",
      localStorageTitle: "本地存储",
      localStorageBody: "选择 Prism 在此电脑上保存聊天记录和记忆档案的位置。",
      useICloud: "使用 iCloud 存储",
      icloudActive: "数据存储在 iCloud Drive 中，所有设备自动同步",
      icloudUnavailable: "当前 Mac 上无法访问 iCloud Drive，请先在系统设置中打开 iCloud Drive。",
      choosePath: "选择本地数据目录...",
      privacyTitle: "数据与隐私",
      privacyBody: "你的所有数据都存储在本地，不会上传到任何第三方服务器（除了你选择的模型 API）。",
      getStarted: "开始使用",
      saving: "正在保存…",
      saveTimeout: "保存引导超时，请检查所选目录后重试。",
      back: "返回",
      next: "继续",
      skip: "跳过引导",
      done: "完成",
      apiKeyInvalid: "API 密钥验证失败。密钥可能无效或服务不可达。",
      apiKeyInvalidContinue: "是否继续？你可以稍后在设置中修改密钥。",
      apiKeyRequired: "请输入 API 密钥后继续。",
      apiKeyChecking: "正在验证 API 密钥…",
      apiKeyValid: "API 密钥验证成功。"
    },
    'zh-hant': {
      welcomeTitle: "歡迎使用 Prism",
      welcomeBody: "Prism 是基於 DeepSeek 的敘事分析 Agent。它識別你的敘事模式、追蹤情緒變化、發現盲點。",
      purposeTitle: "Prism 能做什麼",
      purposeBody: "Prism 基於 DeepSeek 大語言模型，透過對話幫你梳理敘事中的事實、解釋、情緒和未知資訊。",
      featuresTitle: "核心特性",
      featuresBody: "Prism 提供多種方式幫你審視自己的故事：",
      featNarrativeTitle: "敘事梳理",
      featNarrativeDesc: "幫你拆分事實與解釋，區分「發生了什麼」和「你怎麼看」",
      featBlindspotTitle: "盲點識別",
      featBlindspotDesc: "識別思維螺旋、認知偏差和敘事中的缺失視角",
      featPerspectiveTitle: "多視角敘事",
      featPerspectiveDesc: "當故事足夠完整時，提供多個可能的敘事版本供你參考",
      featChapterTitle: "章節歸納",
      featChapterDesc: "自動將長對話歸納為帶標題、摘要和關鍵詞的章節",
      tourTitle: "介面導覽",
      tourBody: "了解 Prism 的主要介面佈局，快速上手：",
      tourSidebarTitle: "側邊欄",
      tourSidebarDesc: "左側側邊欄顯示對話列表和已歸納的章節。右鍵可重新命名或刪除對話，點擊資訊按鈕查看詳情。",
      tourChatTitle: "對話區域",
      tourChatDesc: "中央區域顯示你與 Prism 的對話。每條助手訊息上方可展開「思考鏈」檢視模型的推理過程。",
      tourInputTitle: "輸入框",
      tourInputDesc: "底部輸入框支援多行輸入。按 Return 發送，Shift+Return 換行。",
      tourToolbarTitle: "工具列",
      tourToolbarDesc: "右上角工具列：新增對話和設定，可配置模型參數、API Key、歸納頻率、介面語言等。",
      apiKeyTitle: "設定 DeepSeek API",
      apiKeyBody: "Prism 需要連接 DeepSeek 模型才能運作。請在下方輸入你的 API Key，或稍後在設定中配置。",
      apiKeyPlaceholder: "在此貼上你的 API 金鑰...",
      apiKeyHelp: "前往 platform.deepseek.com 註冊帳號，在「API Keys」頁面建立一個新的 Key。DeepSeek 新用戶通常會有免費額度。",
      modeTitle: "選擇對話模式",
      modeBody: "Prism 提供三種對話模式，你可以隨時在設定中切換：",
      modeRational: "理性",
      modeRationalDesc: "冷靜分析，聚焦事實和邏輯結構",
      modeBalanced: "平衡",
      modeBalancedDesc: "平衡共情與分析，適合大多數情況",
      modeWarm: "溫情",
      modeWarmDesc: "溫暖陪伴，注重理解和情感支持",
      responseLength: "回覆長度",
      modeBrief: "簡潔",
      modeStandard: "標準",
      modeDetailed: "詳細",
      icloudTitle: "雲端同步與儲存",
      icloudBody: "將你的聊天記錄和情感分析檔案保存在 iCloud，以便跨裝置自動同步；或儲存在本機。",
      localStorageTitle: "本機儲存",
      localStorageBody: "選擇 Prism 在此電腦上保存聊天記錄和記憶檔案的位置。",
      useICloud: "使用 iCloud 儲存",
      icloudActive: "資料儲存在 iCloud Drive 中，所有裝置自動同步",
      icloudUnavailable: "目前 Mac 無法存取 iCloud Drive，請先在系統設定中開啟 iCloud Drive。",
      choosePath: "選擇本機資料目錄...",
      privacyTitle: "資料與隱私",
      privacyBody: "你的所有資料都儲存在本機，不會上傳到任何第三方伺服器（除了你選擇的模型 API）。",
      getStarted: "開始使用",
      saving: "正在儲存…",
      saveTimeout: "儲存引導逾時，請檢查所選目錄後重試。",
      back: "返回",
      next: "繼續",
      skip: "跳過引導",
      done: "完成",
      apiKeyInvalid: "API 金鑰驗證失敗。金鑰可能無效或服務不可達。",
      apiKeyInvalidContinue: "是否繼續？你可以稍後在設定中修改金鑰。",
      apiKeyRequired: "請輸入 API 金鑰後繼續。",
      apiKeyChecking: "正在驗證 API 金鑰…",
      apiKeyValid: "API 金鑰驗證成功。"
    }
  };

  const l = obTempSettings.language || 'en';
  return translations[l]?.[key] || translations['en']?.[key] || '';
}

function renderOnboarding() {
  const content = document.getElementById('onboardingContent');
  const skipBtn = document.getElementById('onboardingSkipBtn');
  const backBtn = document.getElementById('onboardingBackBtn');
  const nextBtn = document.getElementById('onboardingNextBtn');
  const dotsContainer = document.getElementById('onboardingDots');

  // The same footer button is reused across pages. Always derive its disabled
  // state from the current validation state instead of carrying it over from
  // the API-key request page.
  nextBtn.disabled = obCurrentPage === 4 && obApiValidation.status === 'checking';

  // Hidden footer controls should not reserve layout space; centering the
  // remaining buttons/dots as a single group keeps Setup visually balanced.
  backBtn.style.display = obCurrentPage > 0 ? 'inline-flex' : 'none';
  skipBtn.style.display = obCurrentPage === 0 ? 'inline-flex' : 'none';
  skipBtn.textContent = getObText('skip');
  backBtn.textContent = getObText('back');

  if (obCurrentPage === obTotalPages - 1) {
    nextBtn.textContent = getObText('getStarted');
  } else {
    nextBtn.textContent = getObText('next');
  }

  dotsContainer.innerHTML = '';
  for (let i = 0; i < obTotalPages; i++) {
    const dot = document.createElement('div');
    dot.className = `onboarding-dot ${i === obCurrentPage ? 'active' : ''}`;
    dotsContainer.appendChild(dot);
  }

  switch (obCurrentPage) {
    case 0:
      content.innerHTML = `
        <div class="ob-logo"><img class="ob-app-icon" src="app-icon.png" alt="Prism"></div>
        <div class="ob-logo-text">${getObText('welcomeTitle')}</div>
        <div class="ob-subtitle">${getObText('welcomeBody')}</div>
        <div style="display:flex;gap:12px;margin-top:10px">
          <select id="obLangSelect" style="padding:6px 12px;border-radius:6px;border:0.5px solid var(--border);background:var(--card-bg);color:var(--text-primary);font-size:12.5px">
            <option value="en" ${obTempSettings.language === 'en' ? 'selected' : ''}>English</option>
            <option value="zh" ${obTempSettings.language === 'zh' ? 'selected' : ''}>简体中文</option>
            <option value="zh-hant" ${obTempSettings.language === 'zh-hant' ? 'selected' : ''}>繁體中文</option>
          </select>
        </div>
      `;
      document.getElementById('obLangSelect').onchange = (e) => {
        obTempSettings.language = e.target.value;
        renderOnboarding();
      };
      break;

    case 1:
      content.innerHTML = `
        <div class="ob-logo">${iconSvg('scale')}</div>
        <div class="ob-logo-text">${getObText('purposeTitle')}</div>
        <div class="ob-desc" style="margin-top:15px">${getObText('purposeBody')}</div>
      `;
      break;

    case 2:
      content.innerHTML = `
        <div class="ob-logo-text">${getObText('featuresTitle')}</div>
        <div class="ob-grid">
          <div class="ob-card">
            <div class="ob-card-title">${iconSvg('bookmark')} ${getObText('featChapterTitle')}</div>
            <div class="ob-card-desc">${getObText('featChapterDesc')}</div>
          </div>
          <div class="ob-card">
            <div class="ob-card-title">${iconSvg('chart')} ${getObText('featNarrativeTitle')}</div>
            <div class="ob-card-desc">${getObText('featNarrativeDesc')}</div>
          </div>
          <div class="ob-card">
            <div class="ob-card-title">${iconSvg('search')} ${getObText('featBlindspotTitle')}</div>
            <div class="ob-card-desc">${getObText('featBlindspotDesc')}</div>
          </div>
          <div class="ob-card">
            <div class="ob-card-title">${iconSvg('brain')} ${getObText('featPerspectiveTitle')}</div>
            <div class="ob-card-desc">${getObText('featPerspectiveDesc')}</div>
          </div>
        </div>
      `;
      break;

    case 3:
      content.innerHTML = `
        <div class="ob-logo">${iconSvg('monitor')}</div>
        <div class="ob-logo-text">${getObText('tourTitle')}</div>
        <div class="ob-grid" style="grid-template-columns:1fr;max-width:460px;gap:8px;margin-top:10px">
          <div style="font-size:11.5px;color:var(--text-secondary);text-align:left;border-left:2px solid var(--accent);padding-left:8px">
            <strong>${getObText('tourSidebarTitle')}:</strong> ${getObText('tourSidebarDesc')}
          </div>
          <div style="font-size:11.5px;color:var(--text-secondary);text-align:left;border-left:2px solid var(--accent);padding-left:8px">
            <strong>${getObText('tourChatTitle')}:</strong> ${getObText('tourChatDesc')}
          </div>
          <div style="font-size:11.5px;color:var(--text-secondary);text-align:left;border-left:2px solid var(--accent);padding-left:8px">
            <strong>${getObText('tourInputTitle')}:</strong> ${getObText('tourInputDesc')}
          </div>
          <div style="font-size:11.5px;color:var(--text-secondary);text-align:left;border-left:2px solid var(--accent);padding-left:8px">
            <strong>${getObText('tourToolbarTitle')}:</strong> ${getObText('tourToolbarDesc')}
          </div>
        </div>
      `;
      break;

    case 4:
      content.innerHTML = `
        <div class="ob-logo">${iconSvg('key')}</div>
        <div class="ob-logo-text">${getObText('apiKeyTitle')}</div>
        <div class="ob-desc">${getObText('apiKeyBody')}</div>
        <div class="ob-input-grp">
          <input type="password" id="onboardingApiKeyInput" placeholder="${getObText('apiKeyPlaceholder')}" value="${obTempSettings.apiKey || ''}">
        </div>
        ${obApiValidation.status !== 'idle' ? `<div class="ob-validation ${obApiValidation.status}">${esc(obApiValidation.message)}</div>` : ''}
        <div class="ob-note-box">${getObText('apiKeyHelp')}</div>
      `;
      break;

    case 5:
      content.innerHTML = `
        <div class="ob-logo-text">${getObText('modeTitle')}</div>
        <div class="ob-mode-cards">
          <div class="ob-mode-card ${obTempSettings.defaultMode === 'rational' ? 'active' : ''}" data-val="rational">
            <span class="ob-mode-icon">${iconSvg('activity')}</span>
            <div class="ob-mode-info">
              <div class="ob-mode-title">${getObText('modeRational')}</div>
              <div class="ob-mode-desc">${getObText('modeRationalDesc')}</div>
            </div>
            ${obTempSettings.defaultMode === 'rational' ? iconSvg('check', 'ui-icon ob-check') : ''}
          </div>
          <div class="ob-mode-card ${obTempSettings.defaultMode === 'balanced' ? 'active' : ''}" data-val="balanced">
            <span class="ob-mode-icon">${iconSvg('scale')}</span>
            <div class="ob-mode-info">
              <div class="ob-mode-title">${getObText('modeBalanced')}</div>
              <div class="ob-mode-desc">${getObText('modeBalancedDesc')}</div>
            </div>
            ${obTempSettings.defaultMode === 'balanced' ? iconSvg('check', 'ui-icon ob-check') : ''}
          </div>
          <div class="ob-mode-card ${obTempSettings.defaultMode === 'warm' ? 'active' : ''}" data-val="warm">
            <span class="ob-mode-icon">${iconSvg('bulb')}</span>
            <div class="ob-mode-info">
              <div class="ob-mode-title">${getObText('modeWarm')}</div>
              <div class="ob-mode-desc">${getObText('modeWarmDesc')}</div>
            </div>
            ${obTempSettings.defaultMode === 'warm' ? iconSvg('check', 'ui-icon ob-check') : ''}
          </div>
        </div>

        <div style="margin-top:16px;width:100%;max-width:440px;text-align:left;display:flex;align-items:center;justify-content:space-between">
          <span style="font-size:12.5px;font-weight:600">${getObText('responseLength')}</span>
          <select id="obLengthSelect" style="padding:4px 8px;border-radius:6px;border:0.5px solid var(--border);background:var(--card-bg);color:var(--text-primary);font-size:12px">
            <option value="brief" ${obTempSettings.responseLength === 'brief' ? 'selected' : ''}>${getObText('modeBrief')}</option>
            <option value="standard" ${obTempSettings.responseLength === 'standard' ? 'selected' : ''}>${getObText('modeStandard')}</option>
            <option value="detailed" ${obTempSettings.responseLength === 'detailed' ? 'selected' : ''}>${getObText('modeDetailed')}</option>
          </select>
        </div>
      `;
      document.querySelectorAll('.ob-mode-card').forEach(card => {
        card.onclick = function() {
          obTempSettings.defaultMode = this.dataset.val;
          renderOnboarding();
        };
      });
      document.getElementById('obLengthSelect').onchange = (e) => {
        obTempSettings.responseLength = e.target.value;
      };
      break;

    case 6:
      const displayPath = obTempSettings.dataPath || '~/Documents/Prism';

      // iCloud is a macOS-only storage provider. Windows keeps the same
      // onboarding page count, but presents the local folder picker instead
      // of showing a control that can never be enabled.
      if (S.platform !== 'darwin') {
        content.innerHTML = `
          <div class="ob-logo">${iconSvg('folder')}</div>
          <div class="ob-logo-text">${getObText('localStorageTitle')}</div>
          <div class="ob-desc">${getObText('localStorageBody')}</div>
          <div style="margin-top:20px;display:flex;flex-direction:column;align-items:center;gap:6px">
            <div class="ob-path-display">${displayPath}</div>
            <button class="btn-text" id="obChooseFolderBtn" style="border:0.5px solid var(--border);padding:4px 10px;font-size:11px">${getObText('choosePath')}</button>
          </div>
        `;
        document.getElementById('obChooseFolderBtn').onclick = async () => {
          try {
            const dir = await window.api.chooseDirectory();
            if (dir) {
              obTempSettings.localDataPath = dir;
              obTempSettings.dataPath = dir;
              renderOnboarding();
            }
          } catch (err) {
            console.error(err);
          }
        };
        break;
      }

      content.innerHTML = `
        <div class="ob-logo">${iconSvg('cloud')}</div>
        <div class="ob-logo-text">${getObText('icloudTitle')}</div>
        <div class="ob-desc">${getObText('icloudBody')}</div>

        <div style="display:flex;align-items:center;gap:8px;margin-top:10px">
          <input type="checkbox" id="obIcloudCheckbox" ${obTempSettings.iCloudSync ? 'checked' : ''} style="width:16px;height:16px;cursor:pointer">
          <label for="obIcloudCheckbox" style="font-size:13px;font-weight:500;cursor:pointer">${getObText('useICloud')}</label>
        </div>

        <div style="margin-top:20px;display:flex;flex-direction:column;align-items:center;gap:6px">
          <div class="ob-path-display">${displayPath}</div>
          ${!obTempSettings.iCloudSync ? `
            <button class="btn-text" id="obChooseFolderBtn" style="border:0.5px solid var(--border);padding:4px 10px;font-size:11px">${getObText('choosePath')}</button>
          ` : ''}
        </div>
      `;
      document.getElementById('obIcloudCheckbox').onchange = async (e) => {
        const enabled = e.target.checked;
        if (enabled) {
          try {
            const paths = await window.api.getStoragePaths();
            if (!paths || !paths.iCloudPath) {
              throw new Error(getObText('icloudUnavailable') || 'iCloud Drive is unavailable on this Mac.');
            }
            obTempSettings.localDataPath = obTempSettings.dataPath || paths.localPath;
            obTempSettings.iCloudSync = true;
            obTempSettings.dataPath = paths.iCloudPath;
          } catch (err) {
            e.target.checked = false;
            obTempSettings.iCloudSync = false;
            alert(errMsg(err));
          }
        } else {
          obTempSettings.iCloudSync = false;
          obTempSettings.dataPath = obTempSettings.localDataPath || obTempSettings.dataPath || '~/Documents/Prism';
        }
        renderOnboarding();
      };
      if (!obTempSettings.iCloudSync) {
        document.getElementById('obChooseFolderBtn').onclick = async () => {
          try {
            const dir = await window.api.chooseDirectory();
            if (dir) {
              obTempSettings.localDataPath = dir;
              obTempSettings.dataPath = dir;
              renderOnboarding();
            }
          } catch (err) {
            console.error(err);
          }
        };
      }
      break;

    case 7:
      content.innerHTML = `
        <div class="ob-logo">${iconSvg('shield')}</div>
        <div class="ob-logo-text">${getObText('privacyTitle')}</div>
        <div class="ob-desc" style="margin-top:15px">${getObText('privacyBody')}</div>
      `;
      break;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// MEMORY PANEL — 4 NATIVE SECTIONS
// ═══════════════════════════════════════════════════════════════════════
function openMemory() {
  document.getElementById('memOverlay').classList.add('open');
  loadMemoryData();
}

function closeMemory() {
  document.getElementById('memOverlay').classList.remove('open');
}

async function loadMemoryData() {
  const body = document.getElementById('memBody');
  body.innerHTML = '<div class="mem-empty">Loading...</div>';

  let html = '';

  // ── 0. Model usage ──
  try {
    const usage = await window.api.getUsageStats();
    const input = Number(usage?.inputTokens || 0);
    const output = Number(usage?.outputTokens || 0);
    const hits = Number(usage?.cacheHitTokens || 0);
    const cacheRate = input > 0 ? ((hits / input) * 100).toFixed(1) + '%' : '0%';
    const number = value => new Intl.NumberFormat(S.lang || 'en').format(value);
    html += `<div class="mem-section">`;
    html += `<div class="mem-section-hdr"><span class="mem-section-icon blue">${iconSvg('chart')}</span>${t('modelUsage')}</div>`;
    html += `<div class="usage-grid">`;
    html += `<div class="usage-card"><div class="usage-value">${number(input)}</div><div class="usage-label">${t('inputTokens')}</div></div>`;
    html += `<div class="usage-card"><div class="usage-value">${number(output)}</div><div class="usage-label">${t('outputTokens')}</div></div>`;
    html += `<div class="usage-card"><div class="usage-value">${cacheRate}</div><div class="usage-label">${t('cacheHitRate')}</div></div>`;
    html += `</div></div>`;
  } catch (error) {
    L.w('Memory', 'Could not load model usage', { error: errMsg(error) });
  }

  // ── 0b. Provider balance (metadata request; no model invocation) ──
  try {
    const balance = S.providerBalance || await window.api.getUserBalance();
    S.providerBalance = balance;
    const infos = Array.isArray(balance?.balanceInfos) ? balance.balanceInfos : [];
    html += `<div class="mem-section">`;
    html += `<div class="mem-section-hdr"><span class="mem-section-icon green">${iconSvg('scale')}</span>${t('accountBalance')}</div>`;
    if (infos.length) {
      html += `<div class="usage-grid">`;
      infos.forEach(info => {
        const currency = esc(info.currency || '');
        html += `<div class="usage-card"><div class="usage-value">${esc(info.totalBalance || '—')} ${currency}</div>`;
        html += `<div class="usage-label">${t('totalBalance')} · ${esc(info.grantedBalance || '0')} ${currency}</div>`;
        html += `<div class="usage-label">${t('toppedUpBalance')} · ${esc(info.toppedUpBalance || '0')} ${currency}</div></div>`;
      });
      html += `</div>`;
    } else {
      html += `<div class="mem-empty" style="padding:12px 0">${t('balanceUnavailable')}</div>`;
    }
    html += `</div>`;
  } catch (error) {
    L.w('Memory', 'Could not load provider balance', { error: errMsg(error) });
  }

  // ── 1. Narrative Timeline ──
  try {
    const events = await window.api.queryNarrativeEvents(S.activeId);
    html += `<div class="mem-section">`;
    html += `<div class="mem-section-hdr"><span class="mem-section-icon purple">${iconSvg('activity')}</span>${t('conversationTimeline')}</div>`;
    if (events?.length) {
      html += `<div class="memory-timeline">`;
      [...events].sort((a, b) => (a.sortIndex || 0) - (b.sortIndex || 0)).forEach(event => {
        const span = event.endLabel ? `${event.startLabel} → ${event.endLabel}` : event.startLabel;
        html += `<div class="memory-timeline-item"><span class="memory-timeline-label">${esc(event.title || '')}</span><span class="memory-timeline-time">${esc(span || '')}</span>${event.summary ? `<span class="memory-timeline-summary">${esc(event.summary)}</span>` : ''}</div>`;
      });
      html += `</div>`;
    } else {
      html += `<div class="mem-empty" style="padding:12px 0">${t('noNarrativeEvents')}</div>`;
    }
    html += `</div>`;
  } catch (error) {
    html += `<div class="mem-section"><div class="mem-section-hdr"><span class="mem-section-icon purple">${iconSvg('activity')}</span>${t('conversationTimeline')}</div><div class="mem-empty" style="padding:12px 0">${t('noNarrativeEvents')}</div></div>`;
  }

  // ── 2. People Section ──
  try {
    const persons = await window.api.queryPersons();
    html += `<div class="mem-section">`;
    html += `<div class="mem-section-hdr"><span class="mem-section-icon blue">${iconSvg('users')}</span>${t('people')}</div>`;
    if (persons?.length) {
      persons.sort((a, b) => (b.mentionCount || 0) - (a.mentionCount || 0));
      persons.forEach(p => {
        const arc = p.emotionalArc || p.notes || '';
        html += `<div class="mem-person">
          <div>
            <div class="mem-person-name">${esc(p.name || '')}</div>
            <div class="mem-person-info">${esc(p.role || '')} · ${p.mentionCount || 0} ${t('mentions')}</div>
          </div>
          ${arc ? `<div class="mem-person-arc" title="${esc(arc)}">${esc(arc)}</div>` : ''}
        </div>`;
      });
    } else {
      html += `<div class="mem-empty" style="padding:12px 0">${t('noPeople')}</div>`;
    }
    html += '</div>';
  } catch(e) {
    html += `<div class="mem-section"><div class="mem-section-hdr"><span class="mem-section-icon blue">${iconSvg('users')}</span>${t('people')}</div><div class="mem-empty" style="padding:12px 0">${t('noPeople')}</div></div>`;
  }

  // ── 2. Emotions Section ──
  try {
    const emotions = await window.api.queryEmotions();
    html += `<div class="mem-section">`;
    html += `<div class="mem-section-hdr"><span class="mem-section-icon purple">${iconSvg('activity')}</span>${t('emotionTimeline')}</div>`;
    if (emotions?.length) {
      const counts = {};
      emotions.forEach(e => {
        const label = e.label || e.emotion || 'unknown';
        counts[label] = (counts[label] || 0) + 1;
      });

      const total = emotions.length;
      const sorted = Object.entries(counts).sort((a, b) => b[1] - a[1]);

      html += '<div class="emotion-grid">';
      sorted.forEach(([label, count]) => {
        const pct = Math.round((count / total) * 100);
        html += `<div class="emotion-card">
          <div class="emotion-name">${esc(label)}</div>
          <div class="emotion-pct">${pct}%</div>
          <div class="emotion-count">${count} ${t('mentions')}</div>
        </div>`;
      });
      html += '</div>';
    } else {
      html += `<div class="mem-empty" style="padding:12px 0">${t('noEmotions')}</div>`;
    }
    html += '</div>';
  } catch(e) {
    html += `<div class="mem-section"><div class="mem-section-hdr"><span class="mem-section-icon purple">${iconSvg('activity')}</span>${t('emotionTimeline')}</div><div class="mem-empty" style="padding:12px 0">${t('noEmotions')}</div></div>`;
  }

  // ── 3. Blindspots Section ──
  try {
    const spots = await window.api.queryBlindspots();
    html += `<div class="mem-section">`;
    html += `<div class="mem-section-hdr"><span class="mem-section-icon red">${iconSvg('eye')}</span>${t('blindspots')}</div>`;
    if (spots?.length) {
      // Show last 10, reversed
      const list = [...spots].reverse().slice(0, 10);
      list.forEach(s => {
        const sev = (s.severity || 'new').toLowerCase();
        html += `<div class="blindspot-item">
          <div class="blindspot-hdr">
            <span class="blindspot-pattern">${esc(s.pattern || s.description || '')}</span>
            <span class="blindspot-severity ${sev}">${esc(s.severity || 'New')}</span>
          </div>
          <div class="blindspot-evidence">"${esc(s.evidence || s.example || '')}"</div>
          ${s.counterQuestion ? `<div class="blindspot-question">? ${esc(s.counterQuestion)}</div>` : ''}
        </div>`;
      });
    } else {
      html += `<div class="mem-empty" style="padding:12px 0">${t('noBlindspots')}</div>`;
    }
    html += '</div>';
  } catch(e) {
    html += `<div class="mem-section"><div class="mem-section-hdr"><span class="mem-section-icon red">${iconSvg('eye')}</span>${t('blindspots')}</div><div class="mem-empty" style="padding:12px 0">${t('noBlindspots')}</div></div>`;
  }

  // ── 4. Insights Section ──
  try {
    const mems = await window.api.queryMemory('');
    html += `<div class="mem-section">`;
    html += `<div class="mem-section-hdr"><span class="mem-section-icon yellow">${iconSvg('bulb')}</span>${t('insights')}</div>`;
    if (mems?.length) {
      mems.reverse().forEach(m => {
        html += `<div class="insight-item">
          <div class="insight-text">${esc(m.content || '')}</div>
          ${m.keywords?.length ? `<div class="insight-tags">${m.keywords.map(k => `<span class="insight-tag">${esc(k)}</span>`).join('')}</div>` : ''}
        </div>`;
      });
    } else {
      html += `<div class="mem-empty" style="padding:12px 0">${t('noInsights')}</div>`;
    }
    html += '</div>';
  } catch(e) {
    html += `<div class="mem-section"><div class="mem-section-hdr"><span class="mem-section-icon yellow">${iconSvg('bulb')}</span>${t('insights')}</div><div class="mem-empty" style="padding:12px 0">${t('noInsights')}</div></div>`;
  }

  body.innerHTML = html;
}

// ═══════════════════════════════════════════════════════════════════════
// SCROLL MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════
function checkScrollPosition() {
  const area = document.getElementById('msgArea');
  const distFromLatest = Math.max(0, latestMessageScrollTop(area) - area.scrollTop);
  S.isAtBottom = distFromLatest < 100;
  updateScrollBottomButton(area, distFromLatest);
}

function updateScrollBottomButton(area, distance = null) {
  const distFromLatest = distance ?? Math.max(0, latestMessageScrollTop(area) - area.scrollTop);
  const btn = document.getElementById('scrollBottomBtn');
  if (distFromLatest > 200) {
    btn.classList.add('visible');
  } else {
    btn.classList.remove('visible');
  }
}

function latestMessageScrollTop(area) {
  const rows = area.querySelectorAll('.msg-row');
  const lastRow = rows[rows.length - 1];
  if (!lastRow) return 0;

  const areaRect = area.getBoundingClientRect();
  const rowRect = lastRow.getBoundingClientRect();
  const bottomPadding = parseFloat(getComputedStyle(area).paddingBottom) || 0;
  const target = area.scrollTop + rowRect.bottom + bottomPadding - areaRect.bottom;
  const maximum = Math.max(0, area.scrollHeight - area.clientHeight);
  return Math.max(0, Math.min(maximum, target));
}

function scrollToBottom() {
  const area = document.getElementById('msgArea');
  requestAnimationFrame(() => {
    // The runway below the messages exists only to allow new turns to pin at
    // the top. “Latest” means the final visible message, not that runway's end.
    const previousBehavior = area.style.scrollBehavior;
    area.style.scrollBehavior = 'auto';
    area.scrollTop = latestMessageScrollTop(area);
    area.style.scrollBehavior = previousBehavior;
    S.isAtBottom = true;
    document.getElementById('scrollBottomBtn').classList.remove('visible');
  });
}

function pinMessageToTop(index) {
  const area = document.getElementById('msgArea');
  requestAnimationFrame(() => {
    const row = area.querySelector(`[data-idx="${index}"]`);
    if (!row) return;

    const paddingTop = parseFloat(getComputedStyle(area).paddingTop) || 0;
    const areaRect = area.getBoundingClientRect();
    const rowRect = row.getBoundingClientRect();
    const target = area.scrollTop + rowRect.top - areaRect.top - paddingTop;
    const maximum = Math.max(0, area.scrollHeight - area.clientHeight);
    const previousBehavior = area.style.scrollBehavior;
    area.style.scrollBehavior = 'auto';
    area.scrollTop = Math.max(0, Math.min(maximum, target));
    area.style.scrollBehavior = previousBehavior;
    // Do not auto-follow streaming just because the whole short response is
    // currently visible. A newly sent turn remains anchored until the user
    // explicitly scrolls to the latest response.
    S.isAtBottom = false;
    updateScrollBottomButton(area);
  });
}

// ═══════════════════════════════════════════════════════════════════════
// SEARCH / FILTER
// ═══════════════════════════════════════════════════════════════════════
function filterConversations() {
  const q = this.value.toLowerCase();
  document.querySelectorAll('.conv-item').forEach(el => {
    const title = el.querySelector('.conv-title')?.textContent.toLowerCase() || '';
    el.style.display = title.includes(q) ? '' : 'none';
  });
}

// ═══════════════════════════════════════════════════════════════════════
// TOAST NOTIFICATION
// ═══════════════════════════════════════════════════════════════════════
function showToast(message) {
  document.querySelectorAll('.toast').forEach(t => t.remove());

  const toast = document.createElement('div');
  toast.className = 'toast';
  toast.textContent = message;
  document.body.appendChild(toast);

  setTimeout(() => {
    toast.classList.add('fadeout');
    setTimeout(() => toast.remove(), 300);
  }, 1800);
}

// ═══════════════════════════════════════════════════════════════════════
// COMPOSER
// ═══════════════════════════════════════════════════════════════════════
function autoResize(ta) {
  ta.style.height = 'auto';
  ta.style.height = Math.min(ta.scrollHeight, 200) + 'px';
}

// ═══════════════════════════════════════════════════════════════════════
// MARKDOWN RENDERER
// ═══════════════════════════════════════════════════════════════════════
function md(text) {
  if (!text) return '';

  let h = esc(text);

  h = h.replace(/```(\w*)\n?([\s\S]*?)```/g, (match, lang, code) => {
    const langLabel = lang ? `<span class="code-lang">${lang}</span>` : '';
    return `<div class="code-block-wrap">${langLabel}<button class="code-copy-btn" onclick="copyCodeBlock(this)">${t('copy')}</button><pre><code>${code.trim()}</code></pre></div>`;
  });

  h = h.replace(/`([^`]+)`/g, '<code>$1</code>');

  h = h.replace(/((?:\|[^\n]+\|\n)+)/g, (match) => {
    const rows = match.trim().split('\n').filter(r => r.trim());
    if (rows.length < 2) return match;

    const isSep = rows[1] && /^\|[\s\-:|]+\|$/.test(rows[1].trim());
    if (!isSep) return match;

    const headerCells = rows[0].split('|').filter(c => c.trim());
    let tableHtml = '<table><thead><tr>';
    headerCells.forEach(c => { tableHtml += `<th>${c.trim()}</th>`; });
    tableHtml += '</tr></thead><tbody>';

    for (let i = 2; i < rows.length; i++) {
      const cells = rows[i].split('|').filter(c => c.trim());
      tableHtml += '<tr>';
      cells.forEach(c => { tableHtml += `<td>${c.trim()}</td>`; });
      tableHtml += '</tr>';
    }
    tableHtml += '</tbody></table>';
    return tableHtml;
  });

  h = h.replace(/^####\s+(.+)$/gm, '<h4>$1</h4>');
  h = h.replace(/^###\s+(.+)$/gm, '<h3>$1</h3>');
  h = h.replace(/^##\s+(.+)$/gm, '<h2>$1</h2>');
  h = h.replace(/^#\s+(.+)$/gm, '<h1>$1</h1>');

  h = h.replace(/^---+$/gm, '<hr>');

  h = h.replace(/\*\*\*([^*]+)\*\*\*/g, '<strong><em>$1</em></strong>');
  h = h.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  h = h.replace(/\*([^*]+)\*/g, '<em>$1</em>');

  h = h.replace(/^&gt;\s?(.+)$/gm, '<blockquote>$1</blockquote>');
  h = h.replace(/^[-*]\s+(.+)$/gm, '<li>$1</li>');
  h = h.replace(/^\d+\.\s+(.+)$/gm, '<li>$1</li>');
  h = h.replace(/((?:<li>.*?<\/li>\n?)+)/g, '<ul>$1</ul>');
  h = h.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');

  h = h.replace(/\n\n/g, '</p><p>');
  h = h.replace(/\n/g, '<br>');

  h = '<p>' + h + '</p>';
  h = h.replace(/<p>\s*<\/p>/g, '');
  h = h.replace(/<p>\s*(<h[1-4]>)/g, '$1');
  h = h.replace(/(<\/h[1-4]>)\s*<\/p>/g, '$1');
  h = h.replace(/<p>\s*(<ul>)/g, '$1');
  h = h.replace(/(<\/ul>)\s*<\/p>/g, '$1');
  h = h.replace(/<p>\s*(<table>)/g, '$1');
  h = h.replace(/(<\/table>)\s*<\/p>/g, '$1');
  h = h.replace(/<p>\s*(<div class="code-block-wrap">)/g, '$1');
  h = h.replace(/(<\/div>)\s*<\/p>/g, '$1');
  h = h.replace(/<p>\s*(<hr>)/g, '$1');
  h = h.replace(/(<hr>)\s*<\/p>/g, '$1');
  h = h.replace(/<p>\s*(<blockquote>)/g, '$1');
  h = h.replace(/(<\/blockquote>)\s*<\/p>/g, '$1');

  return h;
}

function copyCodeBlock(btn) {
  const pre = btn.parentElement.querySelector('pre code');
  if (pre) {
    navigator.clipboard.writeText(pre.textContent).then(() => {
      btn.innerHTML = iconSvg('check');
      setTimeout(() => { btn.textContent = t('copy'); }, 1500);
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════
function esc(s) {
  if (!s) return '';
  const d = document.createElement('div');
  d.textContent = s;
  return d.innerHTML;
}

function formatTime(iso) {
  if (!iso) return '';
  try {
    const d = new Date(iso);
    const now = new Date();
    const diffMs = now - d;
    const diffMin = Math.floor(diffMs / 60000);
    const diffHrs = Math.floor(diffMs / 3600000);
    const diffDays = Math.floor(diffMs / 86400000);

    const isZh = S.lang === 'zh' || S.lang === 'zh-hant';

    if (diffMin < 1) return isZh ? '刚刚' : 'Just now';
    if (diffMin < 60) return isZh ? `${diffMin}分钟前` : `${diffMin}m ago`;
    if (diffHrs < 24) return isZh ? `${diffHrs}小时前` : `${diffHrs}h ago`;
    if (diffDays === 1) return isZh ? '昨天' : 'Yesterday';
    if (diffDays < 7) return isZh ? `${diffDays}天前` : `${diffDays}d ago`;
    if (diffDays < 30) return isZh ? `${Math.floor(diffDays / 7)}周前` : `${Math.floor(diffDays / 7)}w ago`;
    return d.toLocaleDateString(isZh ? 'zh-CN' : 'en-US', { month: 'short', day: 'numeric' });
  } catch { return ''; }
}

function formatDateTime(value) {
  try {
    const d = value instanceof Date ? value : new Date(value);
    if (Number.isNaN(d.getTime())) return '';
    const locale = S.lang === 'zh-hant' ? 'zh-TW' : (S.lang === 'zh' ? 'zh-CN' : 'en-US');
    return d.toLocaleString(locale, {
      year: 'numeric', month: 'numeric', day: 'numeric',
      hour: '2-digit', minute: '2-digit'
    });
  } catch { return ''; }
}

function formatDuration(ms) {
  const safeMs = Math.max(0, Number(ms) || 0);
  const minutes = Math.floor(safeMs / 60000);
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);
  const isZh = S.lang === 'zh' || S.lang === 'zh-hant';
  if (days > 0) return isZh ? `${days}天${hours % 24}小时` : `${days}d ${hours % 24}h`;
  if (hours > 0) return isZh ? `${hours}小时${minutes % 60}分钟` : `${hours}h ${minutes % 60}m`;
  if (minutes > 0) return isZh ? `${minutes}分钟` : `${minutes}m`;
  return isZh ? '不到1分钟' : '<1m';
}

function setStatus(msg) {
  // Status is kept in logs/toasts; the persistent footer was removed to
  // match the native macOS layout.
  L.d('Status', msg);
}

function clearErrorBanner() {
  const eb = document.getElementById('errorBanner');
  if (eb) {
    eb.style.display = 'none';
    eb.textContent = '';
  }
}

function showErrorBanner(msg) {
  const eb = document.getElementById('errorBanner');
  if (eb) {
    eb.style.display = 'block';
    eb.textContent = msg;
  }
}
