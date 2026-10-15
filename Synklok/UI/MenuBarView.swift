import SwiftUI
import AppKit

struct MenuBarView: View {
    @Bindable var state: AppState
    let sync: SyncEngine

    @Bindable private var launchAtLogin = LaunchAtLogin.shared
    @Environment(\.openSettings) private var openSettings
    @State private var removalCommandCopied = false
    @ObservedObject private var updates = UpdateController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            if state.legacyScriptDetected {
                Divider()
                legacyWarning
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }

            Divider()

            stats
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            if !state.history.isEmpty {
                Divider()
                history
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }

            Divider()

            toggles
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

            Divider()

            actions
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .frame(width: 300)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(state.connectionState.indicatorColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.connectionState.summary)
                    .font(.headline)
                if let detail = state.connectionState.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
    }

    // MARK: - Old script warning

    private var legacyWarning: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Old M-1620 Rate Sync is still installed")
                    .font(.subheadline.weight(.semibold))
                Text("It changes the sample rate on its own and can fight Synklok. Paste this command into Terminal to remove it — it will ask for your Mac password.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(removalCommandCopied ? "Copied — paste into Terminal" : "Copy removal command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(LegacyScriptDetector.removalCommand, forType: .string)
                    removalCommandCopied = true
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: - Stats

    private var stats: some View {
        VStack(spacing: 8) {
            statRow(label: "Device rate",  value: formatRate(state.deviceRate))
            statRow(label: "MADI input",   value: formatRate(state.madiRate))
            HStack {
                Text("MADI sync").foregroundStyle(.secondary)
                Spacer()
                syncBadge
            }
            .font(.system(.body, design: .rounded))
        }
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.system(.body, design: .rounded))
    }

    private var syncBadge: some View {
        let locked = state.madiSync == true
        let text   = state.madiSync == nil ? "—"
                   : (locked ? "Locked" : "No signal")
        return HStack(spacing: 4) {
            Circle()
                .fill(locked ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            Text(text).fontWeight(.medium)
        }
    }

    // MARK: - History

    private var history: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent changes")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(state.history.prefix(5)) { change in
                HStack(spacing: 8) {
                    Text(change.timestamp, style: .time)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    Text("\(formatRate(change.from)) → \(formatRate(change.to))")
                        .font(.caption.monospacedDigit())
                }
            }
        }
    }

    // MARK: - Toggles

    private var toggles: some View {
        VStack(spacing: 4) {
            toggleRow(
                icon: state.isPaused ? "pause.circle" : "arrow.triangle.2.circlepath",
                title: state.isPaused ? "Sync paused" : "Auto-sync enabled",
                isOn: Binding(
                    get: { !state.isPaused },
                    set: { _ in sync.togglePause() }
                )
            )
            toggleRow(
                icon: "power.circle",
                title: "Launch at login",
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )
            )
        }
    }

    private func toggleRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .center)
            Text(title)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 0) {
            menuButton("Check for Updates…", systemImage: "arrow.down.circle") {
                updates.checkForUpdates()
            }
            .disabled(!updates.canCheckForUpdates)
            menuButton("Settings…", systemImage: "gearshape") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            menuButton("Quit Synklok", systemImage: "power", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    @ViewBuilder
    private func menuButton(_ title: String,
                            systemImage: String,
                            role: ButtonRole? = nil,
                            action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func formatRate(_ hz: Int?) -> String {
        guard let hz else { return "—" }
        return String(format: "%.1f kHz", Double(hz) / 1000.0)
    }
}
