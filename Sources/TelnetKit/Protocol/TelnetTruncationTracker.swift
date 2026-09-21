/// Reports whether the fed byte stream currently ends inside an incomplete `IAC`
/// sequence.
///
/// libtelnet keeps a partial sequence in its own buffer across calls and reports nothing,
/// so a sequence cut off by the peer closing the connection would otherwise be invisible.
/// The tracker observes the same bytes only to name the dangling suffix as a
/// `.warning(.truncatedSequence(_:))` at end of stream; it never drives protocol behavior,
/// which stays with `telnet_recv` and the event callback.
struct TelnetTruncationTracker {
    private enum State {
        case data
        case iac
        case negotiation
        case subnegotiation
        case subnegotiationIAC
    }

    private var state: State = .data
    private var pending: [UInt8] = []

    /// The bytes held by an incomplete sequence, or nil when the stream ended on a
    /// boundary.
    var truncatedSequence: [UInt8]? {
        state == .data ? nil : pending
    }

    mutating func feed(_ bytes: [UInt8]) {
        for byte in bytes {
            switch state {
            case .data:
                if byte == TelnetWireCoding.iac {
                    state = .iac
                    pending = [byte]
                }
            case .iac:
                append(byte)
                switch byte {
                case TelnetWireCoding.iac:
                    finishSequence()
                case 250:
                    state = .subnegotiation
                case 251, 252, 253, 254:
                    state = .negotiation
                default:
                    finishSequence()
                }
            case .negotiation:
                append(byte)
                finishSequence()
            case .subnegotiation:
                append(byte)
                if byte == TelnetWireCoding.iac { state = .subnegotiationIAC }
            case .subnegotiationIAC:
                append(byte)
                if byte == 240 {
                    finishSequence()
                } else {
                    state = .subnegotiation
                }
            }
        }
    }

    private mutating func append(_ byte: UInt8) {
        // The suffix is reported whole, but a flood must not grow this buffer without a
        // bound; past the bound the warning only needs the leading bytes.
        if pending.count < 64 { pending.append(byte) }
    }

    private mutating func finishSequence() {
        state = .data
        pending = []
    }
}
