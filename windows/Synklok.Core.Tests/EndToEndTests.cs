using System.Net;
using System.Net.Sockets;
using Synklok.Core;
using Synklok.MockDevice;

namespace Synklok.Core.Tests;

/// The real client and engine over real HTTP against the pretend M-1620.
public class EndToEndTests
{
    private static int FreePort()
    {
        var l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        var port = ((IPEndPoint)l.LocalEndpoint).Port;
        l.Stop();
        return port;
    }

    [Fact]
    public async Task Engine_follows_a_madi_rate_change_on_the_mock_device()
    {
        using var device = new MockM1620(FreePort());
        device.Start();
        using var client = new M1620Client();
        var engine = new SyncEngine(client, () => $"localhost:{device.Port}",
                                    delay: (_, _) => Task.CompletedTask);

        await engine.PollOnceAsync();
        Assert.True(engine.Connection.IsConnected);
        Assert.Equal(48000, device.ConfiguredRate);

        device.MadiRate = 96000;
        await engine.PollOnceAsync();

        Assert.Equal(96000, device.ConfiguredRate);
        Assert.Equal(96000, engine.History[0].To);
    }

    [Fact]
    public async Task Engine_reports_an_error_when_nothing_is_listening()
    {
        using var client = new M1620Client();
        var engine = new SyncEngine(client, () => $"localhost:{FreePort()}",
                                    delay: (_, _) => Task.CompletedTask);

        var wait = await engine.PollOnceAsync();

        Assert.Equal(ConnectionKind.Error, engine.Connection.Kind);
        Assert.Equal(SyncEngine.DisconnectedInterval, wait);
    }
}
