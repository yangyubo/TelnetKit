import Logging
import NIOConcurrencyHelpers
import NIOCore

/// The bridge between the NIO channel and `TelnetProtocolCore`.
///
/// Every `telnet_*` call happens in this handler, on the EventLoop that owns the channel.
/// Inbound bytes are parsed into events and yielded in wire order; bytes the core queues
/// while parsing are written after the events so a negotiation never overtakes the data it
/// enabled. The handler is `Sendable` because every stored property is immutable and
/// `Sendable`; the mutable `finished` flag and idle task live in a lock box, although the
/// EventLoop is the only writer.
final class TelnetChannelHandler: ChannelDuplexHandler, Sendable {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = Never
    typealias OutboundIn = TelnetOutboundCommand
    typealias OutboundOut = IOData

    private struct HandlerState: Sendable {
        var finished = false
        var readyCompleted = false
        var idleTask: Scheduled<Void>?
    }

    private let core: TelnetProtocolCore
    private let sink: TelnetEventSink
    private let session: TelnetSessionState
    private let ready: EventLoopPromise<Void>
    private let logger: Logger?
    private let idleTimeout: TimeAmount?
    private let state = NIOLockedValueBox(HandlerState())

    init(
        core: TelnetProtocolCore,
        sink: TelnetEventSink,
        session: TelnetSessionState,
        ready: EventLoopPromise<Void>,
        logger: Logger?,
        idleTimeout: TimeAmount?
    ) {
        self.core = core
        self.sink = sink
        self.session = session
        self.ready = ready
        self.logger = logger
        self.idleTimeout = idleTimeout
    }

    func channelActive(context: ChannelHandlerContext) {
        session.setConnected(true)
        session.setAddresses(
            remote: TelnetChannelHandler.describe(context.channel.remoteAddress),
            local: TelnetChannelHandler.describe(context.channel.localAddress)
        )
        logger?.info("connection active", metadata: ["remote": "\(session.remoteAddress ?? "unknown")"])
        let bytes = core.sendInitialNegotiation()
        if !bytes.isEmpty {
            writeAndFlush(bytes, context: context)
        }
        resetIdleTimer(context: context)
        context.fireChannelActive()
        // `connect` waits on this, so it never returns a session whose first `send`
        // would observe `.notConnected` before the channel became active.
        completeReady(with: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        let bytes = Array(buffer.readableBytesView)
        guard !bytes.isEmpty else { return }
        resetIdleTimer(context: context)
        if let failure = core.feed(bytes) {
            logger?.error("protocol failure", metadata: ["error": "\(failure)"])
            // The core already emitted the matching `.protocolError` event.
            context.close(promise: nil)
            return
        }
        let outbound = core.drainOutbound()
        if !outbound.isEmpty {
            writeAndFlush(outbound, context: context)
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let command = unwrapOutboundIn(data)
        do {
            let outcome = try core.perform(command.kind)
            command.negotiationOutcome?.set(outcome.negotiationSent)
            resetIdleTimer(context: context)
            if outcome.bytes.isEmpty {
                promise?.succeed(())
            } else {
                var buffer = context.channel.allocator.buffer(capacity: outcome.bytes.count)
                buffer.writeBytes(outcome.bytes)
                context.write(wrapOutboundOut(IOData.byteBuffer(buffer)), promise: promise)
            }
        } catch {
            // `perform` is typed `throws(TelnetError)`, so `error` is already the public
            // error the caller expects.
            promise?.fail(error)
        }
    }

    func flush(context: ChannelHandlerContext) {
        context.flush()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let mapped = TelnetNetworkEventMapping.telnetEvent(from: event) {
            sink.yield(mapped)
            return
        }
        context.fireUserInboundEventTriggered(event)
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        logger?.error("channel error", metadata: ["error": "\(error)"])
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        finish()
        context.fireChannelInactive()
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        finish()
    }

    private func writeAndFlush(_ bytes: [UInt8], context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)
        context.writeAndFlush(wrapOutboundOut(IOData.byteBuffer(buffer)), promise: nil)
    }

    /// Restarts the idle countdown; called for every inbound and outbound activity.
    private func resetIdleTimer(context: ChannelHandlerContext) {
        guard let idleTimeout else { return }
        // `ChannelHandlerContext` is deliberately not `Sendable`, so the scheduled closure
        // captures the `Sendable` channel instead of the context.
        let channel = context.channel
        let task = context.eventLoop.scheduleTask(in: idleTimeout) {
            channel.close(promise: nil)
        }
        let previous = state.withLockedValue { handlerState -> Scheduled<Void>? in
            let previous = handlerState.idleTask
            handlerState.idleTask = task
            return previous
        }
        previous?.cancel()
    }

    /// Finishes the event stream and frees the C state exactly once, on the EventLoop.
    private func finish() {
        let alreadyFinished = state.withLockedValue { handlerState -> Bool in
            let previous = handlerState.finished
            handlerState.finished = true
            return previous
        }
        guard !alreadyFinished else { return }
        state.withLockedValue { $0.idleTask?.cancel() }
        // A channel that closes before it became active must release `connect`'s wait.
        completeReady(
            with: TelnetError.transportFailed(
                TelnetTransportFailure(
                    kind: .channelClosed,
                    message: "the connection closed before it became active",
                    isRetryable: true
                )
            )
        )
        core.finish()
        core.destroy()
        session.setConnected(false)
        sink.finish()
    }

    /// Completes the readiness promise exactly once: success on `channelActive`, or the
    /// error that ended the connection first.
    private func completeReady(with error: (any Error)?) {
        let first = state.withLockedValue { handlerState -> Bool in
            guard !handlerState.readyCompleted else { return false }
            handlerState.readyCompleted = true
            return true
        }
        guard first else { return }
        if let error {
            ready.fail(error)
        } else {
            ready.succeed(())
        }
    }

    private static func describe(_ address: SocketAddress?) -> String? {
        guard let address, let host = address.ipAddress, let port = address.port else { return nil }
        return "\(host):\(port)"
    }
}
