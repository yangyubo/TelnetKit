/// A Telnet control command: a single byte in the 236...254 range.
///
/// The set is closed because RFC 854 and its successors fix it; an unrecognized command
/// byte in that range is a protocol violation rather than a new command. The four
/// negotiation verbs are present because a verb and a command share one wire encoding,
/// but a caller matches `.negotiation(_:option:remote:)` for them: the core never emits
/// `.command(.will)`, `.command(.wont)`, `.command(.do_)`, or `.command(.dont)`.
public enum TelnetCommand: UInt8, Sendable, Hashable, CaseIterable {
    case endOfFile = 236
    case suspend = 237
    case abort = 238
    case endOfRecord = 239
    case subnegotiationEnd = 240
    case noOperation = 241
    case dataMark = 242
    case brk = 243
    case interruptProcess = 244
    case abortOutput = 245
    case areYouThere = 246
    case eraseCharacter = 247
    case eraseLine = 248
    case goAhead = 249
    case subnegotiation = 250
    case will = 251
    case wont = 252
    case do_ = 253
    case dont = 254
}

/// One Telnet negotiation verb, with Swift spellings in place of the `WILL`/`WONT`/`DO`/
/// `DONT` macros.
public enum TelnetNegotiation: Sendable, Hashable, CaseIterable {
    case will
    case wont
    case `do`
    case dont
}

extension TelnetNegotiation {
    /// The wire byte for this verb. The mapping lives here so no C macro value reaches
    /// any other file.
    var wireCode: UInt8 {
        return switch self {
        case .will: 251
        case .wont: 252
        case .do: 253
        case .dont: 254
        }
    }

    /// The verb for a wire byte, or nil when the byte is not a negotiation verb.
    init?(wireCode: UInt8) {
        switch wireCode {
        case 251: self = .will
        case 252: self = .wont
        case 253: self = .do
        case 254: self = .dont
        default: return nil
        }
    }
}
