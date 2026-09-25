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

enum SecurityKeyError: LocalizedError {
    case toolMissing
    case noKeyAttached
    case noMatchingCredential
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .toolMissing:
            return "libfido2 isn’t installed. Run “brew install libfido2”, then try again."
        case .noKeyAttached:
            return "No security key detected. Plug in your YubiKey and try again."
        case .noMatchingCredential:
            return "That security key isn’t one of the keys registered with this "
                + "Apple Account. Try your other key."
        case .failed(let m):
            return "Security key failed: \(m)"
        }
    }
}

/// Drives libfido2's `fido2-assert` to get a WebAuthn assertion from an attached
/// key. We build `clientDataJSON` ourselves so the origin matches what Apple's
/// web client sends — the signature covers it, so a wrong origin fails server-side
/// with no useful error.
struct SecurityKeyAuthenticator {

    /// Origin Apple's sign-in widget uses; the assertion is signed over it.
    static let origin = "https://idmsa.apple.com"

    private let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]

    private func tool(_ name: String) -> String? {
        searchPaths.map { $0 + "/" + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// First attached FIDO2 token, as a libfido2 device path.
    func attachedKey() throws -> String {
        guard let list = tool("fido2-token") else { throw SecurityKeyError.toolMissing }
        let out = try run(list, args: ["-L"], stdin: nil).stdout
        // Lines look like: "ioreg://4294971203: vendor=0x1050, product=0x0406 (…)"
        guard let first = out.split(separator: "\n").first,
              let path = first.split(separator: ":").first.map(String.init),
              !path.isEmpty
        else { throw SecurityKeyError.noKeyAttached }
        // Re-join the scheme separator that split() removed.
        let full = String(first).components(separatedBy: ": ").first ?? path
        return full
    }

    /// Ask the attached key to sign Apple's challenge. Requires a physical touch.
    func assert(_ challenge: SecurityKeyChallenge) throws -> SecurityKeyAssertion {
        guard let assertTool = tool("fido2-assert") else { throw SecurityKeyError.toolMissing }
        let device = try attachedKey()

        // WebAuthn clientDataJSON. `challenge` here is base64url, per the spec,
        // even though Apple hands it to us in the standard alphabet.
        let clientDataJSON = """
        {"type":"webauthn.get","challenge":"\(Self.base64url(challenge.challenge))","origin":"\(Self.origin)"}
        """
        let clientData = Data(clientDataJSON.utf8)
        let hash = Data(SHA256.hash(data: clientData)).base64EncodedString()

        // Only one key is plugged in and the account has several registered, so
        // try each credential until one is accepted.
        var lastError = "no credentials tried"
        for handle in challenge.keyHandles {
            let input = "\(hash)\n\(challenge.rpId)\n\(handle)\n"
            let result = try run(assertTool, args: ["-G", "-p", device], stdin: input)
            guard result.status == 0 else {
                lastError = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            // Output: hash, rpId, authenticatorData, signature, [userId]
            let lines = result.stdout.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            guard lines.count >= 4, let rawAuth = Data(base64Encoded: lines[2]) else {
                lastError = "unexpected fido2-assert output"
                continue
            }
            // libfido2 hands back the authenticator data CBOR-wrapped; WebAuthn
            // (and Apple) want the raw bytes, and since the key signed the raw
            // bytes, leaving the header on fails verification server-side.
            let authData = Self.unwrapCBORByteString(rawAuth)
            let flags = authData.count > 32 ? authData[authData.startIndex + 32] : 0
            return SecurityKeyAssertion(
                clientData: clientData.base64EncodedString(),
                authenticatorData: authData.base64EncodedString(),
                signature: lines[3],
                userHandle: lines.count >= 5 ? lines[4].replacingOccurrences(of: "=", with: "") : "",
                credentialID: handle,
                diagnostics: "authData \(rawAuth.count)→\(authData.count) bytes, "
                    + "flags=0x\(String(flags, radix: 16)) "
                    + "(UP=\(flags & 0x01 != 0), UV=\(flags & 0x04 != 0)), "
                    + "clientData \(clientData.count) bytes")
        }
        if lastError.localizedCaseInsensitiveContains("no credentials")
            || lastError.localizedCaseInsensitiveContains("NO_CREDENTIALS") {
            throw SecurityKeyError.noMatchingCredential
        }
        throw SecurityKeyError.failed(lastError)
    }

    // MARK: - Helpers

    /// Strip a CBOR byte-string header, if present, returning the payload.
    /// libfido2 emits `authenticator data (CBOR)`; anything else is passed through
    /// untouched so this stays safe if that ever changes.
    static func unwrapCBORByteString(_ data: Data) -> Data {
        let b = [UInt8](data)
        guard let first = b.first, first >> 5 == 2 else { return data }
        let ai = first & 0x1f
        var offset = 1
        var length = 0
        switch ai {
        case 0..<24:
            length = Int(ai)
        case 24:
            guard b.count > 1 else { return data }
            length = Int(b[1]); offset = 2
        case 25:
            guard b.count > 2 else { return data }
            length = Int(b[1]) << 8 | Int(b[2]); offset = 3
        case 26:
            guard b.count > 4 else { return data }
            length = Int(b[1]) << 24 | Int(b[2]) << 16 | Int(b[3]) << 8 | Int(b[4])
            offset = 5
        default:
            return data
        }
        guard b.count == offset + length else { return data }
        return Data(b[offset ..< offset + length])
    }

    /// Standard base64 → base64url, unpadded (what clientDataJSON must carry).
    static func base64url(_ s: String) -> String {
        s.replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func run(_ path: String, args: [String], stdin: String?) throws
        -> (status: Int32, stdout: String, stderr: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe(), err = Pipe(), inPipe = Pipe()
        p.standardOutput = out; p.standardError = err; p.standardInput = inPipe
        try p.run()
        if let stdin { inPipe.fileHandleForWriting.write(Data(stdin.utf8)) }
        inPipe.fileHandleForWriting.closeFile()
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus,
                String(data: o, encoding: .utf8) ?? "",
                String(data: e, encoding: .utf8) ?? "")
    }
}
