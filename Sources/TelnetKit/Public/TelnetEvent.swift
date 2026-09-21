import NIOCore

/// The scope of an environment variable in an ENVIRON or NEW-ENVIRON exchange.
public enum EnvironmentScope: Sendable, Hashable {
    /// A well-known variable such as `USER` or `TERM`.
    case variable
    /// A user-defined variable.
    case userVariable
}

/// One environment variable from an ENVIRON or NEW-ENVIRON list.
public struct EnvironmentVariable: Sendable, Hashable {
    /// The variable name.
    public var name: String
    /// The variable value, or nil when the list carried a name with no value.
    public var value: String?
    /// Whether the name is well-known or user-defined.
    public var scope: EnvironmentScope

    /// Creates a variable.
    public init(name: String, value: String? = nil, scope: EnvironmentScope = .variable) {
        self.name = name
        self.value = value
        self.scope = scope
    }
}

/// One parsed fact delivered to the caller.
///
/// The core emits cases in wire order. `.data` carries application bytes only: every
/// `IAC` sequence is stripped and NVT newline handling follows
/// `TelnetConfiguration.newlinePolicy`. The three path cases report what
/// Network.framework observed for the connection and never change protocol state.
public enum TelnetEvent: Sendable {
    /// Application data, after negotiation bytes and NVT escaping were removed.
    case data(ByteBuffer)
    /// A `will`, `wont`, `do`, or `dont` arrived; `remote` is true when the peer sent it.
    case negotiation(TelnetNegotiation, option: TelnetOption, remote: Bool)
    /// An `IAC SB ... IAC SE` block arrived for an option with no structured mapping.
    case subnegotiation(option: TelnetOption, payload: [UInt8])
    /// A control command arrived.
    case command(TelnetCommand)
    /// The peer sent `TERMINAL-TYPE SEND`.
    case terminalTypeRequested
    /// The peer sent `TERMINAL-TYPE IS` with a name.
    case terminalType(String)
    /// The peer asked for environment variables with `SEND`.
    case environmentRequested(EnvironmentScope)
    /// The peer sent an ENVIRON or NEW-ENVIRON list.
    case environment(EnvironmentScope, [EnvironmentVariable])
    /// The peer's `will echo` or `wont echo` changed local echo.
    case localEchoChanged(enabled: Bool)
    /// The peer sent an MSSP status list, decoded to a dictionary.
    case mssp([String: String])
    /// The peer sent a ZMP command; the first element is the command name.
    case zmp([String])
    /// A COMPRESS or COMPRESS2 negotiation changed compression state.
    ///
    /// This release builds without zlib and answers every COMPRESS2 negotiation `wont`,
    /// so the case never arrives while compression is unsupported.
    case compressionEnabled(Bool)
    /// Network.framework reported a new path for the connection.
    case pathChanged(viable: Bool, expensive: Bool, constrained: Bool)
    /// The system found a preferred path.
    case betterPathAvailable
    /// The preferred path went away.
    case betterPathUnavailable
    /// The path became usable or unusable; the connection stays open either way.
    case viabilityChanged(isViable: Bool)
    /// The connect attempt is parked until a route exists.
    case waitingForConnectivity(error: String?, description: String)
    /// A recoverable protocol problem; the connection stays usable.
    case warning(TelnetWarning)
    /// A fatal state-machine failure; the connection closes after this event.
    case protocolError(TelnetProtocolError)
}

extension TelnetEvent {
    /// The payload of a `.data` event, or nil for every other case.
    public var bytes: [UInt8]? {
        guard case .data(let buffer) = self else { return nil }
        return Array(buffer.readableBytesView)
    }

    /// The payload of a `.data` event decoded as UTF-8, replacing invalid sequences, or
    /// nil for every other case.
    public var text: String? {
        guard let bytes = self.bytes else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }
}
