using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Runtime.CompilerServices;

namespace PrismAgent;

public class DeepSeekClient
{
    private readonly HttpClient _http;
    private readonly string _model;
    private readonly bool _thinking;

    public DeepSeekClient(string apiKey, string baseUrl, string model, bool thinking)
    {
        _http = new HttpClient { BaseAddress = new Uri(baseUrl.TrimEnd('/')) };
        _http.DefaultRequestHeaders.Add("Authorization", $"Bearer {apiKey}");
        _http.Timeout = TimeSpan.FromMinutes(5);
        _model = model;
        _thinking = thinking;
    }

    public async IAsyncEnumerable<object> StreamAsync(
        IEnumerable<ChatMessage> messages,
        string systemPrompt,
        List<object> tools,
        string? supervisorHint = null,
        ConversationMode mode = ConversationMode.Balanced,
        [EnumeratorCancellation] CancellationToken ct = default)
    {
        var temp = mode switch { ConversationMode.Rational => 0.1, ConversationMode.Warm => 0.6, _ => 0.35 };
        var topP = mode switch { ConversationMode.Rational => 0.8, ConversationMode.Warm => 0.95, _ => 0.9 };

        var body = new
        {
            model = _model,
            messages = BuildMessages(messages, systemPrompt, supervisorHint),
            temperature = temp, top_p = topP, max_tokens = 8192, stream = true,
            tools = tools.Count > 0 ? tools : null,
            thinking = _thinking ? new { type = "enabled" } : new { type = "disabled" }
        };

        var request = new HttpRequestMessage(HttpMethod.Post, "/chat/completions")
        {
            Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json")
        };

        var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
        response.EnsureSuccessStatusCode();

        using var stream = await response.Content.ReadAsStreamAsync(ct);
        using var reader = new StreamReader(stream);
        var toolCallsByIndex = new Dictionary<int, ToolCall>();

        while (!reader.EndOfStream)
        {
            var line = await reader.ReadLineAsync();
            if (line == null || !line.StartsWith("data:")) continue;
            var payload = line[5..].Trim();
            if (payload == "[DONE]") break;

            try
            {
                using var doc = JsonDocument.Parse(payload);
                var delta = doc.RootElement.GetProperty("choices")[0].GetProperty("delta");
                if (delta.TryGetProperty("content", out var c)) yield return new { type = "content", token = c.GetString()! };
                if (delta.TryGetProperty("reasoning_content", out var r)) yield return new { type = "reasoning", token = r.GetString()! };
                if (delta.TryGetProperty("tool_calls", out var tcs))
                {
                    foreach (var tc in tcs.EnumerateArray())
                    {
                        var idx = tc.TryGetProperty("index", out var i) ? i.GetInt32() : 0;
                        if (!toolCallsByIndex.ContainsKey(idx)) toolCallsByIndex[idx] = new ToolCall();
                        if (tc.TryGetProperty("id", out var id)) toolCallsByIndex[idx].Id = id.GetString()!;
                        var fn = tc.GetProperty("function");
                        if (fn.TryGetProperty("name", out var n)) toolCallsByIndex[idx].Name = n.GetString()!;
                        if (fn.TryGetProperty("arguments", out var a)) toolCallsByIndex[idx].Arguments += a.GetString()!;
                    }
                }
            }
            catch { }
        }

        var allCalls = toolCallsByIndex.Values.Where(c => !string.IsNullOrEmpty(c.Name)).ToList();
        if (allCalls.Count > 0) yield return new { type = "tool_calls", calls = allCalls };
    }

    public async Task<string> SummarizeAsync(string systemPrompt, string userContent, CancellationToken ct = default)
    {
        var body = new
        {
            model = _model, messages = new[] { new { role = "system", content = systemPrompt }, new { role = "user", content = userContent } },
            temperature = 0.3, top_p = 0.9, max_tokens = 1024, stream = false, thinking = new { type = "disabled" }
        };
        var request = new HttpRequestMessage(HttpMethod.Post, "/chat/completions")
        {
            Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json")
        };
        var response = await _http.SendAsync(request, ct);
        response.EnsureSuccessStatusCode();
        var json = await response.Content.ReadAsStringAsync(ct);
        using var doc = JsonDocument.Parse(json);
        return doc.RootElement.GetProperty("choices")[0].GetProperty("message").GetProperty("content").GetString() ?? "";
    }

    private List<object> BuildMessages(IEnumerable<ChatMessage> messages, string systemPrompt, string? hint)
    {
        var list = new List<object> { new { role = "system", content = systemPrompt } };
        if (!string.IsNullOrEmpty(hint)) list.Add(new { role = "system", content = $"[监督者方向]\n{hint}" });
        foreach (var m in messages.TakeLast(500))
            list.Add(new { role = m.Role switch { ChatRole.User => "user", ChatRole.Assistant => "assistant", _ => "system" }, content = m.Content });
        return list;
    }
}
