import Foundation

/// Plain-text report a tester can paste into a message: versions, current
/// device state, settings, and the tail of the sync log.
@MainActor
enum Diagnostics {
    static func report(state: AppState, settings: AppSettings, logLines: Int = 200) -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"

        let connection: String
        switch state.connectionState {
        case .connected(let host): connection = "connected (\(host))"
        case .error(let msg):      connection = "error: \(msg)"
        case .connecting:          connection = "connecting"
        case .disconnected:        connection = "stopped"
        }

        let lines = [
            "Synklok diagnostics — \(Date().formatted(date: .abbreviated, time: .standard))",
            "App: \(version) (\(build))",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Mac: \(hardwareModel())",
            "Device address: \(settings.effectiveHost)\(settings.useCustomHost ? " (custom)" : " (default)")",
            "Connection: \(connection)",
            "Device rate: \(hz(state.deviceRate)) | MADI input: \(hz(state.madiRate)) | MADI sync: \(sync(state.madiSync))",
            "Auto-sync: \(state.isPaused ? "paused" : "on") | Out of sync: \(state.rateMismatch ? "yes" : "no")",
            "Old M-1620 Rate Sync detected: \(state.legacyScriptDetected ? "yes" : "no")",
            "Launch at login: \(LaunchAtLogin.shared.isEnabled ? "on" : "off")",
            "",
            "--- last \(logLines) log lines ---",
            logTail(logLines),
        ]
        return lines.joined(separator: "\n")
    }

    private static func hz(_ v: Int?) -> String { v.map { "\($0) Hz" } ?? "—" }

    private static func sync(_ v: Bool?) -> String {
        switch v {
        case true?:  return "locked"
        case false?: return "no signal"
        case nil:    return "—"
        }
    }

    private static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        #if arch(arm64)
        return "\(String(cString: buf)), Apple silicon"
        #else
        return "\(String(cString: buf)), Intel"
        #endif
    }

    private static func logTail(_ n: Int) -> String {
        guard let text = try? String(contentsOf: Logger.shared.logFileURL, encoding: .utf8) else {
            return "(no log yet)"
        }
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(n + 1)
            .joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
    }
}
