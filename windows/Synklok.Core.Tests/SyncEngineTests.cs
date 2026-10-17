using Synklok.Core;

namespace Synklok.Core.Tests;

/// Scripted stand-in for the M-1620: hands out queued statuses (or failures)
/// and records every rate it's told to set.
sealed class FakeM1620 : IM1620Client
{
    private readonly Queue<Func<DeviceStatus>> responses = new();
    public List<int> SetCalls { get; } = [];
    public List<string> HostsSeen { get; } = [];
    public bool FailSet { get; set; }
    public string Host { get; set; } = "";

    public FakeM1620 Returns(int? configured, int? madi, bool? sync = true)
    {
        responses.Enqueue(() => new DeviceStatus(configured, madi, sync));
        return this;
    }

    public FakeM1620 Fails(string message = "unreachable")
    {
        responses.Enqueue(() => throw new M1620Exception(message));
        return this;
    }

    public Task<DeviceStatus> GetStatusAsync(CancellationToken ct = default)
    {
        HostsSeen.Add(Host);
        return Task.FromResult(responses.Dequeue()());
    }

    public Task SetRateAsync(int hz, CancellationToken ct = default)
    {
        if (FailSet) throw new M1620Exception("set failed");
        SetCalls.Add(hz);
        return Task.CompletedTask;
    }
}

public class SyncEngineTests
{
    private DateTimeOffset clock = new(2026, 10, 17, 12, 0, 0, TimeSpan.Zero);
    private string host = "172.20.0.1";
    private readonly List<TimeSpan> delays = [];

    private SyncEngine Engine(FakeM1620 device) =>
        new(device, () => host,
            delay: (t, _) => { delays.Add(t); return Task.CompletedTask; },
            now: () => clock);

    [Fact]
    public async Task Connects_and_reports_status_without_setting_when_rates_match()
    {
        var device = new FakeM1620().Returns(48000, 48000);
        var engine = Engine(device);

        var wait = await engine.PollOnceAsync();

        Assert.Equal(ConnectionKind.Connected, engine.Connection.Kind);
        Assert.Equal("172.20.0.1", engine.Connection.Detail);
        Assert.Equal(48000, engine.DeviceRate);
        Assert.Equal(48000, engine.MadiRate);
        Assert.True(engine.MadiSync);
        Assert.Empty(device.SetCalls);
        Assert.Equal(SyncEngine.ConnectedInterval, wait);
    }

    [Fact]
    public async Task Sets_device_rate_to_madi_rate_on_mismatch()
    {
        var device = new FakeM1620().Returns(48000, 96000);
        var engine = Engine(device);
        (int? from, int to)? changed = null;
        engine.RateChanged += (f, t) => changed = (f, t);

        await engine.PollOnceAsync();

        Assert.Equal([96000], device.SetCalls);
        Assert.Equal((48000, 96000), changed);
        var entry = Assert.Single(engine.History);
        Assert.Equal(48000, entry.From);
        Assert.Equal(96000, entry.To);
        Assert.Contains(SyncEngine.SettleAfterSet, delays);
    }

    [Fact]
    public async Task Does_not_set_while_paused()
    {
        var device = new FakeM1620().Returns(48000, 96000);
        var engine = Engine(device);
        engine.IsPaused = true;

        await engine.PollOnceAsync();

        Assert.Empty(device.SetCalls);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(32000)]
    [InlineData(null)]
    public async Task Ignores_madi_rates_that_are_not_valid(int? madi)
    {
        var device = new FakeM1620().Returns(48000, madi);
        var engine = Engine(device);

        await engine.PollOnceAsync();

        Assert.Empty(device.SetCalls);
    }

    [Fact]
    public async Task Matches_mac_behaviour_of_syncing_even_without_madi_lock()
    {
        // The macOS app doesn't check the lock state before setting; the
        // roadmap's "ignore MADI when not locked" will change both together.
        var device = new FakeM1620().Returns(48000, 96000, sync: false);
        var engine = Engine(device);

        await engine.PollOnceAsync();

        Assert.Equal([96000], device.SetCalls);
    }

    [Fact]
    public async Task Reports_lost_connection_once_and_backs_off()
    {
        var device = new FakeM1620().Returns(48000, 48000).Fails("timed out").Fails("timed out");
        var engine = Engine(device);
        var lost = new List<string>();
        engine.ConnectionLost += lost.Add;

        await engine.PollOnceAsync();
        var wait1 = await engine.PollOnceAsync();
        var wait2 = await engine.PollOnceAsync();

        Assert.Equal(["timed out"], lost);
        Assert.Equal(ConnectionKind.Error, engine.Connection.Kind);
        Assert.Equal(SyncEngine.DisconnectedInterval, wait1);
        Assert.Equal(SyncEngine.DisconnectedInterval, wait2);
    }

    [Fact]
    public async Task Never_connected_device_does_not_raise_connection_lost()
    {
        var device = new FakeM1620().Fails();
        var engine = Engine(device);
        var lost = 0;
        engine.ConnectionLost += _ => lost++;

        await engine.PollOnceAsync();

        Assert.Equal(0, lost);
        Assert.Equal("M-1620 not found", engine.Connection.Summary);
    }

    [Fact]
    public async Task Failed_set_is_logged_and_retried_next_poll()
    {
        var device = new FakeM1620 { FailSet = true }.Returns(48000, 96000).Returns(48000, 96000);
        var engine = Engine(device);
        var warnings = new List<string>();
        engine.Log += (level, msg) => { if (level == LogLevel.Warn) warnings.Add(msg); };

        await engine.PollOnceAsync();
        device.FailSet = false;
        await engine.PollOnceAsync();

        Assert.Contains(warnings, w => w.StartsWith("Set rate failed"));
        Assert.Equal([96000], device.SetCalls);
    }

    [Fact]
    public async Task Flags_mismatch_only_after_the_grace_period()
    {
        var device = new FakeM1620 { FailSet = true }
            .Returns(48000, 96000).Returns(48000, 96000).Returns(48000, 96000).Returns(96000, 96000);
        var engine = Engine(device);

        await engine.PollOnceAsync();
        Assert.False(engine.RateMismatch);

        clock += TimeSpan.FromSeconds(2);
        await engine.PollOnceAsync();
        Assert.False(engine.RateMismatch);

        clock += TimeSpan.FromSeconds(1.5);
        await engine.PollOnceAsync();
        Assert.True(engine.RateMismatch);

        await engine.PollOnceAsync();
        Assert.False(engine.RateMismatch);
    }

    [Fact]
    public async Task Unlocked_madi_never_counts_as_a_mismatch()
    {
        var device = new FakeM1620 { FailSet = true }.Returns(48000, 96000, sync: false).Returns(48000, 96000, sync: false);
        var engine = Engine(device);

        await engine.PollOnceAsync();
        clock += TimeSpan.FromSeconds(10);
        await engine.PollOnceAsync();

        Assert.False(engine.RateMismatch);
    }

    [Fact]
    public async Task Changing_host_reconnects_to_the_new_address()
    {
        var device = new FakeM1620().Returns(48000, 48000).Returns(48000, 48000);
        var engine = Engine(device);

        await engine.PollOnceAsync();
        host = "192.168.1.50";
        await engine.PollOnceAsync();

        Assert.Equal(["172.20.0.1", "192.168.1.50"], device.HostsSeen);
        Assert.Equal("192.168.1.50", engine.Connection.Detail);
    }

    [Fact]
    public async Task History_keeps_the_ten_most_recent_changes()
    {
        var device = new FakeM1620();
        for (var i = 0; i < 12; i++) device.Returns(i % 2 == 0 ? 48000 : 96000, i % 2 == 0 ? 96000 : 48000);
        var engine = Engine(device);

        for (var i = 0; i < 12; i++) await engine.PollOnceAsync();

        Assert.Equal(10, engine.History.Count);
        Assert.Equal(48000, engine.History[0].To);
    }

    [Theory]
    [InlineData(96000, "96.0 kHz", "96k")]
    [InlineData(44100, "44.1 kHz", "44.1k")]
    [InlineData(176400, "176.4 kHz", "176.4k")]
    public void Formats_rates_like_the_mac_app(int hz, string full, string shortForm)
    {
        Assert.Equal(full, Rate.Format(hz));
        Assert.Equal(shortForm, Rate.Short(hz));
    }
}
