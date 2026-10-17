using System.Reflection;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace Synklok.Tray;

/// Automatic updates through WinSparkle, the Windows counterpart of the Mac
/// app's Sparkle. Same behaviour: checks the feed once a day, shows the
/// release notes and asks before installing, and only accepts a download
/// signed with the Sparkle EdDSA key (keychain account "synklok" on John's Mac).
/// Installing runs the downloaded Synklok setup, which waits for us to quit.
public static class Updater
{
    // Public half of the Sparkle key; same value as SUPublicEDKey in the Mac app.
    private const string PublicEdKey = "Sfj2s28ByhgAnhwtChcZD7VBGHK2CSDdXfgq+Dn3YZg=";
    private const string DefaultFeedUrl = "https://synklok.app/downloads/appcast-windows.xml";
    private const string RegistryPath = @"Software\Synklok\WinSparkle";
    private const int OneDay = 24 * 60 * 60;

    // Native code keeps these function pointers, so the delegates must outlive it.
    private static Native.CanShutdown? canShutdown;
    private static Native.Callback? shutdownRequest, error, foundUpdate, noUpdate;
    private static bool started;

    /// Build number from the release script (CURRENT_PROJECT_VERSION in
    /// project.yml); the feed's sparkle:version is compared against it.
    public static string BuildNumber => Metadata("BuildNumber") ?? "0";

    /// The feed is overridable at build time (-p:SynklokUpdateFeed=…) for test builds.
    public static string FeedUrl => Metadata("UpdateFeedUrl") ?? DefaultFeedUrl;

    /// Starts daily checks. `quit` runs on the UI thread when an update is
    /// ready to install and Synklok should exit.
    public static void Start(Action quit)
    {
        var ui = SynchronizationContext.Current ?? throw new InvalidOperationException("Start on the UI thread");
        try
        {
            Native.win_sparkle_set_appcast_url(FeedUrl);
            Native.win_sparkle_set_eddsa_public_key(PublicEdKey);
            Native.win_sparkle_set_app_details("Synklok", "Synklok", Diagnostics.Version);
            Native.win_sparkle_set_app_build_version(BuildNumber);
            Native.win_sparkle_set_registry_path(RegistryPath);
            Native.win_sparkle_set_update_check_interval(OneDay);
            // Like the Mac app (SUEnableAutomaticChecks): on by default, without
            // WinSparkle's "check automatically?" prompt. Later changes in
            // Settings are kept.
            if (!AutomaticChecksConfigured) Native.win_sparkle_set_automatic_check_for_updates(1);

            canShutdown = () => 1;
            shutdownRequest = () =>
            {
                FileLogger.Shared.Info("Quitting to install an update");
                ui.Post(_ => quit(), null);
            };
            error = () => FileLogger.Shared.Warn("Update check failed (no connection, or the feed or download was invalid)");
            foundUpdate = () => FileLogger.Shared.Info("Update available");
            noUpdate = () => FileLogger.Shared.Info("No update available");
            Native.win_sparkle_set_can_shutdown_callback(canShutdown);
            Native.win_sparkle_set_shutdown_request_callback(shutdownRequest);
            Native.win_sparkle_set_error_callback(error);
            Native.win_sparkle_set_did_find_update_callback(foundUpdate);
            Native.win_sparkle_set_did_not_find_update_callback(noUpdate);

            Native.win_sparkle_init();
            started = true;
        }
        catch (Exception ex) when (ex is DllNotFoundException or EntryPointNotFoundException or BadImageFormatException)
        {
            FileLogger.Shared.Warn($"Automatic updates unavailable: {ex.Message}");
        }
    }

    public static bool IsAvailable => started;

    /// "Check for updates…": shows WinSparkle's window either way.
    public static void CheckNow()
    {
        if (started) Native.win_sparkle_check_update_with_ui();
    }

    public static bool AutomaticChecks
    {
        get => started && Native.win_sparkle_get_automatic_check_for_updates() != 0;
        set
        {
            if (!started) return;
            Native.win_sparkle_set_automatic_check_for_updates(value ? 1 : 0);
            FileLogger.Shared.Info(value ? "Automatic update checks on" : "Automatic update checks off");
        }
    }

    public static DateTimeOffset? LastCheck
    {
        get
        {
            if (!started) return null;
            var t = Native.win_sparkle_get_last_check_time();
            return t > 0 ? DateTimeOffset.FromUnixTimeSeconds(t) : null;
        }
    }

    public static void Stop()
    {
        if (started) Native.win_sparkle_cleanup();
        started = false;
    }

    private static bool AutomaticChecksConfigured
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RegistryPath);
            return key?.GetValue("CheckForUpdates") is not null;
        }
    }

    private static string? Metadata(string key) =>
        Assembly.GetExecutingAssembly().GetCustomAttributes<AssemblyMetadataAttribute>()
            .FirstOrDefault(a => a.Key == key && !string.IsNullOrEmpty(a.Value))?.Value;

    // WinSparkle's C API (winsparkle.h, 0.9.x). WinSparkle.dll ships next to Synklok.exe.
    private static class Native
    {
        private const string Dll = "WinSparkle.dll";

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate int CanShutdown();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void Callback();

        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern void win_sparkle_init();
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern void win_sparkle_cleanup();
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)] public static extern void win_sparkle_set_appcast_url(string url);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)] public static extern int win_sparkle_set_eddsa_public_key(string pubkey);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)] public static extern void win_sparkle_set_app_details(string companyName, string appName, string appVersion);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)] public static extern void win_sparkle_set_app_build_version(string build);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)] public static extern void win_sparkle_set_registry_path(string path);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern void win_sparkle_set_automatic_check_for_updates(int state);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int win_sparkle_get_automatic_check_for_updates();
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern void win_sparkle_set_update_check_interval(int interval);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern long win_sparkle_get_last_check_time();
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern void win_sparkle_set_can_shutdown_callback(CanShutdown callback);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern void win_sparkle_set_shutdown_request_callback(Callback callback);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern void win_sparkle_set_error_callback(Callback callback);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern void win_sparkle_set_did_find_update_callback(Callback callback);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern void win_sparkle_set_did_not_find_update_callback(Callback callback);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern void win_sparkle_check_update_with_ui();
    }
}
