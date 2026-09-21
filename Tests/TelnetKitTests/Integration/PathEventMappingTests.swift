import Foundation
import Network
import NIOTransportServices
import Testing

@testable import TelnetKit

@Suite("Path event mapping")
struct PathEventMappingTests {
    @Test("a viability update maps to viabilityChanged")
    func viabilityUpdate() {
        let mapped = TelnetNetworkEventMapping.telnetEvent(
            from: NIOTSNetworkEvents.ViabilityUpdate(isViable: false)
        )
        guard case .viabilityChanged(let isViable) = mapped else {
            Issue.record("viability update did not map")
            return
        }
        #expect(isViable == false)
    }

    @Test("better-path availability maps to both cases")
    func betterPath() {
        guard case .betterPathAvailable = TelnetNetworkEventMapping.telnetEvent(
            from: NIOTSNetworkEvents.BetterPathAvailable()
        ) else {
            Issue.record("betterPathAvailable did not map")
            return
        }
        guard case .betterPathUnavailable = TelnetNetworkEventMapping.telnetEvent(
            from: NIOTSNetworkEvents.BetterPathUnavailable()
        ) else {
            Issue.record("betterPathUnavailable did not map")
            return
        }
    }

    @Test("waiting for connectivity maps with a description and no framework type")
    func waitingForConnectivity() {
        let mapped = TelnetNetworkEventMapping.telnetEvent(
            from: NIOTSNetworkEvents.WaitingForConnectivity(transientError: .posix(.ECONNREFUSED))
        )
        guard case .waitingForConnectivity = mapped else {
            Issue.record("waitingForConnectivity did not map")
            return
        }
    }

    @Test("a real path maps to pathChanged with Network.framework's own flags")
    func pathChanged() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let group = NIOTSEventLoopGroup(loopCount: 1)
        let channel = try await NIOTSConnectionBootstrap(group: group)
            .connect(host: "127.0.0.1", port: server.port)
            .get()
        let path = try await channel.getOption(NIOTSChannelOptions.currentPath).get()
        channel.close(promise: nil)
        group.shutdownGracefully { _ in }

        let mapped = TelnetNetworkEventMapping.telnetEvent(
            from: NIOTSNetworkEvents.PathChanged(newPath: path)
        )
        guard case .pathChanged(let viable, let expensive, let constrained) = mapped else {
            Issue.record("path change did not map")
            return
        }
        #expect(viable == (path.status == .satisfied))
        #expect(expensive == path.isExpensive)
        #expect(constrained == path.isConstrained)
    }

    @Test("an unrelated event is not mapped")
    func unrelatedEvent() {
        #expect(TelnetNetworkEventMapping.telnetEvent(from: "not a network event") == nil)
    }
}
