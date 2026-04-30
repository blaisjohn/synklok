import SwiftUI
import AppKit

struct MenuBarView: View {
    @Bindable var state: AppState
    let sync: SyncEngine

    @Bindable private var launchAtLogin = LaunchAtLogin.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

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
        VStack(spacing: 0) {
            Toggle(isOn: Binding(
                get: { !state.isPaused },
                set: { _ in sync.togglePause() }
            )) {
                Label {
                    Text(state.isPaused ? "Sync paused" : "Auto-sync enabled")
                } icon: {
                    Image(systemName: state.isPaused ? "pause.circle" : "arrow.triangle.2.circlepath")
                }
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 4)
            .padding(.vertical, 4)

            Toggle(isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.setEnabled($0) }
            )) {
                Label("Launch at login", systemImage: "power.circle")
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 0) {
            menuButton("Settings…", systemImage: "gearshape") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            menuButton("Reveal log in Finder", systemImage: "doc.text.magnifyingglass") {
                NSWorkspace.shared.activateFileViewerSelecting([Logger.shared.logFileURL])
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
