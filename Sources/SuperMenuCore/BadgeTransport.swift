import Darwin
import Foundation

// Public libSystem bootstrap APIs declared in <servers/bootstrap.h>, which
// Swift's Darwin module does not re-export.
@_silgen_name("bootstrap_look_up")
private func badgeBootstrapLookup(
    _ port: mach_port_t, _ name: UnsafePointer<CChar>, _ result: UnsafeMutablePointer<mach_port_t>
) -> kern_return_t
@_silgen_name("bootstrap_register")
private func badgeBootstrapRegister(_ port: mach_port_t, _ name: UnsafePointer<CChar>, _ service: mach_port_t)
    -> kern_return_t

public enum BadgeTransportError: Error { case unavailable, oversized, malformed, unauthorized }

/// Inline Mach messages: no out-of-line memory or transferred port descriptors.
/// Audit trailers are supplied by the kernel, not trusted from the JSON payload.
public enum BadgeTransport {
    public static let serviceName = "com.supermenu.git-badges"
    public static let messageLimit = 128 * 1024
    private static let headerSize = MemoryLayout<mach_msg_header_t>.size
    private static let prefixSize = headerSize + MemoryLayout<UInt32>.size
    private static let auditOptions = mach_msg_option_t(
        ((MACH_MSG_TRAILER_FORMAT_0 & 0xf) << 28)
            | ((MACH_RCV_TRAILER_AUDIT & 0xf) << 24))

    public static func request(
        _ data: Data, name: String = serviceName,
        timeout: TimeInterval = 0.5
    ) throws -> Data {
        guard data.count <= messageLimit - prefixSize else { throw BadgeTransportError.oversized }
        var remote: mach_port_t = 0
        guard name.withCString({ badgeBootstrapLookup(bootstrap_port, $0, &remote) }) == KERN_SUCCESS else {
            throw BadgeTransportError.unavailable
        }
        defer { mach_port_deallocate(mach_task_self_, remote) }
        var reply: mach_port_t = 0
        guard mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_RECEIVE, &reply) == KERN_SUCCESS else {
            throw BadgeTransportError.unavailable
        }
        defer { mach_port_mod_refs(mach_task_self_, reply, MACH_PORT_RIGHT_RECEIVE, -1) }
        try send(data, to: remote, reply: reply, timeout: timeout)
        let packet = try receive(on: reply, timeout: timeout)
        defer { if packet.reply != 0 { mach_port_deallocate(mach_task_self_, packet.reply) } }
        guard packet.uid == getuid() else { throw BadgeTransportError.unauthorized }
        return packet.data
    }

    fileprivate static func send(
        _ data: Data, to remote: mach_port_t, reply: mach_port_t = 0,
        timeout: TimeInterval = 0.1
    ) throws {
        guard data.count <= messageLimit - prefixSize else {
            if reply == 0 { mach_port_deallocate(mach_task_self_, remote) }
            throw BadgeTransportError.oversized
        }
        let size = (prefixSize + data.count + 3) & ~3
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { buffer.deallocate() }
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: size)
        let header = buffer.bindMemory(to: mach_msg_header_t.self, capacity: 1)
        header.pointee.msgh_bits =
            reply == 0
            ? mach_msg_bits_t(MACH_MSG_TYPE_MOVE_SEND_ONCE)
            : mach_msg_bits_t(MACH_MSG_TYPE_COPY_SEND | (MACH_MSG_TYPE_MAKE_SEND_ONCE << 8))
        header.pointee.msgh_size = mach_msg_size_t(size)
        header.pointee.msgh_remote_port = remote
        header.pointee.msgh_local_port = reply
        header.pointee.msgh_id = 0x534D42
        buffer.advanced(by: headerSize).storeBytes(of: UInt32(data.count), as: UInt32.self)
        data.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress {
                buffer.advanced(by: prefixSize).copyMemory(from: base, byteCount: data.count)
            }
        }
        let result = mach_msg(
            header, MACH_SEND_MSG | MACH_SEND_TIMEOUT, mach_msg_size_t(size), 0, 0,
            milliseconds(timeout), 0)
        guard result == MACH_MSG_SUCCESS else {
            // Failed reply sends still own the send-once right.
            if reply == 0 { mach_port_deallocate(mach_task_self_, remote) }
            throw BadgeTransportError.unavailable
        }
    }

    fileprivate struct Packet {
        let data: Data
        let reply: mach_port_t
        let uid: uid_t
        let pid: pid_t
    }
    fileprivate static func receive(on port: mach_port_t, timeout: TimeInterval) throws -> Packet {
        let capacity = messageLimit + MemoryLayout<mach_msg_audit_trailer_t>.size
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 8)
        defer { buffer.deallocate() }
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: capacity)
        let header = buffer.bindMemory(to: mach_msg_header_t.self, capacity: 1)
        let result = mach_msg(
            header, MACH_RCV_MSG | MACH_RCV_TIMEOUT | auditOptions,
            0, mach_msg_size_t(capacity), port, milliseconds(timeout), 0)
        guard result == MACH_MSG_SUCCESS else { throw BadgeTransportError.unavailable }
        let size = Int(header.pointee.msgh_size)
        guard header.pointee.msgh_bits & MACH_MSGH_BITS_COMPLEX == 0,
            header.pointee.msgh_id == 0x534D42, size >= prefixSize, size <= messageLimit
        else {
            mach_msg_destroy(header)
            throw BadgeTransportError.malformed
        }
        let count = Int(buffer.advanced(by: headerSize).load(as: UInt32.self))
        let trailerOffset = (size + 3) & ~3
        let trailer = buffer.advanced(by: trailerOffset).load(as: mach_msg_audit_trailer_t.self)
        guard count <= size - prefixSize,
            trailer.msgh_trailer_size >= MemoryLayout<mach_msg_audit_trailer_t>.size
        else {
            mach_msg_destroy(header)
            throw BadgeTransportError.malformed
        }
        return Packet(
            data: Data(bytes: buffer.advanced(by: prefixSize), count: count),
            reply: header.pointee.msgh_remote_port,
            uid: trailer.msgh_audit.val.1, pid: pid_t(trailer.msgh_audit.val.5))
    }
    private static func milliseconds(_ seconds: TimeInterval) -> mach_msg_timeout_t {
        mach_msg_timeout_t(max(1, min(10_000, seconds * 1_000)))
    }
}

public final class BadgePortServer: @unchecked Sendable {
    public let name: String
    private let lock = NSLock()
    private var port: mach_port_t
    public init(
        name: String = BadgeTransport.serviceName,
        handler: @escaping @Sendable (Data, pid_t) -> Data?
    ) throws {
        self.name = name
        var receive: mach_port_t = 0
        guard mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_RECEIVE, &receive) == KERN_SUCCESS else {
            throw BadgeTransportError.unavailable
        }
        guard
            mach_port_insert_right(
                mach_task_self_, receive, receive, mach_msg_type_name_t(MACH_MSG_TYPE_MAKE_SEND))
                == KERN_SUCCESS,
            name.withCString({ badgeBootstrapRegister(bootstrap_port, $0, receive) }) == KERN_SUCCESS
        else {
            mach_port_mod_refs(mach_task_self_, receive, MACH_PORT_RIGHT_RECEIVE, -1)
            throw BadgeTransportError.unavailable
        }
        port = receive
        mach_port_deallocate(mach_task_self_, receive)  // Bootstrap owns its send right.
        // The worker owns only the port value, never the server's lifetime.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while self?.isRunning == true {
                guard let packet = self?.nextPacket() else { continue }
                guard packet.reply != 0 else { continue }
                guard packet.uid == getuid() else {
                    mach_port_deallocate(mach_task_self_, packet.reply)
                    continue
                }
                if let response = handler(packet.data, packet.pid) {
                    try? BadgeTransport.send(response, to: packet.reply)
                } else {
                    mach_port_deallocate(mach_task_self_, packet.reply)
                }
            }
        }
    }
    private var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return port != 0
    }
    private func nextPacket() -> BadgeTransport.Packet? {
        lock.lock()
        defer { lock.unlock() }
        guard port != 0 else { return nil }
        return try? BadgeTransport.receive(on: port, timeout: 0.1)
    }
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        if port != 0 {
            mach_port_mod_refs(mach_task_self_, port, MACH_PORT_RIGHT_RECEIVE, -1)
            port = 0
        }
    }
    deinit { stop() }
}
