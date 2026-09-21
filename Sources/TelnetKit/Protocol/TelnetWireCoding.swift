/// Byte-level coding that is independent of libtelnet's state machine.
///
/// The core owns every `telnet_*` call; this type owns the transformations the library
/// performs on the byte arrays it hands to those calls, so a coding rule can be tested as
/// a pure function.
enum TelnetWireCoding {
    /// The Telnet "interpret as command" octet.
    static let iac: UInt8 = 0xFF
    private static let cr: UInt8 = 0x0D
    private static let nul: UInt8 = 0x00
    private static let lf: UInt8 = 0x0A

    /// Rewrites every line ending in `bytes` to `ending`.
    ///
    /// A carriage return followed by a line feed counts as one ending, so text that
    /// already carries CR LF does not gain a second carriage return. `.none` leaves the
    /// bytes untouched.
    static func applyLineEnding(_ bytes: [UInt8], ending: TelnetLineEnding) -> [UInt8] {
        guard ending != .none, bytes.contains(cr) || bytes.contains(lf) else { return bytes }
        let replacement: [UInt8] = switch ending {
        case .crlf: [cr, lf]
        case .crNul: [cr, nul]
        case .lf: [lf]
        case .none: []
        }

        var out: [UInt8] = []
        out.reserveCapacity(bytes.count + 8)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == cr {
                if index + 1 < bytes.count, bytes[index + 1] == lf {
                    index += 2
                } else {
                    index += 1
                }
                out.append(contentsOf: replacement)
            } else if byte == lf {
                index += 1
                out.append(contentsOf: replacement)
            } else {
                out.append(byte)
                index += 1
            }
        }
        return out
    }

    /// NAWS payload: width then height, each a 16-bit big-endian value.
    ///
    /// The caller validates the range; libtelnet escapes a `0xFF` octet when it writes the
    /// subnegotiation.
    static func encodeWindowSize(columns: Int, rows: Int) -> [UInt8] {
        [
            UInt8((columns >> 8) & 0xFF), UInt8(columns & 0xFF),
            UInt8((rows >> 8) & 0xFF), UInt8(rows & 0xFF),
        ]
    }

    /// NEW-ENVIRON `IS` payload for a variable list.
    ///
    /// The escape octet is doubled around every reserved byte so the peer's parser
    /// recovers the original name and value. libtelnet escapes a literal `0xFF` when it
    /// writes the subnegotiation, so only the NEW-ENVIRON reserved bytes are handled here.
    static func encodeEnvironment(_ values: [EnvironmentVariable], scope: EnvironmentScope) -> [UInt8] {
        let variableType: UInt8 = scope == .variable ? 0x00 : 0x03
        var out: [UInt8] = [0x00]
        for value in values {
            out.append(variableType)
            out.append(contentsOf: escapedEnvironmentBytes(Array(value.name.utf8)))
            if let value = value.value {
                out.append(0x01)
                out.append(contentsOf: escapedEnvironmentBytes(Array(value.utf8)))
            }
        }
        return out
    }

    private static func escapedEnvironmentBytes(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        for byte in bytes {
            if byte <= 0x03 { out.append(0x02) }
            out.append(byte)
        }
        return out
    }
}
