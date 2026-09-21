# TelnetKit Product Requirements Document (PRD)

[中文](PRD.md) | English

| Item | Content |
| --- | --- |
| Product | TelnetKit |
| Version | v0.1 (first release requirements) |
| Status | In review |
| Date | 2026-09-21 |
| Target repository | `TelnetKit` (Swift Package, directory `/Users/yang/workspace/CodinnCode/CoreSSH/TelnetKit`) |
| Upstream dependencies | [apple/swift-nio](https://github.com/apple/swift-nio), [seanmiddleditch/libtelnet](https://github.com/seanmiddleditch/libtelnet) |
| Delivery form | Swift Package (library product `TelnetKit` plus tests and demo executables); macOS 15+ and iOS 18+ |

---

## 1. Background and goals

### 1.1 Background

The Telnet protocol (RFC 854/855 and its many option extensions) is still a common interactive channel for BBS systems, network devices, embedded devices, and industrial terminals. The Swift ecosystem lacks a Telnet client library that is modern, safe under concurrency, and usable out of the box:

- `libtelnet` is a mature C implementation covering RFC 854/855/1091/1143/1408/1572, with Q-method (RFC 1143) option negotiation, ZMP, MCCP2, MSSP, and NEW-ENVIRON. It implements only the **protocol state machine**, it does not manage TCP, and its **callback API with many macros, constants, and raw pointers** is deeply un-Swift.
- Hand-writing Telnet parsing on raw `Network.framework` or POSIX sockets means rewriting the RFC 1143 state machine: a large amount of work with a high error rate.

TelnetKit's position: **wrap libtelnet with the Swift 6 concurrency model and SwiftNIO into a type-safe, testable, C-free async Telnet terminal capability library that serves both macOS 15+ and iOS 18+.**

### 1.2 Product goals

| ID | Goal | Measurement |
| --- | --- | --- |
| G1 | Provide a native Swift async Telnet interface | Callers use only `async/await` and `AsyncSequence`; no callback closure anywhere |
| G2 | Let the library own the TCP connection lifecycle | Connect, timeout, graceful close, backpressure, and cancellation propagation are all `TelnetConnection`'s responsibility |
| G3 | Isolate every C implementation detail | The public API exposes no `OpaquePointer`, no `UInt8` command macro, and no `telnet_*` symbol |
| G4 | Protocol correctness that can be verified | Negotiation, subnegotiation, TTYPE, NEW-ENVIRON, and NAWS behavior each has test coverage |
| G5 | A deliverable example project | The demo covers every public interface and can talk to a real Telnet service |
| G6 | Modern dependencies | Swift 6 language mode + `swift-tools-version` 6.x + macOS 15+ and iOS 18+ deployment targets + swift-nio 2.10x |

### 1.3 Non-goals (out of scope)

- ❌ Terminal emulation (VT100/xterm screen model, cursor, line editing, color rendering). The demo is a **minimal interactive** demonstration, not a full TERM.
- ❌ SSH, RLogin, and Mosh protocols.
- ❌ BBS business logic (ANSI art, door games, ZMODEM and other file-transfer protocols).
- ❌ MCCP2 compression (libtelnet can enable it through `HAVE_ZLIB`; the first release leaves it **off** as a v0.2 option).
- ❌ A Telnet server framework productized on `ServerBootstrap`; the echo server in the test fixture is not part of the product interface.
- ❌ Anything beyond text encoding: `send(text:)` encodes as UTF-8 by default, the encoding strategy is configurable, and no charset autodetection is attempted.
- ❌ Linux and Windows support (the first release promises macOS 15+ and iOS 18+; the code layout does not deliberately block a later port).

---

## 2. Target users and scenarios

### 2.1 User profiles

1. **Application developer**: needs an embedded Telnet session in a macOS or iOS app (device console, serial-over-Telnet gateway client, legacy system integration, mobile operations tool).
2. **Tool developer**: writes a CLI tool that connects to many devices, runs commands, collects output, and automates the protocol.
3. **Protocol researcher or tester**: needs to observe or inject Telnet negotiation and check whether a peer follows RFC 1143.

### 2.2 Core user stories

| ID | User story | Priority |
| --- | --- | --- |
| US-1 | As a developer, I establish a connection and get a session object with one line, `try await TelnetConnection.connect(host:port:)` | P0 |
| US-2 | As a developer, I consume server data and negotiation events with `for await event in conn.events`, without registering a callback | P0 |
| US-3 | As a developer, I send a command line with `send(text:)`, and the library handles the CR/LF (NVT) translation and `0xFF` escaping | P0 |
| US-4 | As a developer, I declare the options this end supports (`will`/`wont`/`do`/`dont`), and the library completes RFC 1143 negotiation without a negotiation loop | P0 |
| US-5 | As a developer, I answer the terminal type when the server requests `TTYPE`, and the window size is reported when it requests `NAWS` | P1 |
| US-6 | As a developer, connection failures (DNS failure, timeout, peer disconnect, buffer overflow) are thrown as typed errors I can handle with `switch` | P0 |
| US-7 | As a developer, I can `await conn.close()` at any time, and unconsumed events cause no task leak or crash | P0 |
| US-8 | As a developer, I cancel a connection attempt with `withTimeout` or `Task`, and the cancellation reaches the socket | P0 |
| US-9 | As a developer, I follow the demo code and have an interactive client running within ten minutes | P1 |
| US-10 | As a maintainer, I run the protocol tests and the loopback integration tests in CI without external network access | P0 |

---

## 3. Verified upstream facts (basis for this document)

These facts were verified before writing this document (2026-09-21, this machine: Xcode 27.0, Swift 6.4, macOS 27.0):

| Item | Conclusion |
| --- | --- |
| Toolchain | `Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)`, SDK MacOSX27.0 |
| Latest swift-nio release | **2.103.0** (2026-09-17) |
| libtelnet repository layout | Only `libtelnet.c`, `libtelnet.h`, `CMakeLists.txt`, autotools files, `test/`, `doc/`, and `util/` |
| Does libtelnet have Package.swift | **No** (neither the `develop` nor the `master` branch). We must vendor the C sources plus a `module.modulemap` inside the Swift Package (agreed with the requester) |
| libtelnet public surface | `telnet_init/free/recv/iac/negotiate/send/send_text/begin_sb/subnegotiation/begin_compress2/printf/raw_printf/begin_newenviron/newenviron_value/ttype_send/ttype_is/send_zmp/send_zmpv/send_vzmpv/begin_zmp/zmp_arg`, plus the macros `telnet_finish_sb`, `telnet_finish_newenviron`, and `telnet_finish_zmp` (invisible to Swift, so the seam must supply them) |
| libtelnet has no option-status query | The header exports **no** function that reports the result of `WILL`/`WONT`/`DO`/`DONT` negotiation. `optionStatus(_:)` must therefore be derived by this library in Swift from observed negotiation events; reading C struct internals is forbidden |
| libtelnet event model | `telnet_event_handler_t(telnet_t*, telnet_event_t*, void *user_data)`; `telnet_event_t` is a union with 15 event types |
| libtelnet compression | Controlled by the `HAVE_ZLIB` build switch, off by default |
| libtelnet license | Public domain dedication (see `COPYING`) |

**Prototype results (actually run, not inferred)**:

1. `clang -c libtelnet.c -I include -Wall` produced **0 warnings and 0 errors** and 23 exported `_telnet*` symbols.
2. With `libtelnet.c/.h` in `Sources/CLibTelnet/` (containing `module.modulemap`), `swift build` succeeded and `swift test` (Swift Testing) passed.
3. On the Swift side, registering a closure callback through `telnet_init` with an `Unmanaged` user_data, then feeding `FF FB 01` (IAC WILL ECHO) and `FF FA 18 01 FF F0` (IAC SB TTYPE SEND IAC SE) yielded only the plain data `hello\r\n`: the negotiation bytes were swallowed correctly, so **the parse path works**.
4. `telnet_send_text("hi\n")` produced the outbound bytes `FF FD 01 68 69 0D 0A`: it first adds `IAC DO ECHO` (because the peer had sent WILL ECHO), then the NVT-translated text with a correct `0x0D 0x0A`, so **the outbound coding and negotiation reply path works**.
5. `NIOAsyncChannel`, `ClientBootstrap`, and the related async APIs are official in swift-nio 2.x; see the [swiftonserver client tutorial](https://swiftonserver.com/building-swiftnio-clients/) and the [NIO TCP echo client example](https://github.com/FranzBusch/swift-nio/blob/0f9d376fb5b414e40d5c3c3326733d829c92b939/Sources/NIOTCPEchoClient/Client.swift).

> Environment note: under this machine's sandbox, compiling a SwiftPM manifest needs `sandbox-exec` permission, so verification used a wider sandbox mode; ordinary development is unaffected.

---

## 4. Overall architecture

### 4.1 Package structure (single package with a vendored C target)

```
TelnetKit/
├── Package.swift                       # swift-tools-version: 6.2, platforms macOS 15 + iOS 18
├── PRD.md
├── README.md
├── LICENSE                             # this library's license (libtelnet is public domain; note it in NOTICE)
├── NOTICE
├── Sources/
│   ├── CLibTelnet/                     # [C] vendored libtelnet, not exposed
│   │   ├── include/
│   │   │   ├── libtelnet.h             # upstream 0.23, synced only, never modified
│   │   │   └── module.modulemap        # module CLibTelnet { header "libtelnet.h" export * }
│   │   └── libtelnet.c
│   ├── TelnetKit/                      # [Swift] the only public product
│   │   ├── Public/                     # public types (all Sendable, no C type)
│   │   │   ├── TelnetConnection.swift
│   │   │   ├── TelnetOptions.swift
│   │   │   ├── TelnetEvent.swift
│   │   │   ├── TelnetCommand.swift
│   │   │   ├── TelnetOption.swift
│   │   │   ├── TelnetError.swift
│   │   │   └── TelnetLogger.swift
│   │   ├── Protocol/                   # Swift wrapper over libtelnet (internal)
│   │   │   ├── TelnetProtocolCore.swift
│   │   │   └── TelnetWireCoding.swift
│   │   ├── Transport/                  # NIO integration (internal)
│   │   │   ├── TelnetChannelHandler.swift
│   │   │   └── TelnetChannelOptions.swift
│   │   └── Demos/                      # optional: SwiftUI components used by DemoApp
│   ├── TelnetDemo/                     # [executable] CLI demo
│   │   └── main.swift
│   └── TelnetEchoServer/               # [executable] local loopback server (demo + integration fixture)
│       └── main.swift
├── Tests/
│   └── TelnetKitTests/
│       ├── PublicAPI/                  # black box: only import TelnetKit
│       ├── Protocol/                   # white box: @testable import, per-event assertions
│       └── Integration/                # loopback: real TCP + real NIO
└── Examples/
    └── TelnetKitDemoApp/               # SwiftUI macOS demo (Xcode project or SwiftPM executable target)
```

### 4.2 Layers and responsibilities

```
┌──────────────────────────────────────────────────────────────┐
│ Public API  TelnetConnection(actor) / TelnetEvent / Options   │  ← the only layer a caller touches
├──────────────────────────────────────────────────────────────┤
│ Protocol    TelnetProtocolCore: telnet_t lifetime,            │
│             event callback → Swift enum, option table, NVT     │
├──────────────────────────────────────────────────────────────┤
│ Transport   TelnetChannelHandler: ChannelInbound/Outbound      │
│             Handler, joining ByteBuffer ↔ ProtocolCore        │
├──────────────────────────────────────────────────────────────┤
│ NIO         ClientBootstrap + NIOAsyncChannel + EventLoopGroup │
├──────────────────────────────────────────────────────────────┤
│ C           CLibTelnet (libtelnet.c)                           │
└──────────────────────────────────────────────────────────────┘
```

**Key design decisions**

| Decision | Choice | Reason |
| --- | --- | --- |
| How the C dependency enters | Vendored C target plus `module.modulemap` in this package | Upstream has no `Package.swift`; avoids an extra repository and submodule complexity and keeps the fork controllable (confirmed) |
| Concurrency boundary | `TelnetProtocolCore` is **owned by the NIO EventLoop** and is not an actor | The libtelnet state machine is not thread-safe and its callback synchronously produces outbound bytes; EventLoop ownership needs no lock and no preemption |
| Public concurrency type | `TelnetConnection` is an `actor`; events are wrapped in `AsyncStream` | Naturally `Sendable` for callers, who need no knowledge of EventLoop |
| Event delivery | `AsyncStream<TelnetEvent>` with a bounded buffer policy | Gives backpressure semantics and prevents unbounded growth |
| Outbound calls | `actor` method → `eventLoop.execute` / `NIOAsyncWriter` serialization | Keeps the call on the same thread as the `telnet_*` call and avoids a data race |
| Error model | A Swift `Error` enum mapped from libtelnet's `telnet_error_t` | No C error code leaks |
| Close semantics | `close()` is idempotent; the `events` stream finishes when the channel closes | Prevents `for await` from hanging forever |

### 4.3 Threading and concurrency model (mandatory constraints)

1. **Single-thread ownership**: `telnet_t*` is accessed only on the EventLoop thread that created it; every `telnet_recv`, `telnet_send*`, `telnet_iac`, and `telnet_negotiate` call happens on that thread.
2. **`user_data` lifetime**: the `Unmanaged` pointer passed to `telnet_init` refers to handler state and must never reach a callback after `telnet_free`; the handler deinit calls `telnet_free` before releasing that state.
3. **No escape from the callback**: the `buffer`, `name`, and `argv` pointers in a `telnet_event_t` are valid **only during the callback** and must be copied into Swift value types immediately.
4. **No reentry inside the callback**: an event callback must not recursively call `telnet_send*`; a send becomes an outbound queue entry that the handler flushes in order after the callback returns.
5. **Swift 6 strict concurrency**: `StrictConcurrency` is on for the whole package, every public type is `Sendable`, and tests must not use `@unchecked Sendable` to hide a real race (the C wrapper is the only exception, and it needs a comment stating why plus a concurrency test).

---

## 5. Public API design

> The signatures below are a **contract draft**, to be frozen by a Swift interface snapshot test once development starts. Every type is `Sendable` and no method mentions a C type.

### 5.1 Enums and base types

```swift
/// Option codes are modeled as a struct with static constants, not an enum:
/// RFC 1073 and RFC 1572 leave many options unmodeled, needing an unnamed fallback.
public struct TelnetOption: RawRepresentable, Sendable, Hashable, CaseIterable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }   // any code, modeled or not

    public static let binary: TelnetOption = .init(rawValue: 0)
    public static let echo: TelnetOption = .init(rawValue: 1)
    public static let suppressGoAhead: TelnetOption = .init(rawValue: 3)
    public static let status: TelnetOption = .init(rawValue: 5)
    public static let timingMark: TelnetOption = .init(rawValue: 6)
    public static let terminalType: TelnetOption = .init(rawValue: 24)
    public static let endOfRecord: TelnetOption = .init(rawValue: 25)
    public static let windowSize: TelnetOption = .init(rawValue: 31)
    public static let terminalSpeed: TelnetOption = .init(rawValue: 32)
    public static let remoteFlowControl: TelnetOption = .init(rawValue: 33)
    public static let lineMode: TelnetOption = .init(rawValue: 34)
    public static let environment: TelnetOption = .init(rawValue: 36)
    public static let newEnvironment: TelnetOption = .init(rawValue: 39)
    public static let mssp: TelnetOption = .init(rawValue: 70)
    public static let compress: TelnetOption = .init(rawValue: 85)
    public static let compress2: TelnetOption = .init(rawValue: 86)
    public static let zmp: TelnetOption = .init(rawValue: 93)
    public static let extendedOptionsList: TelnetOption = .init(rawValue: 255)

    /// The modeled options, for UI display and test traversal
    public static var allCases: [TelnetOption] { [...] }
    /// A human-readable name (unmodeled codes render as "option(\(rawValue))")
    public var displayName: String { get }
}

public enum TelnetCommand: UInt8, Sendable, Hashable {
    case endOfFile = 236, suspend = 237, abort = 238, endOfRecord = 239
    case subnegotiationEnd = 240, noOperation = 241, dataMark = 242, brk = 243
    case interruptProcess = 244, abortOutput = 245, areYouThere = 246
    case eraseCharacter = 247, eraseLine = 248, goAhead = 249, subnegotiation = 250
    case will = 251, wont = 252, do_ = 253, dont = 254
}

/// Negotiation verbs, with Swift spellings replacing the WILL/WONT/DO/DONT macros
public enum TelnetNegotiation: Sendable, Hashable { case will, wont, `do`, dont }

public struct TelnetOptionStatus: Sendable, Hashable {
    public var locallyEnabled: Bool     // this end sent WILL
    public var remotelyEnabled: Bool    // the peer sent WILL
    public var localRequested: Bool     // a WILL/WONT is outstanding
    public var remoteRequested: Bool    // a DO/DONT is outstanding
}

// MARK: Event value types (plain Swift values, no C dependency)

public enum EnvironmentScope: Sendable, Hashable { case variable, userVariable }
public struct EnvironmentVariable: Sendable, Hashable {
    public var name: String
    public var value: String?
    public var scope: EnvironmentScope
}

/// A recoverable protocol problem (produces .warning only, never a disconnect)
public enum TelnetWarning: Error, Sendable, Equatable {
    case truncatedSequence([UInt8])           // a half IAC sequence at end of stream
    case unexpectedByte(UInt8, context: String)
    case subnegotiationTruncated(option: TelnetOption)
    case eventBufferOverflowDropped(count: Int)  // dropped events, see the FR-CONN-08 policy
    case compressionUnavailable
}

/// A fatal protocol error (produces .protocolError and closes the connection)
public enum TelnetProtocolError: Error, Sendable, Equatable {
    case stateMachineFailure(code: TNLErrorCode, message: String)   // structured mapping of a libtelnet errcode
    case invalidSubnegotiation(option: TelnetOption)
    case outOfMemory
}

/// Swift-side mapping of libtelnet's `telnet_error_t` (no C enum on the public surface)
public enum TNLErrorCode: Sendable, Equatable { case badValue, outOfMemory, overflow, protocol, compression }
```

### 5.2 Option configuration

```swift
public struct TelnetOptions: Sendable {
    public struct LocalOption: Sendable, Hashable {   // this end's capabilities
        public var option: TelnetOption
        public var enabledByDefault: Bool
        public init(_ option: TelnetOption, enabledByDefault: Bool = true)
    }
    public struct RemoteOption: Sendable, Hashable {  // capabilities wanted from the peer
        public var option: TelnetOption
        public var requestOnConnect: Bool
        public init(_ option: TelnetOption, requestOnConnect: Bool = true)
    }
    public var local: [LocalOption]
    public var remote: [RemoteOption]

    /// A common preset: BINARY + SGA + ECHO with client semantics
    public static var standardClient: TelnetOptions { get }
    /// A server-side caller actively requests TTYPE / NAWS / NEW-ENVIRON from the client
    public static func serverRequesting(_ options: [TelnetOption]) -> TelnetOptions
    public var isValid: Bool   // rejects illegal combinations such as BINARY with LINEMODE
}
```

### 5.3 Event model

```swift
public enum TelnetEvent: Sendable {
    /// Application data (negotiation bytes stripped, NVT newlines restored)
    case data(ByteBuffer)                    // the library uses NIOCore.ByteBuffer as the binary carrier
    case negotiation(TelnetNegotiation, option: TelnetOption, remote: Bool)
    case subnegotiation(option: TelnetOption, payload: [UInt8])
    case command(TelnetCommand)
    case terminalTypeRequested                       // received TTYPE SEND
    case terminalType(String)                        // received TTYPE IS
    case environmentRequested(EnvironmentScope)      // SEND
    case environment(EnvironmentScope, [EnvironmentVariable])
    case localEchoChanged(enabled: Bool)             // derived convenience event
    case mssp([String: String])
    case zmp([String])
    case compressionEnabled(Bool)
    case warning(TelnetWarning)                      // recoverable: protocol anomaly, oversized SB
    case protocolError(TelnetProtocolError)          // fatal: the state machine reported an error
}

public extension TelnetEvent {
    /// Converts .data to UTF-8 text (the most common caller need)
    var text: String? { get }
}
```

### 5.4 The connection object

```swift
public actor TelnetConnection {

    // MARK: Establish
    public static func connect(
        host: String,
        port: Int = 23,
        options: TelnetOptions = .standardClient,
        configuration: TelnetConfiguration = .init()
    ) async throws(TelnetError) -> TelnetConnection

    // MARK: Event stream (single-consumer semantics)
    public nonisolated var events: AsyncStream<TelnetEvent> { get }

    // MARK: State
    public var isConnected: Bool { get }
    public var remoteAddress: String? { get }
    public var localAddress: String? { get }
    public func optionStatus(_ option: TelnetOption) -> TelnetOptionStatus

    // MARK: Send
    public func send(_ bytes: [UInt8]) async throws(TelnetError)      // raw bytes, IAC escaped
    public func send(text: String) async throws(TelnetError)          // automatic NVT newline translation
    public func send(text: String, lineEnding: TelnetLineEnding) async throws(TelnetError)
    public func sendRaw(_ bytes: [UInt8]) async throws(TelnetError)   // no NVT translation

    // MARK: Negotiation
    @discardableResult
    public func negotiate(_ action: TelnetNegotiation, option: TelnetOption) async throws(TelnetError) -> Bool
    public func requestOption(_ option: TelnetOption) async throws(TelnetError)   // DO/WILL sugar
    public func subnegotiate(option: TelnetOption, payload: [UInt8]) async throws(TelnetError)
    public func send(command: TelnetCommand) async throws(TelnetError)

    // MARK: Capability helpers
    public func replyTerminalType(_ type: String) async throws(TelnetError)
    public func sendEnvironment(_ values: [EnvironmentVariable], scope: EnvironmentScope) async throws(TelnetError)
    public func sendWindowSize(columns: Int, rows: Int) async throws(TelnetError)

    // MARK: Close
    public func close() async
}

public enum TelnetLineEnding: Sendable { case crlf, crNul, lf, none }

public struct TelnetConfiguration: Sendable {
    public var connectTimeout: Duration            // default .seconds(10)
    public var idleTimeout: Duration?              // default nil
    public var inboundBufferLimit: Int             // default 64 KiB; exceeding it throws .bufferOverflow
    public var subnegotiationLimit: Int            // default 8 KiB, against SB flooding
    public var eventBufferPolicy: TelnetEventBufferPolicy  // .bounded(1024) / .unbounded / .dropOldest
    public var newlinePolicy: TelnetNewlinePolicy // .nvt / .raw
    public var logger: Logger?                     // swift-log; nil by default (silent)
    public var tls: TLSConfiguration?              // reserved: TLS over Telnet (see risk R6)
}
```

### 5.5 Error model

```swift
public enum TelnetError: Error, Sendable, Equatable {
    case invalidHost(String)                       // DNS failure
    case connectionRefused(host: String, port: Int)
    case connectTimeout(Duration)
    case notConnected
    case alreadyClosed
    case transportFailed(TelnetTransportFailure)   // underlying IO failure (stringified; no NIO generic leaks)
    case protocolViolation(TelnetProtocolError)
    case bufferOverflow(limit: Int)
    case subnegotiationTooLarge(option: TelnetOption, limit: Int)
    case unsupportedFeature(String)                // e.g. MCCP2 not compiled in
    case invalidConfiguration(String)
    case cancelled
}

/// A structured transport failure: diagnostic detail is kept, but the public surface
/// never names NIOCore's concrete error generics, so NIO changes cannot break SemVer.
public struct TelnetTransportFailure: Error, Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case dns, posix(code: Int32), channelClosed, writeTimeout, other }
    public var kind: Kind
    public var message: String        // a developer-readable description with no payload data
    public var isRetryable: Bool
}
```

### 5.6 Hard constraints on the public interface

| Constraint | Check |
| --- | --- |
| No C type such as `telnet_t`, `telnet_event_t`, `telnet_telopt_t`, or `OpaquePointer` leaks | A test target outside `@testable` plus `swift-api-digester` / interface snapshot review |
| No Swift symbol for a `TELNET_*` macro is exported | The snapshot forbids a constant with the `TELNET_` prefix |
| Every public symbol carries a `///` doc comment with an example | A DocC build with no warning; `swift package generate-documentation` succeeds |
| Every public method states its `async`/`throws` semantics and distinguishes error types | Explicit typed throws, `throws(TelnetError)` |
| Executable targets (demo, echo server) are not part of the product interface | Declared as `.executableTarget` in `Package.swift` and documented as such in the README |

---

## 6. Functional requirements

### 6.1 Connection management (FR-CONN)

| ID | Requirement | Priority | Acceptance criterion |
| --- | --- | --- | --- |
| FR-CONN-01 | `connect(host:port:options:configuration:)` establishes a TCP connection | P0 | Connects to a loopback echo server and receives its greeting |
| FR-CONN-02 | DNS names resolve (`SocketAddress.makeAddressResolvingHost`) | P0 | Both `localhost` and `127.0.0.1` connect |
| FR-CONN-03 | The connect timeout is configurable and throws `.connectTimeout` | P0 | A black-hole address (such as `10.255.255.1:23`) throws within 1.5 s at a 1 s setting |
| FR-CONN-04 | A connection attempt honours `Task` cancellation, throws `.cancelled`, and closes the socket | P0 | No connection is left behind on either side after cancellation |
| FR-CONN-05 | `close()` is idempotent, performs a graceful half-close, and does not fail when called again | P0 | Two consecutive `close()` calls neither crash nor error |
| FR-CONN-06 | The `events` stream finishes when the channel closes (peer FIN/RST, `idleTimeout`) | P0 | `for await` exits within 2 s instead of hanging |
| FR-CONN-07 | Every public call after close throws `.notConnected` | P0 | `send` after close throws |
| FR-CONN-08 | Outbound writes provide backpressure (promise-based `writeAndFlush` plus NIO watermarks) | P1 | Writing 100 MB does not grow memory linearly |
| FR-CONN-09 | Exceeding `inboundBufferLimit` throws `.bufferOverflow` and closes | P1 | A malicious newline-free flood is stopped |
| FR-CONN-10 | Optional `idleTimeout` closes a silent connection and reports it | P2 | With a 1 s setting and no data, the connection closes in about 1 s |

### 6.2 Protocol parsing and events (FR-PROTO)

| ID | Requirement | Priority | Acceptance criterion |
| --- | --- | --- | --- |
| FR-PROTO-01 | Parse all 15 libtelnet events and map them to `TelnetEvent` | P0 | The per-event unit tests pass |
| FR-PROTO-02 | Strip every `IAC` sequence so `.data` carries application data only | P0 | `.data` content matches exactly under mixed input |
| FR-PROTO-03 | Restore the `IAC IAC` escape to one `0xFF` byte inside `.data` | P0 | The test asserts the bytes |
| FR-PROTO-04 | An illegal or truncated `IAC` sequence produces `.warning`, never a crash | P0 | 100,000 iterations of random bytes do not crash |
| FR-PROTO-05 | Subnegotiation content survives intact, including `IAC` escape restoration | P0 | The TTYPE, NAWS, and NEW-ENVIRON payloads match exactly |
| FR-PROTO-06 | `TELNET_FLAG_PROXY` and `TELNET_FLAG_NVT_EOL` are exposed through `configuration`, never as macros | P1 | Each mode has a test |
| FR-PROTO-07 | A subnegotiation longer than `subnegotiationLimit` throws `.subnegotiationTooLarge` | P1 | An oversized SB is stopped |
| FR-PROTO-08 | The callback copy strategy holds no dangling pointer | P0 | The protocol tests pass under AddressSanitizer |

### 6.3 Option negotiation and terminal capabilities (FR-NEG)

| ID | Requirement | Priority | Acceptance criterion |
| --- | --- | --- | --- |
| FR-NEG-01 | Send the initial negotiation from `TelnetOptions` after connecting | P0 | `optionStatus(.echo)` is correct after the handshake with the echo server |
| FR-NEG-02 | Follow RFC 1143 Q-method rules and refuse a negotiation loop | P0 | Simultaneous WILL from both ends produces a bounded message count |
| FR-NEG-03 | Produce a `.negotiation` event for each received `WILL`/`WONT`/`DO`/`DONT` | P0 | Event order and content match exactly |
| FR-NEG-04 | Refuse an option that was not declared, with `DONT`/`WONT` | P0 | A server `DO ZMP` receives `WONT ZMP` |
| FR-NEG-05 | Support `TTYPE`: request, report, and multi-type cycling (a repeated type ends it) | P1 | A simulated server polling loop passes |
| FR-NEG-06 | Support `NAWS`: report the window size on change (4 × UInt16 big-endian, `255` escaped) | P1 | The server receives a new size after the SwiftUI demo window is resized |
| FR-NEG-07 | Support `NEW-ENVIRON`: receive a variable list structurally and send one on demand | P1 | The variable, value, and `ESC` byte sequences are correct |
| FR-NEG-08 | Parse `MSSP` into `[String: String]` | P2 | A standard MSSP message parses correctly |
| FR-NEG-09 | Parse `ZMP` commands and arguments | P2 | Multi-argument and empty-argument boundaries are correct |
| FR-NEG-10 | When COMPRESS2 is not compiled in: answer a request with `WONT`, and throw `.unsupportedFeature` if compression is forced | P1 | A clear error instead of silently garbled data |
| FR-NEG-11 | `optionStatus(_:)` reflects negotiation state live | P1 | State is asserted before and after negotiation |
| FR-NEG-12 | Capabilities such as `sendWindowSize` and `replyTerminalType` can be triggered from the demo | P1 | The demo exposes an entry point for each |

### 6.4 Text and encoding (FR-TEXT)

| ID | Requirement | Priority | Acceptance criterion |
| --- | --- | --- | --- |
| FR-TEXT-01 | `send(text:)` uses a CRLF line ending by default (`TelnetLineEnding.crlf`) | P0 | Outbound bytes assert `0D 0A` |
| FR-TEXT-02 | Support the `crNul`, `lf`, and `none` line endings | P1 | All three assert their bytes |
| FR-TEXT-03 | Skip CR/LF translation when BINARY is negotiated (matching `TELNET_FLAG_NVT_EOL` semantics) | P0 | `0x0A` survives intact in binary mode |
| FR-TEXT-04 | Encode all text as UTF-8; replace illegal input lossily and log a warning | P1 | Non-UTF-8 input does not crash |
| FR-TEXT-05 | `send(_ bytes:)` escapes `0xFF` automatically; `sendRaw` does not (for advanced use) | P0 | The byte assertions pass |

### 6.5 Errors and diagnostics (FR-ERR)

| ID | Requirement | Priority | Acceptance criterion |
| --- | --- | --- | --- |
| FR-ERR-01 | Map every libtelnet `telnet_error_t` value to `TelnetError` | P0 | A mapping-table test; no `default: fatalError` arm |
| FR-ERR-02 | A `.protocolError` closes the connection and finishes the event stream | P0 | Closure and stream finish are asserted |
| FR-ERR-03 | A `.warning` does not interrupt the connection | P0 | The session still sends and receives after a warning |
| FR-ERR-04 | The optional `Logger` (swift-log) emits protocol frames at trace, state changes at debug, connection events at info, and errors at error | P1 | An injected in-memory logger captures at least four categories |
| FR-ERR-05 | Application payload is not logged by default, to avoid leaking sensitive data; it needs an explicit opt-in | P1 | The default configuration logs no payload |

---

## 7. Non-functional requirements

| Category | Requirement |
| --- | --- |
| Language and toolchain | Swift 6 language mode (`swiftLanguageModes: [.v6]`), `swift-tools-version: 6.2`, minimum Xcode 26 / Swift 6.2 |
| Deployment target | `platforms: [.macOS(.v15), .iOS(.v18)]`; both platforms are promised for build products, while Linux, Windows, tvOS, and watchOS are not |
| Strict concurrency | Complete `StrictConcurrency` checking for the whole package, 0 warnings |
| Dependencies | `swift-nio` (2.103.0 or later) and `swift-log` (1.x, for optional logging); no other third-party runtime dependency |
| Binary size | Under a single-architecture release build, the TelnetKit delta is under 500 KiB including the C source |
| Performance | Single-connection throughput of at least 50 MB/s over loopback with a 64 KiB buffer; zero extra allocations per byte in the parse path outside event boundaries |
| Memory | Under 2 MiB resident per connection excluding the NIO EventLoop pool; no leak after 100,000 input events (`leaks`/`valgrind` or Instruments) |
| Security | Peer input is untrusted: every parse path has a length bound, the `IAC` state machine is safe on truncated input, and application data is not logged by default |
| Testability | The protocol layer is unit-testable without a network (`recv → [TelnetEvent]` only); the network layer is integration-testable against a loopback server; tests never touch the external network |
| Documentation | Every public symbol has a DocC comment and a runnable example; the README covers a five-minute start; the CHANGELOG follows Keep a Changelog |
| Compatibility policy | SemVer; a public API snapshot test runs in CI and a breaking change must commit the new snapshot explicitly |
| Observability | Integration with swift-log; optional `NIOAsyncChannel` metrics through `swift-metrics` (P2) |

---

## 8. Test strategy and case inventory

### 8.1 Layers

| Layer | Goal | Method |
| --- | --- | --- |
| L1 protocol unit tests (white box) | Per-event, per-byte correctness | `@testable import TelnetKit` and a direct byte feed into `TelnetProtocolCore` |
| L2 public interface tests (black box) | Contract stability, no C leak, error semantics | `import TelnetKit` only, against a loopback `TelnetEchoServer` |
| L3 integration tests | Real TCP, timeout, cancellation, concurrent connections | `ClientBootstrap` against a local `ServerBootstrap` fixture |
| L4 robustness | Fuzz input and resource bounds | Random and malicious byte streams, oversized SB, flooding |
| L5 static assurance | Interface, concurrency, and both platform builds | `swift-api-digester` snapshot, `swift build -Xswiftc -strict-concurrency=complete`, an AddressSanitizer job, and an iOS 18 simulator build |

Every suite uses **Swift Testing** (`import Testing`, `@Test`/`@Suite`/`#expect`/`#require`) with `async` test functions; a test that needs timeout protection uses a `withTimeout` helper defined in the test target.

### 8.2 Case inventory (required for the public interface)

**A. Connection lifecycle (FR-CONN)**

| Case | Assertion |
| --- | --- |
| `connect_loopback_succeeds` | Returns non-nil, `isConnected == true`, `remoteAddress == "127.0.0.1:<port>"` |
| `connect_refused_throws_connectionRefused` | Connecting to a closed port throws `.connectionRefused` |
| `connect_unresolvable_host_throws_invalidHost` | Throws `.invalidHost` |
| `connect_timeout_throws_connectTimeout` | Black-hole address with `connectTimeout: .seconds(1)` produces `.connectTimeout` |
| `connect_cancellation_throws_cancelled` | `Task` cancellation produces `.cancelled` and no connection left on the server |
| `close_is_idempotent` | Two `close()` calls produce no error |
| `events_finish_on_remote_close` | `for await` ends normally after the server closes, under a 2 s timeout guard |
| `send_after_close_throws_notConnected` | Throws `.notConnected` |
| `optionStatus_reflects_negotiation` | echo and SGA state is correct after the handshake |
| `inbound_buffer_limit_enforced` | Exceeding the bound throws `.bufferOverflow` and closes the connection |

**B. Protocol parsing (FR-PROTO, white box, per event)**

| Case | Input → expectation |
| --- | --- |
| `data_passthrough` | `"hello\r\n"` → `.data("hello\r\n")` |
| `iac_escape_unescaped` | `FF FF` → `.data([0xFF])` |
| `will_wont_do_dont_events` | `FF FB 01` / `FF FC 01` / `FF FD 01` / `FF FE 01` → four `.negotiation` events with the correct remote flag |
| `iac_command_events` | `FF F1` (NOP), `FF F9` (GA), `FF EF` (EOF) → `.command(...)` |
| `subnegotiation_payload` | `FF FA 18 00 78 74 65 72 6D FF F0` → `.terminalType("xterm")` |
| `subnegotiation_with_escaped_ff` | A payload containing `FF FF` restores to `0xFF` |
| `truncated_iac_sequence_warns` | `FF FB` at end of stream produces `.warning` without a crash |
| `garbage_stream_no_crash` | 100,000 random bytes produce no crash and self-consistent events |
| `subnegotiation_limit_exceeded` | Exceeding the bound produces `.subnegotiationTooLarge` |
| `newenviron_parsing` | A VAR/USERVAR/VALUE/ESC combination produces the correct structured variables |
| `mssp_parsing` | `1 name 2 value` → `["name": "value"]` |
| `zmp_parsing` | A multi-argument command → `["cmd", "a", "b"]` |
| `proxy_flag_behavior` | Proxy mode sends no automatic reply |
| `nvt_eol_flag_behavior` | The two newline policies assert their byte differences |

**C. Negotiation and terminal capabilities (FR-NEG)**

| Case | Assertion |
| --- | --- |
| `initial_negotiation_sent_on_connect` | The first bytes the server receives match `TelnetOptions.standardClient` |
| `rfc1143_no_negotiation_loop` | Simultaneous WILL from both ends produces a bounded message count (≤ N) |
| `unsupported_option_rejected` | `DO ZMP` for an undeclared option produces an outbound `WONT ZMP` |
| `ttype_send_triggers_reply_or_event` | TTYPE SEND produces `.terminalTypeRequested`, and the server receives IS after `replyTerminalType` |
| `naws_reported_on_window_resize` | A window change makes the server receive four big-endian bytes |
| `naws_escapes_255` | A 255-column width makes the payload contain `FF FF` |
| `compress2_unsupported` | Negotiation produces `WONT` with no silent `.unsupportedFeature` failure |

**D. Text and encoding (FR-TEXT)**

| Case | Assertion |
| --- | --- |
| `send_text_crlf` / `send_text_crNul` / `send_text_lf` / `send_text_none` | Outbound bytes match exactly |
| `send_text_escapes_iac` | Text containing `0xFF` produces outbound `FF FF` |
| `binary_mode_disables_newline_translation` | `0x0A` passes through after BINARY is negotiated |
| `send_raw_bytes_not_escaped` | `sendRaw([0xFF])` emits a single byte |

**E. Errors and logging (FR-ERR)**

| Case | Assertion |
| --- | --- |
| `error_code_mapping_exhaustive` | Every `telnet_error_t` value maps to a non-crashing result |
| `protocol_error_closes_connection` | After `.protocolError`, `isConnected == false` and the stream finishes |
| `warning_does_not_close` | The session still sends and receives after a warning |
| `logger_receives_expected_categories` | An in-memory logger captures info, debug, and error |
| `logger_redacts_payload_by_default` | The default configuration logs no application data |

**F. Concurrency and resources (NFR)**

| Case | Assertion |
| --- | --- |
| `concurrent_connections_are_isolated` | Eight concurrent connections each receive their own echo with no cross-talk |
| `concurrent_sends_serialized` | 100 concurrent `send(text:)` calls all arrive intact with no interleaved truncation |
| `memory_stable_after_100k_events` | Resident memory growth after 100,000 events stays under the threshold |
| `no_dangling_buffer_with_asan` | The full protocol suite passes under an ASan build |

**G. Public interface contract (§5.6)**

| Case | Assertion |
| --- | --- |
| `publicAPI_has_no_clibtelnet_symbols` | No `telnet_`, `TELNET_`, or `OpaquePointer` in reflection or an interface snapshot |
| `publicAPI_snapshot_matches` | The `swift-api-digester` snapshot has no unreviewed change |
| `documentation_builds` | A DocC build with 0 warnings |

### 8.3 Quality gates

- The public interface tests (L2) **must cover every public symbol listed in §5** (method, property, enum case); the coverage report is checked against the public symbol list and a gap fails the gate.
- Protocol-layer statement coverage of at least 90% and branch coverage of at least 80%.
- Every test runs offline, and one `swift test` invocation finishes in under 60 s.

---

## 9. Demo project requirements

### 9.1 Deliverables

| Name | Form | Purpose |
| --- | --- | --- |
| `TelnetDemo` | `.executableTarget` (CLI) | The minimal verifiable path: connect → print events → send a command → disconnect; covers every public interface |
| `TelnetEchoServer` | `.executableTarget` (local server, macOS only) | An integration target with no external dependency: echo, plus active TTYPE/NAWS/NEW-ENVIRON negotiation and injected negotiation, subnegotiation, and warning scenarios |
| `TelnetKitDemoApp` | SwiftUI macOS app (`Examples/`) | An interactive terminal: connection panel, output area, input field, option-status table, event log, automatic window-size reporting |

### 9.1.1 Documentation deliverables

This PRD's engineering constraints are split into development documents kept beside the code; tiers and writing rules are in [docs/AGENTS.md](docs/AGENTS.md):

| Document | Responsibility |
| --- | --- |
| [AGENTS.md](AGENTS.md) | Standing orders: repository layout, commands, non-negotiable constraints, conventions |
| [docs/architecture.md](docs/architecture.md) | Design map: layers, concurrency model, event flow, C seam, extension points, test layout |
| [docs/public-api.md](docs/public-api.md) | The caller contract and the public symbol test checklist |
| [README.md](README.md) / [README.zh.md](README.zh.md) | The consumer contract: capabilities, install, quick start, known limitations, security |
| [.agents/skills/](.agents/skills/) | Reusable workflows: public API slice, C library import, documentation standard, prose standard |

### 9.2 Interfaces the demo must cover

| Interface | How the demo shows it |
| --- | --- |
| `TelnetConnection.connect(host:port:options:configuration:)` | Connection form (host, port, timeout, option checkboxes) |
| Every `TelnetConfiguration` initializer parameter | Settings panel (timeout, buffer bounds, newline policy, logging switch) |
| `events` and every `TelnetEvent` case | Event log panel, colored by case |
| `send(text:)` / `send(_:)` / `sendRaw(_:)` / `send(text:lineEnding:)` | Input field plus a line-ending picker |
| `negotiate(_:option:)` / `requestOption(_:)` / `subnegotiate(option:payload:)` / `send(command:)` | Manual protocol operation buttons |
| `replyTerminalType(_:)` / `sendEnvironment(...)` / `sendWindowSize(columns:rows:)` | Terminal settings area; window size is reported automatically as the SwiftUI window changes |
| `optionStatus(_:)` / `isConnected` / `remoteAddress` | Status bar |
| `close()` | Disconnect button, plus automatic disconnect on window close |
| Every `TelnetError` case | Error-injection menu (wrong port, black-hole address, oversized SB) that exercises error presentation |
| `Logger` injection | Log level switch for the console and the panel |

### 9.3 Demo acceptance criteria

1. `swift run TelnetEchoServer` plus `swift run TelnetDemo --host 127.0.0.1 --port 2323` runs with one command, needing no network and no external service.
2. The demo can reach a real external Telnet service (a public BBS or a device) and complete one full interaction: the login prompt is visible and commands can be typed; on iOS a minimal simulator example runs the same path against the loopback server.
3. `TelnetKitDemoApp` is usable the moment it opens on macOS 15+; resizing the window triggers a NAWS report that is visible in the echo server log. The library itself builds on an iOS 18+ simulator and passes every non-network test there.
4. The demo code is documentation: every public interface appears at least once in it, and the README carries a matching code snippet.

---

## 10. Milestones and delivery plan

| Milestone | Content | Exit criterion |
| --- | --- | --- |
| M0 scaffolding | `Package.swift`, the vendored `CLibTelnet` target with its modulemap and `UPSTREAM.md` (recording the upstream commit), directory skeleton, CI skeleton, LICENSE and NOTICE | `swift build` and `swift test` pass against the macOS 15 target (**this step is already verified as feasible in the prototype**) |
| M1 protocol layer | `TelnetProtocolCore`, every `TelnetEvent` mapping, NVT coding, and the L1 unit tests (groups B and D) | Groups B and D are green and ASan passes |
| M2 connection layer | `TelnetChannelHandler`, the `TelnetConnection` actor, timeout, cancellation, and close, with L2/L3 tests (group A) | Group A is green with no leak |
| M3 negotiation and capabilities | RFC 1143 negotiation strategy, TTYPE/NAWS/NEW-ENVIRON/MSSP/ZMP, and group C tests | Group C is green with no negotiation loop |
| M4 quality and documentation | Groups E, F, and G, DocC, interface snapshot, coverage gates, README, CHANGELOG | Coverage gates pass and group G is green |
| M5 demo | `TelnetEchoServer`, the CLI demo, and the SwiftUI demo app | All four acceptance criteria in §9.3 pass |
| M6 iOS support | `Package.swift` declares `.iOS(.v18)`; CI gains an iOS 18 simulator build and test job; the platform-sensitive paths (DNS resolution, EventLoop, logging, background suspension) are re-reviewed on iOS | `xcodebuild -destination 'platform=iOS Simulator,name=iPhone 16'` builds, and the protocol and public interface tests are green |
| M7 release | v0.1.0 tag, release notes, macOS and iOS simulator screenshots or recordings | The tag is pushed and `Package.resolved` is archived |

> Suggested pace: M0 and M1 land in one pass; M2 and M3 can run in parallel; M4 and M5 run in parallel after M2 and M3, and M6 depends on the green M4 suites. Every milestone produces something runnable, so no "big integration at the end" risk accumulates.

---

## 11. Risks and mitigations

| ID | Risk | Impact | Mitigation |
| --- | --- | --- | --- |
| R1 | libtelnet has no SwiftPM support, so an upstream update needs a manual sync after vendoring | Low | Record the upstream commit SHA and version (currently 0.23) in `NOTICE` and `CLibTelnet/README`; check the upstream diff quarterly; sync only `libtelnet.c/.h` and do not modify upstream code (a required patch becomes a separate patch file with a note) |
| R2 | A libtelnet callback buffer is valid only during the callback, so Swift code easily creates a dangling pointer | High | Enforce copy-inside-the-callback, keep `TelnetProtocolCore` from exposing pointers, and cover it with ASan tests plus a dedicated code review checklist |
| R3 | `telnet_t` is not thread-safe, so a cross-thread access is a data race | High | Single-EventLoop ownership (§4.3); every inbound and outbound path serializes through the handler; `Sendable` checking plus concurrency tests |
| R4 | `telnet_finish_sb`, `telnet_finish_newenviron`, and `telnet_finish_zmp` are macros, invisible to Swift | Medium | Supply equivalent implementations inside `TelnetProtocolCore` (`telnet_iac(t, TELNET_SE)`) and cover them in unit tests |
| R5 | A self-written negotiation strategy easily produces a loop or state confusion | Medium | Reuse libtelnet's RFC 1143 Q-method implementation entirely and write no state machine; add an assertion that the reported `optionStatus` agrees with libtelnet's internal state |
| R6 | Telnet is plaintext, including passwords | Medium | State the risk prominently in the documentation; do not implement the AUTHENTICATION option in the first release; reserve `configuration.tls` for a TLS-over-Telnet (`NIOSSL`) channel to evaluate in v0.2 |
| R7 | MCCP2 needs zlib (`HAVE_ZLIB`), which differs across build environments | Low | Leave it off in the first release; if enabled, declare it explicitly through SwiftPM `.systemLibrary` or `define` and add an enabled variant to CI |
| R8 | A poor `AsyncStream` buffer policy causes memory growth or event loss | Medium | Default to `.bounded` with a configurable drop or finish policy, emit a `.warning` **when an event is dropped**, and add a high-traffic stress test |
| R9 | The public API couples to swift-nio types such as `ByteBuffer`, which limits a future upgrade | Low | Use `ByteBuffer` as the binary carrier for `TelnetEvent.data` because it matches the NIO ecosystem, and provide `text` and `bytes([UInt8])` accessors so a caller never has to understand NIO |
| R10 | iOS network and background limits: suspending the app drops the connection, and App Store review scrutinizes plaintext protocols | Medium | Document the foreground-session semantics and the disconnect-on-background behavior, add no background daemon, provide `idleTimeout` and a caller-side reconnect example, and flag the plaintext risk in the README security section |
| R11 | Two-platform CI cost and simulator resource use | Low | The iOS job runs only the simulator build and the non-network tests (protocol and public interface); integration tests stay in the macOS job |

---

## 12. Open questions

| ID | Question | Proposed default |
| --- | --- | --- |
| Q1 | Should `TelnetEvent.data` use `NIOCore.ByteBuffer` or a custom `[UInt8]`? | Use `ByteBuffer` (zero copy, consistent with the NIO ecosystem) and provide `[UInt8]` and `String` convenience views |
| Q2 | Should the first release ship TLS over Telnet? | No; reserve the configuration field and document the intent |
| Q3 | Should the SwiftUI demo app be an in-package executable target or a separate `Examples/` Xcode project? | A separate project under `Examples/` so that referencing SwiftUI inside the package cannot slow `swift test`, while reusing the `Sources/TelnetKit/Demos` components |
| Q4 | Is `swift-metrics` or `swift-service-lifecycle` integration needed? | Not in the first release; swift-log is enough |
| Q5 | Should Chinese documentation ship alongside the English? | Decided: every human-facing document is a bilingual pair under the [documentation standard](docs/AGENTS.md#bilingual-pairs); this PRD is canonical in Chinese, with `PRD.en.md` as its counterpart |

---

## 13. References

- [apple/swift-nio](https://github.com/apple/swift-nio) (latest release 2.103.0)
- [seanmiddleditch/libtelnet](https://github.com/seanmiddleditch/libtelnet) (v0.23, public domain, no SwiftPM manifest)
- [Developing a basic Swift echo server using Swift NIO](https://medium.com/processone/developing-a-basic-swift-echo-server-using-swift-nio-8a5bf3d3fef2)
- [Building SwiftNIO clients — swiftonserver.com](https://swiftonserver.com/building-swiftnio-clients/)
- [SwiftNIO `NIOAsyncChannel` and async bootstrap documentation](https://github.com/apple/swift-nio/blob/2.57.0/Sources/NIOCore/Docs.docc/swift-concurrency.md)
- RFC 854 / RFC 855 (the Telnet protocol), RFC 1143 (Q-method option negotiation), RFC 1073 (NAWS), RFC 1091 (TTYPE), RFC 1572 (NEW-ENVIRON), RFC 859/860 (MSSP)
- [Swift Testing documentation](https://developer.apple.com/documentation/testing)

---

## Appendix A: `Package.swift` draft

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TelnetKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "TelnetKit", targets: ["TelnetKit"]),
        .executable(name: "TelnetDemo", targets: ["TelnetDemo"]),
        .executable(name: "TelnetEchoServer", targets: ["TelnetEchoServer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.103.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    ],
    targets: [
        // vendored libtelnet: internal only, never exposed as a product.
        // HAVE_ZLIB stays undefined (MCCP2 off; see §6.3 FR-NEG-10 and risk R7).
        .target(name: "CLibTelnet"),
        .target(
            name: "TelnetKit",
            dependencies: [
                "CLibTelnet",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(name: "TelnetDemo", dependencies: ["TelnetKit"]),
        .executableTarget(name: "TelnetEchoServer", dependencies: [
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOPosix", package: "swift-nio"),
        ]),
        .testTarget(name: "TelnetKitTests", dependencies: ["TelnetKit", "TelnetEchoServer"]),
    ]
)
```

> Note: in the prototype, `CLibTelnet` needed no custom compile macro and no interoperability mode; the `module.modulemap` alone let Swift import it, so the real implementation keeps the same minimal configuration.
> `swiftLanguageModes` could also be declared once for the package (`swiftLanguageModes: [.v6]`); declaring it per target keeps the option of relaxing it for test targets.

## Appendix B: `CLibTelnet` directory and modulemap

```c
// Sources/CLibTelnet/include/module.modulemap
module CLibTelnet {
    header "libtelnet.h"
    export *
}
```

- `libtelnet.c` and `include/libtelnet.h` come straight from the upstream `develop` branch (version tag `\version 0.23`) and are **never modified**.
- The source commit SHA is recorded in `Sources/CLibTelnet/UPSTREAM.md`, and an upgrade checks the diff with a script.
- The macros `telnet_finish_sb`, `telnet_finish_newenviron`, and `telnet_finish_zmp` are implemented equivalently in Swift by `TelnetProtocolCore`, which does not depend on the C macro export.

## Appendix C: Typical usage example (used by the demo and the README)

```swift
import TelnetKit

let conn = try await TelnetConnection.connect(
    host: "127.0.0.1",
    port: 2323,
    options: .standardClient,
    configuration: .init(connectTimeout: .seconds(5))
)

// Consume events
Task {
    for await event in conn.events {
        switch event {
        case .data(let buffer):
            print(buffer.string ?? "", terminator: "")
        case .negotiation(let action, let option, let remote):
            print("[\(remote ? "remote" : "local")] \(action) \(option)")
        case .terminalTypeRequested:
            try? await conn.replyTerminalType("xterm-256color")
        default:
            print(event)
        }
    }
}

try await conn.send(text: "hello telnet")
try await conn.sendWindowSize(columns: 120, rows: 40)
try await conn.close()
```
