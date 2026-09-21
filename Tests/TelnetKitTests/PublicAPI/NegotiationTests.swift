import Foundation
import Testing

import TelnetKit

@Suite("Negotiation")
struct NegotiationTests {
    @Test("connect sends the declared initial negotiation before the caller acts")
    func initialNegotiationSentOnConnect() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server, options: .standardClient)

        // One verb per declared entry: the three local options in order, then the remote
        // one, each as IAC <verb> <option>.
        let expected: [UInt8] = [
            0xFF, 0xFB, 0x00,  // IAC WILL BINARY
            0xFF, 0xFB, 0x03,  // IAC WILL SGA
            0xFF, 0xFB, 0x01,  // IAC WILL ECHO
            0xFF, 0xFD, 0x03,  // IAC DO SGA
        ]
        #expect(await server.waitForReceivedBytes(expected.count) == expected)
        await connection.close()
    }

    @Test("simultaneous and repeated negotiation settles into a bounded byte count")
    func rfc1143NoNegotiationLoop() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        // Echo declared in both directions, so the client offers WILL and asks for DO at
        // connect time and the same verbs arrive from the peer.
        let options = TelnetOptions(local: [.init(.echo)], remote: [.init(.echo)])
        let connection = try await connectToServer(server, options: options)
        #expect(await server.waitForReceivedBytes(6) == [0xFF, 0xFB, 0x01, 0xFF, 0xFD, 0x01])

        let (recorder, task) = recordEvents(connection.events)
        for _ in 0..<5 {
            try await server.send([0xFF, 0xFB, 0x01, 0xFF, 0xFD, 0x01])
        }
        // A data marker sent after the negotiations is parsed after them, so seeing it
        // proves the client finished with the repeated verbs without a fixed sleep.
        try await server.send(Array("PING".utf8))
        #expect(await recorder.waitFor { $0.text == "PING" })

        // RFC 1143 answers each verb once: the client's connect-time WILL and DO stay the
        // only bytes it sends, so the exchange cannot loop.
        #expect(server.receivedBytes == [0xFF, 0xFB, 0x01, 0xFF, 0xFD, 0x01])
        task.cancel()
        await connection.close()
    }

    @Test("a repeated terminal-type request is answered each time")
    func repeatedTerminalTypeRequests() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        let (recorder, task) = recordEvents(connection.events)
        let isRequest: @Sendable (TelnetEvent) -> Bool = {
            if case .terminalTypeRequested = $0 { return true } else { return false }
        }

        for index in 1...2 {
            try await server.send([0xFF, 0xFA, 0x18, 0x01, 0xFF, 0xF0])  // IAC SB TTYPE SEND IAC SE
            #expect(await recorder.waitFor(count: index, isRequest))
            try await connection.replyTerminalType("xterm")
        }

        let reply: [UInt8] = [0xFF, 0xFA, 0x18, 0x00] + Array("xterm".utf8) + [0xFF, 0xF0]
        #expect(await server.waitForReceivedBytes(reply.count * 2) == reply + reply)
        task.cancel()
        await connection.close()
    }
}
