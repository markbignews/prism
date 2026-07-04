using System.Text.Json;
using System.Text.RegularExpressions;

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
        Load(); LoadArchives();
    }

    void Load() { var p = Path.Combine(_dataPath, "conversations.json"); try { Conversations = JsonSerializer.Deserialize<List<Conversation>>(File.ReadAllText(p)) ?? new(); } catch { } }
    void Save() { Directory.CreateDirectory(_dataPath); File.WriteAllText(Path.Combine(_dataPath, "conversations.json"), JsonSerializer.Serialize(Conversations)); }
    void LoadArchives() { PersonArchive = _archives.Load<List<PersonRecord>>("person_archive.json"); EmotionTimeline = _archives.Load<List<EmotionEntry>>("emotion_timeline.json"); Blindspots = _archives.Load<List<BlindspotRecord>>("blindspots.json"); MemoryStore = _archives.Load<List<MemoryEntry>>("memory.json"); }
    void SaveArchives() { _archives.Save("person_archive.json", PersonArchive); _archives.Save("emotion_timeline.json", EmotionTimeline); _archives.Save("blindspots.json", Blindspots); _archives.Save("memory.json", MemoryStore); }

    // ── CRUD ──

    public void CreateConversation(string lang = "zh-Hans") { var c = new Conversation { Title = lang.StartsWith("zh") ? "新对话" : "New Conversation" }; Conversations.Insert(0, c); SelectedConversationID = c.Id; Save(); }
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
            // Step 1: Pre-pipeline (guard + emotion + person)
            var preResult = await _pipeline.RunAsync(conv, s, ct);
            if (preResult.SafetyCrisis)
            {
                conv.Messages.Find(m => m.Id == assistantID)!.Content = PrePipeline.BuildSafetyResponse(preResult, s.Language);
                conv.Messages.Find(m => m.Id == assistantID)!.Reasoning = "Safety intervention";
                IsSending = false; Save(); return;
            }

            // Step 2: Main model + tool loop (max 3 rounds)
            var client = new DeepSeekClient(s.ApiKey, s.BaseURL, s.Model, s.ThinkingEnabled);
            var roundMsgs = BuildWindowedMessages(conv);

            for (int round = 0; round < 3; round++)
            {
                var content = ""; var reasoning = ""; var toolCalls = new List<ToolCall>();
                await foreach (var evt in client.StreamAsync(roundMsgs, AgentPrompt.System(s.Language, s.Mode), Tools.Definitions.ToList(), preResult.GuardHint, s.Mode switch { "rational" => ConversationMode.Rational, "warm" => ConversationMode.Warm, _ => ConversationMode.Balanced }, ct))
                {
                    var json = JsonSerializer.Serialize(evt);
                    using var doc = JsonDocument.Parse(json);
                    var type = doc.RootElement.GetProperty("type").GetString();
                    if (type == "content") { var tok = doc.RootElement.GetProperty("token").GetString()!; content += tok; onToken("content", tok); }
                    else if (type == "reasoning") { var tok = doc.RootElement.GetProperty("token").GetString()!; reasoning += tok; onToken("reasoning", tok); }
                    else if (type == "tool_calls") { var calls = JsonSerializer.Deserialize<List<ToolCall>>(doc.RootElement.GetProperty("calls").GetRawText()); if (calls != null) toolCalls.AddRange(calls); }
                }

                if (toolCalls.Count == 0) { finalContent = content; finalReasoning = reasoning; break; }

                // Persist tool calls to the assistant message
                conv.Messages.Find(m => m.Id == assistantID)!.ToolCalls = toolCalls;

                // Execute tools, collect results
                foreach (var tc in toolCalls)
                {
                    var resultJSON = _tools.Execute(tc.Name, tc.Arguments);
                    // Build new round messages with tool results injected
                    var toolResultMsgs = new List<ChatMessage>(roundMsgs)
                    {
                        new ChatMessage { Role = "assistant", Content = content, ToolCalls = new List<ToolCall> { tc } },
                        new ChatMessage { Role = "tool", Content = resultJSON }
                    };
                    roundMsgs = toolResultMsgs;
                }

                finalContent = content; finalReasoning = reasoning;
            }

            // Finalize
            var aim = conv.Messages.Find(m => m.Id == assistantID)!;
            aim.Content = string.IsNullOrWhiteSpace(finalContent) ? "[No response]" : finalContent.Trim();
            aim.Reasoning = finalReasoning; aim.ToolCalls = null;

            // Step 3: Apply pre-pipeline archive updates + trigger summarization
            _pipeline.ApplyResults(preResult, conv);
            await TriggerSummarizationAsync(s);
        }
        catch (OperationCanceledException)
        {
            var aim = conv.Messages.Find(m => m.Id == assistantID)!;
            aim.Content = s.Language.StartsWith("zh") ? "[已取消生成]" : "[Generation cancelled]";
            aim.Reasoning = "[Cancelled]";
        }
        catch (Exception ex) { ErrorMessage = ex.Message; }
        finally { IsSending = false; Cts = null; Save(); SaveArchives(); }
    }

    public void Cancel() { Cts?.Cancel(); }

    // ── Context Window Strategy ──

    List<ChatMessage> BuildWindowedMessages(Conversation conv)
    {
        if (conv.Messages.Count <= 60) return conv.Messages.ToList();
        return conv.Messages.TakeLast(40).ToList();
        // Note: full implementation would prepend chapter summaries for older content.
        // The model can still retrieve compressed messages via search tools.
    }

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

    // ── Flash Semantic Reranker for Search ──

    public async Task<List<StoryChapter>> SearchChaptersSemanticAsync(string query, AppSettings s, int limit = 5)
    {
        var keywordResults = SearchChapters(query, 15);
        if (keywordResults.Count <= 2) return keywordResults.Take(limit).ToList();
        var client = new DeepSeekClient(s.ApiKey, s.BaseURL, s.FlashModel, false);
        var candidates = string.Join("\n", keywordResults.Select((ch, i) => $"[{i}] {ch.Title} — {ch.Summary[..Math.Min(100, ch.Summary.Length)]}"));
        try
        {
            var raw = await client.SummarizeAsync("你是一个搜索重排序系统。按与查询的相关度排序候选项。仅返回排序后的序号JSON数组，如[3,1,5,2,4]。", $"查询: {query}\n\n候选项:\n{candidates}");
            var match = Regex.Match(raw.Trim(), @"\[[\d,\s]*\]");
            if (match.Success)
            {
                var indices = JsonSerializer.Deserialize<int[]>(match.Value) ?? Array.Empty<int>();
                return indices.Where(i => i < keywordResults.Count).Select(i => keywordResults[i]).Take(limit).ToList();
            }
        }
        catch { }
        return keywordResults.Take(limit).ToList();
    }

    // ── Summarization ──

    async Task TriggerSummarizationAsync(AppSettings s)
    {
        var conv = CurrentConv; if (conv == null) return;
        conv.CompletedDialogCount++;
        if (conv.CompletedDialogCount < 5) return;
        if (conv.LastSummaryMessageIndex >= conv.Messages.Count) return;

        // Every 3 incrementals → full re-scan
        if (conv.IncrementalChapterCount >= 3)
            await FullReSummarizeAsync(conv, s);
        else
            await PerformSummarizationAsync(conv, s);
        conv.CompletedDialogCount = 0;
    }

    async Task PerformSummarizationAsync(Conversation conv, AppSettings s)
    {
        IsSummarizing = true; LastSummaryStatus = "正在归纳...";
        try
        {
            var rawNew = conv.Messages.Skip(conv.LastSummaryMessageIndex).ToList();
            var newMsgs = FilterSummarizable(rawNew);
            if (newMsgs.Count < 2) { LastSummaryStatus = "新消息不足"; return; }

            var transcript = string.Join("\n\n", newMsgs.Select(m => $"[{m.Role}]: {m.Content}"));
            var archiveCtx = BuildArchiveContext(conv);
            var chapterCtx = conv.Chapters.Count > 0 ? "\n\n前序章节:\n" + string.Join("\n", conv.Chapters.TakeLast(3).Select(c => $"- {c.Title}: {c.Summary[..Math.Min(100, c.Summary.Length)]}")) : "";
            var userContent = $"{archiveCtx}{chapterCtx}\n\n对话片段:\n{transcript}";

            var client = new DeepSeekClient(s.ApiKey, s.BaseURL, s.FlashModel, false);
            var raw = await client.SummarizeAsync(AgentPrompt.Summarization, userContent);
            var match = Regex.Match(raw.Trim(), @"\{[\s\S]*\}");
            if (match.Success)
            {
                var json = JsonSerializer.Deserialize<JsonElement>(match.Value);
                var ch = new StoryChapter { Title = json.GetProperty("title").GetString()!, Summary = json.GetProperty("summary").GetString()!, Keywords = json.GetProperty("keywords").EnumerateArray().Select(x => x.GetString()!).ToList(), MessageIDs = newMsgs.Select(m => m.Id).ToList() };
                conv.Chapters.Add(ch); conv.LastSummaryMessageIndex = conv.Messages.Count; conv.IncrementalChapterCount++;
                MemoryStore.Add(new MemoryEntry { Content = ch.Summary, Keywords = ch.Keywords, SourceConversationID = conv.Id, SourceChapterTitle = ch.Title });
                LastSummaryStatus = $"新增章节「{ch.Title}」"; Save(); SaveArchives();
            }
        }
        catch { }
        finally { IsSummarizing = false; }
    }

    async Task FullReSummarizeAsync(Conversation conv, AppSettings s)
    {
        IsSummarizing = true; LastSummaryStatus = "全量重扫...";
        try
        {
            var summarizable = FilterSummarizable(conv.Messages);
            if (summarizable.Count < 2) { LastSummaryStatus = "消息不足"; return; }

            var archiveCtx = BuildArchiveContext(conv);
            var transcript = string.Join("\n\n", summarizable.Select(m => $"[{m.Role}]: {m.Content[..Math.Min(300, m.Content.Length)]}"));
            var userContent = $"{archiveCtx}完整对话记录:\n\n{transcript}";

            var client = new DeepSeekClient(s.ApiKey, s.BaseURL, s.FlashModel, false);
            var raw = await client.SummarizeAsync(AgentPrompt.FullSummarization, userContent);
            var match = Regex.Match(raw.Trim(), @"\[[\s\S]*\]");
            if (match.Success)
            {
                var chapters = JsonSerializer.Deserialize<List<JsonElement>>(match.Value);
                if (chapters != null && chapters.Count > 0)
                {
                    conv.Chapters = chapters.Select(j => new StoryChapter { Title = j.GetProperty("title").GetString()!, Summary = j.GetProperty("summary").GetString()!, Keywords = j.GetProperty("keywords").EnumerateArray().Select(k => k.GetString()!).ToList(), MessageIDs = summarizable.Select(m => m.Id).ToList() }).ToList();
                    conv.LastSummaryMessageIndex = conv.Messages.Count; conv.IncrementalChapterCount = 0;

                    // Upsert memories from chapters
                    foreach (var ch in conv.Chapters)
                        MemoryStore.Add(new MemoryEntry { Content = ch.Summary, Keywords = ch.Keywords, SourceConversationID = conv.Id, SourceChapterTitle = ch.Title });

                    LastSummaryStatus = $"已生成 {conv.Chapters.Count} 个章节";
                    // Generate title
                    await UpdateConversationTitleAsync(conv, s);
                }
            }
        }
        catch { }
        finally { IsSummarizing = false; }
    }

    async Task UpdateConversationTitleAsync(Conversation conv, AppSettings s)
    {
        if (conv.Chapters.Count == 0) return;
        var chapterSummaries = string.Join("\n\n", conv.Chapters.Select((ch, i) => $"第{i + 1}章「{ch.Title}」：{ch.Summary}"));
        var client = new DeepSeekClient(s.ApiKey, s.BaseURL, s.FlashModel, false);
        try
        {
            var raw = await client.SummarizeAsync("根据以下章节摘要，生成对话标题 ≤ 20 字。反映整体叙事脉络。只返回标题文本。", chapterSummaries);
            var title = raw.Trim().Replace("\"", "").Replace("'", ""); if (title.Length > 40) return;
            if (!string.IsNullOrWhiteSpace(title)) { conv.Title = title; conv.UpdatedAt = DateTime.UtcNow; Save(); }
        }
        catch { }
    }

    // ── Helpers ──

    List<ChatMessage> FilterSummarizable(List<ChatMessage> messages)
    {
        var skip = new[] { "[已取消生成]", "[Generation cancelled]", "[Request Failed]", "[Cancelled]", "[Error]" };
        return messages.Where(m => m.Role != "system" && !string.IsNullOrWhiteSpace(m.Content) && !skip.Any(p => m.Content.Trim() == p || m.Content.Trim().StartsWith("[Request Failed]"))).ToList();
    }

    string BuildArchiveContext(Conversation conv)
    {
        var parts = new List<string>();
        var recentEmotions = EmotionTimeline.Where(e => e.ConversationID == conv.Id).TakeLast(5).ToList();
        if (recentEmotions.Count > 0) parts.Add($"近期情绪轨迹: {string.Join(" → ", recentEmotions.Select(e => $"{e.Emotion}({e.Intensity:F1})"))}");

        var activePersons = PersonArchive.Where(p => p.MentionCount > 0).OrderByDescending(p => p.MentionCount).Take(5).ToList();
        if (activePersons.Count > 0) parts.Add($"关键人物: {string.Join(", ", activePersons.Select(p => $"{p.Name}({p.Role}, 提及{p.MentionCount}次)"))}");

        var activeBlindspots = Blindspots.Where(b => b.ConversationID == conv.Id).TakeLast(5).ToList();
        if (activeBlindspots.Count > 0) parts.Add($"已检测到的叙事盲点:\n{string.Join("\n", activeBlindspots.Select(b => $"- [{b.Severity}] {b.Pattern}: {b.Evidence}"))}");

        return parts.Count > 0 ? "\n\n[对话分析上下文]\n" + string.Join("\n\n", parts) + "\n" : "";
    }
}
