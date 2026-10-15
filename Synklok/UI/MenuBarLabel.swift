import SwiftUI

/// Menu bar icon, optionally followed by the device rate (e.g. "96k").
struct MenuBarLabel: View {
    let state: AppState
    let settings: AppSettings

    var body: some View {
        // One Text with an inline image: MenuBarExtra reliably renders this,
        // unlike an HStack of Image + Text.
        if settings.showRateInMenuBar, let rate = state.deviceRate {
            Text("\(Image(systemName: symbol)) \(Self.shortRate(rate))")
                .monospacedDigit()
        } else {
            Image(systemName: symbol)
        }
    }

    /// Menu bar items are drawn monochrome, so problems swap the symbol
    /// instead of tinting it.
    private var symbol: String {
        if state.rateMismatch || state.legacyScriptDetected {
            return "exclamationmark.triangle.fill"
        }
        return state.connectionState.isConnected ? "metronome.fill" : "metronome"
    }

    static func shortRate(_ hz: Int) -> String {
        hz % 1000 == 0 ? "\(hz / 1000)k" : String(format: "%.1fk", Double(hz) / 1000)
    }
}
