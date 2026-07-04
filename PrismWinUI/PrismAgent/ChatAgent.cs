using System.Text.Json;

namespace PrismAgent;

public class ChatAgent
{
    private readonly string _dataPath;
    private readonly Archives _archives;
    private readonly Tools _tools;
    private readonly PrePipeline _pipeline;

    public List<Conversation> Conversations { get; set; } = new();
    public string? SelectedConversationID { get; set; }
    public bool IsSending { get; set; }
    public string? ErrorMessage { get; set; }
    public bool IsSummarizing { get; set; }
    public string LastSummaryStatus { get; set; } = "";
    public CancellationTokenSource? Cts { get; set; }

    public List<PersonRecord> PersonArchive { get; set; } = new();
    public List<EmotionEntry> EmotionTimeline { get; set; } = new();
    public List<BlindspotRecord> Blindspots { get; set; } = new();
    public List<MemoryEntry> MemoryStore { get; set; } = new();

    public Conversation? CurrentConv => Conversations.FirstOrDefault(c => c.Id == SelectedConversationID);
    public List<StoryChapter> AllChapters => Conversations.SelectMany(c => c.Chapters).ToList();

    public ChatAgent(string dataPath)
    {
        _dataPath = dataPath;
        _archives = new Archives(dataPath);
        _tools = new Tools(this);
        _pipeline = new PrePipeline(this);
        Load();
        LoadArchives();
    }

    // ── Persistence ──

    void Load()
    {
        var p = Path.Combine(_dataPath, "conversations.json");
        try { Conversations = JsonSerializer.Deserialize<List<Conversation>>(File.ReadAllText(p)) ?? new(); } catch { }
    }
    void Save() { Directory.CreateDirectory(_dataPath); File.WriteAllText(Path.Combine(_dataPath, "conversations.json"), JsonSerializer.Serialize(Conversations)); }
    void LoadArchives() { PersonArchive = _archives.Load<List<PersonRecord>>("person_archive.json"); EmotionTimeline = _archives.Load<List<EmotionEntry>>("emotion_timeline.json"); Blindspots = _archives.Load<List<BlindspotRecord>>("blindspots.json"); MemoryStore = _archives.Load<List<MemoryEntry>>("memory.json"); }
    void SaveArchives() { _archives.Save("person_archive.json", PersonArchive); _archives.Save("emotion_timeline.json", EmotionTimeline); _archives.Save("blindspots.json", Blindspots); _archives.Save("memory.json", MemoryStore); }

    // ── CRUD ──

    public void CreateConversation(string lang = "zh-Hans")
    {
        var c = new Conversation { Title = lang.StartsWith("zh") ? "新对话" : "New Conversation" };
        Conversations.Insert(0, c); SelectedConversationID = c.Id; Save();
    }
    public void DeleteConversation(string id) { if (IsSummarizing) return; Conversations.RemoveAll(c => c.Id == id); if (SelectedConversationID == id) SelectedConversationID = Conversations.FirstOrDefault()?.Id; Save(); }
    public void DeleteMessage(string convID, string msgID)
    {
        var ci = Conversations.FindIndex(c => c.Id == convID); if (ci == -1) return;
        var mi = Conversations[ci].Messages.FindIndex(m => m.Id == msgID); if (mi == -1) return;
        if (Conversations[ci].Messages[mi].Role == "user" && mi + 1 < Conversations[ci].Messages.Count && Conversations[ci].Messages[mi + 1].Role == "assistant")
            Conversations[ci].Messages.RemoveRange(mi, 2);
        else Conversations[ci].Messages.RemoveAt(mi);
        Conversations[ci].UpdatedAt = DateTime.UtcNow; Save();
    }

    // ── Send (main entry) ──

    public async Task SendAsync(string text, AppSettings s, Action<string, string> onToken)
    {
        text = text.Trim(); if (string.IsNullOrEmpty(text) || IsSending) return;
        var conv = CurrentConv; if (conv == null) return;

        var userMsg = new ChatMessage { Role = "user", Content = text };
        conv.Messages.Add(userMsg); conv.UpdatedAt = DateTime.UtcNow;
        var assistantID = Guid.NewGuid().ToString();
        conv.Messages.Add(new ChatMessage { Id = assistantID, Role = "assistant" });
        Save();

        IsSending = true; ErrorMessage = null;
        Cts = new CancellationTokenSource(); var ct = Cts.Token;
        var finalContent = ""; var finalReasoning = "";

        try
        {
            var preResult = await _pipeline.RunAsync(conv, s, ct);
            if (preResult.SafetyCrisis)
            {
                var crisisMsg = PrePipeline.BuildSafetyResponse(preResult, s.Language);
                var ai = conv.Messages.Find(m => m.Id == assistantID)!;
                ai.Content = crisisMsg; ai.Reasoning = "Safety intervention";
                IsSending = false; Save(); return;
            }

            var client = new DeepSeekClient(s.ApiKey, s.BaseURL, s.Model, s.ThinkingEnabled);
            var roundMsgs = conv.Messages.Count <= 60 ? conv.Messages : conv.Messages.TakeLast(40).ToList();

            for (int round = 0; round < 3; round++)
            {
                var content = ""; var reasoning = ""; var toolCalls = new List<ToolCall>();
                await foreach (var evt in client.StreamAsync(roundMsgs, AgentPrompt.System(s.Language, s.Mode), Tools.Definitions.ToList(), preResult.GuardHint, s.Mode switch { "rational" => ConversationMode.Rational, "warm" => ConversationMode.Warm, _ => ConversationMode.Balanced }, ct))
                {
                    var json = JsonSerializer.Serialize(evt);
                    using var doc = JsonDocument.Parse(json);
                    var type = doc.RootElement.GetProperty("type").GetString();
                    if (type == "content") { content += doc.RootElement.GetProperty("token").GetString(); onToken("content", doc.RootElement.GetProperty("token").GetString()!); }
                    else if (type == "reasoning") { reasoning += doc.RootElement.GetProperty("token").GetString(); onToken("reasoning", doc.RootElement.GetProperty("token").GetString()!); }
                    else if (type == "tool_calls") { var calls = JsonSerializer.Deserialize<List<ToolCall>>(doc.RootElement.GetProperty("calls").GetRawText()); if (calls != null) toolCalls.AddRange(calls); }
                }
                if (toolCalls.Count == 0) { finalContent = content; finalReasoning = reasoning; break; }
                foreach (var tc in toolCalls) { /* execute tool, feed result back — simplified */ }
                finalContent = content; finalReasoning = reasoning;
            }

            var aim = conv.Messages.Find(m => m.Id == assistantID)!;
            aim.Content = string.IsNullOrWhiteSpace(finalContent) ? "[No response]" : finalContent.Trim();
            aim.Reasoning = finalReasoning;

            _pipeline.ApplyResults(preResult, conv);
            TriggerSummarization(s);
        }
        catch (OperationCanceledException)
        {
            var aim = conv.Messages.Find(m => m.Id == assistantID)!;
            aim.Content = s.Language.StartsWith("zh") ? "[已取消生成]" : "[Generation cancelled]";
            aim.Reasoning = "[Cancelled]";
        }
        catch (Exception ex) { ErrorMessage = ex.Message; }
        finally { IsSending = false; Cts = null; Save(); }
    }

    public void Cancel() { Cts?.Cancel(); }

    // ── Search ──

    public List<StoryChapter> SearchChapters(string query, int limit = 10)
    {
        var chapters = AllChapters; if (string.IsNullOrEmpty(query)) return chapters.TakeLast(limit).ToList();
        var terms = SearchExpander.Expand(query.Split(' ', StringSplitOptions.RemoveEmptyEntries));
        return chapters.Select(ch => new { ch, score = terms.Sum(t => (ch.Title.Contains(t, StringComparison.OrdinalIgnoreCase) ? 3 : 0) + (ch.Keywords.Any(k => k.Contains(t, StringComparison.OrdinalIgnoreCase)) ? 2 : 0) + (ch.Summary.Contains(t, StringComparison.OrdinalIgnoreCase) ? 1 : 0)) }).Where(x => x.score > 0).OrderByDescending(x => x.score).Take(limit).Select(x => x.ch).ToList();
    }

    public List<MemoryEntry> SearchMemory(string query, int limit = 10)
    {
        if (string.IsNullOrEmpty(query)) return MemoryStore.TakeLast(limit).ToList();
        var terms = SearchExpander.Expand(query.Split(' ', StringSplitOptions.RemoveEmptyEntries));
        return MemoryStore.Select(e => new { e, score = terms.Sum(t => (e.Keywords.Any(k => k.Equals(t, StringComparison.OrdinalIgnoreCase)) ? 3 : 0) + (e.Keywords.Any(k => k.Contains(t, StringComparison.OrdinalIgnoreCase)) ? 2 : 0) + (e.Content.Contains(t, StringComparison.OrdinalIgnoreCase) ? 1 : 0)) }).Where(x => x.score > 0).OrderByDescending(x => x.score).Take(limit).Select(x => { x.e.RecallCount++; return x.e; }).ToList();
    }

    // ── Summarization (simplified) ──

    async Task TriggerSummarization(AppSettings s)
    {
        var conv = CurrentConv; if (conv == null) return;
        conv.CompletedDialogCount++;
        if (conv.CompletedDialogCount < 5) return;
        IsSummarizing = true; LastSummaryStatus = "正在归纳...";
        try
        {
            var client = new DeepSeekClient(s.ApiKey, s.BaseURL, s.FlashModel, false);
            var newMsgs = conv.Messages.Skip(conv.LastSummaryMessageIndex).ToList();
            if (newMsgs.Count < 2) return;
            var transcript = string.Join("\n\n", newMsgs.Select(m => $"[{m.Role}]: {m.Content}"));
            var raw = await client.SummarizeAsync(AgentPrompt.Summarization, transcript);
            var match = System.Text.RegularExpressions.Regex.Match(raw, @"\{[\s\S]*\}");
            if (match.Success)
            {
                var json = JsonSerializer.Deserialize<JsonElement>(match.Value);
                var ch = new StoryChapter { Title = json.GetProperty("title").GetString()!, Summary = json.GetProperty("summary").GetString()!, Keywords = json.GetProperty("keywords").EnumerateArray().Select(x => x.GetString()!).ToList(), MessageIDs = newMsgs.Select(m => m.Id).ToList() };
                conv.Chapters.Add(ch); conv.LastSummaryMessageIndex = conv.Messages.Count; conv.IncrementalChapterCount++;
                MemoryStore.Add(new MemoryEntry { Content = ch.Summary, Keywords = ch.Keywords, SourceConversationID = conv.Id, SourceChapterTitle = ch.Title });
                LastSummaryStatus = $"已生成章节「{ch.Title}」"; Save(); SaveArchives();
            }
        }
        catch { }
        finally { IsSummarizing = false; conv.CompletedDialogCount = 0; }
    }
}
