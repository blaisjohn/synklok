import Foundation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLogin {
    static let shared = LaunchAtLogin()

    var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set { setEnabled(newValue) }
    }

    private init() {}

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                    Logger.shared.info("Launch at login enabled")
                }
            } else {
                try SMAppService.mainApp.unregister()
                Logger.shared.info("Launch at login disabled")
            }
        } catch {
            Logger.shared.error("Launch at login change failed: \(error.localizedDescription)")
        }
    }
}
