import Foundation
import Testing

import TelnetKit

@Suite("Event delivery")
struct EventDeliveryTests {
    @Test("peer data arrives as a data event with bytes and text")
    func dataEvent() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        let (recorder, task) = recordEvents(connection.events)
        try await server.send(Array("hello".utf8))

        #expect(await recorder.waitFor { $0.text == "hello" })
        let dataEvent = await recorder.events.first { if case .data = $0 { return true } else { return false } }
        #expect(dataEvent?.bytes == Array("hello".utf8))
        task.cancel()
        await connection.close()
    }

    @Test("a peer negotiation arrives with localEchoChanged alongside it")
    func negotiationAndLocalEcho() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let options = TelnetOptions(remote: [.init(.echo)])
        let connection = try await connectToServer(server, options: options)
        let (recorder, task) = recordEvents(connection.events)

        try await server.send([0xFF, 0xFB, 0x01])
        #expect(
            await recorder.waitFor {
                if case .negotiation(.will, .echo, true) = $0 { return true } else { return false }
            }
        )
        // The peer echoes, so the local end must not.
        #expect(await recorder.waitFor { if case .localEchoChanged(false) = $0 { return true } else { return false } })

        try await server.send([0xFF, 0xFC, 0x01])
        // The peer stops echoing, so the local end must.
        #expect(await recorder.waitFor { if case .localEchoChanged(true) = $0 { return true } else { return false } })
        task.cancel()
        await connection.close()
    }

    @Test("a control command arrives as a command event")
    func commandEvent() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        let (recorder, task) = recordEvents(connection.events)
        try await server.send([0xFF, 0xF1])
        #expect(await recorder.waitFor { if case .command(.noOperation) = $0 { return true } else { return false } })
        task.cancel()
        await connection.close()
    }

    @Test("a terminal-type IS arrives with its name")
    func terminalTypeEvent() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        let (recorder, task) = recordEvents(connection.events)
        try await server.send([0xFF, 0xFA, 0x18, 0x00] + Array("xterm".utf8) + [0xFF, 0xF0])
        #expect(await recorder.waitFor { if case .terminalType("xterm") = $0 { return true } else { return false } })
        task.cancel()
        await connection.close()
    }

    @Test("an environment SEND arrives as environmentRequested")
    func environmentRequestedEvent() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        let (recorder, task) = recordEvents(connection.events)
        try await server.send([0xFF, 0xFA, 0x27, 0x01, 0xFF, 0xF0])
        #expect(await recorder.waitFor { if case .environmentRequested(.variable) = $0 { return true } else { return false } })
        task.cancel()
        await connection.close()
    }

    @Test("an environment list arrives as structured variables")
    func environmentEvent() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        let (recorder, task) = recordEvents(connection.events)
        try await server.send(
            [0xFF, 0xFA, 0x27, 0x00, 0x00] + Array("USER".utf8) + [0x01] + Array("me".utf8) + [0xFF, 0xF0]
        )
        #expect(
            await recorder.waitFor {
                if case .environment(let scope, let values) = $0 {
                    return scope == .variable
                        && values == [EnvironmentVariable(name: "USER", value: "me", scope: .variable)]
                }
                return false
            }
        )
        task.cancel()
        await connection.close()
    }

    @Test("an MSSP list arrives as a dictionary")
    func msspEvent() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        let (recorder, task) = recordEvents(connection.events)
        try await server.send(
            [0xFF, 0xFA, 0x46, 0x01] + Array("name".utf8) + [0x02] + Array("value".utf8) + [0xFF, 0xF0]
        )
        #expect(await recorder.waitFor { if case .mssp(let values) = $0 { return values == ["name": "value"] } else { return false } })
        task.cancel()
        await connection.close()
    }

    @Test("a ZMP command arrives as an argument list")
    func zmpEvent() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        let (recorder, task) = recordEvents(connection.events)
        try await server.send(
            [0xFF, 0xFA, 0x5D] + Array("cmd".utf8) + [0x00] + Array("a".utf8) + [0x00]
                + Array("b".utf8) + [0x00, 0xFF, 0xF0]
        )
        #expect(await recorder.waitFor { if case .zmp(let arguments) = $0 { return arguments == ["cmd", "a", "b"] } else { return false } })
        task.cancel()
        await connection.close()
    }

    @Test("an unrecognized subnegotiation keeps its payload")
    func subnegotiationEvent() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        let (recorder, task) = recordEvents(connection.events)
        try await server.send([0xFF, 0xFA, 0x63, 0x41, 0x42, 0xFF, 0xF0])
        #expect(
            await recorder.waitFor {
                if case .subnegotiation(let option, let payload) = $0 {
                    return option == TelnetOption(rawValue: 99) && payload == [0x41, 0x42]
                }
                return false
            }
        )
        task.cancel()
        await connection.close()
    }

    @Test("a truncated sequence at close becomes a warning and finishes the stream")
    func truncatedWarning() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        let (recorder, task) = recordEvents(connection.events)
        try await server.send([0xFF, 0xFB])
        try await server.disconnect()

        #expect(
            await recorder.waitFor(timeout: .seconds(3)) {
                if case .warning(.truncatedSequence(let bytes)) = $0 { return bytes == [0xFF, 0xFB] }
                return false
            }
        )
        task.cancel()
    }

    @Test("an oversized subnegotiation becomes a fatal protocol error")
    func oversizedSubnegotiation() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let configuration = TelnetConfiguration(subnegotiationLimit: 4, waitForConnectivity: false)
        let connection = try await connectToServer(server, configuration: configuration)
        let (recorder, task) = recordEvents(connection.events)

        try await server.send([0xFF, 0xFA, 0x63] + Array(repeating: 0x41, count: 16) + [0xFF, 0xF0])
        #expect(
            await recorder.waitFor(timeout: .seconds(3)) {
                if case .protocolError(.invalidSubnegotiation(let option)) = $0 {
                    return option == TelnetOption(rawValue: 99)
                }
                return false
            }
        )
        #expect(await waitUntil(timeout: .seconds(3)) { await !connection.isConnected })
        task.cancel()
    }

    @Test("COMPRESS2 is refused and leaves compression status all-false")
    func compress2Refused() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        try await server.send([0xFF, 0xFD, 0x56])
        #expect(await server.waitForReceivedBytes(3) == [0xFF, 0xFC, 0x56])

        let status = await connection.optionStatus(.compress2)
        #expect(!status.locallyEnabled && !status.remotelyEnabled)
        #expect(!status.localRequested && !status.remoteRequested)
        await connection.close()
    }
}
