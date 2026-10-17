using System.Runtime.InteropServices;
using Synklok.Core;

namespace Synklok.Tray;

/// Dark popover-style panel shown when the tray icon is clicked — the Windows
/// counterpart of the macOS menu bar popover. Hides when it loses focus.
public sealed class StatusWindow : Form
{
    private static readonly Color Bg = Color.FromArgb(0x18, 0x18, 0x1b);
    private static readonly Color Line = Color.FromArgb(0x2a, 0x2a, 0x2e);
    private static readonly Color Text1 = Color.FromArgb(0xf4, 0xf4, 0xf5);
    private static readonly Color Text2 = Color.FromArgb(0xa1, 0xa1, 0xaa);
    private static readonly Color Green = Color.FromArgb(0x4a, 0xde, 0x80);
    private static readonly Color Amber = Color.FromArgb(0xfb, 0xbf, 0x24);

    private readonly TrayContext app;
    private readonly Label dot = new() { Text = "●", AutoSize = true, Font = new Font("Segoe UI", 12f) };
    private readonly Label summary = new() { AutoSize = true, Font = new Font("Segoe UI Semibold", 10.5f) };
    private readonly Label hint = new() { AutoSize = true, MaximumSize = new Size(250, 0) };
    private readonly Label deviceRate = Value(), madiRate = Value(), madiSync = Value();
    private readonly Label historyTitle = new() { Text = "RECENT CHANGES", AutoSize = true, Font = new Font("Segoe UI", 7.5f) };
    private readonly Label history = new() { AutoSize = true, Font = new Font("Consolas", 9f) };
    private readonly CheckBox autoSync = Toggle("Auto-sync enabled"), launchAtLogin = Toggle("Launch at login");
    private readonly Panel historyBlock = new() { AutoSize = true, Dock = DockStyle.Top };
    private bool updating;

    public StatusWindow(TrayContext app)
    {
        this.app = app;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        BackColor = Bg;
        ForeColor = Text1;
        Font = new Font("Segoe UI", 9.5f);
        // Fixed width; height is fitted to the visible sections in FitHeight().
        Width = 300;
        Padding = new Padding(1);

        hint.ForeColor = Text2;
        historyTitle.ForeColor = Text2;

        var header = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Top, Padding = new Padding(12, 10, 12, 8), WrapContents = false };
        var headerText = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.TopDown, WrapContents = false, Margin = new Padding(6, 0, 0, 0) };
        headerText.Controls.AddRange([summary, hint]);
        header.Controls.AddRange([dot, headerText]);

        var stats = new TableLayoutPanel { AutoSize = true, Dock = DockStyle.Top, ColumnCount = 2, Padding = new Padding(12, 8, 12, 8), Width = 298 };
        stats.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        stats.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        AddRow(stats, "Device rate", deviceRate);
        AddRow(stats, "MADI input", madiRate);
        AddRow(stats, "MADI sync", madiSync);

        var historyInner = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Top, FlowDirection = FlowDirection.TopDown, Padding = new Padding(12, 8, 12, 8), WrapContents = false };
        historyInner.Controls.AddRange([historyTitle, history]);
        historyBlock.Controls.Add(historyInner);
        historyBlock.Controls.Add(Divider());

        var toggles = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Top, FlowDirection = FlowDirection.TopDown, Padding = new Padding(10, 6, 10, 6), WrapContents = false };
        toggles.Controls.AddRange([autoSync, launchAtLogin]);
        autoSync.CheckedChanged += (_, _) => { if (!updating) app.TogglePause(); };
        launchAtLogin.CheckedChanged += (_, _) => { if (!updating) app.SetLaunchAtLogin(launchAtLogin.Checked); };

        var actions = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Top, FlowDirection = FlowDirection.TopDown, Padding = new Padding(8, 4, 8, 8), WrapContents = false };
        actions.Controls.AddRange([
            Action("Settings…", Text1, app.ShowSettings),
            Action("Copy diagnostics", Text1, app.CopyDiagnostics),
            Action("Quit Synklok", Color.FromArgb(0xfc, 0xa5, 0xa5), app.Quit),
        ]);

        // Docked Top controls stack in reverse order of adding.
        Controls.AddRange([actions, Divider(), toggles, Divider(), historyBlock, stats, Divider(), header]);

        Deactivate += (_, _) => { Hide(); LastHidden = DateTime.UtcNow; };
        KeyPreview = true;
        KeyDown += (_, e) => { if (e.KeyCode == Keys.Escape) Hide(); };
    }

    /// When focus loss last hid the window. A tray click that closes the window
    /// also arrives as a click to open it; TrayContext ignores that echo.
    public DateTime LastHidden { get; private set; }

    public void ShowNearTray()
    {
        UpdateFrom(app.Engine);
        var area = Screen.FromPoint(Cursor.Position).WorkingArea;
        // Next to the cursor, kept inside the working area (works for any taskbar edge).
        var x = Math.Clamp(Cursor.Position.X - Width / 2, area.Left + 8, area.Right - Width - 8);
        var y = Math.Clamp(Cursor.Position.Y - Height - 12, area.Top + 8, area.Bottom - Height - 8);
        Location = new Point(x, y);
        Show();
        Activate();
    }

    public void UpdateFrom(SyncEngine engine)
    {
        updating = true;
        var c = engine.Connection;
        dot.ForeColor = engine.RateMismatch ? Amber : c.Kind switch
        {
            ConnectionKind.Connected => Green,
            ConnectionKind.Connecting => Amber,
            _ => Text2,
        };
        summary.Text = engine.RateMismatch ? "Out of sync" : c.Summary;
        hint.Text = engine.RateMismatch ? "The M-1620 isn't following the MADI input" : c.Hint ?? "";
        hint.Visible = hint.Text.Length > 0;

        deviceRate.Text = Rate.Format(engine.DeviceRate);
        madiRate.Text = Rate.Format(engine.MadiRate);
        madiSync.Text = engine.MadiSync switch { true => "● Locked", false => "● No signal", null => "—" };
        madiSync.ForeColor = engine.MadiSync == true ? Green : Text2;

        historyBlock.Visible = engine.History.Count > 0;
        history.Text = string.Join(Environment.NewLine, engine.History.Take(5).Select(h =>
            $"{h.Timestamp:HH:mm:ss}  {Rate.Format(h.From)} → {Rate.Format(h.To)}"));

        autoSync.Text = engine.IsPaused ? "Sync paused" : "Auto-sync enabled";
        autoSync.Checked = !engine.IsPaused;
        launchAtLogin.Checked = StartupRegistration.IsEnabled;
        updating = false;
        FitHeight();
    }

    private void FitHeight()
    {
        PerformLayout();
        Height = Controls.Cast<Control>().Where(c => c.Visible).Sum(c => c.Height) + Padding.Vertical;
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        // Windows 11 rounded corners; harmless no-op on Windows 10.
        var round = 2; // DWMWCP_ROUND
        _ = DwmSetWindowAttribute(Handle, 33 /* DWMWA_WINDOW_CORNER_PREFERENCE */, ref round, sizeof(int));
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        using var pen = new Pen(Line);
        e.Graphics.DrawRectangle(pen, 0, 0, Width - 1, Height - 1);
    }

    private static Label Value() => new() { AutoSize = true, Anchor = AnchorStyles.Right, Font = new Font("Segoe UI Semibold", 9.5f) };

    private static void AddRow(TableLayoutPanel table, string name, Label value)
    {
        table.Controls.Add(new Label { Text = name, AutoSize = true, ForeColor = Text2, Margin = new Padding(0, 3, 0, 3) });
        value.Margin = new Padding(0, 3, 0, 3);
        table.Controls.Add(value);
    }

    private static Panel Divider() => new() { Height = 1, Dock = DockStyle.Top, BackColor = Line };

    private static CheckBox Toggle(string text) => new()
    {
        Text = text, AutoSize = true, FlatStyle = FlatStyle.Flat, ForeColor = Text1, Margin = new Padding(2, 3, 2, 3),
    };

    private static Button Action(string text, Color color, Action onClick)
    {
        var b = new Button
        {
            Text = text, AutoSize = false, Width = 280, Height = 28, FlatStyle = FlatStyle.Flat,
            ForeColor = color, TextAlign = ContentAlignment.MiddleLeft, Margin = new Padding(0),
            Cursor = Cursors.Hand,
        };
        b.FlatAppearance.BorderSize = 0;
        b.FlatAppearance.MouseOverBackColor = Color.FromArgb(0x27, 0x27, 0x2a);
        b.Click += (_, _) => onClick();
        return b;
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
}
