import Foundation

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    static let defaultHost = "172.20.0.1"

    var customHost: String {
        didSet { UserDefaults.standard.set(customHost, forKey: "customHost") }
    }
    var useCustomHost: Bool {
        didSet { UserDefaults.standard.set(useCustomHost, forKey: "useCustomHost") }
    }
    var notifyOnRateChange: Bool {
        didSet { UserDefaults.standard.set(notifyOnRateChange, forKey: "notifyOnRateChange") }
    }
    var notifyOnDisconnect: Bool {
        didSet { UserDefaults.standard.set(notifyOnDisconnect, forKey: "notifyOnDisconnect") }
    }

    var effectiveHost: String {
        useCustomHost && !customHost.isEmpty ? customHost : Self.defaultHost
    }

    private init() {
        let d = UserDefaults.standard
        self.customHost = d.string(forKey: "customHost") ?? ""
        self.useCustomHost = d.bool(forKey: "useCustomHost")
        self.notifyOnRateChange = (d.object(forKey: "notifyOnRateChange") as? Bool) ?? true
        self.notifyOnDisconnect = (d.object(forKey: "notifyOnDisconnect") as? Bool) ?? true
    }
}
