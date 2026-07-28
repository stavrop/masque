import SwiftUI

struct TwoFactorView: View {
    @EnvironmentObject private var state: AppState
    @State private var code = ""

    private var canSubmit: Bool { code.count == 6 && !state.isBusy }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Two-Factor Authentication", systemImage: "lock.shield")
                .font(.headline)

            Text("Enter the 6-digit code shown on your trusted Apple devices.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("000000", text: $code)
                .textFieldStyle(.roundedBorder)
                .font(.system(.title2, design: .monospaced))
                .multilineTextAlignment(.center)
                .onChange(of: code) { _, new in
                    // digits only, max 6
                    let filtered = String(new.filter(\.isNumber).prefix(6))
                    if filtered != new { code = filtered }
                    if filtered.count == 6 { submit() }
                }

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
                    submit()
                } label: {
                    if state.isBusy { ProgressView().controlSize(.small) }
                    else { Text("Verify") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
        }
        .padding(16)
    }

    private func submit() {
        guard canSubmit else { return }
        Task { await state.submitCode(code) }
    }
}
