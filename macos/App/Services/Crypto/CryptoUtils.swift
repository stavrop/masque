import Foundation
import CommonCrypto
import CryptoKit
import BigInt

/// Low-level crypto helpers, matched to pysrp's byte conventions so the SRP
/// handshake reproduces Apple's server expectations exactly.
enum CryptoUtils {

    static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    /// PBKDF2-HMAC-SHA256, 32-byte output.
    static func pbkdf2SHA256(password: Data, salt: Data, iterations: Int, keyLength: Int = 32) -> Data {
        var derived = Data(count: keyLength)
        let status = derived.withUnsafeMutableBytes { derivedPtr in
            salt.withUnsafeBytes { saltPtr in
                password.withUnsafeBytes { pwPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwPtr.baseAddress?.assumingMemoryBound(to: CChar.self), password.count,
                        saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), keyLength)
                }
            }
        }
        precondition(status == kCCSuccess, "PBKDF2 failed")
        return derived
    }

    /// Apple "s2k" / "s2k_fo" password-key derivation.
    /// Always SHA-256 the UTF-8 password first; for `s2k_fo` the digest is
    /// lowercase-hex-encoded (ASCII) before PBKDF2, for `s2k` it's used raw.
    static func derivePasswordKey(password: String, salt: Data, iterations: Int, protocol proto: String) -> Data {
        let inner = sha256(Data(password.utf8))
        let pbInput: Data = (proto == "s2k_fo") ? Data(inner.hexEncodedString().utf8) : inner
        return pbkdf2SHA256(password: pbInput, salt: salt, iterations: iterations)
    }

    // MARK: BigUInt <-> bytes (pysrp `long_to_bytes` semantics: minimal big-endian, min 1 byte)

    static func longToBytes(_ n: BigUInt) -> Data {
        let s = n.serialize()          // minimal big-endian; empty for zero
        return s.isEmpty ? Data([0]) : s
    }

    /// Left-zero-pad to `width` bytes (pysrp's rfc5054 `H(..., width=)` padding).
    static func pad(_ n: BigUInt, to width: Int) -> Data {
        let b = longToBytes(n)
        if b.count >= width { return b }
        return Data(count: width - b.count) + b
    }

    static func bigUInt(_ data: Data) -> BigUInt { BigUInt(data) }
}

extension Data {
    func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
    init?(hex: String) {
        let chars = Array(hex)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8](); bytes.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let b = UInt8(String(chars[i...i+1]), radix: 16) else { return nil }
            bytes.append(b); i += 2
        }
        self = Data(bytes)
    }
}
