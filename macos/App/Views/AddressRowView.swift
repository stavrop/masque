import SwiftUI

struct AddressRowView: View {
    let address: HMEAddress
    let onCopy: () -> Void
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    @State private var confirmingDelete = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(address.isActive ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(address.label ?? "Untitled")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(address.hme)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
                if let note = address.note, !note.isEmpty {
                    Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)

            if hovering {
                HStack(spacing: 2) {
                    iconButton("doc.on.doc", "Copy address", onCopy)
                    iconButton("square.and.pencil", "Edit", onEdit)
                    iconButton(address.isActive ? "pause.circle" : "play.circle",
                               address.isActive ? "Deactivate" : "Reactivate", onToggle)
                    iconButton("trash", "Delete") { confirmingDelete = true }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(hovering ? Color.primary.opacity(0.05) : .clear)
        .onHover { hovering = $0 }
        .confirmationDialog("Delete \(address.hme)?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the address. Mail sent to it will no longer be delivered.")
        }
    }

    private func iconButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11))
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
