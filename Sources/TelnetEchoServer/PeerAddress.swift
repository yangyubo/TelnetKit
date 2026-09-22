import NIOCore

/// Formats a socket address for the echo server's log.
///
/// NIO's own description spells an IPv4 address as `[IPv4]127.0.0.1/127.0.0.1:2323`, which is
/// noise in a log a person reads during a demo.
enum PeerAddress {
    static func describe(_ address: SocketAddress?) -> String {
        guard let address else { return "unknown" }
        if let host = address.ipAddress, let port = address.port {
            return "\(host):\(port)"
        }
        return String(describing: address)
    }
}
