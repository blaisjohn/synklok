import Foundation

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(host: String)
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var displayText: String {
        switch self {
        case .disconnected:        return "Disconnected"
        case .connecting:          return "Connecting…"
        case .connected(let host): return "Connected (\(host))"
        case .error(let msg):      return "Error: \(msg)"
        }
    }
}

struct RateChange: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let from: Int?
    let to: Int
}

@MainActor
@Observable
final class AppState {
    var connectionState: ConnectionState = .disconnected
    var deviceRate: Int?
    var madiRate: Int?
    var madiSync: Bool?
    var history: [RateChange] = []
    var isPaused: Bool = false

    func recordRateChange(from: Int?, to: Int) {
        let change = RateChange(timestamp: Date(), from: from, to: to)
        history.insert(change, at: 0)
        if history.count > 10 { history.removeLast() }
    }
}
