import Foundation

/// Result of an initial sign-in attempt.
enum SignInOutcome: Equatable {
    /// Fully authenticated — an iCloud session is ready and HME calls can be made.
    case authenticated
    /// Password accepted but Apple requires a 2FA security code next.
    case needsTwoFactor
}

/// A trusted phone number Apple can text a code to.
struct TwoFactorPhone: Identifiable, Equatable {
    let id: Int
    /// Masked by Apple, e.g. "+30 ••• ••• ••12".
    let number: String
}

/// Which 2FA routes Apple says this account has, read from `GET /appleauth/auth`
/// after the 409. Lets the UI offer SMS when no trusted device can show a code.
struct TwoFactorOptions: Equatable {
    var hasTrustedDevices: Bool
    var phones: [TwoFactorPhone]
    /// Present when the account uses hardware security keys. When it is set,
    /// Apple will never send a code — this is the only way in.
    var securityKey: SecurityKeyChallenge?

    /// Assume devices exist until Apple tells us otherwise.
    static let unknown = TwoFactorOptions(hasTrustedDevices: true, phones: [],
                                          securityKey: nil)
}

/// Everything the UI needs from iCloud, behind one protocol so the SwiftUI layer
/// is independent of the wire details. `MockICloudService` implements it with
/// in-memory data for previews/UI work; `ICloudLiveService` talks to the real
/// (private) iCloud endpoints.
protocol ICloudService: AnyObject {
    /// Try to restore a previously-trusted session from the Keychain.
    /// Returns true if a usable session was restored (no login needed).
    func restoreSession() async throws -> Bool

    /// Begin sign-in with Apple ID + password (SRP). May require 2FA next.
    func signIn(appleID: String, password: String) async throws -> SignInOutcome

    /// Which 2FA routes this account offers (trusted devices and/or SMS numbers).
    func twoFactorOptions() async throws -> TwoFactorOptions

    /// Ask Apple to push a fresh code to the trusted devices.
    func resendDeviceCode() async throws

    /// Ask Apple to text a code to one of the trusted phone numbers.
    func sendPhoneCode(phoneID: Int) async throws

    /// Complete 2FA with a hardware security key. Requires a physical touch.
    func authenticateWithSecurityKey(_ challenge: SecurityKeyChallenge) async throws

    /// Submit the 6-digit 2FA code, completing login and trusting this device.
    /// `phoneID` is nil for a trusted-device code, or the number the SMS went to.
    func submitSecurityCode(_ code: String, phoneID: Int?) async throws

    /// Forget the stored session/trust token and sign out.
    func signOut() async throws

    // MARK: Hide My Email

    /// Fetch all existing Hide My Email addresses.
    func listAddresses() async throws -> [HMEAddress]

    /// Ask iCloud for a fresh candidate address (not yet reserved).
    func generateAddress() async throws -> String

    /// Reserve a previously-generated candidate, attaching a label + note.
    func reserveAddress(hme: String, label: String, note: String) async throws -> HMEAddress

    /// Activate or deactivate forwarding for an address.
    func setActive(_ active: Bool, anonymousId: String) async throws

    /// Permanently delete an (already deactivated) address.
    func deleteAddress(anonymousId: String) async throws

    /// Update the label/note metadata of an existing address.
    func updateMetadata(anonymousId: String, label: String, note: String) async throws
}

/// Errors surfaced to the UI. The live service maps HTTP/protocol failures onto these.
enum ICloudError: LocalizedError {
    case notAuthenticated
    case invalidCredentials
    case invalidSecurityCode
    case sessionExpired
    case webAccessDisabled
    case rateLimited
    case server(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:  return "Not signed in."
        case .invalidCredentials: return "Incorrect Apple ID or password."
        case .invalidSecurityCode: return "That code wasn’t accepted. Try again."
        case .sessionExpired:    return "Your session expired. Please sign in again."
        case .webAccessDisabled:
            return "“Access iCloud Data on the Web” is turned off for this Apple ID. "
                + "On an iPhone/iPad (Settings › your name › iCloud › Access iCloud Data on the Web) "
                + "or Mac (System Settings › your name › iCloud › Access iCloud Data on the Web), "
                + "turn it on, then sign in again."
        case .rateLimited:       return "Apple is rate-limiting requests. Wait a bit and retry."
        case .server(let m):     return m
        case .network(let m):    return m
        }
    }
}
