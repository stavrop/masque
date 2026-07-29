import SwiftUI
import AppKit

/// Shows the welcome window at launch (menu-bar agents have no window to attach a
/// SwiftUI `.task` to before the popover opens, so this is driven from the delegate).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if WelcomeWindowController.showsAtStartup {
            WelcomeWindowController.shared.show()
        }
    }
}

@main
struct MasqueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state: AppState

    init() {
        // Live iCloud by default. Launch with `-mock` (or MASQUE_MOCK=1) to run
        // against in-memory fake data with no network — useful for UI work.
        let useMock = CommandLine.arguments.contains("-mock")
            || ProcessInfo.processInfo.environment["MASQUE_MOCK"] == "1"
        let service: ICloudService = useMock ? MockICloudService() : ICloudLiveService()
        _state = StateObject(wrappedValue: AppState(service: service))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuRootView()
                .environmentObject(state)
                .task { await state.bootstrap() }
        } label: {
            // Custom label lets us size the glyph up a touch vs the default.
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 16, weight: .regular))
        }
        .menuBarExtraStyle(.window)
    }
}
