using System.Net;
using System.Text;
using System.Text.Json.Nodes;

namespace Synklok.MockDevice;

/// A pretend M-1620 Pro D: answers POST /api/v2/self the way the real device's
/// control API does for the fields Synklok uses. Null fields in a request are
/// queries; values are writes (only clock.sampling_rate is writable here).
public sealed class MockM1620 : IDisposable
{
    private readonly HttpListener listener = new();
    private readonly object gate = new();
    private CancellationTokenSource? cts;

    public MockM1620(int port)
    {
        Port = port;
        listener.Prefixes.Add($"http://localhost:{port}/");
    }

    public int Port { get; }
    public int ConfiguredRate { get { lock (gate) return configured; } set { lock (gate) configured = value; } }
    public int MadiRate { get { lock (gate) return madi; } set { lock (gate) madi = value; } }
    public bool MadiSync { get { lock (gate) return sync; } set { lock (gate) sync = value; } }
    public int RequestCount { get { lock (gate) return requests; } }
    public event Action<int>? RateSet;

    private int configured = 48000, madi = 48000, requests;
    private bool sync = true;

    public void Start()
    {
        listener.Start();
        cts = new CancellationTokenSource();
        _ = Task.Run(() => LoopAsync(cts.Token));
    }

    private async Task LoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            HttpListenerContext ctx;
            try { ctx = await listener.GetContextAsync(); }
            catch (Exception) when (ct.IsCancellationRequested || !listener.IsListening) { return; }
            _ = Task.Run(() => Handle(ctx));
        }
    }

    private void Handle(HttpListenerContext ctx)
    {
        using var response = ctx.Response;
        if (ctx.Request.HttpMethod != "POST" || ctx.Request.Url?.AbsolutePath != "/api/v2/self")
        {
            response.StatusCode = 404;
            return;
        }

        JsonObject? request;
        using (var reader = new StreamReader(ctx.Request.InputStream, Encoding.UTF8))
        {
            try { request = JsonNode.Parse(reader.ReadToEnd()) as JsonObject; }
            catch (System.Text.Json.JsonException) { request = null; }
        }
        if (request?["clock"] is not JsonObject clock)
        {
            response.StatusCode = 400;
            return;
        }

        int? setTo = null;
        lock (gate)
        {
            requests++;
            if (clock.TryGetPropertyValue("sampling_rate", out var rate) && rate is JsonValue v && v.TryGetValue(out int hz))
            {
                configured = hz;
                setTo = hz;
            }
        }
        if (setTo is int set) RateSet?.Invoke(set);

        var reply = new JsonObject
        {
            ["clock"] = new JsonObject
            {
                ["sampling_rate"] = ConfiguredRate,
                ["sources"] = new JsonObject
                {
                    ["madi_coaxial"] = new JsonObject { ["rate"] = MadiRate, ["sync"] = MadiSync },
                },
            },
        };
        var bytes = Encoding.UTF8.GetBytes(reply.ToJsonString());
        response.ContentType = "application/json";
        response.ContentLength64 = bytes.Length;
        response.OutputStream.Write(bytes);
    }

    public void Dispose()
    {
        cts?.Cancel();
        if (listener.IsListening) listener.Stop();
        listener.Close();
    }
}
