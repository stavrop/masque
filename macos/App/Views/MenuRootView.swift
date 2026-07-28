import SwiftUI

/// Root of the menu bar popover. Fixed width; switches on the auth screen.
struct MenuRootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            content
            if let toast = state.toast {
                Divider()
                Text(toast)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .transition(.opacity)
            }
        }
        .frame(width: 360)
        .animation(.default, value: state.toast)
        .animation(.default, value: state.screen)
    }

    @ViewBuilder private var content: some View {
        switch state.screen {
        case .restoring:
            ProgressView("Connecting…")
                .frame(maxWidth: .infinity)
                .padding(24)
        case .login:
            LoginView()
        case .twoFactor:
            TwoFactorView()
        case .addresses:
            AddressListView()
        }
    }
}
