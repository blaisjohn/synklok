import SwiftUI
import UserNotifications

@main
@MainActor
struct SynklokApp: App {
    @State private var state: AppState
    @State private var sync: SyncEngine

    init() {
        let s = AppState()
        let e = SyncEngine(state: s, settings: AppSettings.shared)
        _state = State(initialValue: s)
        _sync = State(initialValue: e)
        Logger.shared.info("Synklok launched — version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?")")
        e.start()
        _ = UpdateController.shared
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: state, sync: sync)
        } label: {
            MenuBarLabel(state: state, settings: AppSettings.shared)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(state: state, sync: sync)
        }
    }
}
