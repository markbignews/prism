using System.Text.Json;

namespace PrismAgent;

public class Tools
{
    private readonly ChatAgent _agent;

    public Tools(ChatAgent agent) { _agent = agent; }

    public static readonly object[] Definitions = {
        new { type = "function", function = new { name = "track_person", description = "查询一个人是否在历史对话中出现过", parameters = new { type = "object", properties = new { name = new { type = "string", description = "人名或身份称呼" } }, required = new[] { "name" } } } },
        new { type = "function", function = new { name = "emotion_timeline", description = "返回用户最近N轮对话的情绪轨迹", parameters = new { type = "object", properties = new { count = new { type = "integer", description = "条数，默认5" } } } } },
        new { type = "function", function = new { name = "search_chapters", description = "语义搜索历史章节", parameters = new { type = "object", properties = new { query = new { type = "string", description = "搜索关键词" }, count = new { type = "integer", description = "返回条数，默认5" } }, required = new[] { "query" } } } },
        new { type = "function", function = new { name = "fetch_chapter_messages", description = "获取指定章节的全部原文消息", parameters = new { type = "object", properties = new { index = new { type = "integer", description = "章节序号，从1开始" } }, required = new[] { "index" } } } },
        new { type = "function", function = new { name = "search_memory", description = "搜索跨对话记忆库", parameters = new { type = "object", properties = new { query = new { type = "string", description = "搜索关键词" }, count = new { type = "integer", description = "返回条数，默认10" } }, required = new[] { "query" } } } },
    };

    public string Execute(string name, string argsJson)
    {
        var args = new Dictionary<string, string>();
        try { args = JsonSerializer.Deserialize<Dictionary<string, string>>(argsJson) ?? new(); } catch { }

        return name switch
        {
            "track_person" => JsonSerializer.Serialize(_agent.PersonArchive.FirstOrDefault(p => p.Name.Contains(args.GetValueOrDefault("name", ""), StringComparison.OrdinalIgnoreCase)) ?? (object)new { found = false }),
            "emotion_timeline" => JsonSerializer.Serialize(new { entries = _agent.EmotionTimeline.TakeLast(int.TryParse(args.GetValueOrDefault("count", "5"), out var n) ? n : 5) }),
            "search_chapters" => JsonSerializer.Serialize(_agent.SearchChapters(args.GetValueOrDefault("query", ""), int.TryParse(args.GetValueOrDefault("count", "5"), out var c) ? c : 5).Select(ch => new { ch.Title, Summary = ch.Summary[..Math.Min(200, ch.Summary.Length)], ch.Keywords })),
            "fetch_chapter_messages" => FetchChapterMessages(args),
            "search_memory" => JsonSerializer.Serialize(_agent.SearchMemory(args.GetValueOrDefault("query", ""), int.TryParse(args.GetValueOrDefault("count", "10"), out var m) ? m : 10).Select(e => new { e.Content, e.Keywords, SourceChapter = e.SourceChapterTitle, e.RecallCount })),
            _ => JsonSerializer.Serialize(new { error = $"unknown tool: {name}" })
        };
    }

    private string FetchChapterMessages(Dictionary<string, string> args)
    {
        if (!int.TryParse(args.GetValueOrDefault("index", "1"), out var idx) || idx < 1) return JsonSerializer.Serialize(new { error = "invalid index" });
        var chapters = _agent.AllChapters;
        if (idx > chapters.Count) return JsonSerializer.Serialize(new { error = "chapter not found" });
        var ch = chapters[idx - 1];
        var msgs = _agent.CurrentConv?.Messages.Where(m => ch.MessageIDs.Contains(m.Id) && m.Role != "system").Take(12) ?? Enumerable.Empty<ChatMessage>();
        return JsonSerializer.Serialize(new { chapter = idx, ch.Title, ch.Summary, ch.Keywords, messages = msgs.Select(m => new { role = m.Role, content = m.Content }) });
    }
}
