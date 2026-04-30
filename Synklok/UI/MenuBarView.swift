import SwiftUI
import AppKit

struct MenuBarView: View {
    @Bindable var state: AppState
    let sync: SyncEngine

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            statusGrid
            Divider()
            historySection
            Divider()
            actions
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Image(systemName: state.connectionState.isConnected ? "metronome.fill" : "metronome")
                .font(.title3)
                .foregroundStyle(state.connectionState.isConnected ? .green : .secondary)
            VStack(alignment: .leading) {
                Text("Synklok").font(.headline)
                Text(state.connectionState.displayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private var statusGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("Device rate").foregroundStyle(.secondary)
                Text(formatRate(state.deviceRate)).fontWeight(.medium)
            }
            GridRow {
                Text("MADI input").foregroundStyle(.secondary)
                Text(formatRate(state.madiRate)).fontWeight(.medium)
            }
            GridRow {
                Text("MADI sync").foregroundStyle(.secondary)
                syncBadge
            }
            GridRow {
                Text("Status").foregroundStyle(.secondary)
                Text(state.isPaused ? "Paused" : "Active")
                    .foregroundStyle(state.isPaused ? .orange : .primary)
            }
        }
        .font(.system(.body, design: .rounded))
    }

    private var syncBadge: some View {
        let locked = state.madiSync == true
        return HStack(spacing: 4) {
            Circle()
                .fill(locked ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            Text(locked ? "Locked" : (state.madiSync == false ? "No sync" : "—"))
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if state.history.isEmpty {
            Text("No rate changes yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent changes").font(.caption).foregroundStyle(.secondary)
                ForEach(state.history.prefix(5)) { change in
                    HStack {
                        Text(change.timestamp, style: .time)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("\(formatRate(change.from)) → \(formatRate(change.to))")
                            .font(.caption)
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 6) {
            Button {
                sync.togglePause()
            } label: {
                Label(state.isPaused ? "Resume sync" : "Pause sync",
                      systemImage: state.isPaused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([Logger.shared.logFileURL])
            } label: {
                Label("Reveal log in Finder", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }

            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Settings…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Synklok", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    private func formatRate(_ hz: Int?) -> String {
        guard let hz else { return "—" }
        return String(format: "%.1f kHz", Double(hz) / 1000.0)
    }
}
