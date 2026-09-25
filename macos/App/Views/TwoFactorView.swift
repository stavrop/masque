import SwiftUI

struct TwoFactorView: View {
    @EnvironmentObject private var state: AppState
    @State private var code = ""

    private var canSubmit: Bool { code.count == 6 && !state.isBusy }

    /// Apple only reveals the code after the sign-in prompt is approved, so say so.
    private var prompt: String {
        if let id = state.pendingPhoneID,
           let phone = state.twoFactorOptions.phones.first(where: { $0.id == id }) {
            return "Enter the 6-digit code texted to \(phone.number)."
        }
        if !state.twoFactorOptions.hasTrustedDevices {
            return "This Apple ID has no trusted device that can display a code. "
                + "Have Apple text one to a trusted number below."
        }
        return "Tap Allow on the sign-in prompt on one of your devices — the "
            + "6-digit code appears only after that — then enter it here."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Two-Factor Authentication", systemImage: "lock.shield")
                .font(.headline)

            Text(prompt)
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

            VStack(alignment: .leading, spacing: 4) {
                Button("Didn’t get a code? Send a new one") {
                    Task { await state.resendDeviceCode() }
                }
                .buttonStyle(.link)
                .font(.caption)
                .disabled(state.isBusy)

                ForEach(state.twoFactorOptions.phones) { phone in
                    Button("Text a code to \(phone.number)") {
                        Task { await state.sendPhoneCode(phone) }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .disabled(state.isBusy)
                }
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
