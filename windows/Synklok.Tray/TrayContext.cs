using System.Reflection;
using Synklok.Core;

namespace Synklok.Tray;

/// The app: a tray icon, its menu, the status window, and the sync engine.
public sealed class TrayContext : ApplicationContext
{
    private readonly AppSettings settings = AppSettings.Load();
    private readonly M1620Client client = new();
    private readonly SyncEngine engine;
    private readonly NotifyIcon tray;
    private readonly Icon iconOk, iconOff, iconWarn;
    public static Icon AppIcon { get; } = LoadIcon("synklok.ico", new Size(32, 32));

    private readonly ToolStripMenuItem statusItem = new() { Enabled = false };
    private readonly ToolStripMenuItem autoSyncItem = new("Auto-sync enabled") { CheckOnClick = false };
    private readonly ToolStripMenuItem loginItem = new("Launch at login") { CheckOnClick = false };
    private StatusWindow? statusWindow;
    private SettingsForm? settingsForm;

    public TrayContext()
    {
        // Engine events fire on whatever context awaits resume on; make that the UI thread.
        SynchronizationContext.SetSynchronizationContext(new WindowsFormsSynchronizationContext());

        var small = SystemInformation.SmallIconSize;
        iconOk = LoadIcon("tray-ok.ico", small);
        iconOff = LoadIcon("tray-off.ico", small);
        iconWarn = LoadIcon("tray-warn.ico", small);

        engine = new SyncEngine(client, () => settings.EffectiveHost);
        engine.Log += (level, msg) =>
        {
            if (level == LogLevel.Info) FileLogger.Shared.Info(msg);
            else if (level == LogLevel.Warn) FileLogger.Shared.Warn(msg);
            else FileLogger.Shared.Error(msg);
        };
        engine.StateChanged += Refresh;
        engine.RateChanged += (_, to) =>
        {
            if (settings.NotifyOnRateChange) Notify("Sample rate changed", $"M-1620 set to {Rate.Format(to)}");
        };
        engine.ConnectionLost += message =>
        {
            if (settings.NotifyOnDisconnect) Notify("M-1620 disconnected", message);
        };

        tray = new NotifyIcon { Icon = iconOff, Text = "Synklok", Visible = true, ContextMenuStrip = BuildMenu() };
        tray.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) ToggleStatusWindow(); };

        FileLogger.Shared.Info($"Synklok for Windows launched — version {Diagnostics.Version}");
        if (!settings.HasLaunchedBefore)
        {
            settings.HasLaunchedBefore = true;
            settings.Save();
            // Windows 11 tucks new tray icons into the ^ overflow; say where it went.
            Notify("Synklok is running", "Find the metronome in the system tray (click ^ by the clock). Drag it onto the taskbar to keep it visible.");
        }

        _ = engine.RunAsync();
        Refresh();
    }

    // ── Menu ──
    private ContextMenuStrip BuildMenu()
    {
        var menu = new ContextMenuStrip();
        autoSyncItem.Click += (_, _) => TogglePause();
        loginItem.Click += (_, _) => SetLaunchAtLogin(!StartupRegistration.IsEnabled);
        menu.Items.AddRange([
            statusItem,
            new ToolStripSeparator(),
            autoSyncItem,
            loginItem,
            new ToolStripSeparator(),
            new ToolStripMenuItem("Settings…", null, (_, _) => ShowSettings()),
            new ToolStripMenuItem("Copy diagnostics", null, (_, _) => CopyDiagnostics()),
            new ToolStripMenuItem("Open log folder", null, (_, _) => OpenLogFolder()),
            new ToolStripMenuItem("About Synklok", null, (_, _) => ShowAbout()),
            new ToolStripSeparator(),
            new ToolStripMenuItem("Quit Synklok", null, (_, _) => ExitThread()),
        ]);
        menu.Opening += (_, _) => Refresh();
        return menu;
    }

    // ── Actions (shared by the menu, status window and settings) ──
    public void TogglePause()
    {
        engine.IsPaused = !engine.IsPaused;
        FileLogger.Shared.Info(engine.IsPaused ? "Sync paused" : "Sync resumed");
        Refresh();
    }

    public void SetLaunchAtLogin(bool enabled)
    {
        try { StartupRegistration.SetEnabled(enabled); }
        catch (Exception ex) when (ex is UnauthorizedAccessException or System.Security.SecurityException or IOException)
        {
            FileLogger.Shared.Warn($"Couldn't change launch at login: {ex.Message}");
        }
        Refresh();
    }

    public void ShowSettings()
    {
        statusWindow?.Hide();
        if (settingsForm is { IsDisposed: false })
        {
            settingsForm.Activate();
            return;
        }
        settingsForm = new SettingsForm(this, settings);
        settingsForm.FormClosed += (_, _) => settingsForm = null;
        settingsForm.Show();
        settingsForm.Activate();
    }

    public void CopyDiagnostics()
    {
        Clipboard.SetText(Diagnostics.Report(engine, settings));
        Notify("Diagnostics copied", "Paste it into a message to send it.");
    }

    public static void OpenLogFolder()
    {
        Directory.CreateDirectory(FileLogger.Shared.LogDirectory);
        System.Diagnostics.Process.Start("explorer.exe", FileLogger.Shared.LogDirectory);
    }

    public static void ShowAbout() =>
        MessageBox.Show(
            $"Synklok for Windows {Diagnostics.Version}\n\n" +
            "Keeps your RME M-1620 Pro D's sample rate matched to its MADI input.\n\n" +
            "© 2026 John Blais. MIT License.\nhttps://synklok.app\n\n" +
            "Not affiliated with RME or Synthax.",
            "About Synklok", MessageBoxButtons.OK, MessageBoxIcon.Information);

    public void SettingsChanged() => settings.Save();

    public void Quit() => ExitThread();

    public SyncEngine Engine => engine;

    // ── Status window ──
    private void ToggleStatusWindow()
    {
        statusWindow ??= new StatusWindow(this);
        if (statusWindow.Visible) statusWindow.Hide();
        else if (DateTime.UtcNow - statusWindow.LastHidden > TimeSpan.FromMilliseconds(300)) statusWindow.ShowNearTray();
        Refresh();
    }

    // ── Refresh everything from engine state ──
    private void Refresh()
    {
        var c = engine.Connection;
        tray.Icon = engine.RateMismatch ? iconWarn : c.IsConnected ? iconOk : iconOff;

        var summary = c.IsConnected && engine.DeviceRate is int rate
            ? $"{c.Summary} · {Rate.Format(rate)}"
            : c.Summary;
        if (engine.IsPaused) summary += " · paused";
        if (engine.RateMismatch) summary += " · out of sync";
        var tip = $"Synklok — {summary}";
        tray.Text = tip.Length > 127 ? tip[..127] : tip;

        statusItem.Text = summary;
        autoSyncItem.Checked = !engine.IsPaused;
        loginItem.Checked = StartupRegistration.IsEnabled;
        statusWindow?.UpdateFrom(engine);
    }

    private void Notify(string title, string body) =>
        tray.ShowBalloonTip(5000, title, body, ToolTipIcon.None);

    private static Icon LoadIcon(string name, Size size)
    {
        var asm = Assembly.GetExecutingAssembly();
        var resource = asm.GetManifestResourceNames().First(n => n.EndsWith("." + name, StringComparison.OrdinalIgnoreCase));
        using var stream = asm.GetManifestResourceStream(resource)!;
        return new Icon(stream, size);
    }

    protected override void ExitThreadCore()
    {
        engine.Stop();
        tray.Visible = false;
        tray.Dispose();
        statusWindow?.Dispose();
        settingsForm?.Dispose();
        client.Dispose();
        FileLogger.Shared.Info("Synklok for Windows quit");
        base.ExitThreadCore();
    }
}
