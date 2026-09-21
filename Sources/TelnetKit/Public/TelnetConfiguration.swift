import Logging

/// The line ending `send(text:)` applies when the NVT newline policy is active.
public enum TelnetLineEnding: Sendable, Hashable, CaseIterable {
    /// CR LF, the NVT default.
    case crlf
    /// CR NUL, the NVT rule for a bare carriage return.
    case crNul
    /// A single LF.
    case lf
    /// No line ending; the line feed is sent unchanged.
    case none
}

/// How queued events behave when the caller has not consumed them.
public enum TelnetEventBufferPolicy: Sendable {
    /// Buffer at most the given count; a drop finishes the stream with a warning.
    case bounded(Int)
    /// Never drop an event.
    case unbounded
    /// Keep at most the given count and discard the oldest, reporting each drop.
    case dropOldest(Int)
}

/// How text sends and received data treat CR and LF.
public enum TelnetNewlinePolicy: Sendable {
    /// Translate line endings for text sends and received data.
    case nvt
    /// Pass bytes through unchanged.
    case raw
}

/// The bounds and policies one connection runs under.
///
/// Every field has a default, so `TelnetConfiguration()` is the configuration a caller
/// gets by passing nothing. The library takes no part in confidentiality: Telnet carries
/// plaintext, including passwords.
public struct TelnetConfiguration: Sendable {
    /// Upper bound on address resolution plus TCP connect. Default 10 seconds.
    public var connectTimeout: Duration
    /// Nil disables idle closing. Default nil.
    public var idleTimeout: Duration?
    /// Maximum buffered inbound bytes before `.bufferOverflow`. Default 64 KiB.
    public var inboundBufferLimit: Int
    /// Maximum subnegotiation payload in bytes. Default 8 KiB.
    public var subnegotiationLimit: Int
    /// How queued events behave when unconsumed. Default `.bounded(1024)`.
    public var eventBufferPolicy: TelnetEventBufferPolicy
    /// How CR and LF are treated. Default `.nvt`.
    public var newlinePolicy: TelnetNewlinePolicy
    /// True parks a connect attempt that has no route instead of failing. Default true.
    public var waitForConnectivity: Bool
    /// Optional swift-log logger. Nil logs nothing, and payload bytes are never logged.
    public var logger: Logger?

    /// Creates a configuration.
    public init(
        connectTimeout: Duration = .seconds(10),
        idleTimeout: Duration? = nil,
        inboundBufferLimit: Int = 65_536,
        subnegotiationLimit: Int = 8_192,
        eventBufferPolicy: TelnetEventBufferPolicy = .bounded(1024),
        newlinePolicy: TelnetNewlinePolicy = .nvt,
        waitForConnectivity: Bool = true,
        logger: Logger? = nil
    ) {
        self.connectTimeout = connectTimeout
        self.idleTimeout = idleTimeout
        self.inboundBufferLimit = inboundBufferLimit
        self.subnegotiationLimit = subnegotiationLimit
        self.eventBufferPolicy = eventBufferPolicy
        self.newlinePolicy = newlinePolicy
        self.waitForConnectivity = waitForConnectivity
        self.logger = logger
    }
}
