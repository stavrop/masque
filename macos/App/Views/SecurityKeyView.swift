import SwiftUI

/// Shown when the Apple Account uses hardware security keys. There is no code
/// to wait for in this flow — Apple disables code-based 2FA once keys are
/// registered — so the only action is to touch the key.
struct SecurityKeyView: View {
    @EnvironmentObject private var state: AppState

    private var keyNames: String {
        let names = state.twoFactorOptions.securityKey?.keyNames ?? []
        return names.isEmpty ? "your security key" : names.joined(separator: " or ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Security Key Required", systemImage: "key.radiowaves.forward")
                .font(.headline)

            Text("This Apple Account signs in with \(keyNames). Plug the key in, "
                 + "then touch it when it starts blinking.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = state.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Back") { Task { await state.signOut() } }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await state.authenticateWithSecurityKey() }
                } label: {
                    if state.isBusy {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Touch your key…")
                        }
                    } else {
                        Text("Use Security Key")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(state.isBusy)
            }
        }
        .padding(16)
    }
}
