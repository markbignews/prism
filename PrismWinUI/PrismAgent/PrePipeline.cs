using System.Text.Json;

namespace PrismAgent;

public class PrePipelineResult
{
    public string GuardHint { get; set; } = "";
    public bool SafetyCrisis { get; set; }
    public List<string> SafetySignals { get; set; } = new();
    public string SafetyHint { get; set; } = "";
    public string SafetyResources { get; set; } = "";
    public List<(string Segment, string Emotion, double Intensity)> Emotions { get; set; } = new();
    public List<(string Name, string Role)> Persons { get; set; } = new();
    public List<(string Pattern, string Evidence, string CounterQuestion, string Severity)> BlindspotFindings { get; set; } = new();
}

public class PrePipeline
{
    private readonly ChatAgent _agent;
    public PrePipeline(ChatAgent agent) { _agent = agent; }

    public async Task<PrePipelineResult> RunAsync(Conversation conv, AppSettings s, CancellationToken ct = default)
    {
        var r = new PrePipelineResult();
        var recent = conv.Messages.Where(m => m.Role == "user" || m.Role == "assistant").TakeLast(10).ToList();
        if (recent.Count == 0) return r;
        if (!recent.Any(m => m.Role == "assistant" && !string.IsNullOrWhiteSpace(m.Content))) return r;

        var convText = string.Join("\n\n", recent.Select(m => $"[{m.Role}] {m.Content}"));
        var known = string.Join(", ", _agent.PersonArchive.Select(p => $"{p.Name}({p.Role})"));
        var bsHistory = string.Join("\n", _agent.Blindspots.Select(b => $"- [{b.Severity}] {b.Pattern}: {b.Evidence}"));
        var userContent = $"最近对话：\n{convText}\n\n已知人物：{(string.IsNullOrEmpty(known) ? "（无）" : known)}\n\n历史盲点：{(string.IsNullOrEmpty(bsHistory) ? "（无）" : bsHistory)}";

        try
        {
            var client = new DeepSeekClient(s.ApiKey, s.BaseURL, s.FlashModel, false);
            var raw = await client.SummarizeAsync(AgentPrompt.GuardPanel, userContent, ct);
            raw = raw.Trim();
            if (raw.StartsWith("```")) raw = raw[(raw.IndexOf('\n') + 1)..]; if (raw.EndsWith("```")) raw = raw[..^3];
            var match = System.Text.RegularExpressions.Regex.Match(raw, @"\{[\s\S]*\}");
            if (!match.Success) return r;

            var obj = JsonSerializer.Deserialize<JsonElement>(match.Value);
            if (obj.TryGetProperty("guard", out var g))
            {
                var hints = new List<string>();
                foreach (var dim in new[] { "reality", "spiral", "blindspots", "ingratiation", "action_hollow" })
                    if (g.TryGetProperty(dim, out var d) && d.TryGetProperty("flag", out var f) && f.GetString() == "warning")
                        hints.Add($"[{dim}] {(d.TryGetProperty("hint", out var h) ? h.GetString() : "")}");
                r.GuardHint = string.Join("\n", hints);

                if (g.TryGetProperty("safety", out var sf) && sf.TryGetProperty("flag", out var sflag) && sflag.GetString() == "crisis")
                {
                    r.SafetyCrisis = true;
                    r.SafetySignals = sf.TryGetProperty("signals", out var sigs) ? sigs.EnumerateArray().Select(x => x.GetString()!).ToList() : new();
                    r.SafetyHint = sf.TryGetProperty("suggest", out var sug) ? sug.GetString() ?? "" : "";
                }
                if (g.TryGetProperty("blindspots", out var bs) && bs.TryGetProperty("findings", out var finds))
                    foreach (var fnd in finds.EnumerateArray())
                        r.BlindspotFindings.Add((fnd.GetProperty("pattern").GetString()!, fnd.GetProperty("evidence").GetString()!, fnd.GetProperty("counter_question").GetString()!, fnd.TryGetProperty("severity", out var sev) ? sev.GetString()! : "new"));
            }
            if (obj.TryGetProperty("emotions", out var ems))
                foreach (var e in ems.EnumerateArray())
                    r.Emotions.Add((e.GetProperty("segment").GetString()!, e.GetProperty("emotion").GetString()!, e.GetProperty("intensity").GetDouble()));
            if (obj.TryGetProperty("persons", out var ps))
                foreach (var p in ps.EnumerateArray())
                    r.Persons.Add((p.GetProperty("name").GetString()!, p.GetProperty("role").GetString()!));
        }
        catch { /* degrade gracefully */ }
        return r;
    }

    public void ApplyResults(PrePipelineResult r, Conversation conv)
    {
        foreach (var e in r.Emotions) _agent.EmotionTimeline.Add(new EmotionEntry { ConversationID = conv.Id, Segment = e.Segment, Emotion = e.Emotion, Intensity = e.Intensity });
        if (_agent.EmotionTimeline.Count > 200) _agent.EmotionTimeline = _agent.EmotionTimeline.TakeLast(200).ToList();

        foreach (var p in r.Persons)
        {
            var existing = _agent.PersonArchive.FirstOrDefault(x => x.Name == p.Name);
            if (existing != null) { existing.LastMentionedAt = DateTime.UtcNow; existing.MentionCount++; }
            else _agent.PersonArchive.Add(new PersonRecord { Name = p.Name, Role = p.Role });
        }
        if (_agent.PersonArchive.Count > 200) _agent.PersonArchive = _agent.PersonArchive.OrderByDescending(x => x.LastMentionedAt).Take(200).ToList();

        foreach (var f in r.BlindspotFindings)
        {
            var existing = _agent.Blindspots.FirstOrDefault(b => b.Pattern == f.Pattern);
            _agent.Blindspots.Add(new BlindspotRecord { ConversationID = conv.Id, Pattern = f.Pattern, Evidence = f.Evidence, CounterQuestion = f.CounterQuestion, Severity = existing != null ? (existing.Severity == "persistent" ? "persistent" : "recurring") : f.Severity });
        }
        if (_agent.Blindspots.Count > 300) _agent.Blindspots = _agent.Blindspots.TakeLast(300).ToList();
    }

    public static string BuildSafetyResponse(PrePipelineResult r, string lang)
    {
        var signals = string.Join("\n", r.SafetySignals.Select(s => $"• {s}"));
        return lang.StartsWith("zh")
            ? $"我听到了你正在经历的事情。\n\n有些情况需要认真对待——你现在需要的是专业支持。\n\n检测到的安全信号：\n{signals}\n\n请尽快联系专业心理援助机构或前往最近的医院急诊科。\n\n你的安全是最重要的。我暂停叙事分析。"
            : $"I hear what you're going through.\n\nThis calls for professional support.\n\nSafety signals detected:\n{signals}\n\nPlease reach out to a mental health professional or go to your nearest emergency room.\n\nYour safety comes first.";
    }
}
