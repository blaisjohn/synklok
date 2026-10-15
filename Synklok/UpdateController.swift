import AppKit
import Combine
import Sparkle

/// Sparkle wrapper. Feed URL and public EdDSA key live in Info.plist.
@MainActor
final class UpdateController: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    static let shared = UpdateController()

    @Published private(set) var canCheckForUpdates = false
    private var controller: SPUStandardUpdaterController!

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: self)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    // Synklok has no Dock icon, so bring it forward before Sparkle shows a
    // scheduled update; otherwise the window can open behind other apps.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                               forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
    }
}
