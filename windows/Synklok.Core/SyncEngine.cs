namespace Synklok.Core;

public enum ConnectionKind { Stopped, Connecting, Connected, Error }

public sealed record ConnectionState(ConnectionKind Kind, string? Detail = null)
{
    public bool IsConnected => Kind == ConnectionKind.Connected;

    /// Short summary for the status header (same wording as the macOS app).
    public string Summary => Kind switch
    {
        ConnectionKind.Stopped => "Stopped",
        ConnectionKind.Connecting => "Looking for M-1620…",
        ConnectionKind.Connected => "Connected",
        _ => "M-1620 not found",
    };

    /// Second line: host when connected, a hint when it can't be reached.
    public string? Hint => Kind switch
    {
        ConnectionKind.Connected => Detail,
        ConnectionKind.Error => "Check that the USB REMOTE cable is plugged in",
        _ => null,
    };
}

public sealed record RateChange(DateTimeOffset Timestamp, int? From, int To);

public enum LogLevel { Info, Warn, Error }

/// Polls the M-1620 and sets its sample rate to match the MADI input.
/// A line-for-line port of the macOS SyncEngine so both apps behave the same.
public sealed class SyncEngine
{
    public static readonly IReadOnlySet<int> ValidRates = new HashSet<int> { 44100, 48000, 88200, 96000, 176400, 192000 };

    public static readonly TimeSpan ConnectedInterval = TimeSpan.FromMilliseconds(500);
    public static readonly TimeSpan DisconnectedInterval = TimeSpan.FromSeconds(3);
    public static readonly TimeSpan SettleAfterSet = TimeSpan.FromSeconds(2);
    /// Normal switches resolve in about a second; only flag a mismatch that outlasts this.
    public static readonly TimeSpan MismatchGrace = TimeSpan.FromSeconds(3);

    private readonly IM1620Client client;
    private readonly Func<string> hostProvider;
    private readonly Func<TimeSpan, CancellationToken, Task> delay;
    private readonly Func<DateTimeOffset> now;

    private bool connected;
    private string? lastConnectedHost;
    private int? lastMadiRate;
    private DateTimeOffset? mismatchSince;
    private readonly List<RateChange> history = [];
    private CancellationTokenSource? loopCts;

    public SyncEngine(IM1620Client client, Func<string> hostProvider,
                      Func<TimeSpan, CancellationToken, Task>? delay = null,
                      Func<DateTimeOffset>? now = null)
    {
        this.client = client;
        this.hostProvider = hostProvider;
        this.delay = delay ?? Task.Delay;
        this.now = now ?? (() => DateTimeOffset.Now);
    }

    // ── State, read by the UI ──
    public ConnectionState Connection { get; private set; } = new(ConnectionKind.Stopped);
    public int? DeviceRate { get; private set; }
    public int? MadiRate { get; private set; }
    public bool? MadiSync { get; private set; }
    public bool IsPaused { get; set; }
    /// Device rate has disagreed with a locked MADI input for longer than MismatchGrace.
    public bool RateMismatch { get; private set; }
    public IReadOnlyList<RateChange> History => history;

    // ── Events ──
    public event Action? StateChanged;
    public event Action<int?, int>? RateChanged;
    public event Action<string>? ConnectionLost;
    public event Action<LogLevel, string>? Log;

    public bool IsRunning => loopCts is not null;

    /// Runs the poll loop until Stop(). Await it from the UI thread so events
    /// arrive on that thread.
    public async Task RunAsync()
    {
        if (loopCts is not null) return;
        loopCts = new CancellationTokenSource();
        var ct = loopCts.Token;
        Log?.Invoke(LogLevel.Info, $"Sync starting (host: {hostProvider()})");
        Connection = new(ConnectionKind.Connecting);
        StateChanged?.Invoke();
        try
        {
            while (!ct.IsCancellationRequested)
            {
                var wait = await PollOnceAsync(ct);
                await delay(wait, ct);
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested) { }
    }

    public void Stop()
    {
        loopCts?.Cancel();
        loopCts = null;
        connected = false;
        Connection = new(ConnectionKind.Stopped);
        UpdateMismatch(null);
        Log?.Invoke(LogLevel.Info, "Sync stopped");
        StateChanged?.Invoke();
    }

    /// One iteration of the loop. Returns how long to wait before the next poll.
    public async Task<TimeSpan> PollOnceAsync(CancellationToken ct = default)
    {
        var host = hostProvider();
        client.Host = host;

        try
        {
            var status = await client.GetStatusAsync(ct);
            if (!connected || lastConnectedHost != host)
            {
                Connection = new(ConnectionKind.Connected, host);
                Log?.Invoke(LogLevel.Info, $"Connected to {host}");
                connected = true;
                lastConnectedHost = host;
            }

            DeviceRate = status.ConfiguredRate;
            MadiRate = status.MadiRate;
            MadiSync = status.MadiSync;

            if (status.MadiRate is int madiNow && lastMadiRate is int prev && madiNow != prev)
                Log?.Invoke(LogLevel.Info, $"MADI input rate changed: {prev} → {madiNow} Hz");
            lastMadiRate = status.MadiRate;
            UpdateMismatch(status);

            if (!IsPaused
                && status.ConfiguredRate is int configured
                && status.MadiRate is int madi
                && ValidRates.Contains(madi)
                && configured != madi)
            {
                Log?.Invoke(LogLevel.Info, $"Syncing {configured} → {madi} Hz");
                try
                {
                    await client.SetRateAsync(madi, ct);
                    Record(configured, madi);
                    RateChanged?.Invoke(configured, madi);
                    Log?.Invoke(LogLevel.Info, $"Set rate to {madi} Hz");
                    StateChanged?.Invoke();
                    await delay(SettleAfterSet, ct);
                }
                catch (M1620Exception ex)
                {
                    Log?.Invoke(LogLevel.Warn, $"Set rate failed: {ex.Message}");
                }
            }
        }
        catch (M1620Exception ex)
        {
            if (connected)
            {
                Log?.Invoke(LogLevel.Warn, $"Lost connection: {ex.Message}");
                ConnectionLost?.Invoke(ex.Message);
                connected = false;
            }
            Connection = new(ConnectionKind.Error, ex.Message);
            UpdateMismatch(null);
        }

        StateChanged?.Invoke();
        return connected ? ConnectedInterval : DisconnectedInterval;
    }

    /// Probe a host without affecting the running sync (Settings → Test).
    public static async Task<(bool Ok, string Message)> TestConnectionAsync(string host)
    {
        using var probe = new M1620Client(host);
        try
        {
            var status = await probe.GetStatusAsync();
            var rate = status.ConfiguredRate is int r ? $"{r} Hz" : "unknown";
            return (true, $"✓ Connected. Device rate: {rate}");
        }
        catch (M1620Exception ex)
        {
            return (false, $"✗ {ex.Message}");
        }
    }

    private void Record(int? from, int to)
    {
        history.Insert(0, new RateChange(now(), from, to));
        if (history.Count > 10) history.RemoveAt(history.Count - 1);
    }

    private void UpdateMismatch(DeviceStatus? status)
    {
        if (status is not { MadiSync: true, ConfiguredRate: int configured, MadiRate: int madi }
            || !ValidRates.Contains(madi) || configured == madi)
        {
            mismatchSince = null;
            RateMismatch = false;
            return;
        }
        mismatchSince ??= now();
        RateMismatch = now() - mismatchSince.Value >= MismatchGrace;
    }
}
