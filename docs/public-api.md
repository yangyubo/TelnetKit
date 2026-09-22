# TelnetKit Public API

English | [中文](public-api.zh.md)

This document is the caller contract for the `TelnetKit` library product. It defines every public type, method, and case, and it is the contract of record: when code and this document disagree, one of them is a defect and the change fixes both. The library and the two executables are implemented; the SwiftUI demo is designed and not written, so statements about it stay **Designed** under the [design-status rule](../AGENTS.md#design-status); requirements and acceptance criteria live in [PRD.md](../PRD.md), and internal design lives in [architecture.md](architecture.md).

## Public surface rules

These rules are mechanical. A review rejects a change that breaks one, and the [public API skill](../.agents/skills/telnetkit-public-api-slice/SKILL.md) checks them before a slice is reported done.

| Rule | Check |
|---|---|
| No C type, function, or macro appears in `public` | Grep the public sources for `telnet_`, `TELNET_`, `OpaquePointer`, `Unsafe` |
| Every public declaration has a `///` comment stating its caller contract | Read the generated interface |
| Every fallible public method is `async throws(TelnetError)` | Read the generated interface |
| Every public type is `Sendable` | Build with complete concurrency checking |
| A public type lives in `Sources/TelnetKit/Public/` | Compare the file path with the declaration |
| Every public symbol has an automated test | Compare the [symbol checklist](#symbol-checklist) with the public API suite |

## Glossary

These terms have one meaning across this repository. Do not add a synonym for one.

- **option** — a Telnet capability identified by an 8-bit code, such as `echo` (code 1). Options are negotiated, not configured.
- **negotiation** — one of the four exchange verbs `will`, `wont`, `do`, `dont`, sent for one option in one direction.
- **subnegotiation** — an option-specific payload exchanged between `IAC SB` and `IAC SE`, such as the window size for `windowSize`.
- **command** — a single Telnet control byte that is not an option, such as `noOperation` or `areYouThere`.
- **event** — one parsed fact delivered to the caller: data, a negotiation, a subnegotiation, a command, or a derived convenience case.
- **connection** — one TCP session with one remote endpoint and one protocol state machine.
- **session** — the caller's use of a connection. The library owns connections, not sessions.
- **NVT** — the network virtual terminal conventions in RFC 854: CR LF for a newline, and `0xFF` doubled to carry a literal `0xFF` byte.

## Lifetime contract

**Verified.** `TelnetConnection.connect(host:port:options:configuration:)` returns a connected, ready-to-negotiate session. The connection is usable until it closes, and it closes in exactly one of four ways: the caller calls `close()`, the remote endpoint closes, a fatal protocol error occurs, or a configured timeout expires.

The event stream delivers events in wire order and finishes exactly once, on any close path. A caller that never consumes the stream still observes the closure: outbound calls throw `.notConnected` and `isConnected` becomes false. The stream is single-consumer; a second consumer receives nothing rather than a copy.

`close()` is idempotent. Calling any sending or negotiation method after close throws `.notConnected`; calling `close()` again succeeds and does nothing.

Cancellation propagates. Cancelling a task inside `connect` or inside a sending method closes the connection when the cancelled operation owns it, and throws `.cancelled` from the cancelled call. A cancelled `connect` leaves no open socket and no arena behind.

## Connection

```swift
public actor TelnetConnection {
    public static func connect(
        host: String,
        port: Int = 23,
        options: TelnetOptions = .standardClient,
        configuration: TelnetConfiguration = .init()
    ) async throws(TelnetError) -> TelnetConnection

    public nonisolated var events: AsyncStream<TelnetEvent> { get }

    public var isConnected: Bool { get }
    public var remoteAddress: String? { get }
    public var localAddress: String? { get }
    public func optionStatus(_ option: TelnetOption) -> TelnetOptionStatus
}
```

| Member | Contract |
|---|---|
| `connect(host:port:options:configuration:)` | Resolves `host`, opens a TCP connection within `configuration.connectTimeout`, sends the initial negotiation for `options`, and returns the connection. Throws `.invalidHost` when resolution fails, `.connectionRefused` when the peer refuses, `.connectTimeout` on the configured bound, `.invalidConfiguration` when `options` is invalid, and `.cancelled` when the calling task is cancelled. |
| `events` | The single-consumer event stream. `nonisolated`, so a caller can start consuming before or after any actor call. Finishes on close. Yields in wire order. |
| `isConnected` | True from a successful `connect` until the close path begins. False afterwards, including after a fatal error. |
| `remoteAddress` | `host:port` of the peer, or nil before connection completion. |
| `localAddress` | `host:port` of the local socket, or nil. |
| `optionStatus(_:)` | The ledger entry for one option: whether each direction is enabled and whether a request is outstanding. Derived from observed negotiations, never from C state. An option that was never mentioned reports all-false. |

## Sending

```swift
extension TelnetConnection {
    public func send(_ bytes: [UInt8]) async throws(TelnetError)
    public func send(text: String) async throws(TelnetError)
    public func send(text: String, lineEnding: TelnetLineEnding) async throws(TelnetError)
    public func sendRaw(_ bytes: [UInt8]) async throws(TelnetError)
    public func send(command: TelnetCommand) async throws(TelnetError)
}
```

| Member | Contract |
|---|---|
| `send(_:)` | Sends application bytes. Doubles every `0xFF` to `0xFF 0xFF` per NVT. Does not alter CR or LF. |
| `send(text:)` | Encodes `text` as UTF-8, applies `configuration.newlinePolicy` and `TelnetLineEnding.crlf`, then escapes. |
| `send(text:lineEnding:)` | Sends `text` with an explicit line ending, ignoring the configured default. |
| `sendRaw(_:)` | Sends bytes with no escaping and no line-ending translation. Intended for carrying an already-encoded Telnet stream; it can break the session if the bytes contain a bare `IAC`. |
| `send(command:)` | Sends a Telnet command as `IAC <command>`. |

Every sending method completes when the bytes are written to the socket or throws `.transportFailed` when the write fails, `.notConnected` when the connection is closed, and `.cancelled` when the task is cancelled. Concurrent calls serialize in the order the actor receives them, and no call interleaves a partial frame with another.

## Negotiation and options

```swift
extension TelnetConnection {
    @discardableResult
    public func negotiate(_ action: TelnetNegotiation, option: TelnetOption) async throws(TelnetError) -> Bool
    public func requestOption(_ option: TelnetOption) async throws(TelnetError)
    public func subnegotiate(option: TelnetOption, payload: [UInt8]) async throws(TelnetError)
    public func replyTerminalType(_ type: String) async throws(TelnetError)
    public func sendEnvironment(_ values: [EnvironmentVariable], scope: EnvironmentScope) async throws(TelnetError)
    public func sendWindowSize(columns: Int, rows: Int) async throws(TelnetError)
}
```

| Member | Contract |
|---|---|
| `negotiate(_:option:)` | Sends one negotiation verb for one option. Returns false when libtelnet suppresses the send because RFC 1143 state makes it redundant, true when bytes were queued. Updates the ledger on return. |
| `requestOption(_:)` | Sends `will` for an option the local end provides or `do` for one it wants from the peer, choosing by `options`. Throws `.invalidConfiguration` when the option is in neither list, because the peer would answer a request the caller has not declared. |
| `subnegotiate(option:payload:)` | Sends `IAC SB <option> <payload> IAC SE`, escaping `0xFF` in the payload. Throws `.subnegotiationTooLarge` when the payload exceeds the configured bound. |
| `replyTerminalType(_:)` | Answers a pending terminal-type request by sending `IAC SB TERMINAL-TYPE IS <type> IAC SE`. Valid only after a `.terminalTypeRequested` event; otherwise throws `.invalidConfiguration`. |
| `sendEnvironment(_:scope:)` | Sends a NEW-ENVIRON list with the given scope, escaping the escape byte inside names and values. Throws `.subnegotiationTooLarge` when the encoded list exceeds the configured bound. |
| `sendWindowSize(columns:rows:)` | Sends NAWS as four big-endian bytes, escaping the `0xFF` octet that RFC 1073 requires. Rejects a dimension outside 0...65535 with `.invalidConfiguration`. |

## Options configuration

```swift
public struct TelnetOptions: Sendable {
    public struct LocalOption: Sendable, Hashable {
        public var option: TelnetOption
        public var enabledByDefault: Bool
        public init(_ option: TelnetOption, enabledByDefault: Bool = true)
    }
    public struct RemoteOption: Sendable, Hashable {
        public var option: TelnetOption
        public var requestOnConnect: Bool
        public init(_ option: TelnetOption, requestOnConnect: Bool = true)
    }

    public var local: [LocalOption]
    public var remote: [RemoteOption]
    public var isValid: Bool

    public init(local: [LocalOption] = [], remote: [RemoteOption] = [])

    public static var standardClient: TelnetOptions { get }
    public static func serverRequesting(_ options: [TelnetOption]) -> TelnetOptions
}
```

`local` lists the options this end offers with `will`, and `remote` lists the options this end asks the peer for with `do`. Connect-time negotiation sends one verb per entry in declaration order, honoring `enabledByDefault` and `requestOnConnect`. An option in both lists negotiates both directions, which is legal and common: `echo` and `suppressGoAhead` are negotiated in both directions by most peers.

`isValid` is false for a combination the protocol rejects, currently `binary` together with `lineMode` in `local`. `connect` throws `.invalidConfiguration` rather than negotiating an invalid set.

`standardClient` is `binary`, `suppressGoAhead`, `terminalType`, and `windowSize` offered locally, and `suppressGoAhead` and `echo` requested remotely. `serverRequesting(_:)` builds the peer set a server-side caller needs.

## Events

```swift
public enum TelnetEvent: Sendable {
    case data(ByteBuffer)
    case negotiation(TelnetNegotiation, option: TelnetOption, remote: Bool)
    case subnegotiation(option: TelnetOption, payload: [UInt8])
    case command(TelnetCommand)
    case terminalTypeRequested
    case terminalType(String)
    case environmentRequested(EnvironmentScope)
    case environment(EnvironmentScope, [EnvironmentVariable])
    case localEchoChanged(enabled: Bool)
    case mssp([String: String])
    case zmp([String])
    case compressionEnabled(Bool)
    case pathChanged(viable: Bool, expensive: Bool, constrained: Bool)
    case betterPathAvailable
    case betterPathUnavailable
    case viabilityChanged(isViable: Bool)
    case waitingForConnectivity(error: String?, description: String)
    case warning(TelnetWarning)
    case protocolError(TelnetProtocolError)
}

extension TelnetEvent {
    public var bytes: [UInt8]?
    public var text: String?
}
```

| Case | Produced when |
|---|---|
| `.data` | The peer sent application bytes, after negotiation bytes and NVT escaping are removed |
| `.negotiation(_:option:remote:)` | A `will`, `wont`, `do`, or `dont` arrived; `remote` is true when the peer sent it |
| `.subnegotiation(option:payload:)` | An `IAC SB ... IAC SE` block arrived; `payload` excludes the option code and restores escaped `0xFF` |
| `.command(_:)` | A control command arrived, such as `areYouThere` or `goAhead` |
| `.terminalTypeRequested` | The peer sent `TERMINAL-TYPE SEND`; answer with `replyTerminalType(_:)`, or ignore to send nothing |
| `.terminalType(_:)` | The peer sent `TERMINAL-TYPE IS` with a name |
| `.environmentRequested(_:)` | The peer asked for environment variables with `SEND`; answer with `sendEnvironment(_:scope:)` |
| `.environment(_:_:)` | The peer sent an ENVIRON or NEW-ENVIRON list |
| `.localEchoChanged(enabled:)` | The peer's `will echo` or `wont echo` changed whether the local end should echo typed input |
| `.mssp(_:)` | The peer sent an MSSP status list, decoded to a dictionary |
| `.zmp(_:)` | The peer sent a ZMP command; the first element is the command name |
| `.compressionEnabled(_:)` | A COMPRESS or COMPRESS2 negotiation changed compression state. The first release builds without zlib and never accepts a compressed stream, so this case never arrives: every COMPRESS2 negotiation is answered `wont` and the stream stays uncompressed |
| `.pathChanged(viable:expensive:constrained:)` | Network.framework reported a new path for the connection; the three flags come from `NWPath` and are copied into Swift values |
| `.betterPathAvailable` | The system found a preferred path, usually Wi-Fi while cellular carries the connection |
| `.betterPathUnavailable` | That preferred path went away |
| `.waitingForConnectivity(error:description:)` | The connect attempt is parked until a route exists, because `waitForConnectivity` is on. The connection is not closed and `connect` has not returned yet |
| `.viabilityChanged(isViable:)` | The path became usable or unusable. A non-viable path does not close the connection; it reports that no traffic can flow until it recovers |
| `.warning(_:)` | A recoverable protocol problem: a truncated sequence, an unexpected byte, a truncated subnegotiation, or dropped events |
| `.protocolError(_:)` | A fatal state-machine failure; the connection closes after this event |

`.bytes` returns the payload of a `.data` event and nil for every other case. `.text` decodes that payload as UTF-8, replacing invalid sequences, and returns nil for every case except `.data`.

## Supporting values

```swift
public struct TelnetOption: RawRepresentable, Sendable, Hashable, CaseIterable {
    public let rawValue: UInt8
    public init(rawValue: UInt8)
    public var displayName: String { get }
    public static var allCases: [TelnetOption] { get }

    public static let binary: TelnetOption
    public static let echo: TelnetOption
    public static let suppressGoAhead: TelnetOption
    public static let status: TelnetOption
    public static let timingMark: TelnetOption
    public static let terminalType: TelnetOption
    public static let endOfRecord: TelnetOption
    public static let windowSize: TelnetOption
    public static let terminalSpeed: TelnetOption
    public static let remoteFlowControl: TelnetOption
    public static let lineMode: TelnetOption
    public static let environment: TelnetOption
    public static let newEnvironment: TelnetOption
    public static let mssp: TelnetOption
    public static let compress: TelnetOption
    public static let compress2: TelnetOption
    public static let zmp: TelnetOption
    public static let extendedOptionsList: TelnetOption
}

public struct TelnetOptionStatus: Sendable, Hashable {
    public var locallyEnabled: Bool
    public var remotelyEnabled: Bool
    public var localRequested: Bool
    public var remoteRequested: Bool
}

public enum TelnetNegotiation: Sendable, Hashable { case will, wont, `do`, dont }

public enum TelnetCommand: UInt8, Sendable, Hashable {
    case endOfFile = 236, suspend = 237, abort = 238, endOfRecord = 239
    case subnegotiationEnd = 240, noOperation = 241, dataMark = 242, brk = 243
    case interruptProcess = 244, abortOutput = 245, areYouThere = 246
    case eraseCharacter = 247, eraseLine = 248, goAhead = 249, subnegotiation = 250
    case will = 251, wont = 252, do_ = 253, dont = 254
}

public enum TelnetLineEnding: Sendable, Hashable { case crlf, crNul, lf, none }
public enum EnvironmentScope: Sendable, Hashable { case variable, userVariable }
public struct EnvironmentVariable: Sendable, Hashable {
    public var name: String
    public var value: String?
    public var scope: EnvironmentScope
}
```

Numeric option codes are the RFC assignments: `binary` 0, `echo` 1, `suppressGoAhead` 3, `status` 5, `timingMark` 6, `terminalType` 24, `endOfRecord` 25, `windowSize` 31, `terminalSpeed` 32, `remoteFlowControl` 33, `lineMode` 34, `environment` 36, `newEnvironment` 39, `mssp` 70, `compress` 85, `compress2` 86, `zmp` 93, `extendedOptionsList` 255. Any other code stays constructible through `init(rawValue:)` and renders as `option(<code>)`.

`will`, `wont`, `do`, and `dont` in `TelnetCommand` exist because a command byte and a negotiation verb share one wire encoding; `.negotiation(_:option:remote:)` is the event a caller matches for negotiation, and `.command(.will)` never appears.

## Configuration

```swift
public struct TelnetConfiguration: Sendable {
    public var connectTimeout: Duration
    public var idleTimeout: Duration?
    public var inboundBufferLimit: Int
    public var subnegotiationLimit: Int
    public var eventBufferPolicy: TelnetEventBufferPolicy
    public var newlinePolicy: TelnetNewlinePolicy
    public var waitForConnectivity: Bool
    public var logger: Logger?

    public init(
        connectTimeout: Duration = .seconds(10),
        idleTimeout: Duration? = nil,
        inboundBufferLimit: Int = 65_536,
        subnegotiationLimit: Int = 8_192,
        eventBufferPolicy: TelnetEventBufferPolicy = .bounded(1024),
        newlinePolicy: TelnetNewlinePolicy = .nvt,
        waitForConnectivity: Bool = true,
        logger: Logger? = nil
    )
}

public enum TelnetEventBufferPolicy: Sendable {
    case bounded(Int)
    case unbounded
    case dropOldest(Int)
}

public enum TelnetNewlinePolicy: Sendable { case nvt, raw }
```

| Member | Contract |
|---|---|
| `connectTimeout` | Upper bound on address resolution plus TCP connect. |
| `idleTimeout` | Nil disables idle closing. When set, a connection with no inbound and no outbound traffic for the interval closes and finishes the stream. |
| `inboundBufferLimit` | Maximum buffered inbound bytes; exceeding it emits a fatal `.protocolError` and closes. |
| `subnegotiationLimit` | Maximum subnegotiation payload; exceeding it raises `.subnegotiationTooLarge`. |
| `eventBufferPolicy` | `.bounded` finishes the stream with a `.warning` when full, `.unbounded` never drops, `.dropOldest` discards the oldest queued event and emits `.warning(.eventBufferOverflowDropped(count:))`. |
| `newlinePolicy` | `.nvt` translates CR and LF for text sends and for received data; `.raw` passes bytes through. `binary` negotiation overrides both to raw while it is enabled. |
| `logger` | Optional `swift-log` logger. Nil logs nothing. Payload content is never logged, at any level. |
| `waitForConnectivity` | True parks a connect attempt that has no route instead of failing, and the attempt resumes when a route appears (FR-PATH-01). The connect call has not returned while it is parked, and `.waitingForConnectivity` reports the state. |

The defaults are the ones a caller gets by passing nothing, and each is asserted by a configuration test. `inboundBufferLimit` and `subnegotiationLimit` are byte counts; `eventBufferPolicy` counts events; `waitForConnectivity` is a flag.

## Errors

```swift
public enum TelnetError: Error, Sendable, Equatable {
    case invalidHost(String)
    case connectionRefused(host: String, port: Int)
    case connectTimeout(Duration)
    case notConnected
    case alreadyClosed
    case transportFailed(TelnetTransportFailure)
    case protocolViolation(TelnetProtocolError)
    case bufferOverflow(limit: Int)
    case subnegotiationTooLarge(option: TelnetOption, limit: Int)
    case unsupportedFeature(String)
    case invalidConfiguration(String)
    case cancelled
}

public struct TelnetTransportFailure: Error, Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case dns, posix(code: Int32), tls, channelClosed, writeTimeout, other }
    public var kind: Kind
    public var message: String
    public var isRetryable: Bool

    public init(kind: Kind, message: String, isRetryable: Bool)
}

public enum TelnetWarning: Error, Sendable, Equatable {
    case truncatedSequence([UInt8])
    case unexpectedByte(UInt8, context: String)
    case subnegotiationTruncated(option: TelnetOption)
    case eventBufferOverflowDropped(count: Int)
    case compressionUnavailable
}

public enum TelnetProtocolError: Error, Sendable, Equatable {
    case stateMachineFailure(code: TelnetErrorCode, message: String)
    case invalidSubnegotiation(option: TelnetOption)
    case outOfMemory
}

public enum TelnetErrorCode: Sendable, Equatable { case badValue, outOfMemory, overflow, protocol, compression }
```

Each libtelnet `telnet_error_t` value maps one-to-one: `TELNET_EBADVAL` to `.badValue`, `TELNET_ENOMEM` to `.outOfMemory`, `TELNET_EOVERFLOW` to `.overflow`, `TELNET_EPROTOCOL` to `.protocol`, and `TELNET_ECOMPRESS` to `.compression`. `TELNET_EOK` is success and produces no error.

`.notConnected` means a call was made after close; `.alreadyClosed` means `close()` raced a close that had already begun and the caller asked to distinguish it. `isRetryable` is true for `.dns`, for a connection-refused or timed-out `.posix` code, and for `.other` when the underlying `NWError` is transient such as `.waitingForConnectivity`; it is false for `.tls`, `.channelClosed`, and `.writeTimeout`, because retrying those without a change repeats the same failure.

## Logging

**Verified.** When `configuration.logger` is non-nil, the library logs connection lifecycle at `info`, negotiation and state changes at `debug`, and protocol frames at `trace`. No level logs payload bytes, option values sent by the peer, or environment values. Silence is the default: an unconfigured connection emits no log records.

## Symbol checklist

Every symbol below requires an automated test in `Tests/TelnetKitTests/PublicAPI/` before the slice that adds it is complete.

| Type | Symbols |
|---|---|
| `TelnetConnection` | `connect`, `events`, `isConnected`, `remoteAddress`, `localAddress`, `optionStatus`, `send(_:)`, `send(text:)`, `send(text:lineEnding:)`, `sendRaw(_:)`, `send(command:)`, `negotiate(_:option:)`, `requestOption(_:)`, `subnegotiate(option:payload:)`, `replyTerminalType(_:)`, `sendEnvironment(_:scope:)`, `sendWindowSize(columns:rows:)`, `close()` |
| `TelnetEvent` | all 19 cases plus `bytes` and `text`; `compressionEnabled` has no producer while the build ships without zlib |
| `TelnetOptions` | `init(local:remote:)`, `LocalOption`, `RemoteOption`, `local`, `remote`, `isValid`, `standardClient`, `serverRequesting(_:)` |
| `TelnetOption` | `init(rawValue:)`, `rawValue`, `displayName`, `allCases`, and all 18 constants |
| `TelnetOptionStatus` | all four properties |
| `TelnetNegotiation` | all four cases |
| `TelnetCommand` | all 19 cases |
| `TelnetLineEnding` | all four cases |
| `EnvironmentScope`, `EnvironmentVariable` | all cases and properties |
| `TelnetConfiguration` | `init` with every default, and all eight properties |
| `TelnetEventBufferPolicy`, `TelnetNewlinePolicy` | all cases |
| `TelnetError` | all 12 cases; `.alreadyClosed`, `.bufferOverflow`, and `.unsupportedFeature` are reachable as values only, because `close()` is idempotent, an inbound overflow surfaces as `.protocolError`, and the v0.2 zlib path is out of scope |
| `TelnetTransportFailure`, `TelnetTransportFailure.Kind` | `init(kind:message:isRetryable:)`, all properties and cases |
| `TelnetWarning` | all five cases; `compressionUnavailable` is reserved for v0.2 zlib support and has no trigger while the build ships without zlib |
| `TelnetProtocolError`, `TelnetErrorCode` | all cases |
