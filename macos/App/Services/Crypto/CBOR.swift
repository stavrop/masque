import Foundation

/// The sliver of CBOR (RFC 8949) that CTAP2 needs: unsigned integers, byte and
/// text strings, arrays, maps and booleans.
///
/// CTAP2 mandates canonical encoding. For the requests Masque builds that comes
/// down to emitting map keys in ascending numeric order, which the encoder does
/// not enforce — callers pass them already sorted.
enum CBOR {

    // MARK: - Encoding

    static func uint(_ v: UInt64) -> Data { header(major: 0, value: v) }
    static func bytes(_ d: Data) -> Data { header(major: 2, value: UInt64(d.count)) + d }

    static func text(_ s: String) -> Data {
        let u = Data(s.utf8)
        return header(major: 3, value: UInt64(u.count)) + u
    }

    static func array(_ items: [Data]) -> Data {
        header(major: 4, value: UInt64(items.count)) + items.reduce(Data(), +)
    }

    static func map(_ pairs: [(Data, Data)]) -> Data {
        header(major: 5, value: UInt64(pairs.count))
            + pairs.reduce(Data()) { $0 + $1.0 + $1.1 }
    }

    static func bool(_ b: Bool) -> Data { Data([b ? 0xf5 : 0xf4]) }

    private static func header(major: UInt8, value: UInt64) -> Data {
        let m = major << 5
        switch value {
        case ..<24:
            return Data([m | UInt8(value)])
        case ..<0x100:
            return Data([m | 24, UInt8(value)])
        case ..<0x1_0000:
            return Data([m | 25, UInt8(truncatingIfNeeded: value >> 8),
                         UInt8(truncatingIfNeeded: value)])
        case ..<0x1_0000_0000:
            return Data([m | 26,
                         UInt8(truncatingIfNeeded: value >> 24),
                         UInt8(truncatingIfNeeded: value >> 16),
                         UInt8(truncatingIfNeeded: value >> 8),
                         UInt8(truncatingIfNeeded: value)])
        default:
            var d = Data([m | 27])
            for shift in stride(from: 56, through: 0, by: -8) {
                d.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
            }
            return d
        }
    }

    // MARK: - Decoding

    indirect enum Value {
        case uint(UInt64)
        case negative(Int64)
        case bytes(Data)
        case text(String)
        case array([Value])
        case map([(Value, Value)])
        case bool(Bool)
        case simple

        /// Look up an unsigned-integer key — how every CTAP2 response is shaped.
        subscript(key: UInt64) -> Value? {
            guard case .map(let pairs) = self else { return nil }
            for (k, v) in pairs {
                if case .uint(let n) = k, n == key { return v }
            }
            return nil
        }

        var dataValue: Data? {
            if case .bytes(let d) = self { return d }
            return nil
        }
    }

    struct DecodeError: LocalizedError {
        let message: String
        var errorDescription: String? { "Malformed CBOR: \(message)" }
    }

    static func decode(_ data: Data) throws -> Value {
        var i = data.startIndex
        let v = try decodeValue(data, &i)
        return v
    }

    private static func decodeValue(_ d: Data, _ i: inout Data.Index) throws -> Value {
        guard i < d.endIndex else { throw DecodeError(message: "truncated") }
        let initial = d[i]; i = d.index(after: i)
        let major = initial >> 5
        let ai = initial & 0x1f

        // Simple values live in major type 7 and carry no length.
        if major == 7 {
            switch ai {
            case 20: return .bool(false)
            case 21: return .bool(true)
            default: return .simple
            }
        }

        let value = try length(d, &i, ai)

        switch major {
        case 0: return .uint(value)
        case 1: return .negative(-1 - Int64(value))
        case 2:
            let end = try advance(d, i, by: Int(value))
            defer { i = end }
            return .bytes(d[i..<end])
        case 3:
            let end = try advance(d, i, by: Int(value))
            defer { i = end }
            guard let s = String(data: d[i..<end], encoding: .utf8) else {
                throw DecodeError(message: "bad UTF-8")
            }
            return .text(s)
        case 4:
            var items: [Value] = []
            for _ in 0..<value { items.append(try decodeValue(d, &i)) }
            return .array(items)
        case 5:
            var pairs: [(Value, Value)] = []
            for _ in 0..<value {
                let k = try decodeValue(d, &i)
                let v = try decodeValue(d, &i)
                pairs.append((k, v))
            }
            return .map(pairs)
        default:
            throw DecodeError(message: "unsupported major type \(major)")
        }
    }

    private static func length(_ d: Data, _ i: inout Data.Index, _ ai: UInt8) throws -> UInt64 {
        switch ai {
        case ..<24: return UInt64(ai)
        case 24, 25, 26, 27:
            let count = 1 << Int(ai - 24)
            let end = try advance(d, i, by: count)
            var v: UInt64 = 0
            for b in d[i..<end] { v = v << 8 | UInt64(b) }
            i = end
            return v
        default:
            throw DecodeError(message: "indefinite lengths are not used by CTAP2")
        }
    }

    private static func advance(_ d: Data, _ i: Data.Index, by n: Int) throws -> Data.Index {
        guard let end = d.index(i, offsetBy: n, limitedBy: d.endIndex) else {
            throw DecodeError(message: "truncated")
        }
        return end
    }
}
