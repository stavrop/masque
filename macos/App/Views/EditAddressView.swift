import SwiftUI

/// Edit the label/note of an existing address.
struct EditAddressView: View {
    @EnvironmentObject private var state: AppState
    let address: HMEAddress
    let onClose: () -> Void

    @State private var label: String
    @State private var note: String

    init(address: HMEAddress, onClose: @escaping () -> Void) {
        self.address = address
        self.onClose = onClose
        _label = State(initialValue: address.label ?? "")
        _note = State(initialValue: address.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { onClose() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Text("Edit Address").font(.headline)
                Spacer()
            }

            Text(address.hme)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let fwd = address.forwardToEmail {
                Label("Forwards to \(fwd)", systemImage: "arrow.right")
                    .font(.caption).foregroundStyle(.secondary)
            }

            TextField("Label", text: $label)
                .textFieldStyle(.roundedBorder)
            TextField("Note", text: $note)
                .textFieldStyle(.roundedBorder)

            if let error = state.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { onClose() }
                Button {
                    Task {
                        await state.updateMetadata(address, label: label, note: note)
                        onClose()
                    }
                } label: {
                    if state.isBusy { ProgressView().controlSize(.small) }
                    else { Text("Save") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(label.isEmpty || state.isBusy)
            }
        }
        .padding(16)
    }
}
