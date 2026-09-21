import Foundation
import TelnetKit
import Testing

/// Connects to a fixture on the loopback address with connectivity waiting off, so a test
/// never parks on a route that the sandbox does not have.
func connectToServer(
    _ server: TestServer,
    options: TelnetOptions = TelnetOptions(),
    configuration: TelnetConfiguration = TelnetConfiguration(waitForConnectivity: false)
) async throws(TelnetError) -> TelnetConnection {
    try await TelnetConnection.connect(
        host: "127.0.0.1",
        port: server.port,
        options: options,
        configuration: configuration
    )
}

/// Polls `predicate` until it is true or the bound expires.
func waitUntil(
    timeout: Duration = .seconds(2),
    _ predicate: @Sendable () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await predicate() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await predicate()
}
