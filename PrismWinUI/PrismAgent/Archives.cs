using System.Text.Json;

namespace PrismAgent;

public class Archives
{
    private readonly string _dir;

    public Archives(string dataPath) { _dir = Path.Combine(dataPath, "Data"); Directory.CreateDirectory(_dir); }

    public T Load<T>(string name) where T : new()
    {
        var p = Path.Combine(_dir, name);
        try { return JsonSerializer.Deserialize<T>(File.ReadAllText(p)) ?? new T(); }
        catch { return new T(); }
    }

    public void Save<T>(string name, T data)
    {
        File.WriteAllText(Path.Combine(_dir, name), JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true }));
    }
}
