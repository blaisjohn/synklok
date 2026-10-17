using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Nodes;

namespace Synklok.Core;

public sealed record DeviceStatus(int? ConfiguredRate, int? MadiRate, bool? MadiSync);

public sealed class M1620Exception(string message, Exception? inner = null) : Exception(message, inner);

public interface IM1620Client
{
    string Host { get; set; }
    Task<DeviceStatus> GetStatusAsync(CancellationToken ct = default);
    Task SetRateAsync(int hz, CancellationToken ct = default);
}

/// HTTP client for the M-1620 Pro D's control API (POST JSON to /api/v2/self).
/// Mirrors the macOS app's M1620Client: 2 s timeout, null fields request values.
public sealed class M1620Client : IM1620Client, IDisposable
{
    public const string DefaultHost = "172.20.0.1";

    private readonly HttpClient http;

    public M1620Client(string host = DefaultHost, HttpMessageHandler? handler = null)
    {
        Host = host;
        http = handler is null ? new HttpClient() : new HttpClient(handler);
        http.Timeout = TimeSpan.FromSeconds(2);
    }

    public string Host { get; set; }

    private Uri Url => new($"http://{Host}/api/v2/self");

    public async Task<DeviceStatus> GetStatusAsync(CancellationToken ct = default)
    {
        var payload = new JsonObject
        {
            ["clock"] = new JsonObject
            {
                ["sampling_rate"] = null,
                ["sources"] = new JsonObject
                {
                    ["madi_coaxial"] = new JsonObject { ["rate"] = null, ["sync"] = null },
                },
            },
        };
        var json = await PostAsync(payload, ct);
        var clock = json["clock"] as JsonObject;
        var madi = clock?["sources"]?["madi_coaxial"] as JsonObject;
        return new DeviceStatus(
            ConfiguredRate: TryInt(clock?["sampling_rate"]),
            MadiRate: TryInt(madi?["rate"]),
            MadiSync: TryBool(madi?["sync"]));
    }

    public async Task SetRateAsync(int hz, CancellationToken ct = default)
    {
        await PostAsync(new JsonObject { ["clock"] = new JsonObject { ["sampling_rate"] = hz } }, ct);
    }

    private async Task<JsonObject> PostAsync(JsonObject payload, CancellationToken ct)
    {
        using var content = new StringContent(payload.ToJsonString(), Encoding.UTF8);
        content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        HttpResponseMessage response;
        try
        {
            response = await http.PostAsync(Url, content, ct);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException && !ct.IsCancellationRequested)
        {
            throw new M1620Exception(ex is TaskCanceledException ? "The M-1620 didn't respond" : ex.Message, ex);
        }

        using (response)
        {
            if (!response.IsSuccessStatusCode)
                throw new M1620Exception("Unexpected response from device");
            var body = await response.Content.ReadAsStringAsync(ct);
            try
            {
                return JsonNode.Parse(body) as JsonObject ?? throw new M1620Exception("Unexpected response from device");
            }
            catch (System.Text.Json.JsonException ex)
            {
                throw new M1620Exception("Unexpected response from device", ex);
            }
        }
    }

    private static int? TryInt(JsonNode? node) =>
        node is JsonValue v && v.TryGetValue(out int i) ? i : null;

    private static bool? TryBool(JsonNode? node) =>
        node is JsonValue v && v.TryGetValue(out bool b) ? b : null;

    public void Dispose() => http.Dispose();
}
