/// A Telnet option, identified by its 8-bit RFC code.
///
/// `TelnetOption` is a `RawRepresentable` struct with static constants rather than an
/// `enum`: Telnet assigns over 250 option codes and libtelnet accepts any of them, so a
/// closed enum would have to model codes this release does not know while still allowing
/// traversal of the modeled set. Any code stays constructible through
/// `init(rawValue:)` and renders through `displayName`.
public struct TelnetOption: RawRepresentable, Sendable, Hashable, CaseIterable {
    /// The RFC option code.
    public let rawValue: UInt8

    /// Creates an option from its RFC code, modeled or not.
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// The binary transmission option (RFC 856), code 0.
    public static let binary = TelnetOption(rawValue: 0)
    /// The echo option (RFC 857), code 1.
    public static let echo = TelnetOption(rawValue: 1)
    /// The suppress-go-ahead option (RFC 858), code 3.
    public static let suppressGoAhead = TelnetOption(rawValue: 3)
    /// The status option (RFC 859), code 5.
    public static let status = TelnetOption(rawValue: 5)
    /// The timing-mark option (RFC 860), code 6.
    public static let timingMark = TelnetOption(rawValue: 6)
    /// The terminal-type option (RFC 1091), code 24.
    public static let terminalType = TelnetOption(rawValue: 24)
    /// The end-of-record option (RFC 885), code 25.
    public static let endOfRecord = TelnetOption(rawValue: 25)
    /// The window-size option (RFC 1073), code 31.
    public static let windowSize = TelnetOption(rawValue: 31)
    /// The terminal-speed option (RFC 1079), code 32.
    public static let terminalSpeed = TelnetOption(rawValue: 32)
    /// The remote-flow-control option (RFC 1372), code 33.
    public static let remoteFlowControl = TelnetOption(rawValue: 33)
    /// The line-mode option (RFC 1184), code 34.
    public static let lineMode = TelnetOption(rawValue: 34)
    /// The environment option (RFC 1408), code 36.
    public static let environment = TelnetOption(rawValue: 36)
    /// The new-environment option (RFC 1572), code 39.
    public static let newEnvironment = TelnetOption(rawValue: 39)
    /// The MSSP option (RFC 859/860), code 70.
    public static let mssp = TelnetOption(rawValue: 70)
    /// The COMPRESS option (RFC 1073 successor), code 85.
    public static let compress = TelnetOption(rawValue: 85)
    /// The COMPRESS2 option (MCCP2), code 86.
    public static let compress2 = TelnetOption(rawValue: 86)
    /// The ZMP option, code 93.
    public static let zmp = TelnetOption(rawValue: 93)
    /// The extended-options-list option (RFC 861), code 255.
    public static let extendedOptionsList = TelnetOption(rawValue: 255)

    /// The modeled options, for display and test traversal.
    public static var allCases: [TelnetOption] {
        [
            .binary, .echo, .suppressGoAhead, .status, .timingMark, .terminalType,
            .endOfRecord, .windowSize, .terminalSpeed, .remoteFlowControl, .lineMode,
            .environment, .newEnvironment, .mssp, .compress, .compress2, .zmp,
            .extendedOptionsList,
        ]
    }

    /// A human-readable name. A code with no constant renders as `option(<code>)`.
    public var displayName: String {
        return switch self {
        case .binary: "binary"
        case .echo: "echo"
        case .suppressGoAhead: "suppressGoAhead"
        case .status: "status"
        case .timingMark: "timingMark"
        case .terminalType: "terminalType"
        case .endOfRecord: "endOfRecord"
        case .windowSize: "windowSize"
        case .terminalSpeed: "terminalSpeed"
        case .remoteFlowControl: "remoteFlowControl"
        case .lineMode: "lineMode"
        case .environment: "environment"
        case .newEnvironment: "newEnvironment"
        case .mssp: "mssp"
        case .compress: "compress"
        case .compress2: "compress2"
        case .zmp: "zmp"
        case .extendedOptionsList: "extendedOptionsList"
        default: "option(\(rawValue))"
        }
    }
}

/// The negotiation state of one option, in both directions.
///
/// An option the peer and this end never mentioned reports every field false. The value
/// is derived from observed `will`, `wont`, `do`, and `dont` negotiations, never read
/// from libtelnet's internal state, which the library does not export.
public struct TelnetOptionStatus: Sendable, Hashable {
    /// This end sent `will` and the peer answered `do`.
    public var locallyEnabled: Bool = false
    /// The peer sent `will` and this end answered `do`.
    public var remotelyEnabled: Bool = false
    /// A `will` or `wont` from this end is outstanding.
    public var localRequested: Bool = false
    /// A `do` or `dont` from this end is outstanding.
    public var remoteRequested: Bool = false
}
