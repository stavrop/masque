import CryptoKit
import Foundation

/// Apple's `fsaChallenge` second factor: a WebAuthn assertion from a hardware
/// security key. Accounts with security keys registered get this *instead of*
/// six-digit codes — Apple stops offering trusted-device and SMS verification
/// entirely, so this is the only way such an account can sign in.
struct SecurityKeyChallenge: Equatable {
    /// Apple's challenge, exactly as sent (standard base64 alphabet).
    var challenge: String
    /// Credential IDs of the registered keys (standard base64).
    var keyHandles: [String]
    /// WebAuthn relying party — "apple.com".
    var rpId: String
    /// Human names Apple shows for the keys, e.g. "YubiKey Nano".
    var keyNames: [String]
}

/// The pieces Apple wants posted back to `/verify/security/key`.
struct SecurityKeyAssertion {
    var clientData: String
    var authenticatorData: String
    var signature: String
    var userHandle: String
    var credentialID: String
    /// Non-secret shape info for the debug log (byte lengths, flags).
    var diagnostics: String
}

/// Produces a WebAuthn assertion by speaking CTAP2 to an attached key.
///
/// `clientDataJSON` is built here rather than by the system, so the origin
/// matches what Apple's web sign-in widget sends. The assertion signature covers
/// it, and a wrong origin fails server-side with an opaque error.
struct SecurityKeyAuthenticator {

    /// Origin Apple's sign-in widget uses; the assertion is signed over it.
    static let origin = "https://idmsa.apple.com"

    /// authenticatorGetAssertion.
    private static let getAssertion: UInt8 = 0x02

    /// Generous: the user has to physically reach over and touch the key.
    private static let touchTimeout: TimeInterval = 60

    func assert(_ challenge: SecurityKeyChallenge) throws -> SecurityKeyAssertion {
        guard let device = CTAPHIDDevice.firstAvailable() else {
            throw CTAPHIDDevice.DeviceError.notFound
        }
        try device.open()
        defer { device.close() }

        // WebAuthn clientDataJSON. `challenge` is base64url here, per the spec,
        // even though Apple hands it to us in the standard alphabet.
        let clientDataJSON = """
        {"type":"webauthn.get","challenge":"\(Self.base64url(challenge.challenge))","origin":"\(Self.origin)"}
        """
        let clientData = Data(clientDataJSON.utf8)
        let clientDataHash = Data(SHA256.hash(data: clientData))

        // Every registered credential goes in one allowList, so the key picks the
        // one it holds and the user touches once.
        let allowList = challenge.keyHandles.compactMap { handle -> Data? in
            guard let id = Data(base64Encoded: handle) else { return nil }
            return CBOR.map([
                (CBOR.text("id"), CBOR.bytes(id)),
                (CBOR.text("type"), CBOR.text("public-key")),
            ])
        }
        guard !allowList.isEmpty else {
            throw CTAPHIDDevice.DeviceError.protocolError("no usable credential ids")
        }

        // CTAP2 canonical CBOR: unsigned map keys in ascending order.
        let request = CBOR.map([
            (CBOR.uint(1), CBOR.text(challenge.rpId)),
            (CBOR.uint(2), CBOR.bytes(clientDataHash)),
            (CBOR.uint(3), CBOR.array(allowList)),
            (CBOR.uint(5), CBOR.map([(CBOR.text("up"), CBOR.bool(true))])),
        ])

        let response = try device.cbor(Self.getAssertion, request, timeout: Self.touchTimeout)
        let decoded = try CBOR.decode(response)

        guard let authData = decoded[2]?.dataValue,
              let signature = decoded[3]?.dataValue
        else {
            throw CTAPHIDDevice.DeviceError.protocolError("assertion missing authData or signature")
        }

        // Prefer the credential the key actually used over the one we guessed.
        var credentialID = challenge.keyHandles.first ?? ""
        if case .map(let pairs)? = decoded[1] {
            for (k, v) in pairs {
                if case .text("id") = k, let id = v.dataValue {
                    credentialID = id.base64EncodedString()
                }
            }
        }
        var userHandle = ""
        if case .map(let pairs)? = decoded[4] {
            for (k, v) in pairs {
                if case .text("id") = k, let id = v.dataValue {
                    userHandle = id.base64EncodedString().replacingOccurrences(of: "=", with: "")
                }
            }
        }

        let flags = authData.count > 32 ? authData[authData.startIndex + 32] : 0
        return SecurityKeyAssertion(
            clientData: clientData.base64EncodedString(),
            authenticatorData: authData.base64EncodedString(),
            signature: signature.base64EncodedString(),
            userHandle: userHandle,
            credentialID: credentialID,
            diagnostics: "authData \(authData.count) bytes, "
                + "flags=0x\(String(flags, radix: 16)) "
                + "(UP=\(flags & 0x01 != 0), UV=\(flags & 0x04 != 0)), "
                + "sig \(signature.count) bytes, clientData \(clientData.count) bytes")
    }

    /// Standard base64 → base64url, unpadded (what clientDataJSON must carry).
    static func base64url(_ s: String) -> String {
        s.replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
