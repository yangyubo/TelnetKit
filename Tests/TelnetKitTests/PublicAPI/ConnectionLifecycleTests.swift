import Foundation
import Testing

import TelnetKit

@Suite("Connection lifecycle")
struct ConnectionLifecycleTests {
    @Test("a loopback connection succeeds and reports its addresses")
    func connectLoopbackSucceeds() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        #expect(await connection.isConnected)
        #expect(await connection.remoteAddress == "127.0.0.1:\(server.port)")
        #expect(await connection.localAddress != nil)
        await connection.close()
    }

    @Test("a greeting reaches the event stream as data")
    func greetingArrives() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        let (recorder, task) = recordEvents(connection.events)
        try await server.send(Array("hello\r\n".utf8))

        #expect(await recorder.waitFor { if case .data = $0 { return true } else { return false } })
        // The default NVT newline policy restores the peer's CR LF to a single LF.
        #expect(await recorder.events.compactMap(\.text).joined() == "hello\n")
        task.cancel()
        await connection.close()
    }

    @Test("a closed port reports connectionRefused")
    func connectRefused() async throws {
        await #expect(throws: TelnetError.connectionRefused(host: "127.0.0.1", port: 1)) {
            _ = try await TelnetConnection.connect(
                host: "127.0.0.1",
                port: 1,
                configuration: TelnetConfiguration(waitForConnectivity: false)
            )
        }
    }

    @Test("an unresolvable host reports invalidHost")
    func connectInvalidHost() async throws {
        await #expect(throws: TelnetError.invalidHost("no-such-host.invalid")) {
            _ = try await TelnetConnection.connect(
                host: "no-such-host.invalid",
                port: 23,
                configuration: TelnetConfiguration(waitForConnectivity: false)
            )
        }
    }

    @Test("invalid options are rejected before a socket opens")
    func connectInvalidConfiguration() async throws {
        let options = TelnetOptions(local: [.init(.binary), .init(.lineMode)])
        await #expect(throws: TelnetError.self) {
            _ = try await TelnetConnection.connect(host: "127.0.0.1", port: 1, options: options)
        }
    }

    @Test("close is idempotent and later calls throw notConnected")
    func closeIsIdempotent() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        await connection.close()
        await connection.close()
        #expect(await !connection.isConnected)

        await #expect(throws: TelnetError.notConnected) {
            try await connection.send(text: "after close")
        }
        await #expect(throws: TelnetError.notConnected) {
            try await connection.send([0x01])
        }
        await #expect(throws: TelnetError.notConnected) {
            try await connection.sendRaw([0x01])
        }
        await #expect(throws: TelnetError.notConnected) {
            try await connection.send(command: .noOperation)
        }
        await #expect(throws: TelnetError.notConnected) {
            try await connection.negotiate(.will, option: .echo)
        }
        await #expect(throws: TelnetError.notConnected) {
            try await connection.requestOption(.echo)
        }
        await #expect(throws: TelnetError.notConnected) {
            try await connection.subnegotiate(option: .windowSize, payload: [0, 80, 0, 24])
        }
        await #expect(throws: TelnetError.notConnected) {
            try await connection.replyTerminalType("xterm")
        }
        await #expect(throws: TelnetError.notConnected) {
            try await connection.sendEnvironment([EnvironmentVariable(name: "USER", value: "me")], scope: .variable)
        }
        await #expect(throws: TelnetError.notConnected) {
            try await connection.sendWindowSize(columns: 80, rows: 24)
        }
    }

    @Test("the event stream finishes when the peer closes")
    func eventsFinishOnRemoteClose() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        let streamFinished = StreamFinishFlag()
        let consumer = Task {
            for await _ in connection.events {}
            await streamFinished.markFinished()
        }
        try await server.disconnect()

        // The stream must finish instead of hanging.
        #expect(await waitUntil(timeout: .seconds(3)) { await streamFinished.isFinished })
        #expect(await !connection.isConnected)
        consumer.cancel()
    }

    @Test("optionStatus tracks a negotiation after the handshake")
    func optionStatusReflectsNegotiation() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let options = TelnetOptions(local: [.init(.echo)], remote: [.init(.echo)])
        let connection = try await connectToServer(server, options: options)

        // The connect-time WILL and DO are outstanding until the peer answers.
        let initial = await connection.optionStatus(.echo)
        #expect(initial.localRequested || initial.remoteRequested)

        // The peer answers DO ECHO and WILL ECHO.
        try await server.send([0xFF, 0xFD, 0x01, 0xFF, 0xFB, 0x01])

        let settled = await waitUntil {
            let status = await connection.optionStatus(.echo)
            return status.locallyEnabled && status.remotelyEnabled
                && !status.localRequested && !status.remoteRequested
        }
        #expect(settled)
        let untouched = await connection.optionStatus(TelnetOption(rawValue: 200))
        #expect(!untouched.locallyEnabled && !untouched.remotelyEnabled)
        #expect(!untouched.localRequested && !untouched.remoteRequested)
        await connection.close()
    }

    @Test("a cancelled send reports cancelled")
    func cancelledSend() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        // The fixture never reads, and the payload is far larger than the socket buffer,
        // so the write promise stays pending until cancellation.
        let payload = String(repeating: "x", count: 8 * 1024 * 1024)
        let task = Task {
            try await connection.send(text: payload)
        }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        do {
            try await task.value
            Issue.record("a cancelled send returned normally")
        } catch let error as TelnetError {
            #expect(error == .cancelled)
        }
        await connection.close()
    }
}
