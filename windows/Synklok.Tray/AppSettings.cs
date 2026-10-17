using System.Text.Json;
using Synklok.Core;

namespace Synklok.Tray;

/// User settings, saved as JSON in %APPDATA%\Synklok\settings.json.
/// Same options and defaults as the macOS app.
public sealed class AppSettings
{
    public string CustomHost { get; set; } = "";
    public bool UseCustomHost { get; set; }
    public bool NotifyOnRateChange { get; set; } = true;
    public bool NotifyOnDisconnect { get; set; } = true;
    public bool HasLaunchedBefore { get; set; }

    public string EffectiveHost =>
        UseCustomHost && !string.IsNullOrWhiteSpace(CustomHost) ? CustomHost.Trim() : M1620Client.DefaultHost;

    private static readonly string Dir =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Synklok");
    private static string FilePath => Path.Combine(Dir, "settings.json");

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath)) ?? new AppSettings();
        }
        catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException)
        {
            FileLogger.Shared.Warn($"Couldn't read settings, using defaults: {ex.Message}");
        }
        return new AppSettings();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Dir);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            FileLogger.Shared.Warn($"Couldn't save settings: {ex.Message}");
        }
    }
}
