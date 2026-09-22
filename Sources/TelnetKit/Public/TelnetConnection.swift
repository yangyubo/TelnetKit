import NIOCore

/// One Telnet session with one remote endpoint.
///
/// `connect` opens the connection, sends the initial negotiation for `options`, and
/// returns a ready session. The actor owns the connection: every fallible method throws
/// `TelnetError`, and every sending method completes when the bytes reach the socket.
public actor TelnetConnection {
    private let channel: Channel
    private let ledger: TelnetOptionLedger
    private let session: TelnetSessionState

    /// The single-consumer event stream.
    ///
    /// `nonisolated`, so a caller can start consuming before or after any actor call.
    /// Events arrive in wire order, and the stream finishes exactly once on any close path.
    public nonisolated let events: AsyncStream<TelnetEvent>

    private init(result: TelnetConnectionBootstrap.Result) {
        self.channel = result.channel
        self.events = result.events
        self.ledger = result.ledger
        self.session = result.session
    }

    deinit {
        // A caller that never calls `close()` must not strand the socket.
        channel.close(promise: nil)
    }

    // MARK: Establish and state

    /// Resolves `host`, opens a TCP connection within `configuration.connectTimeout`,
    /// sends the initial negotiation for `options`, and returns the connection.
    ///
    /// Throws `.invalidHost` when resolution fails, `.connectionRefused` when the peer
    /// refuses, `.connectTimeout` on the configured bound, `.invalidConfiguration` when
    /// `options` is invalid, and `.cancelled` when the calling task is cancelled. A
    /// cancelled attempt leaves no open socket.
    public static func connect(
        host: String,
        port: Int = 23,
        options: TelnetOptions = .standardClient,
        configuration: TelnetConfiguration = .init()
    ) async throws(TelnetError) -> TelnetConnection {
        let result = try await TelnetConnectionBootstrap.connect(
            host: host,
            port: port,
            options: options,
            configuration: configuration
        )
        return TelnetConnection(result: result)
    }

    /// True from a successful `connect` until the close path begins.
    public var isConnected: Bool {
        session.isConnected
    }

    /// `host:port` of the peer, or nil before connection completion.
    public var remoteAddress: String? {
        session.remoteAddress
    }

    /// `host:port` of the local socket, or nil.
    public var localAddress: String? {
        session.localAddress
    }

    /// The ledger entry for one option, derived from observed negotiations.
    ///
    /// An option that was never mentioned reports all-false.
    public func optionStatus(_ option: TelnetOption) -> TelnetOptionStatus {
        ledger.status(for: option)
    }

    // MARK: Sending

    /// Sends application bytes, doubling every `0xFF` per NVT. CR and LF are unchanged.
    ///
    /// Throws `.notConnected` after close, `.transportFailed` when the write fails, and
    /// `.cancelled` when the task is cancelled.
    public func send(_ bytes: [UInt8]) async throws(TelnetError) {
        try await perform(.send(bytes))
    }

    /// Encodes `text` as UTF-8, rewrites the newlines it already carries per the configured
    /// newline policy with `TelnetLineEnding.crlf`, then escapes.
    ///
    /// No terminator is added: `send(text: "hi")` writes `68 69`, and
    /// `send(text: "hi\n")` writes `68 69 0D 0A`.
    public func send(text: String) async throws(TelnetError) {
        try await perform(.sendText(text, .crlf))
    }

    /// The same as `send(text:)` with an explicit line ending instead of the configured
    /// default. The ending replaces the newlines the string carries; it is never added.
    public func send(text: String, lineEnding: TelnetLineEnding) async throws(TelnetError) {
        try await perform(.sendText(text, lineEnding))
    }

    /// Sends bytes with no escaping and no line-ending translation.
    ///
    /// A bare `IAC` in `bytes` can break the session; prefer `send(_:)`.
    public func sendRaw(_ bytes: [UInt8]) async throws(TelnetError) {
        try await perform(.sendRaw(bytes))
    }

    /// Sends a Telnet command as `IAC <command>`.
    public func send(command: TelnetCommand) async throws(TelnetError) {
        try await perform(.command(command))
    }

    // MARK: Negotiation and capabilities

    /// Sends one negotiation verb for one option.
    ///
    /// Returns false when libtelnet suppresses the send because RFC 1143 state makes it
    /// redundant, true when bytes were queued.
    @discardableResult
    public func negotiate(_ action: TelnetNegotiation, option: TelnetOption) async throws(TelnetError) -> Bool {
        let outcome = NegotiationOutcome()
        try await perform(.negotiate(action, option), negotiationOutcome: outcome)
        return outcome.wasSent
    }

    /// Sends `will` for an option this end provides or `do` for one it wants from the peer.
    ///
    /// Throws `.invalidConfiguration` when the option is in neither option list.
    public func requestOption(_ option: TelnetOption) async throws(TelnetError) {
        try await perform(.requestOption(option))
    }

    /// Sends `IAC SB <option> <payload> IAC SE`, escaping `0xFF` in the payload.
    ///
    /// Throws `.subnegotiationTooLarge` when the payload exceeds the configured bound.
    public func subnegotiate(option: TelnetOption, payload: [UInt8]) async throws(TelnetError) {
        try await perform(.subnegotiate(option, payload))
    }

    /// Answers a pending terminal-type request with `IAC SB TERMINAL-TYPE IS <type> IAC SE`.
    ///
    /// Throws `.invalidConfiguration` when no `.terminalTypeRequested` event is pending.
    public func replyTerminalType(_ type: String) async throws(TelnetError) {
        try await perform(.replyTerminalType(type))
    }

    /// Sends a NEW-ENVIRON list with the given scope.
    public func sendEnvironment(_ values: [EnvironmentVariable], scope: EnvironmentScope) async throws(TelnetError) {
        try await perform(.sendEnvironment(values, scope))
    }

    /// Sends NAWS as four big-endian bytes.
    ///
    /// Throws `.invalidConfiguration` when a dimension is outside 0...65535.
    public func sendWindowSize(columns: Int, rows: Int) async throws(TelnetError) {
        try await perform(.sendWindowSize(columns: columns, rows: rows))
    }

    // MARK: Close

    /// Closes the connection. Idempotent: a second call succeeds and does nothing.
    public func close() async {
        guard session.isConnected else { return }
        channel.close(promise: nil)
        try? await channel.closeFuture.get()
    }

    // MARK: Private

    private func perform(
        _ kind: TelnetOutboundCommand.Kind,
        negotiationOutcome: NegotiationOutcome? = nil
    ) async throws(TelnetError) {
        guard session.isConnected else {
            throw TelnetError.notConnected
        }
        let command = TelnetOutboundCommand(kind, negotiationOutcome: negotiationOutcome)
        do {
            try await channel.writeAndFlush(command).getAbandoningOnCancel()
        } catch is CancellationError {
            throw TelnetError.cancelled
        } catch let error as TelnetError {
            throw error
        } catch {
            throw TelnetError.transportFailed(TelnetNetworkEventMapping.transportFailure(from: error))
        }
    }
}
