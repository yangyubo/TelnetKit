import Foundation
import Testing

import TelnetKit

@Suite("Sending")
struct SendingTests {
    @Test("send(_:) escapes a literal 0xFF")
    func sendEscapesIAC() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        try await connection.send([0x41, 0xFF, 0x42])
        #expect(await server.waitForReceivedBytes(4) == [0x41, 0xFF, 0xFF, 0x42])
        await connection.close()
    }

    @Test("send(text:) ends the line with CR LF")
    func sendTextCRLF() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        try await connection.send(text: "hi")
        #expect(await server.waitForReceivedBytes(2) == [0x68, 0x69])
        try await connection.send(text: "hi\n")
        #expect(await server.waitForReceivedBytes(6) == [0x68, 0x69, 0x68, 0x69, 0x0D, 0x0A])
        await connection.close()
    }

    @Test("each explicit line ending produces its bytes")
    func explicitLineEndings() async throws {
        let cases: [(TelnetLineEnding, [UInt8])] = [
            (.crlf, [0x0D, 0x0A]),
            (.crNul, [0x0D, 0x00]),
            (.lf, [0x0A]),
            (.none, [0x0A]),
        ]
        for (ending, expected) in cases {
            let server = try await TestServer.start()
            let connection = try await connectToServer(server)
            try await connection.send(text: "hi\n", lineEnding: ending)
            #expect(await server.waitForReceivedBytes(2 + expected.count) == [0x68, 0x69] + expected)
            await connection.close()
            await server.stop()
        }
    }

    @Test("sendRaw sends bytes without escaping")
    func sendRawDoesNotEscape() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        try await connection.sendRaw([0xFF])
        #expect(await server.waitForReceivedBytes(1) == [0xFF])
        await connection.close()
    }

    @Test("send(command:) writes IAC and the command byte")
    func sendCommand() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        try await connection.send(command: .areYouThere)
        #expect(await server.waitForReceivedBytes(2) == [0xFF, 0xF6])
        await connection.close()
    }

    @Test("subnegotiate wraps the payload in IAC SB and IAC SE")
    func subnegotiate() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        try await connection.subnegotiate(option: .windowSize, payload: [0x00, 0x50, 0x00, 0x18])
        #expect(
            await server.waitForReceivedBytes(9)
                == [0xFF, 0xFA, 0x1F, 0x00, 0x50, 0x00, 0x18, 0xFF, 0xF0]
        )
        await connection.close()
    }

    @Test("a payload past the configured bound throws subnegotiationTooLarge")
    func subnegotiateTooLarge() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let configuration = TelnetConfiguration(subnegotiationLimit: 2, waitForConnectivity: false)
        let connection = try await connectToServer(server, configuration: configuration)
        await #expect(throws: TelnetError.subnegotiationTooLarge(option: .windowSize, limit: 2)) {
            try await connection.subnegotiate(option: .windowSize, payload: [0x01, 0x02, 0x03])
        }
        await connection.close()
    }

    @Test("sendWindowSize sends the four big-endian NAWS bytes")
    func sendWindowSize() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        try await connection.sendWindowSize(columns: 80, rows: 24)
        #expect(
            await server.waitForReceivedBytes(9)
                == [0xFF, 0xFA, 0x1F, 0x00, 0x50, 0x00, 0x18, 0xFF, 0xF0]
        )
        await connection.close()
    }

    @Test("a window dimension outside 0...65535 is rejected")
    func sendWindowSizeRange() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        await #expect(throws: TelnetError.self) {
            try await connection.sendWindowSize(columns: 70_000, rows: 24)
        }
        await connection.close()
    }

    @Test("sendEnvironment emits a NEW-ENVIRON IS payload")
    func sendEnvironment() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        try await connection.sendEnvironment(
            [EnvironmentVariable(name: "USER", value: "me", scope: .variable)],
            scope: .variable
        )
        let expected: [UInt8] =
            [0xFF, 0xFA, 0x27, 0x00, 0x00] + Array("USER".utf8) + [0x01] + Array("me".utf8) + [0xFF, 0xF0]
        #expect(await server.waitForReceivedBytes(expected.count) == expected)
        await connection.close()
    }

    @Test("negotiate reports whether libtelnet sent the verb")
    func negotiateResult() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        #expect(try await connection.negotiate(.will, option: .echo))
        #expect(await server.waitForReceivedBytes(3) == [0xFF, 0xFB, 0x01])
        // RFC 1143 makes a repeated WILL redundant, so libtelnet suppresses it.
        #expect(try await connection.negotiate(.will, option: .echo) == false)
        await connection.close()
    }

    @Test("requestOption chooses will for a local option and do for a remote one")
    func requestOptionDirection() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        // Neither option is negotiated at connect time, so each request produces bytes.
        let options = TelnetOptions(
            local: [.init(.echo, enabledByDefault: false)],
            remote: [.init(.suppressGoAhead, requestOnConnect: false)]
        )
        let connection = try await connectToServer(server, options: options)
        _ = await server.waitForReceivedBytes(1)

        try await connection.requestOption(.echo)
        #expect(await server.waitForReceivedBytes(3).suffix(3) == [0xFF, 0xFB, 0x01])

        try await connection.requestOption(.suppressGoAhead)
        #expect(await server.waitForReceivedBytes(6).suffix(3) == [0xFF, 0xFD, 0x03])
        await connection.close()
    }

    @Test("requestOption rejects an option that was never declared")
    func requestOptionUndeclared() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        await #expect(throws: TelnetError.self) {
            try await connection.requestOption(.zmp)
        }
        await connection.close()
    }

    @Test("replyTerminalType answers a pending request and otherwise throws")
    func replyTerminalType() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        await #expect(throws: TelnetError.self) {
            try await connection.replyTerminalType("xterm")
        }

        try await server.send([0xFF, 0xFA, 0x18, 0x01, 0xFF, 0xF0])
        let (recorder, task) = recordEvents(connection.events)
        #expect(await recorder.waitFor { if case .terminalTypeRequested = $0 { return true } else { return false } })

        try await connection.replyTerminalType("xterm")
        let expected: [UInt8] = [0xFF, 0xFA, 0x18, 0x00] + Array("xterm".utf8) + [0xFF, 0xF0]
        #expect(await server.waitForReceivedBytes(expected.count) == expected)
        task.cancel()
        await connection.close()
    }
}
