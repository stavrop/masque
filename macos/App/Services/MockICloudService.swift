import Foundation

/// In-memory fake used for UI development and previews. No network. Lets the
/// whole menu bar flow (login → 2FA → list → create → manage) be exercised
/// before the real SRP/HME networking exists.
final class MockICloudService: ICloudService {
    private var authenticated = false
    private var pendingTwoFactor = false
    private var store: [HMEAddress]

    /// Toggle to simulate an account that skips 2FA.
    var requiresTwoFactor = true

    init() {
        store = [
            HMEAddress(anonymousId: "a1", hme: "swift.otter@icloud.com",
                       forwardToEmail: "me@icloud.com", label: "Newsletter Signup",
                       note: "Tech newsletters", domain: "icloud.com",
                       createTimestamp: 1_700_000_000_000, isActive: true),
            HMEAddress(anonymousId: "a2", hme: "quiet.harbor@icloud.com",
                       forwardToEmail: "me@icloud.com", label: "Shopping",
                       note: nil, domain: "icloud.com",
                       createTimestamp: 1_710_000_000_000, isActive: true),
            HMEAddress(anonymousId: "a3", hme: "amber.field@icloud.com",
                       forwardToEmail: "me@icloud.com", label: "Old Forum",
                       note: "Deactivated after spam", domain: "icloud.com",
                       createTimestamp: 1_690_000_000_000, isActive: false),
        ]
    }

    func restoreSession() async throws -> Bool {
        // Start already signed-in when asked (handy for UI work / screenshots).
        if ProcessInfo.processInfo.environment["MASQUE_MOCK_AUTHED"] == "1" {
            authenticated = true
            return true
        }
        return false
    }

    func signIn(appleID: String, password: String) async throws -> SignInOutcome {
        try await Task.sleep(nanoseconds: 500_000_000)
        guard !password.isEmpty else { throw ICloudError.invalidCredentials }
        if requiresTwoFactor {
            pendingTwoFactor = true
            return .needsTwoFactor
        }
        authenticated = true
        return .authenticated
    }

    func twoFactorOptions() async throws -> TwoFactorOptions {
        TwoFactorOptions(hasTrustedDevices: true,
                         phones: [TwoFactorPhone(id: 1, number: "+30 ••• ••• ••12")])
    }

    func resendDeviceCode() async throws {}

    func authenticateWithSecurityKey(_ challenge: SecurityKeyChallenge) async throws {
        authenticated = true
    }

    func sendPhoneCode(phoneID: Int) async throws {}

    func submitSecurityCode(_ code: String, phoneID: Int?) async throws {
        try await Task.sleep(nanoseconds: 400_000_000)
        guard code == "123456" else { throw ICloudError.invalidSecurityCode }
        pendingTwoFactor = false
        authenticated = true
    }

    func signOut() async throws {
        authenticated = false
        pendingTwoFactor = false
    }

    private func requireAuth() throws {
        guard authenticated else { throw ICloudError.notAuthenticated }
    }

    func listAddresses() async throws -> [HMEAddress] {
        try requireAuth()
        try await Task.sleep(nanoseconds: 300_000_000)
        return store.sorted { ($0.createTimestamp ?? 0) > ($1.createTimestamp ?? 0) }
    }

    private var counter = 0
    func generateAddress() async throws -> String {
        try requireAuth()
        try await Task.sleep(nanoseconds: 300_000_000)
        let words = ["misty.pine", "brave.lark", "sunny.creek", "calm.willow", "bold.finch"]
        let pick = words[counter % words.count]
        counter += 1
        return "\(pick)@icloud.com"
    }

    func reserveAddress(hme: String, label: String, note: String) async throws -> HMEAddress {
        try requireAuth()
        try await Task.sleep(nanoseconds: 300_000_000)
        let addr = HMEAddress(anonymousId: UUID().uuidString, hme: hme,
                              forwardToEmail: "me@icloud.com",
                              label: label.isEmpty ? nil : label,
                              note: note.isEmpty ? nil : note,
                              domain: "icloud.com",
                              createTimestamp: 1_720_000_000_000, isActive: true)
        store.insert(addr, at: 0)
        return addr
    }

    func setActive(_ active: Bool, anonymousId: String) async throws {
        try requireAuth()
        guard let i = store.firstIndex(where: { $0.anonymousId == anonymousId }) else { return }
        store[i].isActive = active
    }

    func deleteAddress(anonymousId: String) async throws {
        try requireAuth()
        store.removeAll { $0.anonymousId == anonymousId }
    }

    func updateMetadata(anonymousId: String, label: String, note: String) async throws {
        try requireAuth()
        guard let i = store.firstIndex(where: { $0.anonymousId == anonymousId }) else { return }
        store[i].label = label.isEmpty ? nil : label
        store[i].note = note.isEmpty ? nil : note
    }
}
