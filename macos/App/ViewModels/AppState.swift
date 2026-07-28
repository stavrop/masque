import Foundation
import SwiftUI

/// Top-level UI state machine. Owns the `ICloudService` and exposes async
/// intents the views call. All mutation happens on the main actor so SwiftUI
/// stays consistent.
@MainActor
final class AppState: ObservableObject {

    enum Screen: Equatable {
        case restoring          // checking Keychain for a trusted session
        case login              // Apple ID + password form
        case twoFactor          // 6-digit code entry
        case addresses          // signed in: list + create + manage
    }

    @Published var screen: Screen = .restoring
    @Published var addresses: [HMEAddress] = []
    @Published var searchText: String = ""

    @Published var isBusy = false
    @Published var errorMessage: String?
    /// Transient confirmation, e.g. "Copied ✓".
    @Published var toast: String?

    private let service: ICloudService

    init(service: ICloudService) {
        self.service = service
    }

    var filteredAddresses: [HMEAddress] {
        addresses.filter { $0.matches(searchText) }
    }

    // MARK: Lifecycle

    func bootstrap() async {
        screen = .restoring
        do {
            if try await service.restoreSession() {
                try await loadAddresses()
                screen = .addresses
            } else {
                screen = .login
            }
        } catch {
            screen = .login
        }
    }

    // MARK: Auth

    func signIn(appleID: String, password: String) async {
        await run {
            switch try await self.service.signIn(appleID: appleID, password: password) {
            case .needsTwoFactor:
                self.screen = .twoFactor
            case .authenticated:
                try await self.loadAddresses()
                self.screen = .addresses
            }
        }
    }

    func submitCode(_ code: String) async {
        await run {
            try await self.service.submitSecurityCode(code)
            try await self.loadAddresses()
            self.screen = .addresses
        }
    }

    func signOut() async {
        await run {
            try await self.service.signOut()
            self.addresses = []
            self.searchText = ""
            self.screen = .login
        }
    }

    // MARK: Hide My Email

    func refresh() async {
        await run { try await self.loadAddresses() }
    }

    private func loadAddresses() async throws {
        addresses = try await service.listAddresses()
    }

    /// Generate a candidate address without reserving it yet.
    func generateCandidate() async -> String? {
        var result: String?
        await run { result = try await self.service.generateAddress() }
        return result
    }

    func reserve(hme: String, label: String, note: String) async -> Bool {
        var ok = false
        await run {
            let addr = try await self.service.reserveAddress(hme: hme, label: label, note: note)
            self.addresses.insert(addr, at: 0)
            self.flash("Created \(addr.hme)")
            ok = true
        }
        return ok
    }

    func toggleActive(_ address: HMEAddress) async {
        await run {
            try await self.service.setActive(!address.isActive, anonymousId: address.anonymousId)
            if let i = self.addresses.firstIndex(where: { $0.id == address.id }) {
                self.addresses[i].isActive.toggle()
            }
        }
    }

    func delete(_ address: HMEAddress) async {
        await run {
            try await self.service.deleteAddress(anonymousId: address.anonymousId)
            self.addresses.removeAll { $0.id == address.id }
            self.flash("Deleted")
        }
    }

    func updateMetadata(_ address: HMEAddress, label: String, note: String) async {
        await run {
            try await self.service.updateMetadata(anonymousId: address.anonymousId,
                                                   label: label, note: note)
            if let i = self.addresses.firstIndex(where: { $0.id == address.id }) {
                self.addresses[i].label = label.isEmpty ? nil : label
                self.addresses[i].note = note.isEmpty ? nil : note
            }
            self.flash("Saved")
        }
    }

    // MARK: Helpers

    func copy(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        flash("Copied")
    }

    func flash(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if self.toast == message { self.toast = nil }
        }
    }

    /// Runs an async intent with shared busy/error handling.
    private func run(_ work: @escaping () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await work()
        } catch let error as ICloudError {
            errorMessage = error.errorDescription
            if case .sessionExpired = error { screen = .login }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
