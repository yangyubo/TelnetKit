import Foundation
import Testing

import TelnetKit

@Suite("Error handling")
struct ErrorHandlingTests {
    @Test("a warning leaves the session usable in both directions")
    func warningDoesNotClose() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        let (recorder, task) = recordEvents(connection.events)

        // An empty TERMINAL-TYPE subnegotiation makes libtelnet report a recoverable
        // warning instead of a fatal error.
        try await server.send([0xFF, 0xFA, 0x18, 0xFF, 0xF0])
        #expect(await recorder.waitFor { if case .warning = $0 { return true } else { return false } })
        #expect(await connection.isConnected)

        // The session still receives and sends after the warning.
        try await server.send(Array("PONG".utf8))
        #expect(await recorder.waitFor { $0.text == "PONG" })
        try await connection.send(text: "ping\n", lineEnding: .lf)
        #expect(await server.waitForReceivedBytes(5) == Array("ping\n".utf8))
        task.cancel()
        await connection.close()
    }

    @Test("a fatal protocol error closes the connection and finishes the stream")
    func protocolErrorCloses() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let configuration = TelnetConfiguration(subnegotiationLimit: 4, waitForConnectivity: false)
        let connection = try await connectToServer(server, configuration: configuration)
        let (recorder, task) = recordEvents(connection.events)

        try await server.send([0xFF, 0xFA, 0x63] + Array(repeating: 0x41, count: 16) + [0xFF, 0xF0])
        #expect(
            await recorder.waitFor(timeout: .seconds(3)) {
                if case .protocolError = $0 { return true } else { return false }
            }
        )
        #expect(await waitUntil(timeout: .seconds(3)) { await !connection.isConnected })
        #expect(await waitUntil(timeout: .seconds(3)) { await recorder.finished })

        // A call after the fatal error reports the closed connection.
        await #expect(throws: TelnetError.notConnected) {
            try await connection.send(text: "after failure")
        }
        task.cancel()
    }
}
