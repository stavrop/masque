import SwiftUI

struct AddressListView: View {
    @EnvironmentObject private var state: AppState
    @State private var panel: Panel = .list

    /// Persisted user-chosen list height; 0 means "use the screen-relative default".
    @AppStorage("masque.listHeight") private var savedListHeight: Double = 0
    @State private var dragStartHeight: Double?

    enum Panel: Equatable {
        case list
        case create
        case edit(HMEAddress)
    }

    private var screenHeight: CGFloat { NSScreen.main?.visibleFrame.height ?? 800 }
    private var minListHeight: CGFloat { 140 }
    private var maxListHeight: CGFloat { max(300, screenHeight * 0.8) }
    /// ~40% of the screen by default (≈6–8 rows on most displays).
    private var defaultListHeight: CGFloat { min(maxListHeight, max(300, screenHeight * 0.4)) }
    private var listHeight: CGFloat {
        savedListHeight > 0 ? min(maxListHeight, max(minListHeight, CGFloat(savedListHeight)))
                            : defaultListHeight
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
                .frame(height: listHeight)
            resizeHandle
            Divider()
            footer
        }
    }

    /// Draggable grip to resize the list height; the choice is persisted.
    private var resizeHandle: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 30, height: 4)
            .frame(maxWidth: .infinity)
            .frame(height: 11)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStartHeight == nil { dragStartHeight = Double(listHeight) }
                        let proposed = dragStartHeight! + Double(value.translation.height)
                        savedListHeight = min(Double(maxListHeight), max(Double(minListHeight), proposed))
                    }
                    .onEnded { _ in dragStartHeight = nil }
            )
            .help("Drag to resize")
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
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "tray").font(.title2).foregroundStyle(.secondary)
                Text(state.addresses.isEmpty ? "No addresses yet." : "No matches.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Button("About Masque") { WelcomeWindowController.shared.show() }
                Button("Star on GitHub ★") { NSWorkspace.shared.open(Links.githubStar) }
                Button("Buy Me a Coffee ☕") { NSWorkspace.shared.open(Links.buyMeACoffee) }
                Divider()
                Button("Sign Out") { Task { await state.signOut() } }
                Button("Quit Masque") { NSApplication.shared.terminate(nil) }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .fixedSize()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}
