import Foundation
import SwiftUI

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(host: String)
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    /// Short, user-friendly summary suitable for the popover header.
    var summary: String {
        switch self {
        case .disconnected: return "Stopped"
        case .connecting:   return "Looking for M-1620…"
        case .connected:    return "Connected"
        case .error:        return "M-1620 not found"
        }
    }

    /// Optional second line — host on connect, raw error on failure.
    var detail: String? {
        switch self {
        case .disconnected, .connecting:
            return nil
        case .connected(let host):
            return host
        case .error:
            return "Check that the USB REMOTE cable is plugged in"
        }
    }

    /// Color of the status dot.
    var indicatorColor: Color {
        switch self {
        case .connected:    return .green
        case .connecting:   return .yellow
        case .error:        return .secondary
        case .disconnected: return .secondary
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
    /// The old M-1620 Rate Sync script is running or set to start at boot.
    var legacyScriptDetected: Bool = false

    func recordRateChange(from: Int?, to: Int) {
        let change = RateChange(timestamp: Date(), from: from, to: to)
        history.insert(change, at: 0)
        if history.count > 10 { history.removeLast() }
    }
}
