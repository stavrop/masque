import Foundation
import BigInt

/// SRP-6a client matching pysrp (`srp` package) with `rfc5054_enable()` +
/// `no_username_in_x()`, SHA-256, and the RFC-5054 2048-bit group — the exact
/// configuration Apple's idmsa SRP endpoint expects. Verified byte-for-byte
/// against pysrp reference vectors in `SRPClientTests`.
final class SRPClient {

    /// RFC 5054 2048-bit group prime N (hex), g = 2.
    static let nHex =
        "ac6bdb41324a9a9bf166de5e1389582faf72b6651987ee07fc3192943db56050" +
        "a37329cbb4a099ed8193e0757767a13dd52312ab4b03310dcd7f48a9da04fd50" +
        "e8083969edb767b0cf6095179a163ab3661a05fbd5faaae82918a9962f0b93b8" +
        "55f97993ec975eeaa80d740adbf4ff747359d041d5c33ea71d281e446b14773b" +
        "ca97b43a23fb801676bd207a436c6481f1d2b9078717461a5b9d32e688f87748" +
        "544523b524b0d57d5ea77a2775d2ecfa032cfbdbf52fb3786160279004e57ae6" +
        "af874e7303ce53299ccc041c7bc308d82a5698f3a8d0c38271ae35f8e9dbfbb6" +
        "94b5c803d89f7ae435de236d525f54759b65e372fcd68ef20fa7111f9e4aff73"

    let N: BigUInt
    let g: BigUInt = 2
    let width: Int              // byte length of N (256)
    private let k: BigUInt
    private let username: String
    private let a: BigUInt          // client private
    let A: BigUInt                  // client public

    /// A depends only on the private exponent and the group, so the client is
    /// constructed before `signin/init` returns; the password key (derived from
    /// the salt/iteration/protocol in that response) is supplied later to `process`.
    /// - Parameter privateA: fixed private exponent for testing; random otherwise.
    init(username: String, privateA: Data? = nil) {
        self.N = BigUInt(Data(hex: SRPClient.nHex)!)
        self.width = CryptoUtils.longToBytes(N).count
        self.username = username

        // k = H(N | g), both padded to width (rfc5054).
        self.k = BigUInt(CryptoUtils.sha256(CryptoUtils.pad(N, to: width) + CryptoUtils.pad(g, to: width)))

        if let privateA {
            self.a = BigUInt(privateA)
        } else {
            self.a = BigUInt(Data((0..<256).map { _ in UInt8.random(in: 0...255) }))
        }
        self.A = g.power(a, modulus: N)
    }

    /// The `a` field for signin/init: base64 of minimal-big-endian A.
    var aBase64: String { CryptoUtils.longToBytes(A).base64EncodedString() }

    struct Proof { let m1: Data; let m2: Data }

    /// pysrp `process_challenge`: given the server salt, B, and the s2k/s2k_fo
    /// derived password key, produce M1 (to send) and M2 (the client's H_AMK,
    /// which pyicloud also sends as `m2`).
    func process(salt: Data, serverB: Data, passwordKey: Data) -> Proof {
        let B = BigUInt(serverB)
        precondition(B % N != 0, "invalid server B")

        // u = H( PAD(A) | PAD(B) )
        let u = BigUInt(CryptoUtils.sha256(CryptoUtils.pad(A, to: width) + CryptoUtils.pad(B, to: width)))

        // x = H( salt | H(":" | passwordKey) )   (username dropped, colon kept)
        let inner = CryptoUtils.sha256(Data(":".utf8) + passwordKey)
        let x = BigUInt(CryptoUtils.sha256(salt + inner))

        let v = g.power(x, modulus: N)

        // S = (B - k*v) ^ (a + u*x) mod N   — reduce a possibly-negative base mod N first.
        var base = (BigInt(B) - BigInt(k) * BigInt(v)) % BigInt(N)
        if base.sign == .minus { base += BigInt(N) }
        let S = BigUInt(base).power(a + u * x, modulus: N)

        let K = CryptoUtils.sha256(CryptoUtils.longToBytes(S))

        // M1 = H( (H(N) xor H(g)) | H(I) | salt | A | B | K )   — A,B minimal (not padded)
        let hN = CryptoUtils.sha256(CryptoUtils.pad(N, to: width))
        let hG = CryptoUtils.sha256(CryptoUtils.pad(g, to: width))
        let hNxorG = Data(zip(hN, hG).map { $0 ^ $1 })
        var m1Data = Data()
        m1Data += hNxorG
        m1Data += CryptoUtils.sha256(Data(username.utf8))
        m1Data += salt
        m1Data += CryptoUtils.longToBytes(A)
        m1Data += CryptoUtils.longToBytes(B)
        m1Data += K
        let M1 = CryptoUtils.sha256(m1Data)

        // M2 (H_AMK) = H( A | M1 | K )
        let M2 = CryptoUtils.sha256(CryptoUtils.longToBytes(A) + M1 + K)

        return Proof(m1: M1, m2: M2)
    }
}
