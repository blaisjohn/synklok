using Synklok.MockDevice;

// Pretend M-1620 for testing Synklok without hardware.
// In Synklok's settings, use the custom address  localhost:8620
var port = args.Length > 0 && int.TryParse(args[0], out var p) ? p : 8620;
using var device = new MockM1620(port);
device.RateSet += hz => Console.WriteLine($"  ← Synklok set the device rate to {hz} Hz");
device.Start();

var keys = new Dictionary<char, int>
{
    ['1'] = 44100, ['2'] = 48000, ['3'] = 88200, ['4'] = 96000, ['5'] = 176400, ['6'] = 192000,
};

Console.WriteLine($"Pretend M-1620 running at localhost:{port}");
Console.WriteLine("Point Synklok at it: Settings → Use custom IP / hostname → localhost:" + port);
Console.WriteLine();
Console.WriteLine("Change the MADI input rate:  1=44.1  2=48  3=88.2  4=96  5=176.4  6=192");
Console.WriteLine("U = toggle MADI lock   S = show status   Q = quit");
Console.WriteLine();
Status();

while (true)
{
    var key = char.ToUpperInvariant(Console.ReadKey(intercept: true).KeyChar);
    if (key == 'Q') break;
    if (keys.TryGetValue(key, out var rate))
    {
        device.MadiRate = rate;
        Console.WriteLine($"→ MADI input now {rate} Hz");
    }
    else if (key == 'U')
    {
        device.MadiSync = !device.MadiSync;
        Console.WriteLine($"→ MADI {(device.MadiSync ? "locked" : "no signal")}");
    }
    else if (key == 'S')
    {
        Status();
    }
}

void Status() =>
    Console.WriteLine($"  device {device.ConfiguredRate} Hz | MADI in {device.MadiRate} Hz | " +
                      $"{(device.MadiSync ? "locked" : "no signal")} | requests so far: {device.RequestCount}");
