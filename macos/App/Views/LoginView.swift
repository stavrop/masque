import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var state: AppState
    @State private var appleID = ""
    @State private var password = ""

    private var canSubmit: Bool {
        !appleID.isEmpty && !password.isEmpty && !state.isBusy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sign in to iCloud", systemImage: "person.badge.key")
                .font(.headline)

            Text("Masque uses your Apple ID to manage Hide My Email addresses. Credentials are sent only to Apple and never stored.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Apple ID", text: $appleID)
                .textContentType(.username)
                .disableAutocorrection(true)
                .textFieldStyle(.roundedBorder)

            SecureField("Password", text: $password)
                .textContentType(.password)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canSubmit { submit() } }

            if let error = state.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button {
                    submit()
                } label: {
                    if state.isBusy { ProgressView().controlSize(.small) }
                    else { Text("Sign In") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }

            Divider()
            HStack {
                Button("About") { WelcomeWindowController.shared.show() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit Masque") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private func submit() {
        Task { await state.signIn(appleID: appleID, password: password) }
    }
}
