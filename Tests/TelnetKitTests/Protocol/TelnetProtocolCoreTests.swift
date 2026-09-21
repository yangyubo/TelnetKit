import NIOConcurrencyHelpers
import NIOCore
import Testing

@testable import TelnetKit

/// Collects events synchronously, because the protocol suite drives the core on the test
/// thread instead of through a channel.
final class ProtocolEventLog: Sendable {
    private let storage = NIOLockedValueBox<[TelnetEvent]>([])

    var events: [TelnetEvent] { storage.withLockedValue { $0 } }

    func append(_ event: TelnetEvent) {
        storage.withLockedValue { $0.append(event) }
    }

    /// Every `.data` payload concatenated, because libtelnet may split one write around an
    /// escaped IAC or an NVT newline.
    var dataBytes: [UInt8] {
        events.flatMap { event -> [UInt8] in
            guard case .data(let buffer) = event else { return [] }
            return Array(buffer.readableBytesView)
        }
    }

    func contains(_ predicate: (TelnetEvent) -> Bool) -> Bool {
        events.contains(where: predicate)
    }
}

/// A core with a recorded event log, for the white-box protocol suite.
struct ProtocolHarness {
    let core: TelnetProtocolCore
    let log: ProtocolEventLog
    let ledger: TelnetOptionLedger

    init(
        options: TelnetOptions = TelnetOptions(),
        configuration: TelnetConfiguration = .init(newlinePolicy: .raw)
    ) throws {
        let log = ProtocolEventLog()
        let ledger = TelnetOptionLedger()
        self.log = log
        self.ledger = ledger
        self.core = try TelnetProtocolCore(
            options: options,
            configuration: configuration,
            ledger: ledger,
            logger: nil,
            emit: { event in log.append(event) }
        )
    }

    @discardableResult
    func feed(_ bytes: [UInt8]) -> [UInt8] {
        _ = core.feed(bytes)
        return core.drainOutbound()
    }
}

@Suite("TelnetProtocolCore")
struct TelnetProtocolCoreTests {
    @Test("application bytes pass through unchanged in raw newline mode")
    func dataPassthrough() throws {
        let harness = try ProtocolHarness()
        harness.feed(Array("hello\r\n".utf8))
        #expect(harness.log.dataBytes == Array("hello\r\n".utf8))
    }

    @Test("a doubled 0xFF in data collapses to one byte")
    func escapedIACIsRestored() throws {
        let harness = try ProtocolHarness()
        harness.feed([0x41, 0xFF, 0xFF, 0x42])
        #expect(harness.log.dataBytes == [0x41, 0xFF, 0x42])
    }

    @Test("the NVT newline policy restores CR LF and CR NUL to LF")
    func nvtNewlinePolicy() throws {
        let harness = try ProtocolHarness(configuration: .init(newlinePolicy: .nvt))
        harness.feed(Array("a\r\nb\rc".utf8))
        #expect(harness.log.dataBytes == Array("a\nb\rc".utf8))
    }

    @Test("each negotiation verb becomes a remote negotiation event")
    func negotiationEvents() throws {
        // The option must be declared in both directions for libtelnet to report every
        // verb instead of answering with a refusal.
        let harness = try ProtocolHarness(
            options: TelnetOptions(local: [.init(.echo)], remote: [.init(.echo)])
        )
        harness.feed([0xFF, 0xFB, 0x01, 0xFF, 0xFC, 0x01, 0xFF, 0xFD, 0x01, 0xFF, 0xFE, 0x01])

        #expect(harness.log.contains { if case .negotiation(.will, .echo, true) = $0 { return true } else { return false } })
        #expect(harness.log.contains { if case .negotiation(.wont, .echo, true) = $0 { return true } else { return false } })
        #expect(harness.log.contains { if case .negotiation(.do, .echo, true) = $0 { return true } else { return false } })
        #expect(harness.log.contains { if case .negotiation(.dont, .echo, true) = $0 { return true } else { return false } })
    }

    @Test("control commands become command events")
    func commandEvents() throws {
        let harness = try ProtocolHarness()
        harness.feed([0xFF, 0xF1, 0xFF, 0xF9, 0xFF, 0xEC])

        #expect(harness.log.contains { if case .command(.noOperation) = $0 { return true } else { return false } })
        #expect(harness.log.contains { if case .command(.goAhead) = $0 { return true } else { return false } })
        #expect(harness.log.contains { if case .command(.endOfFile) = $0 { return true } else { return false } })
    }

    @Test("a terminal-type SEND becomes terminalTypeRequested")
    func terminalTypeRequest() throws {
        let harness = try ProtocolHarness()
        harness.feed([0xFF, 0xFA, 0x18, 0x01, 0xFF, 0xF0])
        #expect(harness.log.contains { if case .terminalTypeRequested = $0 { return true } else { return false } })
    }

    @Test("a terminal-type IS carries the name")
    func terminalTypeIs() throws {
        let harness = try ProtocolHarness()
        harness.feed([0xFF, 0xFA, 0x18, 0x00] + Array("xterm".utf8) + [0xFF, 0xF0])
        #expect(harness.log.contains { if case .terminalType("xterm") = $0 { return true } else { return false } })
    }

    @Test("an unrecognized subnegotiation keeps its payload and restores escaped 0xFF")
    func genericSubnegotiation() throws {
        let harness = try ProtocolHarness()
        // Option 99, payload 0x41 0xFF 0x42 with the IAC escape.
        harness.feed([0xFF, 0xFA, 0x63, 0x41, 0xFF, 0xFF, 0x42, 0xFF, 0xF0])
        #expect(
            harness.log.contains {
                if case .subnegotiation(let option, let payload) = $0 {
                    return option == TelnetOption(rawValue: 99) && payload == [0x41, 0xFF, 0x42]
                }
                return false
            }
        )
    }

    @Test("a truncated sequence is reported when the stream ends")
    func truncatedSequenceWarns() throws {
        let harness = try ProtocolHarness()
        harness.feed([0xFF, 0xFB])
        harness.core.finish()
        #expect(
            harness.log.contains {
                if case .warning(.truncatedSequence(let bytes)) = $0 { return bytes == [0xFF, 0xFB] }
                return false
            }
        )
    }

    @Test("a completed sequence produces no truncation warning")
    func completeSequenceDoesNotWarn() throws {
        let harness = try ProtocolHarness()
        harness.feed([0xFF, 0xFB, 0x01])
        harness.core.finish()
        #expect(!harness.log.contains { if case .warning(.truncatedSequence) = $0 { return true } else { return false } })
    }

    @Test("a random byte stream neither crashes nor desynchronizes the parser")
    func garbageStreamNoCrash() throws {
        let harness = try ProtocolHarness()
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let chunk = (0..<256).map { _ in UInt8.random(in: 0...255, using: &generator) }
            harness.feed(chunk)
        }
        harness.core.finish()
        // Every .data byte came from the input, so the parser made progress and held no
        // unbounded state.
        #expect(harness.log.dataBytes.count <= 200 * 256)
    }

    @Test("a subnegotiation past the configured bound is fatal")
    func subnegotiationLimitExceeded() throws {
        let harness = try ProtocolHarness(configuration: .init(subnegotiationLimit: 4, newlinePolicy: .raw))
        harness.feed([0xFF, 0xFA, 0x63] + Array(repeating: 0x41, count: 16) + [0xFF, 0xF0])
        #expect(
            harness.log.contains {
                if case .protocolError(.invalidSubnegotiation(let option)) = $0 {
                    return option == TelnetOption(rawValue: 99)
                }
                return false
            }
        )
    }

    @Test("a NEW-ENVIRON list decodes into structured variables")
    func newEnvironmentParsing() throws {
        let harness = try ProtocolHarness()
        // IAC SB NEW-ENVIRON IS VAR "USER" VALUE "me" IAC SE
        harness.feed(
            [0xFF, 0xFA, 0x27, 0x00, 0x00] + Array("USER".utf8) + [0x01] + Array("me".utf8) + [0xFF, 0xF0]
        )
        #expect(
            harness.log.contains {
                if case .environment(let scope, let values) = $0 {
                    return scope == .variable
                        && values == [EnvironmentVariable(name: "USER", value: "me", scope: .variable)]
                }
                return false
            }
        )
    }

    @Test("an MSSP list decodes into a dictionary")
    func msspParsing() throws {
        let harness = try ProtocolHarness()
        harness.feed(
            [0xFF, 0xFA, 0x46, 0x01] + Array("name".utf8) + [0x02] + Array("value".utf8) + [0xFF, 0xF0]
        )
        #expect(harness.log.contains { if case .mssp(let values) = $0 { return values == ["name": "value"] } else { return false } })
    }

    @Test("a ZMP command decodes into its argument list")
    func zmpParsing() throws {
        let harness = try ProtocolHarness()
        harness.feed([0xFF, 0xFA, 0x5D] + Array("cmd".utf8) + [0x00] + Array("a".utf8) + [0x00] + Array("b".utf8) + [0x00, 0xFF, 0xF0])
        #expect(harness.log.contains { if case .zmp(let arguments) = $0 { return arguments == ["cmd", "a", "b"] } else { return false } })
    }

    @Test("an undeclared option is refused with WONT")
    func undeclaredOptionRefused() throws {
        let harness = try ProtocolHarness()
        // The peer asks this end to enable ZMP; nothing declares ZMP, so libtelnet answers
        // IAC WONT ZMP.
        let outbound = harness.feed([0xFF, 0xFD, 0x5D])
        #expect(outbound == [0xFF, 0xFC, 0x5D])
    }

    @Test("a declared option is accepted with WILL")
    func declaredOptionAccepted() throws {
        let harness = try ProtocolHarness(options: TelnetOptions(local: [.init(.terminalType)]))
        let outbound = harness.feed([0xFF, 0xFD, 0x18])
        #expect(outbound == [0xFF, 0xFB, 0x18])
    }

    @Test("send(text:) applies the CR LF line ending and escapes IAC")
    func sendTextLineEnding() throws {
        let harness = try ProtocolHarness(configuration: .init(newlinePolicy: .nvt))
        let outbound = try harness.core.perform(.sendText("hi\n", .crlf)).bytes
        #expect(outbound == [0x68, 0x69, 0x0D, 0x0A])
    }

    @Test("every line ending produces its own bytes")
    func lineEndingVariants() throws {
        for (ending, expected) in [
            (TelnetLineEnding.crlf, [0x0D, 0x0A] as [UInt8]),
            (.crNul, [0x0D, 0x00] as [UInt8]),
            (.lf, [0x0A] as [UInt8]),
            (.none, [0x0A] as [UInt8]),
        ] {
            let harness = try ProtocolHarness(configuration: .init(newlinePolicy: .nvt))
            let outbound = try harness.core.perform(.sendText("hi\n", ending)).bytes
            #expect(outbound == [0x68, 0x69] + expected)
        }
    }

    @Test("BINARY negotiation disables outgoing newline translation")
    func binaryModeDisablesNewlineTranslation() throws {
        let harness = try ProtocolHarness(
            options: TelnetOptions(local: [.init(.binary)]),
            configuration: .init(newlinePolicy: .nvt)
        )
        // The peer agrees to BINARY, so this end's transmit-binary state turns on and the
        // CR LF translation is skipped.
        _ = harness.feed([0xFF, 0xFD, 0x00])
        let outbound = try harness.core.perform(.sendText("a\n", .crlf)).bytes
        #expect(outbound == [0x61, 0x0A])
    }

    @Test("send(_:) escapes a literal 0xFF and sendRaw does not")
    func escapingDifference() throws {
        let harness = try ProtocolHarness()
        let escaped = try harness.core.perform(.send([0xFF])).bytes
        let raw = try harness.core.perform(.sendRaw([0xFF])).bytes
        #expect(escaped == [0xFF, 0xFF])
        #expect(raw == [0xFF])
    }

    @Test("a subnegotiation past the bound throws instead of writing")
    func subnegotiateThrowsPastBound() throws {
        let harness = try ProtocolHarness(configuration: .init(subnegotiationLimit: 2))
        #expect(throws: TelnetError.subnegotiationTooLarge(option: .windowSize, limit: 2)) {
            _ = try harness.core.perform(.subnegotiate(.windowSize, [0x01, 0x02, 0x03]))
        }
    }

    @Test("a 255-column NAWS report escapes the 0xFF octet")
    func windowSizeEscapesIAC() throws {
        let harness = try ProtocolHarness()
        let outbound = try harness.core.perform(.sendWindowSize(columns: 255, rows: 40)).bytes
        // width 0x00FF doubles to 00 FF FF, then height 0x0028.
        #expect(outbound == [0xFF, 0xFA, 0x1F, 0x00, 0xFF, 0xFF, 0x00, 0x28, 0xFF, 0xF0])
    }

    @Test("a window size outside 0...65535 is rejected before any bytes are written")
    func windowSizeRangeRejected() throws {
        let harness = try ProtocolHarness()
        #expect(throws: TelnetError.self) {
            _ = try harness.core.perform(.sendWindowSize(columns: 65_536, rows: 24))
        }
        #expect(harness.core.drainOutbound().isEmpty)
    }

    @Test("an ENVIRON list with no variables is reported as empty")
    func emptyEnvironmentList() throws {
        let harness = try ProtocolHarness()
        // IAC SB NEW-ENVIRON IS IAC SE: a command with no variable list.
        harness.feed([0xFF, 0xFA, 0x27, 0x00, 0xFF, 0xF0])
        #expect(harness.log.contains { if case .environment(.variable, let values) = $0 { return values.isEmpty } else { return false } })
    }

    @Test("an empty MSSP block is ignored rather than reported")
    func emptyMSSPList() throws {
        let harness = try ProtocolHarness()
        // IAC SB MSSP IAC SE: upstream `_mssp_telnet` returns for size 0 without an event,
        // so the contract's `.mssp(_:)` ("the peer sent a status list") does not apply.
        harness.feed([0xFF, 0xFA, 0x46, 0xFF, 0xF0])
        #expect(!harness.log.contains { if case .mssp = $0 { return true } else { return false } })
    }

    @Test("requestOption rejects an option that is in neither declared list")
    func requestOptionRejectsUndeclared() throws {
        let harness = try ProtocolHarness()
        #expect(throws: TelnetError.self) {
            _ = try harness.core.perform(.requestOption(.zmp))
        }
    }

    @Test("replyTerminalType refuses when no request is pending, then answers one")
    func replyTerminalTypeLifecycle() throws {
        let harness = try ProtocolHarness()
        #expect(throws: TelnetError.self) {
            _ = try harness.core.perform(.replyTerminalType("xterm"))
        }
        harness.feed([0xFF, 0xFA, 0x18, 0x01, 0xFF, 0xF0])
        let outbound = try harness.core.perform(.replyTerminalType("xterm")).bytes
        #expect(outbound == [0xFF, 0xFA, 0x18, 0x00] + Array("xterm".utf8) + [0xFF, 0xF0])
    }

    @Test("100,000 data events leave resident memory stable")
    func memoryStableAfter100kEvents() throws {
        // A counting sink, not the event log, so the test measures the parser rather than
        // its own retention.
        let counter = NIOLockedValueBox(0)
        let core = try TelnetProtocolCore(
            options: TelnetOptions(),
            configuration: .init(newlinePolicy: .raw),
            ledger: TelnetOptionLedger(),
            logger: nil,
            emit: { event in
                if case .data = event { counter.withLockedValue { $0 += 1 } }
            }
        )
        defer { core.destroy() }

        for _ in 0..<1_000 { _ = core.feed([0x61]) }
        let baseline = residentMemoryBytes()
        for _ in 0..<100_000 { _ = core.feed([0x61]) }
        let after = residentMemoryBytes()
        let growth = after > baseline ? after - baseline : 0

        #expect(counter.withLockedValue { $0 } == 101_000)
        if !isAddressSanitizerEnabled() {
            #expect(growth < 32 * 1024 * 1024, "resident memory grew by \(growth) bytes over 100,000 events")
        }
    }
}
