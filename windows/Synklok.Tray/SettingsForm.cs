using Synklok.Core;

namespace Synklok.Tray;

/// Settings window: device address, notifications, startup, logs.
/// Changes apply immediately, like the macOS app.
public sealed class SettingsForm : Form
{
    private readonly TrayContext app;
    private readonly AppSettings settings;
    private readonly CheckBox useCustom = new() { Text = "Use custom IP / hostname", AutoSize = true };
    private readonly TextBox host = new() { Width = 260, PlaceholderText = "e.g. 192.168.1.42 or M1620-012ABC.local" };
    private readonly Button test = new() { Text = "Test", AutoSize = true };
    private readonly Label testResult = new() { AutoSize = true, MaximumSize = new Size(400, 0) };
    private readonly CheckBox notifyRate = new() { Text = "Notify on sample rate change", AutoSize = true };
    private readonly CheckBox notifyDisconnect = new() { Text = "Notify when the device disconnects", AutoSize = true };
    private readonly CheckBox launchAtLogin = new() { Text = "Launch Synklok when I sign in to Windows", AutoSize = true };

    public SettingsForm(TrayContext app, AppSettings settings)
    {
        this.app = app;
        this.settings = settings;
        Text = "Synklok Settings";
        Icon = TrayContext.AppIcon;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;
        Font = new Font("Segoe UI", 9.5f);
        Padding = new Padding(12);

        useCustom.Checked = settings.UseCustomHost;
        host.Text = settings.CustomHost;
        host.Enabled = settings.UseCustomHost;
        notifyRate.Checked = settings.NotifyOnRateChange;
        notifyDisconnect.Checked = settings.NotifyOnDisconnect;
        launchAtLogin.Checked = StartupRegistration.IsEnabled;

        useCustom.CheckedChanged += (_, _) =>
        {
            settings.UseCustomHost = useCustom.Checked;
            host.Enabled = useCustom.Checked;
            app.SettingsChanged();
        };
        host.TextChanged += (_, _) => { settings.CustomHost = host.Text.Trim(); app.SettingsChanged(); };
        test.Click += async (_, _) => await RunTestAsync();
        notifyRate.CheckedChanged += (_, _) => { settings.NotifyOnRateChange = notifyRate.Checked; app.SettingsChanged(); };
        notifyDisconnect.CheckedChanged += (_, _) => { settings.NotifyOnDisconnect = notifyDisconnect.Checked; app.SettingsChanged(); };
        launchAtLogin.CheckedChanged += (_, _) => app.SetLaunchAtLogin(launchAtLogin.Checked);

        var hostRow = Row(host, test);
        var device = Group("Device",
            useCustom, hostRow, testResult,
            Note($"Default is {M1620Client.DefaultHost} — the M-1620's USB REMOTE address. " +
                 "For a network connection, use the address shown on the device's STATE → network page."));

        var notifications = Group("Notifications", notifyRate, notifyDisconnect);
        var startup = Group("Startup", launchAtLogin);

        var logPath = new TextBox { Text = FileLogger.Shared.LogFile, ReadOnly = true, Width = 300, BorderStyle = BorderStyle.FixedSingle };
        var openLogs = new Button { Text = "Open folder", AutoSize = true };
        openLogs.Click += (_, _) => TrayContext.OpenLogFolder();
        var copyDiag = new Button { Text = "Copy diagnostics", AutoSize = true };
        copyDiag.Click += (_, _) => app.CopyDiagnostics();
        var logs = Group("Logs", Row(logPath, openLogs), Row(Note("Having trouble? Copy a report to send."), copyDiag));

        var about = new LinkLabel { Text = $"Synklok for Windows {Diagnostics.Version} · About", AutoSize = true, Margin = new Padding(3, 8, 3, 0) };
        about.LinkClicked += (_, _) => TrayContext.ShowAbout();

        var layout = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.TopDown, WrapContents = false, Dock = DockStyle.Fill };
        layout.Controls.AddRange([device, notifications, startup, logs, about]);
        Controls.Add(layout);
    }

    private async Task RunTestAsync()
    {
        test.Enabled = false;
        testResult.ForeColor = SystemColors.GrayText;
        testResult.Text = "Testing…";
        var target = useCustom.Checked && !string.IsNullOrWhiteSpace(host.Text) ? host.Text.Trim() : M1620Client.DefaultHost;
        var (ok, message) = await SyncEngine.TestConnectionAsync(target);
        testResult.ForeColor = ok ? Color.SeaGreen : Color.Firebrick;
        testResult.Text = message;
        test.Enabled = true;
    }

    private static GroupBox Group(string title, params Control[] children)
    {
        var flow = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.TopDown, WrapContents = false, Dock = DockStyle.Fill, Padding = new Padding(4) };
        flow.Controls.AddRange(children);
        var box = new GroupBox { Text = title, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, Width = 440, Margin = new Padding(3, 3, 3, 9), Padding = new Padding(8) };
        box.Controls.Add(flow);
        return box;
    }

    private static FlowLayoutPanel Row(params Control[] children)
    {
        var row = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = new Padding(0) };
        row.Controls.AddRange(children);
        return row;
    }

    private static Label Note(string text) => new()
    {
        Text = text, AutoSize = true, MaximumSize = new Size(400, 0), ForeColor = SystemColors.GrayText, Margin = new Padding(3, 4, 3, 2),
    };
}
