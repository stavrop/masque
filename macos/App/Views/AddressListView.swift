import SwiftUI

struct AddressListView: View {
    @EnvironmentObject private var state: AppState
    @State private var panel: Panel = .list

    enum Panel: Equatable {
        case list
        case create
        case edit(HMEAddress)
    }

    var body: some View {
        switch panel {
        case .list:
            listPanel
        case .create:
            CreateAddressView(onClose: { panel = .list })
        case .edit(let address):
            EditAddressView(address: address, onClose: { panel = .list })
        }
    }

    private var listPanel: some View {
        VStack(spacing: 0) {
            header
            searchField
            Divider()
            listBody
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack {
            Text("Hide My Email").font(.headline)
            Spacer()
            Button {
                Task { await state.refresh() }
            } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Refresh")
                .disabled(state.isBusy)
            Button {
                panel = .create
            } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .help("New address")
        }
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search label, note, or address", text: $state.searchText)
                .textFieldStyle(.plain)
            if !state.searchText.isEmpty {
                Button { state.searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    @ViewBuilder private var listBody: some View {
        let items = state.filteredAddresses
        if state.isBusy && items.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(24)
        } else if items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "tray").font(.title2).foregroundStyle(.secondary)
                Text(state.addresses.isEmpty ? "No addresses yet." : "No matches.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(24)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { address in
                        AddressRowView(
                            address: address,
                            onCopy: { state.copy(address.hme) },
                            onToggle: { Task { await state.toggleActive(address) } },
                            onEdit: { panel = .edit(address) },
                            onDelete: { Task { await state.delete(address) } }
                        )
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 320)
        }
    }

    private var footer: some View {
        HStack {
            if let error = state.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
            } else {
                Text("\(state.addresses.count) address\(state.addresses.count == 1 ? "" : "es")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Sign Out") { Task { await state.signOut() } }
                Button("Quit Masque") { NSApplication.shared.terminate(nil) }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .fixedSize()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}
