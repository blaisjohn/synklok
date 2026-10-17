namespace Synklok.Tray;

static class Program
{
    [STAThread]
    static void Main()
    {
        // One Synklok per user session: a second launch just exits.
        using var single = new Mutex(initiallyOwned: true, @"Local\Synklok.Tray.SingleInstance", out var isFirst);
        if (!isFirst) return;

        ApplicationConfiguration.Initialize();
        Application.Run(new TrayContext());
    }
}
