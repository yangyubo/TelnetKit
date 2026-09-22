/// The wire vocabulary the echo server reads and writes.
///
/// The echo server is an independent peer: it links neither `TelnetKit` nor the pinned
/// libtelnet, so a defect in the library's parser cannot be mirrored by the fixture that is
/// supposed to catch it (PRD §9.1). This file therefore carries the server's own minimal model
/// of the protocol, and no value here is derived from the library; see `docs/architecture.md`.
///
/// The byte codes follow RFC 854, RFC 1091 (TERMINAL-TYPE), RFC 1073 (NAWS), and RFC 1572
/// (NEW-ENVIRON).
enum TelnetWire {
    // MARK: Commands

    /// Interpret As Command, the escape byte that introduces every sequence.
    static let iac: UInt8 = 0xFF
    static let se: UInt8 = 0xF0
    static let nop: UInt8 = 0xF1
    static let dataMark: UInt8 = 0xF2
    static let brk: UInt8 = 0xF3
    static let interruptProcess: UInt8 = 0xF4
    static let abortOutput: UInt8 = 0xF5
    static let areYouThere: UInt8 = 0xF6
    static let eraseCharacter: UInt8 = 0xF7
    static let eraseLine: UInt8 = 0xF8
    static let goAhead: UInt8 = 0xF9
    static let sb: UInt8 = 0xFA
    static let will: UInt8 = 0xFB
    static let wont: UInt8 = 0xFC
    static let doVerb: UInt8 = 0xFD
    static let dont: UInt8 = 0xFE

    // MARK: Options

    static let binary: UInt8 = 0
    static let echo: UInt8 = 1
    static let suppressGoAhead: UInt8 = 3
    static let terminalType: UInt8 = 24
    static let windowSize: UInt8 = 31
    static let newEnviron: UInt8 = 39

    // MARK: Subcommands

    static let terminalTypeIs: UInt8 = 0
    static let terminalTypeSend: UInt8 = 1
    static let environmentIs: UInt8 = 0
    static let environmentSend: UInt8 = 1
    static let environmentVar: UInt8 = 0
    static let environmentValue: UInt8 = 1
    static let environmentEsc: UInt8 = 2
    static let environmentUservar: UInt8 = 3

    // MARK: Frames

    /// A three-byte negotiation, `IAC <verb> <option>`.
    static func negotiation(_ verb: UInt8, _ option: UInt8) -> [UInt8] {
        [iac, verb, option]
    }

    /// A subnegotiation frame, `IAC SB <option> <payload> IAC SE`, with `0xFF` escaped.
    static func subnegotiation(_ option: UInt8, _ payload: [UInt8]) -> [UInt8] {
        [iac, sb, option] + escaping(payload) + [iac, se]
    }

    /// Doubles every `0xFF`, so the peer reads it back as one data byte.
    static func escaping(_ payload: [UInt8]) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(payload.count)
        for byte in payload {
            output.append(byte)
            if byte == iac { output.append(iac) }
        }
        return output
    }

    // MARK: Text for the log

    /// The display name of an option code, spelled as the library spells it so both peers'
    /// logs read the same way.
    static func name(of option: UInt8) -> String {
        switch option {
        case binary: "BINARY"
        case echo: "ECHO"
        case suppressGoAhead: "SGA"
        case terminalType: "TTYPE"
        case windowSize: "NAWS"
        case newEnviron: "NEW-ENVIRON"
        default: "option(\(option))"
        }
    }

    /// Renders peer-supplied bytes for the log: printable ASCII passes through, every other
    /// byte becomes `\xNN`, and the result is capped.
    ///
    /// The escaping and the cap are the point. The peer chooses these bytes, so without them a
    /// hostile peer could write terminal control sequences into the operator's terminal or
    /// stretch one log line without bound.
    static func printable(_ bytes: [UInt8], limit: Int = 64) -> String {
        var text = ""
        for byte in bytes.prefix(limit) {
            if (0x20...0x7E).contains(byte) {
                text.append(Character(UnicodeScalar(byte)))
            } else {
                text += "\\x" + hexPair(byte)
            }
        }
        if bytes.count > limit { text += "..." }
        return text
    }

    /// Renders a frame as hex, capped so an injected multi-kilobyte frame stays one line.
    static func describe(_ bytes: [UInt8], limit: Int = 24) -> String {
        let head = bytes.prefix(limit).map(hexPair).joined(separator: " ")
        return bytes.count > limit ? "\(head) ... (\(bytes.count) bytes)" : head
    }

    // MARK: NEW-ENVIRON

    /// The `name=value` pairs of a NEW-ENVIRON `IS` subnegotiation, capped at `limit`.
    ///
    /// RFC 1572 ends a field on the next VAR, USERVAR, or VALUE marker rather than on a NUL,
    /// and lets `ESC` protect a literal marker byte.
    static func environmentEntries(from payload: [UInt8], limit: Int = 8) -> [(name: String, value: String)] {
        guard payload.first == environmentIs else { return [] }
        var entries: [(name: String, value: String)] = []
        var index = payload.startIndex + 1
        while index < payload.endIndex, entries.count < limit {
            guard payload[index] == environmentVar || payload[index] == environmentUservar else { break }
            index += 1
            let name = environmentField(payload, index: &index)
            var value = ""
            if index < payload.endIndex, payload[index] == environmentValue {
                index += 1
                value = environmentField(payload, index: &index)
            }
            entries.append((name, value))
        }
        return entries
    }

    /// Reads one NEW-ENVIRON field, leaving `index` on the marker that ended it.
    private static func environmentField(_ payload: [UInt8], index: inout Int) -> String {
        var bytes: [UInt8] = []
        while index < payload.endIndex {
            let byte = payload[index]
            if byte == environmentVar || byte == environmentUservar || byte == environmentValue { break }
            index += 1
            if byte == environmentEsc, index < payload.endIndex {
                bytes.append(payload[index])
                index += 1
                continue
            }
            bytes.append(byte)
        }
        return printable(bytes, limit: 32)
    }

    private static func hexPair(_ byte: UInt8) -> String {
        String(byte >> 4, radix: 16, uppercase: true) + String(byte & 0x0F, radix: 16, uppercase: true)
    }
}
