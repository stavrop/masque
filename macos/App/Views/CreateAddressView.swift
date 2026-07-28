import SwiftUI

/// Generate a candidate address, let the user relabel it, then reserve it.
struct CreateAddressView: View {
    @EnvironmentObject private var state: AppState
    let onClose: () -> Void

    @State private var candidate: String?
    @State private var label = ""
    @State private var note = ""
    @State private var generating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { onClose() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Text("New Address").font(.headline)
                Spacer()
            }

            // Candidate
            HStack(spacing: 8) {
                Text(candidate ?? "—")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(candidate == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    Task { await generate() }
                } label: {
                    if generating { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.triangle.2.circlepath") }
                }
                .buttonStyle(.borderless)
                .help("Generate a different address")
                .disabled(generating)
            }
            .padding(8)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            TextField("Label (e.g. Amazon)", text: $label)
                .textFieldStyle(.roundedBorder)
            TextField("Note (optional)", text: $note)
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
                        guard let hme = candidate else { return }
                        if await state.reserve(hme: hme, label: label, note: note) { onClose() }
                    }
                } label: {
                    if state.isBusy && !generating { ProgressView().controlSize(.small) }
                    else { Text("Create") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(candidate == nil || label.isEmpty || state.isBusy)
            }
        }
        .padding(16)
        .task { if candidate == nil { await generate() } }
    }

    private func generate() async {
        generating = true
        defer { generating = false }
        candidate = await state.generateCandidate()
    }
}
