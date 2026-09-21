import Foundation
import Testing

import TelnetKit

/// Starts `count` independent loopback fixtures.
func startServers(count: Int) async throws -> [TestServer] {
    var servers: [TestServer] = []
    for _ in 0..<count {
        servers.append(try await TestServer.start())
    }
    return servers
}

@Suite("Concurrency and resources")
struct ConcurrencyTests {
    @Test("concurrent connections keep their bytes to themselves")
    func concurrentConnectionsAreIsolated() async throws {
        let count = 4
        let servers = try await startServers(count: count)
        defer { Task { for server in servers { await server.stop() } } }

        let payloads = (0..<count).map { Array("connection-\($0)\n".utf8) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<count {
                let server = servers[index]
                let payload = payloads[index]
                group.addTask {
                    let connection = try await connectToServer(server)
                    try await connection.send(payload)
                    _ = await server.waitForReceivedBytes(payload.count)
                    await connection.close()
                }
            }
            try await group.waitForAll()
        }

        for index in 0..<count {
            #expect(await servers[index].waitForReceivedBytes(payloads[index].count) == payloads[index])
        }
    }

    @Test("concurrent sends arrive intact and in a serialized order")
    func concurrentSendsSerialize() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let connection = try await connectToServer(server)
        let lines = (0..<100).map { "line-\($0)" }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for line in lines {
                group.addTask {
                    try await connection.send(text: line + "\n", lineEnding: .lf)
                }
            }
            try await group.waitForAll()
        }

        let expected = lines.reduce(into: [UInt8]()) { $0 += Array(($1 + "\n").utf8) }
        let received = await server.waitForReceivedBytes(expected.count, timeout: .seconds(5))
        #expect(received.count == expected.count)
        // Every line arrives whole; the actor serializes concurrent sends, so the order is
        // the order the actor received them rather than the order the tasks were created.
        let receivedLines = String(decoding: received, as: UTF8.self).split(separator: "\n").map(String.init)
        #expect(receivedLines.sorted() == lines.sorted())
        await connection.close()
    }

    @Test("an idle connection closes and finishes its stream")
    func idleTimeoutCloses() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let configuration = TelnetConfiguration(idleTimeout: .seconds(1), waitForConnectivity: false)
        let connection = try await connectToServer(server, configuration: configuration)
        #expect(await waitUntil(timeout: .seconds(4)) { await !connection.isConnected })
    }

    @Test("inbound bytes without a data event hit the buffer bound")
    func inboundBufferLimitEnforced() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let configuration = TelnetConfiguration(
            inboundBufferLimit: 8,
            subnegotiationLimit: 100_000,
            waitForConnectivity: false
        )
        let connection = try await connectToServer(server, configuration: configuration)
        let (recorder, task) = recordEvents(connection.events)

        // A long subnegotiation produces no data event, so the inbound bound is what stops
        // it before the much larger subnegotiation bound would.
        try await server.send([0xFF, 0xFA, 0x63] + Array(repeating: 0x41, count: 64) + [0xFF, 0xF0])

        #expect(
            await recorder.waitFor(timeout: .seconds(3)) {
                if case .protocolError(.stateMachineFailure(code: .overflow, _)) = $0 { return true }
                return false
            }
        )
        #expect(await waitUntil(timeout: .seconds(3)) { await !connection.isConnected })
        task.cancel()
    }
}
