using System.Globalization;

namespace Synklok.Tray;

/// %LOCALAPPDATA%\Synklok\Logs\sync.log with 1 MB rotation and 5 archives,
/// in the same line format as the macOS app's sync.log.
public sealed class FileLogger
{
    public static FileLogger Shared { get; } = new();

    private const long MaxBytes = 1_000_000;
    private readonly object gate = new();

    public string LogDirectory { get; } =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Synklok", "Logs");
    public string LogFile => Path.Combine(LogDirectory, "sync.log");

    public void Info(string msg) => Write("INFO", msg);
    public void Warn(string msg) => Write("WARN", msg);
    public void Error(string msg) => Write("ERROR", msg);

    private void Write(string level, string msg)
    {
        var line = $"[{DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture)}] [{level}] {msg}{Environment.NewLine}";
        lock (gate)
        {
            try
            {
                Directory.CreateDirectory(LogDirectory);
                RotateIfNeeded();
                File.AppendAllText(LogFile, line);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Logging must never take the app down.
            }
        }
    }

    private void RotateIfNeeded()
    {
        var file = new FileInfo(LogFile);
        if (!file.Exists || file.Length <= MaxBytes) return;
        string Archive(int n) => Path.Combine(LogDirectory, $"sync.log.{n}");
        File.Delete(Archive(5));
        for (var i = 4; i >= 1; i--)
            if (File.Exists(Archive(i))) File.Move(Archive(i), Archive(i + 1));
        File.Move(LogFile, Archive(1));
    }

    public string Tail(int lines)
    {
        lock (gate)
        {
            try
            {
                return File.Exists(LogFile)
                    ? string.Join(Environment.NewLine, File.ReadLines(LogFile).TakeLast(lines))
                    : "(no log yet)";
            }
            catch (IOException) { return "(log unavailable)"; }
        }
    }
}
