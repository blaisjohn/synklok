using System.Globalization;

namespace Synklok.Core;

public static class Rate
{
    /// "96.0 kHz", or "—" when unknown.
    public static string Format(int? hz) =>
        hz is int v ? (v / 1000.0).ToString("0.0", CultureInfo.InvariantCulture) + " kHz" : "—";

    /// "96k" / "44.1k" for the tray tooltip.
    public static string Short(int hz) =>
        hz % 1000 == 0
            ? $"{hz / 1000}k"
            : (hz / 1000.0).ToString("0.0", CultureInfo.InvariantCulture) + "k";
}
