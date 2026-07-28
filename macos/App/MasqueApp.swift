import SwiftUI

@main
struct MasqueApp: App {
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
        MenuBarExtra("Masque", systemImage: "envelope.badge.shield.half.filled") {
            MenuRootView()
                .environmentObject(state)
                .task { await state.bootstrap() }
        }
        .menuBarExtraStyle(.window)
    }
}
