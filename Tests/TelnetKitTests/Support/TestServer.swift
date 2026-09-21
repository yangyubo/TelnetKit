import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOTransportServices
import TelnetKit
import Testing

/// A loopback listener for the public API and integration suites.
///
/// It binds through `NIOTSListenerBootstrap`, so the fixture uses the same
/// Network.framework transport as the library and never touches a POSIX socket. The server
/// records every byte a client sends and pushes scripted bytes on request, which keeps a
/// test's expectation explicit instead of depending on a server's own negotiation choices.
final class TestServer: Sendable {
    private static let group = NIOTSEventLoopGroup(loopCount: 1)

    let port: Int
    private let listener: Channel
    private let recorder: ByteRecorder
    private let childBox: NIOLockedValueBox<Channel?>
    private let connectionPromise: EventLoopPromise<Channel>
    private let connectionDelivered: NIOLockedValueBox<Bool>
    private let acceptedChildren: NIOLockedValueBox<[Channel]>

    private init(
        listener: Channel,
        port: Int,
        recorder: ByteRecorder,
        childBox: NIOLockedValueBox<Channel?>,
        connectionPromise: EventLoopPromise<Channel>,
        connectionDelivered: NIOLockedValueBox<Bool>,
        acceptedChildren: NIOLockedValueBox<[Channel]>
    ) {
        self.listener = listener
        self.port = port
        self.recorder = recorder
        self.childBox = childBox
        self.connectionPromise = connectionPromise
        self.connectionDelivered = connectionDelivered
        self.acceptedChildren = acceptedChildren
    }

    deinit {
        // A NIO promise must be completed before it is released, even when no client ever
        // connected; a fixture that is started and never used must not crash the suite.
        if markDeliveredIfFirst() {
            connectionPromise.fail(TestServerError.noConnection)
        }
    }

    /// Returns true when this call is the first completion, so the promise is completed
    /// exactly once.
    private func markDeliveredIfFirst() -> Bool {
        connectionDelivered.withLockedValue { delivered -> Bool in
            let first = !delivered
            delivered = true
            return first
        }
    }

    static func start() async throws -> TestServer {
        let recorder = ByteRecorder()
        let childBox = NIOLockedValueBox<Channel?>(nil)
        let connectionPromise = group.next().makePromise(of: Channel.self)
        let delivered = NIOLockedValueBox(false)
        let acceptedChildren = NIOLockedValueBox<[Channel]>([])

        let bootstrap = NIOTSListenerBootstrap(group: group)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(
                    RecordingHandler(
                        recorder: recorder,
                        onActive: { child in
                            childBox.withLockedValue { $0 = child }
                            // Keep only the live children, so a soak of many connections
                            // does not retain every channel the fixture ever accepted.
                            acceptedChildren.withLockedValue { children in
                                children.removeAll { !$0.isActive }
                                children.append(child)
                            }
                            let first = delivered.withLockedValue { value -> Bool in
                                let previous = !value
                                value = true
                                return previous
                            }
                            if first { connectionPromise.succeed(child) }
                        }
                    )
                )
            }

        let listener = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
        guard let port = listener.localAddress?.port else {
            throw TestServerError.noBoundPort
        }
        return TestServer(
            listener: listener,
            port: port,
            recorder: recorder,
            childBox: childBox,
            connectionPromise: connectionPromise,
            connectionDelivered: delivered,
            acceptedChildren: acceptedChildren
        )
    }

    /// How many client connections the listener has accepted so far.
    var acceptedConnectionCount: Int {
        acceptedChildren.withLockedValue { $0.count }
    }

    /// True once every accepted client connection has closed; used to prove a cancelled
    /// connect leaves nothing behind on the server.
    func waitForNoActiveConnections(timeout: Duration = .seconds(2)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let active = acceptedChildren.withLockedValue { children in
                children.contains { $0.isActive }
            }
            if !active { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return acceptedChildren.withLockedValue { children in
            !children.contains { $0.isActive }
        }
    }

    /// Waits until a client connection is accepted and returns its channel.
    func waitForConnection() async throws -> Channel {
        let channel = try await connectionPromise.futureResult.get()
        childBox.withLockedValue { $0 = channel }
        return channel
    }

    /// Pushes bytes to the connected client.
    func send(_ bytes: [UInt8]) async throws {
        let channel = try await waitForConnection()
        var buffer = channel.allocator.buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)
        try await channel.writeAndFlush(buffer).get()
    }

    /// Everything the client has sent so far.
    var receivedBytes: [UInt8] {
        recorder.bytes
    }

    /// Waits until the client has sent at least `count` bytes and returns everything read.
    func waitForReceivedBytes(_ count: Int, timeout: Duration = .seconds(2)) async -> [UInt8] {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let bytes = recorder.bytes
            if bytes.count >= count { return bytes }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return recorder.bytes
    }

    func stop() async {
        listener.close(promise: nil)
        try? await listener.closeFuture.get()
        if markDeliveredIfFirst() {
            connectionPromise.fail(TestServerError.noConnection)
        }
    }

    /// Closes the accepted client connection while the listener stays open.
    func disconnect() async throws {
        let channel = try await waitForConnection()
        channel.close(promise: nil)
        try? await channel.closeFuture.get()
    }
}

enum TestServerError: Error {
    case noBoundPort
    case noConnection
}

/// Records inbound bytes under a lock, because the EventLoop writes and the test reads.
final class ByteRecorder: Sendable {
    private let storage = NIOLockedValueBox<[UInt8]>([])

    var bytes: [UInt8] { storage.withLockedValue { $0 } }

    func append(_ bytes: [UInt8]) {
        storage.withLockedValue { $0.append(contentsOf: bytes) }
    }

    func reset() {
        storage.withLockedValue { $0 = [] }
    }
}

private final class RecordingHandler: ChannelInboundHandler, Sendable {
    typealias InboundIn = ByteBuffer

    private let recorder: ByteRecorder
    private let onActive: @Sendable (Channel) -> Void

    init(recorder: ByteRecorder, onActive: @escaping @Sendable (Channel) -> Void) {
        self.recorder = recorder
        self.onActive = onActive
    }

    func channelActive(context: ChannelHandlerContext) {
        onActive(context.channel)
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        recorder.append(Array(buffer.readableBytesView))
    }
}

/// Collects events from a stream so a test can await a condition with a generous bound.
actor EventRecorder {
    private(set) var events: [TelnetEvent] = []

    func append(_ event: TelnetEvent) {
        events.append(event)
    }

    func waitFor(
        timeout: Duration = .seconds(2),
        _ predicate: @Sendable (TelnetEvent) -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if events.contains(where: predicate) { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return events.contains(where: predicate)
    }

    /// Waits until at least `count` events match, for a test that drives the same request
    /// more than once.
    func waitFor(
        count: Int,
        timeout: Duration = .seconds(2),
        _ predicate: @Sendable (TelnetEvent) -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if events.count(where: predicate) >= count { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return events.count(where: predicate) >= count
    }
}

/// Records that a stream finished, so a test can wait for the finish without a fixed
/// sleep.
actor StreamFinishFlag {
    private(set) var isFinished = false

    func markFinished() {
        isFinished = true
    }
}

/// Starts consuming `stream` and returns the recorder plus its task.
func recordEvents(_ stream: AsyncStream<TelnetEvent>) -> (EventRecorder, Task<Void, Never>) {
    let recorder = EventRecorder()
    let task = Task {
        for await event in stream {
            await recorder.append(event)
        }
    }
    return (recorder, task)
}
