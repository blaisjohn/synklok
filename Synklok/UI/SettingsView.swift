import SwiftUI

struct SettingsView: View {
    @Bindable var state: AppState
    let sync: SyncEngine

    @Bindable private var settings = AppSettings.shared
    @Bindable private var launchAtLogin = LaunchAtLogin.shared
    @State private var discovery = DeviceDiscovery()
    @State private var testResult: String?
    @State private var testing = false
    @State private var diagnosticsCopied = false
    @ObservedObject private var updates = UpdateController.shared

    var body: some View {
        TabView {
            connectionTab
                .tabItem { Label("Connection", systemImage: "network") }
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 460, height: 420)
        .padding()
    }

    // MARK: - Connection

    private var connectionTab: some View {
        Form {
            Section("Device") {
                Toggle("Use custom IP / hostname", isOn: $settings.useCustomHost)

                HStack {
                    TextField("172.20.0.1",
                              text: $settings.customHost,
                              prompt: Text("e.g. 192.168.1.42 or m1620.local"))
                        .textFieldStyle(.roundedBorder)
                        .disabled(!settings.useCustomHost)
                    Button("Test") { runTest() }
                        .disabled(testing || (!settings.useCustomHost && false))
                }

                if let testResult {
                    Text(testResult)
                        .font(.caption)
                        .foregroundStyle(testResult.hasPrefix("✓") ? .green : .red)
                }

                Text("Default is 172.20.0.1 — the M-1620's USB control address.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Discovered on network")
                    Spacer()
                    if discovery.isBrowsing {
                        ProgressView().controlSize(.small)
                    }
                }

                if discovery.discoveredHosts.isEmpty {
                    Text("Nothing found yet. Make sure the device is on the same network.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(discovery.discoveredHosts, id: \.self) { host in
                        HStack {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .foregroundStyle(.secondary)
                            Text(host).font(.system(.body, design: .monospaced))
                            Spacer()
                            Button("Use") {
                                settings.customHost = host
                                settings.useCustomHost = true
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section("Notifications") {
                Toggle("Notify on sample rate change", isOn: $settings.notifyOnRateChange)
                Toggle("Notify when device disconnects", isOn: $settings.notifyOnDisconnect)
            }

            Section("Menu bar") {
                Toggle("Show sample rate in menu bar", isOn: $settings.showRateInMenuBar)
                Text("A warning icon replaces the metronome if the M-1620 and MADI input stay out of sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates },
                    set: { updates.automaticallyChecksForUpdates = $0 }
                ))
                HStack {
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("About Synklok") { AboutPanel.show() }
                    Button("Check now") { updates.checkForUpdates() }
                        .disabled(!updates.canCheckForUpdates)
                }
            }

            Section("Startup") {
                Toggle("Launch Synklok at login",
                       isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                       ))
            }

            Section("Logs") {
                HStack {
                    Text(Logger.shared.logFileURL.path)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([Logger.shared.logFileURL])
                    }
                }
                HStack {
                    Text(diagnosticsCopied
                         ? "Copied — paste it into a message."
                         : "Having trouble? Copy a report to send.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Copy diagnostics") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            Diagnostics.report(state: state, settings: settings),
                            forType: .string)
                        diagnosticsCopied = true
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func runTest() {
        testing = true
        testResult = nil
        let host = settings.useCustomHost && !settings.customHost.isEmpty
            ? settings.customHost
            : AppSettings.defaultHost
        Task {
            let result = await sync.testConnection(host: host)
            await MainActor.run {
                testing = false
                switch result {
                case .success(let status):
                    let rate = status.configuredRate.map { "\($0) Hz" } ?? "unknown"
                    testResult = "✓ Connected. Device rate: \(rate)"
                case .failure(let err):
                    testResult = "✗ \(err.localizedDescription)"
                }
            }
        }
    }
}
