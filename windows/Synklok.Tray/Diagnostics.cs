using System.Reflection;
using System.Runtime.InteropServices;
using Synklok.Core;

namespace Synklok.Tray;

/// Plain-text report a tester can paste into a message (matches the macOS
/// app's Copy diagnostics).
public static class Diagnostics
{
    public static string Version =>
        Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
            .Split('+')[0] ?? "?";

    public static string Report(SyncEngine engine, AppSettings settings, int logLines = 200)
    {
        var connection = engine.Connection.Kind switch
        {
            ConnectionKind.Connected => $"connected ({engine.Connection.Detail})",
            ConnectionKind.Error => $"error: {engine.Connection.Detail}",
            ConnectionKind.Connecting => "connecting",
            _ => "stopped",
        };
        var sync = engine.MadiSync switch { true => "locked", false => "no signal", null => "—" };
        string Hz(int? v) => v is int i ? $"{i} Hz" : "—";

        return string.Join(Environment.NewLine,
            $"Synklok for Windows diagnostics — {DateTime.Now:yyyy-MM-dd HH:mm:ss}",
            $"App: {Version}",
            $"Windows: {RuntimeInformation.OSDescription} ({RuntimeInformation.OSArchitecture})",
            $"Device address: {settings.EffectiveHost} ({(settings.UseCustomHost ? "custom" : "default")})",
            $"Connection: {connection}",
            $"Device rate: {Hz(engine.DeviceRate)} | MADI input: {Hz(engine.MadiRate)} | MADI sync: {sync}",
            $"Auto-sync: {(engine.IsPaused ? "paused" : "on")} | Out of sync: {(engine.RateMismatch ? "yes" : "no")}",
            $"Launch at login: {(StartupRegistration.IsEnabled ? "on" : "off")}",
            "",
            $"--- last {logLines} log lines ---",
            FileLogger.Shared.Tail(logLines));
    }
}
