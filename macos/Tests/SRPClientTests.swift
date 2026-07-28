import XCTest
import BigInt
@testable import Masque

/// Ground-truth values produced by the reference pysrp (`srp` Python package)
/// with rfc5054_enable() + no_username_in_x(), SHA-256, NG_2048. See
/// scratchpad/gen_vectors.py. If Apple ever changes the handshake these pin the
/// exact byte framing our Swift must reproduce.
final class SRPClientTests: XCTestCase {

    private func hex(_ s: String) -> Data { Data(hex: s)! }

    func testPublicAndProofMatchReferenceVectors() {
        let username = "test@icloud.com"
        let passwordKey = hex("00112233445566778899aabbccddeeff00112233445566778899aabbccddee01")
        let salt = hex("a1b2c3d4e5f60718293a4b5c6d7e8f90")
        let privateA = hex(String(repeating: "0f", count: 256))
        let serverB = hex("ab843f895be2378b5d935f33aa5dbb67fb13c7f443ca2104336f4b28c86750af" +
                          "aa22023d35d1c138e102f19e26156964abbba93d39bae7fbe6b4f14bd6d4c8eb" +
                          "5155c874a0cc022504e29b532ae6885fd61570c4a66e6ca07294a230ec7f2963" +
                          "0995d7cca58bb2923954fad24104cfc209f6d111aecf1024ab2a455767f970a1" +
                          "fbb3abbaad4e3307473452f70ae638b422dfe184da59ca6fdcce5a6c6d07358b" +
                          "4b6e0aebd076125639ac07bbba872d54ae82c808ac62a6c771dbcd720ce3c1f7" +
                          "dd8fe7e3ef612c6ef3d67e3cb6c5c3dfd8f7dfcf91c33337001ffa3cc35d7240" +
                          "0f2f467ff256d8a0f8afea269b31cb2671ae985a35883beeb55e8f169953b78b")

        let expectedA = "601407be924e66555c4415c222004e4892f09255606f5ea82a1ebce8a21b1fbd57f41735f4986cb6b995f2f37f56b4a87478a80736f6d9d1e658f32ff9b3cfd8e81aa25008fcd04a29d079028f81c304852978489d3f58c2112aa13f3414694022e37e8e3216e3121d8e6cb2cc592f92447fb50e66d8131bc0b88e2f2a5b74b76ab162ee0a7bf8865fdaef15a6ece35996aca1bc8500a8d08cbc9b0ab394afafee3ff61f7891ee9af96e13d70bd1f6009a5d87c2d7ed120a5a9b7362f489f8f230fe06046397722f45dee6c8432b09add0e2d7536588bd7f362ecfae40f7a1d214747ea03f841ad18a62a3a7568178cf558bbbefa4f36af7d4ae9935a4198819"
        let expectedM1 = "5f27e58d36fddf235f42bb3e610724d1a0edb9a80de55b2a21b08fe48c7e5736"
        let expectedM2 = "b8cabdae8e1459ddc847abefc72e798a069b00312305672339a75bc788d5d6b0"

        let client = SRPClient(username: username, privateA: privateA)
        XCTAssertEqual(CryptoUtils.longToBytes(client.A).hexEncodedString(), expectedA, "A mismatch")

        let proof = client.process(salt: salt, serverB: serverB, passwordKey: passwordKey)
        XCTAssertEqual(proof.m1.hexEncodedString(), expectedM1, "M1 mismatch")
        XCTAssertEqual(proof.m2.hexEncodedString(), expectedM2, "M2 mismatch")
    }

    func testS2KDerivationMatchesReference() {
        let salt = hex("0102030405060708")
        let s2k = CryptoUtils.derivePasswordKey(password: "hunter2secret", salt: salt,
                                                iterations: 20433, protocol: "s2k")
        let s2kFo = CryptoUtils.derivePasswordKey(password: "hunter2secret", salt: salt,
                                                  iterations: 20433, protocol: "s2k_fo")
        XCTAssertEqual(s2k.hexEncodedString(),
                       "e9cb912d56ea0fb2a8bd4cfaba61758ed6b62302b3397c9b2ec12337669a2988")
        XCTAssertEqual(s2kFo.hexEncodedString(),
                       "3b047fca0111fc182561eafdacd96fc82fd2a888511a35d43a8838a3e85b91f0")
    }
}
