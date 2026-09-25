import Foundation
import IOKit.hid

/// CTAPHID transport (FIDO's USB HID protocol) over IOKit.
///
/// Replaces the libfido2 CLI Masque shelled out to in 0.4: talking to the key
/// in-process is what lets the app stay sandboxed, needing only
/// `com.apple.security.device.usb`. No crypto happens here — the authenticator
/// produces the signature; we only frame requests and reassemble replies.
final class CTAPHIDDevice {

    /// FIDO devices advertise this HID usage page; it is how they are found.
    private static let usagePage = 0xF1D0
    private static let usage = 0x01

    private static let packetSize = 64
    private static let broadcastCID: UInt32 = 0xFFFF_FFFF

    private enum Cmd: UInt8 {
        case ping = 0x01, msg = 0x03, cbor = 0x10, initChannel = 0x06
        case cancel = 0x11, keepalive = 0x3B, error = 0x3F
    }

    enum DeviceError: LocalizedError {
        case notFound
        case cannotOpen(IOReturn)
        case timeout
        case protocolError(String)
        case ctap(UInt8)

        var errorDescription: String? {
            switch self {
            case .notFound:
                return "No security key found. Plug it in and try again."
            case .cannotOpen(let r):
                return String(format: "Couldn’t open the security key (IOKit 0x%08X).", UInt32(bitPattern: r))
            case .timeout:
                return "The security key didn’t respond in time."
            case .protocolError(let m):
                return "Security key protocol error: \(m)."
            case .ctap(let code):
                // 0x2E = no matching credential on this key.
                if code == 0x2E {
                    return "This key isn’t one of the keys registered with this Apple Account."
                }
                return String(format: "The security key refused the request (CTAP 0x%02X).", code)
            }
        }
    }

    private let device: IOHIDDevice
    private let queue = DispatchQueue(label: "stavrop.Masque.ctaphid")
    private var buffer = [UInt8](repeating: 0, count: packetSize)
    private let lock = NSCondition()
    private var inbox: [Data] = []
    private var channel: UInt32 = broadcastCID
    private var opened = false

    // MARK: - Discovery

    /// First attached FIDO authenticator, or nil when none is present.
    static func firstAvailable() -> CTAPHIDDevice? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDPrimaryUsagePageKey: usagePage,
            kIOHIDPrimaryUsageKey: usage,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        defer {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(),
                                              CFRunLoopMode.defaultMode.rawValue)
        }
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = set.first
        else { return nil }
        return CTAPHIDDevice(device: device)
    }

    private init(device: IOHIDDevice) { self.device = device }

    deinit { close() }

    // MARK: - Lifecycle

    func open() throws {
        guard !opened else { return }
        let r = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else { throw DeviceError.cannotOpen(r) }

        let context = Unmanaged.passUnretained(self).toOpaque()
        buffer.withUnsafeMutableBufferPointer { buf in
            IOHIDDeviceRegisterInputReportCallback(
                device, buf.baseAddress!, buf.count,
                { context, _, _, _, _, report, length in
                    guard let context else { return }
                    let me = Unmanaged<CTAPHIDDevice>.fromOpaque(context).takeUnretainedValue()
                    me.received(Data(bytes: report, count: length))
                },
                context)
        }
        IOHIDDeviceSetDispatchQueue(device, queue)
        IOHIDDeviceActivate(device)
        opened = true

        try allocateChannel()
    }

    func close() {
        guard opened else { return }
        opened = false
        IOHIDDeviceCancel(device)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func received(_ packet: Data) {
        lock.lock()
        inbox.append(packet)
        lock.signal()
        lock.unlock()
    }

    // MARK: - Framing

    /// CTAPHID_INIT against the broadcast channel, which returns our own channel id.
    private func allocateChannel() throws {
        var nonce = Data(count: 8)
        _ = nonce.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 8, $0.baseAddress!) }
        channel = Self.broadcastCID
        let reply = try transact(.initChannel, payload: nonce, timeout: 3)
        guard reply.count >= 17, reply.prefix(8) == nonce else {
            throw DeviceError.protocolError("INIT nonce mismatch")
        }
        channel = reply[reply.startIndex + 8 ..< reply.startIndex + 12]
            .reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    /// Send a CTAP2 CBOR command and return its response payload (status byte stripped).
    func cbor(_ command: UInt8, _ body: Data, timeout: TimeInterval) throws -> Data {
        let reply = try transact(.cbor, payload: Data([command]) + body, timeout: timeout)
        guard let status = reply.first else { throw DeviceError.protocolError("empty CBOR reply") }
        guard status == 0x00 else { throw DeviceError.ctap(status) }
        return reply.dropFirst()
    }

    private func transact(_ cmd: Cmd, payload: Data, timeout: TimeInterval) throws -> Data {
        try write(cmd, payload)
        return try read(timeout: timeout)
    }

    private func write(_ cmd: Cmd, _ payload: Data) throws {
        var packets: [Data] = []

        var initPacket = Data()
        initPacket += withUnsafeBytes(of: channel.bigEndian) { Data($0) }
        initPacket.append(cmd.rawValue | 0x80)
        initPacket.append(UInt8(truncatingIfNeeded: payload.count >> 8))
        initPacket.append(UInt8(truncatingIfNeeded: payload.count))
        let firstChunk = payload.prefix(Self.packetSize - 7)
        initPacket += firstChunk
        packets.append(initPacket)

        var seq: UInt8 = 0
        var rest = payload.dropFirst(firstChunk.count)
        while !rest.isEmpty {
            var cont = Data()
            cont += withUnsafeBytes(of: channel.bigEndian) { Data($0) }
            cont.append(seq)
            let chunk = rest.prefix(Self.packetSize - 5)
            cont += chunk
            packets.append(cont)
            rest = rest.dropFirst(chunk.count)
            seq += 1
        }

        for var p in packets {
            p += Data(repeating: 0, count: Self.packetSize - p.count)   // reports are fixed size
            let r = p.withUnsafeBytes { raw in
                IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0,
                                     raw.bindMemory(to: UInt8.self).baseAddress!, p.count)
            }
            guard r == kIOReturnSuccess else { throw DeviceError.cannotOpen(r) }
        }
    }

    private func read(timeout: TimeInterval) throws -> Data {
        var payload = Data()
        var expected = 0
        var started = false
        let deadline = Date().addingTimeInterval(timeout)

        while true {
            guard let packet = nextPacket(before: deadline) else { throw DeviceError.timeout }
            guard packet.count >= 5 else { continue }

            let cid = packet.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            guard cid == channel else { continue }           // not ours
            let byte4 = packet[packet.startIndex + 4]

            if byte4 & 0x80 != 0 {                            // initialisation packet
                let cmd = byte4 & 0x7f
                if cmd == Cmd.keepalive.rawValue { continue } // still waiting for the touch
                if cmd == Cmd.error.rawValue {
                    let code = packet.count > 7 ? packet[packet.startIndex + 7] : 0
                    throw DeviceError.protocolError(String(format: "HID error 0x%02X", code))
                }
                expected = Int(packet[packet.startIndex + 5]) << 8
                    | Int(packet[packet.startIndex + 6])
                payload = Data(packet.dropFirst(7))
                started = true
            } else {
                guard started else { continue }
                payload += packet.dropFirst(5)
            }
            if payload.count >= expected { return payload.prefix(expected) }
        }
    }

    private func nextPacket(before deadline: Date) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        while inbox.isEmpty {
            if Date() >= deadline { return nil }
            if !lock.wait(until: min(deadline, Date().addingTimeInterval(0.25))) { continue }
        }
        return inbox.removeFirst()
    }
}
