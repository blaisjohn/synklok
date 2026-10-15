import AppKit

/// Standard About window. Synklok has no main menu, so Settings opens it.
/// Credits carry Synklok's MIT license and Sparkle's required notices.
enum AboutPanel {
    @MainActor
    static func show() {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
        if let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            // Explicit label colours so the text stays readable in dark mode.
            options[.credits] = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: options)
    }
}
