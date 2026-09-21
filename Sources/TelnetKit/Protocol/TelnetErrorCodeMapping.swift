import CLibTelnet

/// Maps every libtelnet error value to a Swift code.
///
/// The switch names each value the pinned header defines, so an upstream value that this
/// build does not know is the only input the `default` arm can see; every known value has
/// its own arm and none is swallowed silently.
enum TelnetErrorCodeMapping {
    /// The Swift code for a libtelnet error value, or nil for success (`TELNET_EOK`).
    static func code(for value: telnet_error_t) -> TelnetErrorCode? {
        switch value {
        case TELNET_EOK:
            return nil
        case TELNET_EBADVAL:
            return .badValue
        case TELNET_ENOMEM:
            return .outOfMemory
        case TELNET_EOVERFLOW:
            return .overflow
        case TELNET_EPROTOCOL:
            return .protocol
        case TELNET_ECOMPRESS:
            return .compression
        default:
            // A code newer than this build: reported as a bad value rather than ignored.
            return .badValue
        }
    }
}
