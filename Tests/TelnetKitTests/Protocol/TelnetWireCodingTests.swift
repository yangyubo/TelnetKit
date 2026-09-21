import Testing

@testable import TelnetKit

@Suite("TelnetWireCoding")
struct TelnetWireCodingTests {
    @Test("a CR LF pair counts as one ending")
    func crlfIsOneEnding() {
        #expect(
            TelnetWireCoding.applyLineEnding(Array("a\r\nb\n".utf8), ending: .crlf)
                == Array("a\r\nb\r\n".utf8)
        )
    }

    @Test("a lone CR becomes the configured ending")
    func loneCarriageReturn() {
        #expect(TelnetWireCoding.applyLineEnding([0x61, 0x0D, 0x62], ending: .crlf) == [0x61, 0x0D, 0x0A, 0x62])
        #expect(TelnetWireCoding.applyLineEnding([0x61, 0x0D, 0x62], ending: .lf) == [0x61, 0x0A, 0x62])
    }

    @Test("none leaves the text unchanged")
    func noneLeavesText() {
        #expect(TelnetWireCoding.applyLineEnding([0x61, 0x0D, 0x0A], ending: .none) == [0x61, 0x0D, 0x0A])
    }

    @Test("NAWS encodes width then height as big-endian pairs")
    func windowSize() {
        #expect(TelnetWireCoding.encodeWindowSize(columns: 0x0102, rows: 0x0304) == [0x01, 0x02, 0x03, 0x04])
        #expect(TelnetWireCoding.encodeWindowSize(columns: 255, rows: 40) == [0x00, 0xFF, 0x00, 0x28])
    }

    @Test("NEW-ENVIRON escapes the reserved bytes in names and values")
    func environmentEncoding() {
        let payload = TelnetWireCoding.encodeEnvironment(
            [EnvironmentVariable(name: "USER", value: "me", scope: .variable)],
            scope: .variable
        )
        #expect(payload == [0x00, 0x00] + Array("USER".utf8) + [0x01] + Array("me".utf8))

        let escaped = TelnetWireCoding.encodeEnvironment(
            [EnvironmentVariable(name: "A\u{02}B", value: nil, scope: .userVariable)],
            scope: .userVariable
        )
        #expect(escaped == [0x00, 0x03, 0x41, 0x02, 0x02, 0x42])
    }
}

@Suite("TelnetTruncationTracker")
struct TelnetTruncationTrackerTests {
    @Test("a complete sequence leaves nothing pending")
    func completeSequence() {
        var tracker = TelnetTruncationTracker()
        tracker.feed([0xFF, 0xFB, 0x01])
        #expect(tracker.truncatedSequence == nil)
    }

    @Test("an escaped IAC is not a pending sequence")
    func escapedIAC() {
        var tracker = TelnetTruncationTracker()
        tracker.feed([0x41, 0xFF, 0xFF, 0x42])
        #expect(tracker.truncatedSequence == nil)
    }

    @Test("a half negotiation keeps its bytes")
    func halfNegotiation() {
        var tracker = TelnetTruncationTracker()
        tracker.feed([0xFF, 0xFB])
        #expect(tracker.truncatedSequence == [0xFF, 0xFB])
    }

    @Test("an unfinished subnegotiation keeps its bytes")
    func halfSubnegotiation() {
        var tracker = TelnetTruncationTracker()
        tracker.feed([0xFF, 0xFA, 0x18, 0x01])
        #expect(tracker.truncatedSequence == [0xFF, 0xFA, 0x18, 0x01])
    }
}
