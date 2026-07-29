import AppKit
import SwiftUI

/// Hosts the `WelcomeView` in a standalone window. Because Masque is a menu-bar
/// agent (no Dock icon), the window is created and brought to front manually.
@MainActor
final class WelcomeWindowController {
    static let shared = WelcomeWindowController()
    private var window: NSWindow?

    /// Whether the welcome window should appear at launch (default true).
    static var showsAtStartup: Bool {
        UserDefaults.standard.object(forKey: "masque.showWelcome") as? Bool ?? true
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: WelcomeView())
            let win = NSWindow(contentViewController: hosting)
            win.title = "Masque"
            win.styleMask = [.titled, .closable, .fullSizeContentView]
            win.titlebarAppearsTransparent = true
            win.isMovableByWindowBackground = true
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }
}
