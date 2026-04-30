import Foundation
import UserNotifications

@MainActor
@Observable
final class SyncEngine {
    static let validRates: Set<Int> = [44100, 48000, 88200, 96000, 176400, 192000]

    private let state: AppState
    private let settings: AppSettings
    private let client: M1620Client
    private var task: Task<Void, Never>?
    private var lastMadiRate: Int?
    private var lastConnectedHost: String?

    private let pollInterval: Duration = .milliseconds(500)

    init(state: AppState, settings: AppSettings) {
        self.state = state
        self.settings = settings
        self.client = M1620Client(host: settings.effectiveHost)
    }

    func start() {
        guard task == nil else { return }
        Logger.shared.info("Sync starting (host: \(settings.effectiveHost))")
        task = Task { await loop() }
    }

    func stop() {
        task?.cancel()
        task = nil
        state.connectionState = .disconnected
        Logger.shared.info("Sync stopped")
    }

    func togglePause() {
        state.isPaused.toggle()
        Logger.shared.info(state.isPaused ? "Sync paused" : "Sync resumed")
    }

    /// Probe a host without affecting the running sync.
    func testConnection(host: String) async -> Result<DeviceStatus, Error> {
        let probe = M1620Client(host: host)
        do {
            let status = try await probe.getStatus()
            return .success(status)
        } catch {
            return .failure(error)
        }
    }

    private func loop() async {
        state.connectionState = .connecting
        var connected = false

        while !Task.isCancelled {
            let host = settings.effectiveHost
            await client.setHost(host)

            do {
                let status = try await client.getStatus()
                if !connected || lastConnectedHost != host {
                    state.connectionState = .connected(host: host)
                    Logger.shared.info("Connected to \(host)")
                    connected = true
                    lastConnectedHost = host
                }

                state.deviceRate = status.configuredRate
                state.madiRate   = status.madiRate
                state.madiSync   = status.madiSync

                if let madi = status.madiRate,
                   let prev = lastMadiRate,
                   madi != prev {
                    Logger.shared.info("MADI input rate changed: \(prev) → \(madi) Hz")
                }
                lastMadiRate = status.madiRate

                if !state.isPaused,
                   let configured = status.configuredRate,
                   let madi = status.madiRate,
                   Self.validRates.contains(madi),
                   configured != madi {
                    Logger.shared.info("Syncing \(configured) → \(madi) Hz")
                    do {
                        try await client.setRate(madi)
                        state.recordRateChange(from: configured, to: madi)
                        if settings.notifyOnRateChange {
                            await notify(title: "Sample rate changed",
                                         body: "M-1620 set to \(formatRate(madi))")
                        }
                        Logger.shared.info("Set rate to \(madi) Hz")
                        try? await Task.sleep(for: .seconds(2))
                    } catch {
                        Logger.shared.warn("Set rate failed: \(error.localizedDescription)")
                    }
                }
            } catch {
                if connected {
                    Logger.shared.warn("Lost connection: \(error.localizedDescription)")
                    if settings.notifyOnDisconnect {
                        await notify(title: "M-1620 disconnected",
                                     body: error.localizedDescription)
                    }
                    connected = false
                }
                state.connectionState = .error(error.localizedDescription)
            }

            try? await Task.sleep(for: pollInterval)
        }
    }

    private func formatRate(_ hz: Int) -> String {
        String(format: "%.1f kHz", Double(hz) / 1000.0)
    }

    private func notify(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(req)
    }
}
