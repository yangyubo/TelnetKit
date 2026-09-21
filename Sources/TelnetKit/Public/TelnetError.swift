/// Every failure a caller can observe, as a typed value.
///
/// Each C library error code maps to exactly one `TelnetErrorCode` case, and
/// the mapping is exhaustive: no `default` arm swallows a code. The public surface names
/// no C library symbol, no C macro, and no NIO error generic.
public enum TelnetError: Error, Sendable, Equatable {
    /// The host name could not be resolved.
    case invalidHost(String)
    /// The peer refused the connection.
    case connectionRefused(host: String, port: Int)
    /// The connect attempt exceeded `TelnetConfiguration.connectTimeout`.
    case connectTimeout(Duration)
    /// A call was made after the connection closed.
    case notConnected
    /// A `close()` raced a close that had already begun.
    case alreadyClosed
    /// The underlying transport failed.
    case transportFailed(TelnetTransportFailure)
    /// The protocol state machine reported a fatal condition.
    case protocolViolation(TelnetProtocolError)
    /// Inbound bytes accumulated past `TelnetConfiguration.inboundBufferLimit`.
    case bufferOverflow(limit: Int)
    /// A subnegotiation payload exceeded `TelnetConfiguration.subnegotiationLimit`.
    case subnegotiationTooLarge(option: TelnetOption, limit: Int)
    /// The build does not support a requested capability.
    case unsupportedFeature(String)
    /// The supplied options or configuration are not usable.
    case invalidConfiguration(String)
    /// The calling task was cancelled.
    case cancelled
}

/// A structured transport failure: diagnostic detail is kept, but the public surface
/// never names a NIO error generic, so a NIO change cannot break SemVer.
public struct TelnetTransportFailure: Error, Sendable, Equatable {
    /// The broad category of the failure.
    public enum Kind: Sendable, Equatable {
        /// Name resolution failed.
        case dns
        /// A POSIX error with its errno value.
        case posix(code: Int32)
        /// A TLS-layer failure.
        case tls
        /// The channel closed unexpectedly.
        case channelClosed
        /// A write did not complete in time.
        case writeTimeout
        /// A transient failure that does not fit another case.
        case other
    }

    /// The broad category of the failure.
    public var kind: Kind
    /// A developer-readable description that carries no payload data.
    public var message: String
    /// True when retrying the same operation can succeed without a change.
    public var isRetryable: Bool

    /// Creates a transport failure.
    public init(kind: Kind, message: String, isRetryable: Bool) {
        self.kind = kind
        self.message = message
        self.isRetryable = isRetryable
    }
}

/// A recoverable protocol problem, delivered as `.warning` and never closing the
/// connection.
public enum TelnetWarning: Error, Sendable, Equatable {
    /// A half `IAC` sequence at the end of the stream.
    case truncatedSequence([UInt8])
    /// A byte that is invalid in its position.
    case unexpectedByte(UInt8, context: String)
    /// A subnegotiation block ended before its payload was complete.
    case subnegotiationTruncated(option: TelnetOption)
    /// Queued events were dropped under the configured buffer policy.
    case eventBufferOverflowDropped(count: Int)
    /// A compressed stream arrived while the build has no zlib support.
    case compressionUnavailable
}

/// A fatal protocol error, delivered as `.protocolError`; the connection closes after it.
public enum TelnetProtocolError: Error, Sendable, Equatable {
    /// A libtelnet state-machine failure, with its structured code.
    case stateMachineFailure(code: TelnetErrorCode, message: String)
    /// A subnegotiation block was malformed for its option.
    case invalidSubnegotiation(option: TelnetOption)
    /// The state machine could not allocate.
    case outOfMemory
}

/// The Swift-side mapping of the C library's error codes, one case per value.
public enum TelnetErrorCode: Sendable, Equatable, CaseIterable {
    /// An invalid parameter or API misuse.
    case badValue
    /// An allocation failed.
    case outOfMemory
    /// Data exceeded the internal buffer.
    case overflow
    /// An invalid sequence of special bytes.
    case `protocol`
    /// A compressed-stream failure.
    case compression
}
