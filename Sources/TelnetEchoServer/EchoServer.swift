import Foundation
import NIOCore
import NIOTransportServices

/// The loopback Telnet server behind `telnetkit-echo-server`.
///
/// The listener is a `NIOTSListenerBootstrap` on a one-loop `NIOTSEventLoopGroup`, so the
/// fixture uses the same Network.framework transport as the library and no POSIX socket call
/// exists in the package. It is a manual entry point for `telnetkit-client` and the SwiftUI
/// demo, not a substitute for a suite; `docs/testing.md` owns that split.
struct EchoServer: Sendable {
    let arguments: ServerArguments

    func run() async throws {
        let group = NIOTSEventLoopGroup(loopCount: 1)
        let log = EchoLog()
        let scenarios = arguments.scenarios

        let bootstrap = NIOTSListenerBootstrap(group: group)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(
                    EchoSessionHandler(scenarios: scenarios, log: log, eventLoop: channel.eventLoop)
                )
            }

        let listener = try await bootstrap.bind(host: arguments.host, port: arguments.port).get()
        let address = listener.localAddress.map(PeerAddress.describe)
            ?? "\(arguments.host):\(arguments.port)"
        log.line("telnetkit-echo-server listening on \(address)")
        if !scenarios.isEmpty {
            log.line("injecting \(scenarios.map(\.rawValue).joined(separator: ", ")) on connect")
        }
        try await listener.closeFuture.get()
    }
}
