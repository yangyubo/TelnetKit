import CLibTelnet
import Logging
import Testing

@testable import TelnetKit

@Suite("Logging")
struct LoggingTests {
    @Test("a configured logger captures info, debug, trace, and error")
    func loggerCategories() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let logs = RecordingLogHandler()
        // A tiny inbound bound lets the test reach the error category deterministically.
        let configuration = TelnetConfiguration(
            inboundBufferLimit: 16,
            subnegotiationLimit: 100_000,
            waitForConnectivity: false,
            logger: Logger(label: "test", factory: { _ in logs })
        )
        let options = TelnetOptions(remote: [.init(.echo)])
        let connection = try await connectToServer(server, options: options, configuration: configuration)

        // debug: the peer's accepted negotiation; trace: the outbound frame.
        try await server.send([0xFF, 0xFB, 0x01])
        try await connection.send(text: "hi")
        #expect(await waitUntil(timeout: .seconds(3)) { logs.levels.contains(.debug) })
        #expect(logs.levels.contains(.trace))

        // error: an inbound block past the bound closes the connection.
        try await server.send([0xFF, 0xFA, 0x63] + Array(repeating: 0x41, count: 64) + [0xFF, 0xF0])
        #expect(await waitUntil(timeout: .seconds(3)) { logs.levels.contains(.error) })

        // info: the connection lifecycle, logged when the channel became active.
        #expect(logs.levels.contains(.info))
    }

    @Test("payload bytes never reach the log")
    func loggerRedactsPayload() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        let logs = RecordingLogHandler()
        let configuration = TelnetConfiguration(
            waitForConnectivity: false,
            logger: Logger(label: "test", factory: { _ in logs })
        )
        let connection = try await connectToServer(server, configuration: configuration)
        try await connection.send(text: "SECRET-TOKEN")
        try await server.send(Array("PEER-SECRET".utf8))

        #expect(await waitUntil(timeout: .seconds(3)) { logs.levels.contains(.trace) })
        #expect(!logs.allText.contains("SECRET"))
        #expect(!logs.records.isEmpty)
        await connection.close()
    }

    @Test("every libtelnet error code maps to a Swift code without a crash")
    func errorCodeMappingExhaustive() {
        let values: [telnet_error_t] = [
            TELNET_EOK,
            TELNET_EBADVAL,
            TELNET_ENOMEM,
            TELNET_EOVERFLOW,
            TELNET_EPROTOCOL,
            TELNET_ECOMPRESS,
        ]
        let mapped = values.compactMap { TelnetErrorCodeMapping.code(for: $0) }
        #expect(Set(mapped) == Set(TelnetErrorCode.allCases))
        #expect(TelnetErrorCodeMapping.code(for: TELNET_EOK) == nil)
    }
}
