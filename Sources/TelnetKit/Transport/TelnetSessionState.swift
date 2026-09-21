import NIOConcurrencyHelpers

/// The connection facts `TelnetConnection` reports without an `await`.
///
/// The handler writes them on the connection's EventLoop and the actor reads them from
/// wherever it runs, so the box carries its own lock rather than relying on the EventLoop.
final class TelnetSessionState: Sendable {
    struct Snapshot: Sendable {
        var isConnected = false
        var remoteAddress: String?
        var localAddress: String?
    }

    private let box = NIOLockedValueBox(Snapshot())

    var snapshot: Snapshot { box.withLockedValue { $0 } }

    var isConnected: Bool { box.withLockedValue { $0.isConnected } }
    var remoteAddress: String? { box.withLockedValue { $0.remoteAddress } }
    var localAddress: String? { box.withLockedValue { $0.localAddress } }

    func setConnected(_ value: Bool) {
        box.withLockedValue { $0.isConnected = value }
    }

    func setAddresses(remote: String?, local: String?) {
        box.withLockedValue {
            $0.remoteAddress = remote
            $0.localAddress = local
        }
    }
}
