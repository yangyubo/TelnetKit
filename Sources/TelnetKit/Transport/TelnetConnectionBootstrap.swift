import Logging
import NIOCore
import NIOTransportServices

/// Builds the EventLoop pipeline for one connection and completes the TCP connect.
///
/// The library owns the connection through `NIOTSConnectionBootstrap` on the shared
/// `NIOTSEventLoopGroup`; no POSIX socket call exists in the package. The handler and its
/// `telnet_t` are created inside the channel initializer, which runs on the channel's
/// EventLoop, so the core never exists off its owning thread.
enum TelnetConnectionBootstrap {
    struct Result: Sendable {
        let channel: Channel
        let events: AsyncStream<TelnetEvent>
        let ledger: TelnetOptionLedger
        let session: TelnetSessionState
    }

    static func connect(
        host: String,
        port: Int,
        options: TelnetOptions,
        configuration: TelnetConfiguration
    ) async throws(TelnetError) -> Result {
        guard options.isValid else {
            throw TelnetError.invalidConfiguration("binary and lineMode cannot both be offered locally")
        }

        let address: SocketAddress
        do {
            address = try SocketAddress.makeAddressResolvingHost(host, port: port)
        } catch {
            throw TelnetError.invalidHost(host)
        }

        let (stream, continuation) = AsyncStream<TelnetEvent>.makeStream(
            bufferingPolicy: Self.bufferingPolicy(for: configuration.eventBufferPolicy)
        )
        let sink = TelnetEventSink(continuation: continuation, policy: configuration.eventBufferPolicy)
        let ledger = TelnetOptionLedger()
        let session = TelnetSessionState()
        let logger = configuration.logger

        let bootstrap = NIOTSConnectionBootstrap(group: NIOTSEventLoopGroup.singleton)
            .connectTimeout(TimeAmount(configuration.connectTimeout))
            .channelOption(NIOTSChannelOptions.waitForActivity, value: configuration.waitForConnectivity)
            .channelInitializer { channel in
                let core: TelnetProtocolCore
                do {
                    core = try TelnetProtocolCore(
                        options: options,
                        configuration: configuration,
                        ledger: ledger,
                        logger: logger,
                        emit: { event in sink.yield(event) }
                    )
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
                let handler = TelnetChannelHandler(
                    core: core,
                    sink: sink,
                    session: session,
                    logger: logger,
                    idleTimeout: configuration.idleTimeout.map(TimeAmount.init)
                )
                return channel.pipeline.addHandler(handler)
            }

        let future = bootstrap.connect(to: address)
        let channel: Channel
        do {
            channel = try await withTaskCancellationHandler {
                try await future.getAbandoningOnCancel()
            } onCancel: {
                // The future itself cannot be cancelled, so close the socket the moment it
                // opens: a cancelled connect leaves no connection behind.
                future.whenSuccess { channel in channel.close(promise: nil) }
            }
        } catch is CancellationError {
            throw TelnetError.cancelled
        } catch {
            throw TelnetNetworkEventMapping.connectError(
                from: error,
                host: host,
                port: port,
                timeout: configuration.connectTimeout
            )
        }

        if Task.isCancelled {
            channel.close(promise: nil)
            throw TelnetError.cancelled
        }

        return Result(channel: channel, events: stream, ledger: ledger, session: session)
    }

    private static func bufferingPolicy(
        for policy: TelnetEventBufferPolicy
    ) -> AsyncStream<TelnetEvent>.Continuation.BufferingPolicy {
        switch policy {
        case .bounded(let count):
            return .bufferingOldest(max(1, count))
        case .unbounded:
            return .unbounded
        case .dropOldest(let count):
            return .bufferingNewest(max(1, count))
        }
    }
}
