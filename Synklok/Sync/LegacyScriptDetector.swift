import Foundation

/// Detects the pre-Synklok "M-1620 Rate Sync" Python script, which also sets
/// the M-1620 sample rate and would fight Synklok if left running.
enum LegacyScriptDetector {
    /// The script installer used a LaunchAgent; the .pkg used a LaunchDaemon.
    static let startupFiles = [
        NSHomeDirectory() + "/Library/LaunchAgents/com.studio.m1620sync.plist",
        "/Library/LaunchDaemons/com.studio.m1620sync.plist",
    ]

    /// Terminal one-liner that removes both install variants.
    static let removalCommand = """
        launchctl unload ~/Library/LaunchAgents/com.studio.m1620sync.plist 2>/dev/null; \
        rm -f ~/Library/LaunchAgents/com.studio.m1620sync.plist; \
        sudo launchctl unload /Library/LaunchDaemons/com.studio.m1620sync.plist 2>/dev/null; \
        sudo rm -f /Library/LaunchDaemons/com.studio.m1620sync.plist /usr/local/bin/studio/m1620_rate_sync.py; \
        sudo rmdir /usr/local/bin/studio 2>/dev/null; \
        sudo pkgutil --forget com.studio.m1620sync >/dev/null 2>&1; \
        rm -f /tmp/m1620_rate_sync.log; echo "Old M-1620 Rate Sync removed"
        """

    /// True if the script is running now, or installed to start at login/boot.
    static func detect() -> Bool {
        isRunning() || startupFiles.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private static func isRunning() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        // Match Python running the script, not e.g. an editor that has it open.
        p.arguments = ["-i", "-f", "python.*m1620_rate_sync\\.py"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }
}
