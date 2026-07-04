import Foundation

enum ChatRole: String, Codable, CaseIterable {
    case user
    case assistant
    case system
}

struct ChatMessage: Identifiable, Codable, Equatable {
    var id = UUID()
    var role: ChatRole
    var content: String
    var reasoning: String?
    var toolCalls: [ToolCall]?
    var createdAt = Date()
    var suggestions: [String] = []
}

struct Conversation: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var createdAt = Date()
    var updatedAt = Date()
    var messages: [ChatMessage] = []
    var chapters: [StoryChapter] = []
    /// Kept for backward compatibility — no longer drives summarization logic.
    var summaryIntervalMinutes: Int = 5
    var lastSummarizedAt: Date?
    var lastSummaryMessageIndex: Int = 0
    /// Number of completed user+assistant dialog turns since the last summary.
    var completedDialogCount: Int = 0
    /// How many incremental chapters have been appended since the last full re-scan.
    /// When this reaches 3, the next auto-summary uses fullReSummarize to
    /// consolidate chapters into a consistent style.
    var incrementalChapterCount: Int = 0

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [ChatMessage] = [],
        chapters: [StoryChapter] = [],
        summaryIntervalMinutes: Int = 5
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.chapters = chapters
        self.summaryIntervalMinutes = summaryIntervalMinutes
        self.lastSummarizedAt = nil
        self.lastSummaryMessageIndex = 0
        self.completedDialogCount = 0
    }

    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, updatedAt, messages, chapters
        case summaryIntervalMinutes, lastSummarizedAt, lastSummaryMessageIndex
        case completedDialogCount, incrementalChapterCount
    }
}

struct StoryChapter: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var summary: String
    var keywords: [String]
    var messageIDs: [UUID]
    var createdAt = Date()
    var updatedAt = Date()
}

struct ModelParameters: Codable, Equatable {
    var thinkingEnabled: Bool = true
    var reasoningEffort: String = "high"
}

enum ConversationMode: String, CaseIterable, Codable {
    case rational = "rational"
    case balanced = "balanced"
    case warm = "warm"
}

enum ResponseLength: String, CaseIterable, Codable {
    case brief = "brief"
    case standard = "standard"
    case detailed = "detailed"
}

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"

    var id: String { rawValue }
}

// MARK: - Post‑Pipeline Data (stored in local JSON)

struct EmotionEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var conversationID: UUID
    var segment: String
    var emotion: String
    var intensity: Double
    var createdAt = Date()
}

struct PersonRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var role: String              // ex-partner / 家人 / 朋友 / 同事 / ...
    var firstMentionedAt: Date
    var lastMentionedAt: Date
    var mentionCount: Int = 1
    var emotionalArc: String = "" // "愤怒 → 释然"
    var notes: [String] = []       // per-conversation deltas
}

// MARK: - Smart Search Results

struct SearchSnippet: Identifiable {
    var id = UUID()
    var context: String
    var matchPosition: Int
    var matchLength: Int
    var messageIndex: Int       // 1‑based
    var source: String          // "title" | "message" | "chapter"
}

struct SearchResult: Identifiable {
    var id: UUID { conversationID }
    var conversationID: UUID
    var conversationTitle: String
    var score: Int
    var snippets: [SearchSnippet]
}

// MARK: - Cross‑Conversation Memory

struct MemoryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var content: String            // distilled insight / chapter summary
    var keywords: [String]
    var sourceConversationID: UUID
    var sourceChapterTitle: String
    var createdAt = Date()
    var lastRecalledAt: Date?
    var recallCount: Int = 0
}

struct BlindspotRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var conversationID: UUID
    var pattern: String
    var evidence: String
    var counterQuestion: String
    var severity: String = "new"  // new / recurring / persistent
    var createdAt = Date()
}

// MARK: - MCP Tool Call / Response (Function Calling wire format)

struct ToolCall: Equatable {
    var id: String
    var name: String
    var arguments: String  // JSON string

    // Custom Codable to match DeepSeek API wire format:
    // {"id":"call_xxx","type":"function","function":{"name":"...","arguments":"..."}}
    enum CodingKeys: String, CodingKey {
        case id, type
        case function
    }
    enum FunctionKeys: String, CodingKey {
        case name, arguments
    }

    init(id: String = "", name: String = "", arguments: String = "") {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

extension ToolCall: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        let fn = try c.nestedContainer(keyedBy: FunctionKeys.self, forKey: .function)
        name = try fn.decode(String.self, forKey: .name)
        arguments = try fn.decode(String.self, forKey: .arguments)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode("function", forKey: .type)
        var fn = c.nestedContainer(keyedBy: FunctionKeys.self, forKey: .function)
        try fn.encode(name, forKey: .name)
        try fn.encode(arguments, forKey: .arguments)
    }
}

struct ToolCallDelta: Codable {
    var index: Int?
    var id: String?
    var function: ToolFnDelta?

    struct ToolFnDelta: Codable {
        var name: String?
        var arguments: String?
    }
}

struct ToolResult: Codable, Equatable {
    var toolCallID: String
    var name: String
    var content: String  // JSON result string
}

