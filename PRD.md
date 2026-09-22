# TelnetKit Product Requirements Document (PRD)

English | [中文](PRD.zh.md)

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
- Hand-writing the connection layer, whether directly on Network.framework or on raw sockets, still means rewriting the RFC 1143 state machine: a large amount of work with a high error rate.

TelnetKit's position: **wrap libtelnet with the Swift 6 concurrency model and SwiftNIO into a type-safe, testable, C-free async Telnet terminal capability library that serves both macOS 15+ and iOS 18+.**

### 1.2 Product goals

| ID | Goal | Measurement |
| --- | --- | --- |
| G1 | Provide a native Swift async Telnet interface | Callers use only `async/await` and `AsyncSequence`; no callback closure anywhere |
| G2 | Let the library own the connection lifecycle | Connect, timeout, graceful close, backpressure, cancellation propagation, and network path changes are all `TelnetConnection`'s responsibility |
| G3 | Isolate every C implementation detail | The public API exposes no `OpaquePointer`, no `UInt8` command macro, and no `telnet_*` symbol |
| G4 | Protocol correctness that can be verified | Negotiation, subnegotiation, TTYPE, NEW-ENVIRON, and NAWS behavior each has test coverage |
| G5 | A deliverable example project | The demo covers every public interface and can talk to a real Telnet service |
| G6 | One Apple-first technical route | Network.framework through NIOTS is the transport, with no POSIX/BSD socket path and no branch kept for another platform |

### 1.3 Non-goals (out of scope)

- ❌ Terminal emulation (VT100/xterm screen model, cursor, line editing, color rendering). The demo is a **minimal interactive** demonstration, not a full TERM.
- ❌ SSH, RLogin, and Mosh protocols.
- ❌ BBS business logic (ANSI art, ZMODEM and other file-transfer protocols).
- ❌ MCCP2 compression (`HAVE_ZLIB`). All three Apple SDKs ship zlib (I verified `-lz` links for macOS, iOS, and iPadOS), so leaving it off is a tradeoff rather than a dependency gap: the target users (developers, operators, and technical enthusiasts) do not rely on it, and accepting a compressed stream would add three undesigned contracts: an inflation-ratio bound, event-flow behavior under compression, and a compressed-state failure mode. The first release answers `wont`, and v0.2 evaluates the enablement conditions in §6.3.
- ❌ Proxy mode (`TELNET_FLAG_PROXY`). It turns libtelnet into a transparent pipe: RFC 1143 answering is switched off and every `WILL`/`WONT`/`DO`/`DONT` is reported to the application to forward by itself, with COMPRESS2 auto-detection as its only extra. That is the middle-man shape (client ↔ proxy ↔ server) and the debug-tool shape, where the forwarder must not take a position on options. This library is the opposite: it is an endpoint, and its value is exactly the RFC 1143 answering, the option table, and `optionStatus(_:)` that proxy mode would switch off; the COMPRESS2 extra is zlib-gated and off in the first release. A caller that needs transparent forwarding runs upstream libtelnet in proxy mode; v0.2 revisits this only under the precondition rule §6.3 sets for compression.
- ❌ A Telnet server framework productized on `NIOTSListenerBootstrap`; the echo server the demo ships is not part of the product interface.
- ❌ Anything beyond text encoding: `send(text:)` encodes as UTF-8 by default, the encoding strategy is configurable, and no charset autodetection is attempted.
- ❌ Telnet over TLS/SSL (`telnets`/992, START-TLS, the TELNET ENCRYPT and AUTHENTICATION options). Devices and servers that offer it are rare, the standard was abandoned, Apple's and Homebrew's telnet both lack it, and upstream libtelnet implements neither ENCRYPT nor AUTHENTICATION. A deployment that needs confidentiality uses a VPN or a bastion host; this library carries plaintext Telnet only and states that fact prominently in its documentation.
- ❌ Non-Apple platforms (Linux, Windows, and Android are out of scope, with no abstraction or conditional compilation kept for them).
- ❌ A POSIX/BSD socket transport (`NIOPosix`, raw `socket()`, `select`/`kqueue`); Network.framework is the only transport.
- ❌ A productized server or listener side (`NIOTSListenerBootstrap`); the echo server the demo ships is not part of the product interface.

---

## 2. Target users and scenarios

### 2.1 User profiles

1. **Application developer**: needs an embedded Telnet session in a macOS or iOS app (device console, serial-over-Telnet gateway client, legacy system integration).
2. **Operator**: writes CLI tools that connect to many network devices and servers to run commands, collect output, and automate inspection.
3. **Technical enthusiast and protocol researcher**: needs to observe or inject Telnet negotiation, check whether a peer follows RFC 1143, or wire an old device into a personal toolchain.

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
| libtelnet implements no security option | The header defines only the option numbers `TELNET_TELOPT_AUTHENTICATION` (37) and `TELNET_TELOPT_ENCRYPT` (38); `libtelnet.c` contains zero implementation code for either (`grep -c` is 0) and no TLS or START-TLS symbol. Protocol-level Telnet encryption or authentication will therefore never exist upstream, and confidentiality has to come from the transport or the deployment |
| libtelnet event model | `telnet_event_handler_t(telnet_t*, telnet_event_t*, void *user_data)`; `telnet_event_t` is a union with 15 event types |
| libtelnet compression | Controlled by the `HAVE_ZLIB` build switch, off by default |
| Transport | NIOTS (`swift-nio-transport-services` 1.x) brings Network.framework's EventLoop, Channels, and Bootstraps into SwiftNIO; it needs swift-nio >= 2.83.0 and supports macOS 10.14+, iOS 12+, tvOS 12+, and watchOS 6+, all far below our floors |
| Apple's own telnet | The source lives in `apple-oss-distributions/remote_cmds`. The `telnet(1)` and `telnetd(8)` man pages never mention TLS, SSL, or certificates; the Xcode project defines only `AUTHENTICATION`, `KRB5`, `SKEY`, `IPSEC`, and `INET6` among security switches and **never defines `ENCRYPTION`** (`grep -c ENCRYPTION project.pbxproj` is 0), so the TELNET ENCRYPT option (RFC 2946) is compiled out and the `-x` man page claim that stream encryption is now the default contradicts the binary. Apple's telnet authenticates with Kerberos V5 or S/Key and never encrypts or speaks TLS |
| Homebrew telnet | `brew install telnet` installs **netkit-telnet 308**, whose usage is `telnet [-4] [-6] [-8] [-E] [-K] [-L] [-N] [-S tos] [-X atype] ...`, again with no TLS or SSL option |
| Standard status of Telnet over TLS | Neither IETF draft became an RFC: [draft-altman-telnet-starttls](https://datatracker.ietf.org/doc/draft-altman-telnet-starttls/) (individual submission, IESG state **Dead**, expired) and [draft-ietf-tn3270e-telnet-tls](https://datatracker.ietf.org/doc/draft-ietf-tn3270e-telnet-tls/) (tn3270e working group, expired in 2002 with intended status None). IANA's `telnets 992/tcp` has no RFC reference and no contact. TLS-capable implementations exist only in the OpenSSL family, `telnet-ssl` and `telnetd-ssl`, which Debian still maintains and the FreeBSD and Apple line never merged |
| libtelnet license | Public domain dedication (see `COPYING`) |

**Prototype results (actually run, not inferred)**:

1. `clang -c libtelnet.c -I include -Wall` produced **0 warnings and 0 errors** and 23 exported `_telnet*` symbols.
2. With `libtelnet.c/.h` in `Sources/CLibTelnet/` (containing `module.modulemap`), `swift build` succeeded and `swift test` (Swift Testing) passed.
3. On the Swift side, registering a closure callback through `telnet_init` with an `Unmanaged` user_data, then feeding `FF FB 01` (IAC WILL ECHO) and `FF FA 18 01 FF F0` (IAC SB TTYPE SEND IAC SE) yielded only the plain data `hello\r\n`: the negotiation bytes were swallowed correctly, so **the parse path works**.
4. `telnet_send_text("hi\n")` produced the outbound bytes `FF FD 01 68 69 0D 0A`: it first adds `IAC DO ECHO` (because the peer had sent WILL ECHO), then the NVT-translated text with a correct `0x0D 0x0A`, so **the outbound coding and negotiation reply path works**.
5. The transport choice is verified against official documentation: NIOTS (`swift-nio-transport-services` 1.x) brings Network.framework's EventLoop, Channels, and Bootstraps into SwiftNIO, states that a regular NIO application only changes its event loop group and bootstrap, needs swift-nio >= 2.83.0, and supports macOS 10.14+, iOS 12+, tvOS 12+, and watchOS 6+. `NIOAsyncChannel` and the related async APIs are official in swift-nio 2.x; see the [swiftonserver client tutorial](https://swiftonserver.com/building-swiftnio-clients/).

> Environment note: under this machine's sandbox, compiling a SwiftPM manifest needs `sandbox-exec` permission, so verification used a wider sandbox mode; ordinary development is unaffected.

---

## 4. Overall architecture

### 4.1 Package structure (one package, a libtelnet submodule, Apple-only transport)

```
TelnetKit/
├── Package.swift                       # macOS 15 / iOS 18 / watchOS 11 / tvOS 18 / visionOS 2
├── .gitmodules                         # the libtelnet submodule URL
├── libtelnet/                          # [submodule] upstream sources, COPYING, and history, untouched
│   └── include/module.modulemap        # tracked; module CLibTelnet { umbrella header "libtelnet.h" export * }
├── PRD.md
├── README.md
├── LICENSE                             # this library's license (libtelnet is public domain; note it in NOTICE)
├── NOTICE
├── Sources/
│   ├── CLibTelnet/                     # the C target: a tracked map, two symlinks, and the record
│   │   ├── libtelnet.c                 # symlink -> ../../libtelnet/libtelnet.c
│   │   ├── include/
│   │   │   ├── libtelnet.h             # symlink -> ../../../libtelnet/libtelnet.h
│   │   │   └── module.modulemap        # ours, tracked
│   │   ├── UPSTREAM.md
│   │   └── UPSTREAM.zh.md
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
│   ├── Transport/                  # NIOTS/Network.framework integration (internal)
│   │   ├── TelnetChannelHandler.swift
│   │   ├── TelnetConnectionBootstrap.swift
│   │   └── TelnetNetworkEventMapping.swift
│   ├── TelnetKitClient/                # [executable, macOS only] the telnetkit-client CLI
│   │   └── main.swift
│   └── TelnetEchoServer/               # [executable, macOS only] local loopback server (demo + manual peer)
│       └── main.swift
├── Tests/
│   └── TelnetKitTests/
│       ├── PublicAPI/                  # black box: only import TelnetKit
│       ├── Protocol/                   # white box: @testable import, per-event assertions
│       └── Integration/                # loopback: a real connection through NIOTS
└── Examples/
    └── TelnetKitDemoApp/               # SwiftUI demo (Xcode project; macOS and iOS targets)
```

### 4.2 Layers and responsibilities

```
┌──────────────────────────────────────────────────────────────┐
│ Public API  TelnetConnection(actor) / TelnetEvent / Options   │  ← the only layer a caller touches
├──────────────────────────────────────────────────────────────┤
│ Protocol    TelnetProtocolCore: telnet_t lifetime,            │
│             event callback → Swift enum, option table, NVT     │
├──────────────────────────────────────────────────────────────┤
│ Transport   TelnetChannelHandler: ChannelDuplexHandler,        │
│             joining ByteBuffer (in) / IOData (out) ↔ Core      │
├──────────────────────────────────────────────────────────────┤
│ NIOTS       NIOTSConnectionBootstrap + NIOTSEventLoopGroup     │
├──────────────────────────────────────────────────────────────┤
│ System      Network.framework (path, proxy, VPN, power)       │
├──────────────────────────────────────────────────────────────┤
│ C           CLibTelnet (libtelnet.c, protocol parsing only)    │
└──────────────────────────────────────────────────────────────┘
```

**Key design decisions**

| Decision | Choice | Reason |
| --- | --- | --- |
| How the C dependency enters | A git submodule plus a C target whose path is the submodule root | Upstream has no `Package.swift`; the submodule keeps the upstream code, license, and history, a version bump is a checkout, and the generated module map keeps the pin clean |
| Concurrency boundary | `TelnetProtocolCore` is **owned by the NIO EventLoop** and is not an actor | The libtelnet state machine is not thread-safe and its callback synchronously produces outbound bytes; EventLoop ownership needs no lock and no preemption |
| Public concurrency type | `TelnetConnection` is an `actor`; events are wrapped in `AsyncStream` | Naturally `Sendable` for callers, who need no knowledge of EventLoop |
| Event delivery | `AsyncStream<TelnetEvent>` with a bounded buffer policy | Gives backpressure semantics and prevents unbounded growth |
| Outbound calls | `actor` method → `eventLoop.execute` / `NIOAsyncWriter` serialization | Keeps the call on the same thread as the `telnet_*` call and avoids a data race |
| Error model | A Swift `Error` enum mapped from libtelnet's `telnet_error_t` | No C error code leaks |
| Close semantics | `close()` is idempotent; the `events` stream finishes when the channel closes | Prevents `for await` from hanging forever |

### 4.3 Threading and concurrency model (mandatory constraints)

1. **Single-thread ownership**: `telnet_t*` is accessed only on the EventLoop that created it; every `telnet_recv`, `telnet_send*`, `telnet_iac`, and `telnet_negotiate` call happens on the same `NIOTSEventLoop` (a serial `DispatchQueue` underneath).
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

    /// A common preset: BINARY + SGA + TTYPE + NAWS offered locally, SGA + ECHO requested from the peer
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
    public var waitForConnectivity: Bool           // default true: wait for a route instead of failing at once
    public var idleTimeout: Duration?              // default nil
    public var inboundBufferLimit: Int             // default 64 KiB; exceeding it throws .bufferOverflow
    public var subnegotiationLimit: Int            // default 8 KiB, against SB flooding
    public var maxInflatedBytes: Int               // default 16 MiB; bounds one inflate output once zlib ships in v0.2, against bombs
    public var eventBufferPolicy: TelnetEventBufferPolicy  // .bounded(1024) / .unbounded / .dropOldest
    public var newlinePolicy: TelnetNewlinePolicy // .nvt / .raw
    public var logger: Logger?                     // swift-log; nil by default (silent)
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
    case unsupportedFeature(String)                // a capability this build lacks (no trigger in the first release)
    case invalidConfiguration(String)
    case cancelled
}

/// A structured transport failure: diagnostic detail is kept, but the public surface
/// never names NIOCore's concrete error generics, so NIO changes cannot break SemVer.
public struct TelnetTransportFailure: Error, Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case dns, posix(code: Int32), tls, channelClosed, writeTimeout, other }
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
| FR-PROTO-06 | NVT end-of-line semantics are exposed through `configuration.newlinePolicy`, never as a macro; proxy mode is out of scope (§1.3) | P1 | The newline policy has a test; no proxy-mode acceptance criterion exists |
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
| FR-NEG-10 | `compress2` is not registered in `TelnetOptions`: this end answers negotiations with `WONT` and never accepts a compressed stream | P1 | A `DO COMPRESS2` receives `WONT COMPRESS2`, and `optionStatus(.compress2)` reports all-false |
| FR-NEG-11 | The precondition for enabling compression (v0.2) is explicit: the inflation bound, event-flow behavior under compression, and the compressed-stream failure mode must all be designed | P2 | Each of the three has a test; `HAVE_ZLIB` stays undefined while any is missing |
| FR-NEG-12 | `optionStatus(_:)` reflects negotiation state live | P1 | State is asserted before and after negotiation |
| FR-NEG-13 | Capabilities such as `sendWindowSize` and `replyTerminalType` can be triggered from the demo | P1 | The demo exposes an entry point for each |

### 6.4 Text and encoding (FR-TEXT)

| ID | Requirement | Priority | Acceptance criterion |
| --- | --- | --- | --- |
| FR-TEXT-01 | `send(text:)` uses a CRLF line ending by default (`TelnetLineEnding.crlf`) | P0 | Outbound bytes assert `0D 0A` |
| FR-TEXT-02 | Support the `crNul`, `lf`, and `none` line endings | P1 | All three assert their bytes |
| FR-TEXT-03 | Skip CR/LF translation when BINARY is negotiated (matching `TELNET_FLAG_NVT_EOL` semantics) | P0 | `0x0A` survives intact in binary mode |
| FR-TEXT-04 | Encode all text as UTF-8; replace illegal input lossily and log a warning | P1 | Non-UTF-8 input does not crash |
| FR-TEXT-05 | `send(_ bytes:)` escapes `0xFF` automatically; `sendRaw` does not (for advanced use) | P0 | The byte assertions pass |

### 6.5 Network path and connection availability (FR-PATH)

NIOTS exposes Network.framework path events to SwiftNIO (`NIOTSNetworkEvents`). That capability is why a single transport is worth it, so it is a requirement rather than an option.

| ID | Requirement | Priority | Acceptance criterion |
| --- | --- | --- | --- |
| FR-PATH-01 | With `waitForConnectivity: true`, a connect request with no available route waits instead of failing immediately | P0 | In a simulated no-route state the call neither throws nor finishes, and the connection completes once a route returns |
| FR-PATH-02 | A path change maps to `.pathChanged(viable:expensive:constrained:)` | P0 | Switching between cellular and Wi-Fi produces the event, and `viable` matches `NWPath` |
| FR-PATH-03 | A better path produces `.betterPathAvailable`, and its loss produces `.betterPathUnavailable` | P1 | The pair follows `NIOTSNetworkEvents` semantics |
| FR-PATH-04 | A connection the system suspends (waiting for connectivity) emits `.waitingForConnectivity(error:description:)` without closing | P0 | The event is observable and recovery emits no duplicate connection event |
| FR-PATH-05 | A path event leaves protocol state untouched: `optionStatus(_:)` and negotiation state match before and after a path switch | P0 | `optionStatus` is asserted unchanged across the switch |
| FR-PATH-06 | Path events reach the public API as Swift values with no `NWPath` leak | P1 | The snapshot contains no `NWPath`, `NWError`, or `nw_*` |
| FR-PATH-07 | `.pathChanged` is emitted with the current viability only after the channel is active | P1 | A test asserts no path event precedes the connection event |

### 6.6 Errors and diagnostics (FR-ERR)

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
| Deployment target | `platforms: [.macOS(.v15), .iOS(.v18), .watchOS(.v11), .tvOS(.v18), .visionOS(.v2)]`; build products are promised for these five Apple platforms only, and non-Apple platforms get neither support nor a branch |
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

The case inventory below is the requirement list; [docs/testing.md](docs/testing.md) owns the environment, commands, quality gates, and CI matrix.

| Layer | Goal | Method |
| --- | --- | --- |
| L1 protocol unit tests (white box) | Per-event, per-byte correctness | `@testable import TelnetKit` and a direct byte feed into `TelnetProtocolCore` |
| L2 public interface tests (black box) | Contract stability, no C leak, error semantics | `import TelnetKit` only, against the test target's loopback fixture |
| L3 integration tests | A real connection, timeout, cancellation, concurrent connections, path events | `NIOTSConnectionBootstrap` against a local `NIOTSListenerBootstrap` fixture |
| L4 robustness | Fuzz input and resource bounds | Random and malicious byte streams, oversized SB, flooding |
| L5 static assurance | Interface, concurrency, and five platform builds | `swift-api-digester` snapshot, `swift build -Xswiftc -strict-concurrency=complete`, an AddressSanitizer job, and iOS, watchOS, tvOS, and visionOS simulator builds |

Every suite uses **Swift Testing** (`import Testing`, `@Test`/`@Suite`/`#expect`/`#require`) with `async` test functions; a test that needs timeout protection uses a `withTimeout` helper defined in the test target. The protocol and public interface suites run on all five platforms; the integration suite, which binds a socket and starts an echo server, runs on macOS and the iOS simulator.

### 8.2 Case inventory (required for the public interface)

**A. Connection lifecycle (FR-CONN)**

| Case | Assertion |
| --- | --- |
| `connect_loopback_succeeds` | Returns non-nil, `isConnected == true`, `remoteAddress == "127.0.0.1:<port>"` |
| `connect_refused_throws_connectionRefused` | Connecting to a closed port throws `.connectionRefused` |
| `connect_unresolvable_host_throws_invalidHost` | Throws `.invalidHost` |
| `connect_timeout_throws_connectTimeout` | A connect that outlives its configured bound produces `.connectTimeout` |
| `connect_cancellation_throws_cancelled` | `Task` cancellation produces `.cancelled` and no connection left on the server |
| `close_is_idempotent` | Two `close()` calls produce no error |
| `events_finish_on_remote_close` | `for await` ends normally after the server closes, under a 2 s timeout guard |
| `send_after_close_throws_notConnected` | Throws `.notConnected` |
| `optionStatus_reflects_negotiation` | echo and SGA state is correct after the handshake |
| `inbound_buffer_limit_enforced` | Exceeding the bound emits a fatal `.protocolError` and closes the connection |

**B. Protocol parsing (FR-PROTO, white box, per event)**

| Case | Input → expectation |
| --- | --- |
| `data_passthrough` | `"hello\r\n"` → `.data("hello\r\n")` |
| `iac_escape_unescaped` | `FF FF` → `.data([0xFF])` |
| `will_wont_do_dont_events` | `FF FB 01` / `FF FC 01` / `FF FD 01` / `FF FE 01` → four `.negotiation` events with the correct remote flag |
| `iac_command_events` | `FF F1` (NOP), `FF F9` (GA), `FF EC` (EOF) → `.command(...)` |
| `subnegotiation_payload` | `FF FA 18 00 78 74 65 72 6D FF F0` → `.terminalType("xterm")` |
| `subnegotiation_with_escaped_ff` | A payload containing `FF FF` restores to `0xFF` |
| `truncated_iac_sequence_warns` | `FF FB` at end of stream produces `.warning` without a crash |
| `garbage_stream_no_crash` | 100,000 random bytes produce no crash and self-consistent events |
| `subnegotiation_limit_exceeded` | An inbound block past the bound produces `.protocolError(.invalidSubnegotiation(option:))`; an outbound payload past it throws `.subnegotiationTooLarge` |
| `newenviron_parsing` | A VAR/USERVAR/VALUE/ESC combination produces the correct structured variables |
| `mssp_parsing` | `1 name 2 value` → `["name": "value"]` |
| `zmp_parsing` | A multi-argument command → `["cmd", "a", "b"]` |
| `nvt_eol_flag_behavior` | The two newline policies assert their byte differences |

**C. Negotiation and terminal capabilities (FR-NEG)**

| Case | Assertion |
| --- | --- |
| `initial_negotiation_sent_on_connect` | The first bytes the server receives are one `IAC <verb> <option>` triple per declared entry, in declaration order |
| `rfc1143_no_negotiation_loop` | Repeated and simultaneous verbs are each answered once; the client's byte count stays bounded |
| `unsupported_option_rejected` | `DO ZMP` for an undeclared option produces an outbound `WONT ZMP` |
| `ttype_send_triggers_reply_or_event` | TTYPE SEND produces `.terminalTypeRequested`; `replyTerminalType` sends IS, and a repeated SEND is answered again |
| `naws_reported_on_window_resize` | A window change makes the server receive four big-endian bytes |
| `naws_escapes_255` | A 255-column width makes the payload contain `FF FF` |
| `compress2_unsupported` | Negotiation produces `WONT`, `optionStatus(.compress2)` reports all-false, and no error is thrown |

**D. Text and encoding (FR-TEXT)**

| Case | Assertion |
| --- | --- |
| `send_text_crlf` / `send_text_crNul` / `send_text_lf` / `send_text_none` | Outbound bytes match exactly |
| `send_escapes_iac` | Application bytes containing `0xFF` produce outbound `FF FF`; UTF-8 text never carries a `0xFF` byte |
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
| `publicAPI_snapshot_matches` | `swift package diagnose-api-breaking-changes <baseline>` reports no breaking change |
| `documentation_builds` | `xcodebuild docbuild` produces `TelnetKit.doccarchive` with 0 diagnostics for the target |

### 8.3 Quality gates

- The public interface tests (L2) **must cover every public symbol listed in §5** (method, property, enum case); the coverage report is checked against the public symbol list and a gap fails the gate.
- Protocol-layer statement coverage of at least 90%. `llvm-cov` emits no branch data for Swift, so region (84.1%) and function (78.2%) coverage are recorded beside it rather than a branch gate.
- Every test runs offline, and one `swift test` invocation finishes in under 60 s.

---

## 9. Demo project requirements

### 9.1 Deliverables

| Name | Form | Purpose |
| --- | --- | --- |
| `telnetkit-client` | `.executableTarget` (CLI, macOS only) | A complete interactive Telnet client that accepts the `telnet(1)` flags and drives TelnetKit; it is a working tool rather than an interface showcase |
| `TelnetEchoServer` (the `telnetkit-echo-server` command) | `.executableTarget` (local server, macOS only) | An integration target with no external dependency: echo, plus active TTYPE/NAWS/NEW-ENVIRON negotiation and injected negotiation, subnegotiation, warning, and oversized-subnegotiation scenarios |
| `TelnetKitDemoApp` | SwiftUI app, macOS and iOS targets (`Examples/`) | An interactive terminal: connection panel, output area, input field, option-status table, event log, automatic window-size reporting |

### 9.1.1 Documentation deliverables

This PRD's engineering constraints are split into development documents kept beside the code; tiers and writing rules are in [docs/AGENTS.md](docs/AGENTS.md):

| Document | Responsibility |
| --- | --- |
| [AGENTS.md](AGENTS.md) | Standing orders: repository layout, commands, non-negotiable constraints, conventions |
| [docs/architecture.md](docs/architecture.md) | Design map: layers, concurrency model, event flow, C seam, extension points, test layout |
| [docs/public-api.md](docs/public-api.md) | The caller contract and the public symbol test checklist |
| [README.md](README.md) / [README.zh.md](README.zh.md) | The consumer contract: capabilities, install, quick start, known limitations, security |
| [Examples/TelnetKitDemoApp/README.md](Examples/TelnetKitDemoApp/README.md) | The demo app's run procedure and the interfaces it exercises |
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

1. `swift run telnetkit-client 127.0.0.1 2323` reaches a local server and carries an interaction, needing no network and no external service.
2. The demo can reach a real external Telnet service (a public BBS or a device) and complete one full interaction: the login prompt is visible and commands can be typed; on iOS a minimal simulator example runs the same path against the loopback server.
3. `TelnetKitDemoApp` is usable the moment it opens on macOS 15+; resizing the window triggers a NAWS report that is visible in the echo server log. The library itself builds on an iOS 18+ simulator and passes every non-network test there.
4. The demo code is documentation: every public interface appears at least once in it, and the README carries a matching code snippet.

---

## 10. Milestones and delivery plan

| Milestone | Content | Exit criterion | Status |
| --- | --- | --- |
| M0 scaffolding | `Package.swift` (five platforms plus the NIOTS dependency), the libtelnet submodule with our tracked module map, two symlinks, and `UPSTREAM.md` (recording the pinned commit), directory skeleton, CI skeleton, LICENSE and NOTICE | `swift build` and `swift test` pass against the macOS 15 target and all five platforms build (**verified: `swift build --target TelnetKit --triple` succeeds for the macOS 15, iOS 18, watchOS 11, tvOS 18, and visionOS 2 floors**) | Shipped |
| M1 protocol layer | `TelnetProtocolCore`, every `TelnetEvent` mapping, NVT coding, and the L1 unit tests (groups B and D) | Groups B and D are green and ASan passes | Shipped |
| M2 connection layer | `TelnetChannelHandler`, the `TelnetConnection` actor, timeout, cancellation, and close, with L2/L3 tests (group A) | Group A is green; `leaks --atExit` reports 0 leaked bytes over 300 connections and 100,000 events | Shipped |
| M3 negotiation and capabilities | RFC 1143 negotiation strategy, TTYPE/NAWS/NEW-ENVIRON/MSSP/ZMP, and group C tests | Group C is green; repeated and simultaneous negotiation produces a bounded byte count | Shipped |
| M4 quality and documentation | Groups E, F, and G, DocC, interface snapshot, coverage gates, README, CHANGELOG | Protocol line coverage is 92.3%; the DocC build reports 0 target diagnostics; the symbol graph holds no forbidden name; the API baseline shows no breaking change | Shipped |
| M5 demo | `telnetkit-client`, `telnetkit-echo-server`, and the SwiftUI demo app in `Examples/TelnetKitDemoApp/` | Criteria 1 and 4 hold: the client reaches the echo server, and the app covers every public interface with a matching README snippet. Criterion 2 and criterion 3's local half are manual steps that are not recorded | Partial |
| M6 Apple platform matrix | `Package.swift` declares all five platforms; CI gains iOS, watchOS, tvOS, and visionOS simulator builds and tests; the path events (FR-PATH) and background-suspension behavior are re-reviewed on iOS | All five platforms build; the protocol and public interface suites are green on macOS and iOS, and the remaining platforms build | Partial |
| M7 release | v0.1.0 tag, release notes, macOS and iOS simulator screenshots or recordings | The tag is pushed and `Package.resolved` is archived | Planned |

> Status: **Shipped** means the exit criterion is met and the evidence is in [AGENTS.md](AGENTS.md#design-status); **Partial** means code or evidence has landed but the exit criterion is not met; **Planned** means no work has started. M6 has built all five floors but has not run their test matrix; M5 has shipped all three demo programs, and its two manual acceptance steps (one full interaction with a real service, and the window-size report on resize) are not recorded.

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
| R6 | Telnet is plaintext, including passwords, and this library offers no encrypted channel | High | State it prominently in the README and DocC; list `telnets`, START-TLS, ENCRYPT, and AUTHENTICATION as unsupported; a deployment that needs confidentiality uses a VPN or a bastion host, and the `TelnetConfiguration` documentation says the library takes no part in confidentiality |
| R7 | Enabling MCCP2 exposes the inflate path to a decompression bomb (a few KB into gigabytes of memory) | Medium | Leave it off in the first release; enabling it in v0.2 requires the `maxInflatedBytes` bound, the event-flow contract under compression, and a compressed-stream failure test, plus an enabled CI variant. zlib itself needs no work: the macOS, iOS, and iPadOS SDKs all ship it (verified linkable with `-lz`) |
| R8 | A poor `AsyncStream` buffer policy causes memory growth or event loss | Medium | Default to `.bounded` with a configurable drop or finish policy, emit a `.warning` **when an event is dropped**, and add a high-traffic stress test |
| R9 | The public API couples to swift-nio types such as `ByteBuffer`, which limits a future upgrade | Low | Use `ByteBuffer` as the binary carrier for `TelnetEvent.data` because it matches the NIO ecosystem, and provide `text` and `bytes([UInt8])` accessors so a caller never has to understand NIO |
| R10 | Suspending the app drops the connection (most visible on watchOS and iOS), and App Store review scrutinizes plaintext protocols | Medium | Document the foreground-session semantics and the disconnect-on-background behavior, add no background daemon, provide `idleTimeout` and a caller-side reconnect example, and let `waitForConnectivity` remove the hand-written retry loop on recovery; flag the plaintext risk in the README security section |
| R11 | Five-platform CI cost and simulator resource use | Medium | iOS runs the full suite; watchOS, tvOS, and visionOS run the build plus the protocol and public interface suites; integration tests stay in the macOS job |
| R12 | NIOTS can only be verified on a runtime that has Network.framework, so a local `swift test` cannot exercise real path events | Medium | The integration suite starts a local fixture with `NIOTSListenerBootstrap`; path events are tested at the protocol layer with injected `NIOTSNetworkEvents`; a real cellular-to-Wi-Fi switch on a device or simulator is a manual M6 acceptance step |
| R13 | One transport leaves no fallback: if Network.framework misbehaves on a platform (watchOS connection availability, for example), there is no alternative path | Medium | Promise only the five Apple platforms and only officially supported combinations; document a platform-level defect as a platform limitation instead of introducing a POSIX branch, which would overturn G6 |

---

## 12. Open questions

| ID | Question | Proposed default |
| --- | --- | --- |
| Q1 | Should `TelnetEvent.data` use `NIOCore.ByteBuffer` or a custom `[UInt8]`? | Use `ByteBuffer` (zero copy, consistent with the NIO ecosystem) and provide `[UInt8]` and `String` convenience views |
| Q2 | Does the library provide reconnection, or only an example? | An example only: the library owns `waitForConnectivity` and clear errors, and the caller owns the retry policy |
| Q3 | Should the SwiftUI demo app be an in-package executable target or a separate `Examples/` Xcode project? | Decided: a separate project under `Examples/`, committed together with its XcodeGen `project.yml`, so referencing SwiftUI inside the package cannot slow `swift test`; the app carries its own views instead of adding a package component |
| Q4 | Is `swift-metrics` or `swift-service-lifecycle` integration needed? | Not in the first release; swift-log is enough |
| Q5 | Should Chinese documentation ship alongside the English? | Decided: every human-facing document is a bilingual pair under the [documentation standard](docs/AGENTS.md#bilingual-pairs), so this PRD pairs with [PRD.zh.md](PRD.zh.md) |

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
    platforms: [.macOS(.v15), .iOS(.v18), .watchOS(.v11), .tvOS(.v18), .visionOS(.v2)],
    products: [
        .library(name: "TelnetKit", targets: ["TelnetKit"]),
        .executable(name: "telnetkit-client", targets: ["TelnetKitClient"]),
        .executable(name: "telnetkit-echo-server", targets: ["TelnetEchoServer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.103.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.20.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    ],
    targets: [
        // SwiftPM finds a custom module map only in the public headers directory, which must sit
        // under the target path while the .c compiles from that same path, so the target is our own
        // directory and two committed symlinks reach the submodule's source and header.
        // HAVE_ZLIB stays undefined: the Apple SDKs ship zlib and -lz links, but the first release does not link it (rationale in §1.3, enablement conditions in §6.3 FR-NEG-11).
        .target(
            name: "CLibTelnet",
            path: "Sources/CLibTelnet",
            publicHeadersPath: "include"
        ),
        .target(
            name: "TelnetKit",
            dependencies: [
                "CLibTelnet",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(name: "TelnetKitClient", dependencies: ["TelnetKit"], path: "Sources/TelnetKitClient"),
        // Executables declare macOS only: watchOS, tvOS, and visionOS have no process or loopback-server semantics.
        .executableTarget(name: "TelnetEchoServer", dependencies: [
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
        ]),
        .testTarget(name: "TelnetKitTests", dependencies: ["TelnetKit"]),
    ]
)
```

> Note: in the prototype, `CLibTelnet` needed no custom compile macro and no interoperability mode; the `module.modulemap` alone let Swift import it, so the real implementation keeps the same minimal configuration.
> `swiftLanguageModes` could also be declared once for the package (`swiftLanguageModes: [.v6]`); declaring it per target keeps the option of relaxing it for test targets.
> A clone needs one command, `git submodule update --init --recursive`; the symlinks and the module map are tracked, so no generation step exists.
> `path` and `publicHeadersPath` are SwiftPM requirements: the `.c` compiles from the target path, and the public headers must live under it.
> `path: "libtelnet"` and `publicHeadersPath: "include"` are SwiftPM requirements: the `.c` compiles from the target path, and the public headers must live under it.

## Appendix B: `CLibTelnet` directory and modulemap

```c
// Sources/CLibTelnet/include/module.modulemap, tracked; module CLibTelnet lives here
module CLibTelnet {
    umbrella header "libtelnet.h"   // the header is a symlink into the submodule
    export *
}
```

- `libtelnet.c` and `libtelnet.h` come from the `libtelnet/` submodule at the pinned commit `5f5ecee` (version tag `\version 0.23`), reached by two tracked relative symlinks; **no upstream file is modified and nothing is written into the submodule**.
- The gitlink carries the pin and `Sources/CLibTelnet/UPSTREAM.md` records it; an upgrade checks out a new commit and confirms both links still resolve.
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
