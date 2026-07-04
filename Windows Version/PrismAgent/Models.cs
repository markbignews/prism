namespace PrismAgent;

public enum ChatRole { User, Assistant, System }

public enum ConversationMode { Rational, Balanced, Warm }

public enum AppLanguage { ZhHans, ZhHant, En }

public class ChatMessage
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Role { get; set; } = "";
    public string Content { get; set; } = "";
    public string? Reasoning { get; set; }
    public List<ToolCall>? ToolCalls { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public class Conversation
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Title { get; set; } = "";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    public List<ChatMessage> Messages { get; set; } = new();
    public List<StoryChapter> Chapters { get; set; } = new();
    public int LastSummaryMessageIndex { get; set; }
    public int CompletedDialogCount { get; set; }
    public int IncrementalChapterCount { get; set; }
}

public class StoryChapter
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Title { get; set; } = "";
    public string Summary { get; set; } = "";
    public List<string> Keywords { get; set; } = new();
    public List<string> MessageIDs { get; set; } = new();
}

public class EmotionEntry
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string ConversationID { get; set; } = "";
    public string Segment { get; set; } = "";
    public string Emotion { get; set; } = "";
    public double Intensity { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public class PersonRecord
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Name { get; set; } = "";
    public string Role { get; set; } = "";
    public DateTime FirstMentionedAt { get; set; } = DateTime.UtcNow;
    public DateTime? LastMentionedAt { get; set; }
    public int MentionCount { get; set; }
    public List<string> Notes { get; set; } = new();
}

public class BlindspotRecord
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string ConversationID { get; set; } = "";
    public string Pattern { get; set; } = "";
    public string Evidence { get; set; } = "";
    public string CounterQuestion { get; set; } = "";
    public string Severity { get; set; } = "new";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public class MemoryEntry
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Content { get; set; } = "";
    public List<string> Keywords { get; set; } = new();
    public string SourceConversationID { get; set; } = "";
    public string SourceChapterTitle { get; set; } = "";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public int RecallCount { get; set; }
}

public class ToolCall
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Arguments { get; set; } = "";
}

public class AppSettings
{
    public string ApiKey { get; set; } = "";
    public string BaseURL { get; set; } = "https://api.deepseek.com";
    public string Model { get; set; } = "deepseek-v4-pro";
    public string FlashModel { get; set; } = "deepseek-v4-flash";
    public string Language { get; set; } = "zh-Hans";
    public string Mode { get; set; } = "balanced";
    public bool ThinkingEnabled { get; set; } = true;
    public string ReasoningEffort { get; set; } = "high";
}

public class StreamToken
{
    public string Type { get; set; } = ""; // "content" or "reasoning"
    public string Token { get; set; } = "";
}
