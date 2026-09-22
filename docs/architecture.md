# TelnetKit Architecture

English | [中文](architecture.zh.md)

Read this before changing anything under `Sources/`. It is the design contract: the library layers and the demo programs are implemented, every statement below is **Designed** unless marked otherwise, and status lives in the [design-status rule](../AGENTS.md#design-status). Requirements and acceptance criteria live in [PRD.md](../PRD.md); caller-visible signatures live in [public-api.md](public-api.md).

## Composition

TelnetKit separates protocol parsing from connection management, so a test can drive either one without the other.

```text
TelnetConnection (actor, Public)            caller-facing session
  AsyncStream<TelnetEvent>                  event delivery, including path events
        |
TelnetProtocolCore (internal)               owns telnet_t, maps events
  option table, option status ledger        Swift-side state libtelnet does not export
        |
TelnetChannelHandler (internal)             ChannelDuplexHandler
  ByteBuffer in / IOData out                copies callback buffers, queues outbound bytes
        |
NIOTSConnectionBootstrap + NIOTSEventLoopGroup
  waits for a route, reports path changes   Network.framework owns the connection
        |
Network.framework                            path, proxy, VPN, power
        |
CLibTelnet (C target)                       libtelnet submodule 0.23, parsing only
```

One connection owns exactly one `TelnetProtocolCore`, one handler, one channel, and one `NIOTSEventLoop`. No state is shared between connections, so two sessions cannot observe each other's bytes.

## Platform and transport decision

**Verified.** The library builds for the macOS 15, iOS 18, watchOS 11, tvOS 18, and visionOS 2 floors from one source tree; Network.framework through NIOTS is the only transport. Non-Apple platforms are not promised, and no abstraction or conditional compilation is kept for them.

The decision record:

| Decision | Choice | Reason |
|---|---|---|
| Transport | `NIOTSConnectionBootstrap` on `NIOTSEventLoopGroup` | Network.framework is Apple's supported transport and supplies connection management, proxy and VPN integration, path monitoring, and energy behavior without per-feature code |
| No POSIX path | `NIOPosix` is not a dependency | A second transport would double the invariants (backpressure, cancellation, path reporting) to prove on five platforms while adding no capability a caller asked for |
| No TLS | Telnet over TLS/SSL is unsupported: not `telnets`/992, not START-TLS, not the TELNET ENCRYPT or AUTHENTICATION options | The standard was abandoned, devices that offer it are rare, neither Apple's nor Homebrew's telnet implements it, upstream libtelnet implements neither option, and confidentiality belongs to a VPN or a bastion host rather than to this library |
| Executables | macOS only | Both need a process, a terminal, and a loopback listener, which watchOS, tvOS, and visionOS do not provide; `TelnetEchoServer` links neither `TelnetKit` nor `CLibTelnet`, so it cannot share a parser defect with the library |

Test placement follows the same split: the protocol and public interface suites run on all five platforms, while the integration suite, which binds a loopback listener, runs on macOS and the iOS simulator.

## Concurrency model

**Verified.** The protocol state machine is single-threaded, and the design enforces that by ownership rather than by locking.

| Rule | Reason |
|---|---|
| `telnet_t` is created, used, and freed on the EventLoop that owns the channel | libtelnet has no internal synchronization; a lock would serialize two threads inside a parser that also invokes callbacks |
| `TelnetProtocolCore` exposes no method that may be called off its EventLoop | A precondition-free API invites a cross-thread call that only fails under load |
| `TelnetConnection` is an `actor`; public methods are `async` | Callers get `Sendable` access without learning about EventLoop; the actor hops work onto the owning EventLoop |
| Event delivery uses a bounded `AsyncStream` | The caller controls backpressure; a dropped event is reported rather than silently lost |
| The event callback copies and returns | `telnet_event_t` payload pointers expire at callback return |
| Outbound bytes collected during a callback are flushed after it returns | Calling `telnet_send*` inside a callback reenters the parser mid-parse |

Event ordering per connection is: parse inbound bytes, emit events in wire order, flush queued outbound bytes, then complete the write promise. A caller observing `events` sees the same order for every connection, and a `.data` event never overtakes the negotiation that enabled it.

`NIOTSEventLoop` is a serial `DispatchQueue` underneath, so the rule that every `telnet_*` call happens on one thread holds exactly as it does for NIO's POSIX event loop; the difference is Dispatch QoS scheduling instead of `pthreads` plus `kqueue`.

## Event flow

Inbound: NIO delivers a `ByteBuffer` to `TelnetChannelHandler.channelRead`; the handler passes the bytes to `TelnetProtocolCore.feed`, which calls `telnet_recv`; libtelnet invokes the C event callback once per protocol event; the callback copies payload bytes and appends a Swift `TelnetEvent` to the queue; after `telnet_recv` returns, the handler yields the queued events to the `AsyncStream` continuation.

Outbound: a public call such as `send(text:)` enters the actor and hops to the EventLoop; the handler encodes through `telnet_send` or `telnet_send_text`; libtelnet reports the encoded bytes as `TELNET_EV_SEND`, which the callback appends to the outbound queue; the handler writes that queue as `IOData` and completes the promise; the public call returns when the write completes or throws `TelnetError.transportFailed`.

Path events travel on a separate channel: SwiftNIO's `NIOTSNetworkEvents` (`PathChanged`, `BetterPathAvailable`, `BetterPathUnavailable`, `ViabilityUpdate`, `WaitingForConnectivity`) are read by `TelnetNetworkEventMapping` and mapped to the path cases of `TelnetEvent`. These events never touch the protocol state machine: they call neither `telnet_recv` nor the option ledger.

Negotiation is a three-step exchange, and all three steps are observable:

1. Connect-time negotiation sends the initial `WILL`/`DO` set from `TelnetOptions`.
2. Each received `WILL`/`WONT`/`DO`/`DONT` yields a `.negotiation` event and updates the Swift option ledger.
3. libtelnet answers according to RFC 1143 Q-method rules, and the answer appears as outbound bytes.

Step 3 is libtelnet's; steps 1 and 2 are ours. The option ledger exists because libtelnet 0.23 exports no query for negotiated state, so `optionStatus(_:)` is derived from events the core already sees.

## The C seam

**Verified.** The C target is `Sources/CLibTelnet`, which reaches the submodule through two committed relative symlinks and holds a tracked module map declaring `umbrella header "libtelnet.h"`. The submodule's source compiles with no warnings and Swift imports the functions directly, while the submodule's working tree stays clean.

The seam is narrow on purpose. `TelnetProtocolCore` is the only file in the package that imports `CLibTelnet`; every other file works in Swift types. Three libtelnet facilities are macros and therefore invisible to Swift, so the core supplies them: `telnet_finish_sb` as `telnet_iac(handle, TELNET_SE)`, `telnet_finish_newenviron` and `telnet_finish_zmp` as that same call.

The pin, the generated module map, and the upstream upgrade procedure are owned by `Sources/CLibTelnet/UPSTREAM.md` and the [import skill](../.agents/skills/telnetkit-import-c-library/SKILL.md).

## Option and command modeling

**Verified.** Wire codes become Swift values in one mapping file, `Sources/TelnetKit/Public/TelnetOption.swift` and `TelnetCommand.swift`, and nowhere else.

`TelnetOption` is a `RawRepresentable` struct wrapping `UInt8` with static constants, not an enum: Telnet assigns over 250 option codes and libtelnet accepts any of them, so an enum would need an unbounded associated-value case and would break `CaseIterable` traversal. A code with no constant stays representable, and `displayName` renders it as `option(<code>)`.

`TelnetCommand` is a closed enum because RFC 854 and its successors fix the command set at 20 values, and an unrecognized command byte is a protocol violation rather than a new command.

`TelnetNegotiation` names the four negotiation verbs with Swift spellings (`will`, `wont`, `do`, `dont`) so no macro constant reaches the public surface. The numeric mapping lives in the same file as a one-way conversion used only by the core.

## Event model

**Verified.** `TelnetEvent` is a closed enum with one case per libtelnet event plus the structured cases the core derives: `localEchoChanged`, `terminalType(_:)`, `environment(_:_:)`, and the path reports. A caller that needs only bytes and text matches two cases; a caller that needs protocol detail matches all.

Byte payloads travel as `NIOCore.ByteBuffer` because it is the type NIO already produced, so delivery copies nothing. A convenience accessor exposes bytes and UTF-8 text, so a caller never has to learn NIO to read output.

The union discrimination that C performs with `event.type` happens in one `switch` in the core. Because libtelnet's union zero-fills `type` and reuses the first field as an alias, the core reads the aliased field and must not read a member that the event type does not select. Two events, `TELNET_EV_WARNING` and `TELNET_EV_ERROR`, carry a file, function, and line and are mapped into `TelnetWarning` and `TelnetProtocolError` with the C strings copied into Swift strings.

## Error model

**Verified.** Failures are values, never crashes. `TelnetError` covers connection establishment, transport, protocol, and configuration failures; each libtelnet `telnet_error_t` case maps to exactly one `TelnetError` case, and the mapping is exhaustive with no `default` arm.

Recoverable and fatal stay separate. A `.warning` event leaves the connection usable; a `.protocolError` closes it, finishes the event stream, and makes later calls throw `.notConnected`. Mapping a fatal condition to a warning would strand a caller in a parser that cannot make progress, and mapping a warning to fatal would drop a session over a malformed sequence.

Network.framework's error set (`NWError`) is mapped to `TelnetTransportFailure.Kind` inside `TelnetNetworkEventMapping`, so no `NWError` or `nw_*` type reaches the public API.

## Resource bounds

**Verified.** Every peer-controlled value has a ceiling with an owner in `TelnetConfiguration`; the v0.2 inflated-bytes row stays designed while zlib is off.

| Bound | Default | Owner | Failure |
|---|---|---|---|
| Inbound bytes without a data event | 64 KiB | `inboundBufferLimit` | `.protocolError`, connection closes |
| Subnegotiation payload | 8 KiB | `subnegotiationLimit` | `.subnegotiationTooLarge` |
| Inflated bytes per `inflate` call (v0.2, zlib off in the first release) | 16 MiB | `maxInflatedBytes` | `.bufferOverflow`, connection closes |
| Queued events awaiting consumption | 1024 | `eventBufferPolicy` | policy-dependent: `.warning` with a drop count, or stream finish |
| Connect handshake | 10 s | `connectTimeout` | `.connectTimeout` |
| Waiting with no route | on | `waitForConnectivity` | No failure: the connect suspends and emits `.waitingForConnectivity` |
| Idle connection | none | `idleTimeout` | connection closes |

## Extension points

**Designed.** A new capability attaches to one of five places, and the choice fixes where its tests go.

| Goal | Place | Consequence |
|---|---|---|
| Support another Telnet option | Add a constant in `TelnetOption.swift` and handle the case in the core; no new public type | Public surface unchanged |
| Add a structured event | Add a `TelnetEvent` case, a `switch` arm in the core, and a test in the protocol suite | Public surface widens; public-api.md updates in the same change |
| Change connection setup, such as connectivity waiting or multipath | `TelnetConfiguration` plus the bootstrap in `Transport/` | Public surface widens or keeps its shape; connect tests cover the path |
| Add a convenience operation such as window-size reporting | A method on `TelnetConnection` that composes existing core calls | No core change; public-api.md and its test update together |
| Change output text handling | `TelnetWireCoding` | Line-ending and escaping tests in the protocol suite cover it |

No extension point changes the parse layer: `telnet_recv` and the event callback stay the only path from bytes to events.

## Test architecture

Tests mirror the layers, and each layer is reachable without the one above it.

| Suite | Layer under test | Fixture |
|---|---|---|
| `Tests/TelnetKitTests/Protocol/` | `TelnetProtocolCore` through `@testable import` | Byte arrays in, `[TelnetEvent]` out; no socket |
| `Tests/TelnetKitTests/PublicAPI/` | `TelnetConnection` through `import TelnetKit` only | A `NIOTSListenerBootstrap` fixture in the test target |
| `Tests/TelnetKitTests/Integration/` | Connection behavior: timeout, cancellation, close, concurrency, path events | A local fixture started with `NIOTSListenerBootstrap`, plus injected `NIOTSNetworkEvents` |

The protocol suite is the correctness gate for RFC behavior; the public API suite is the contract gate, and it touches every public symbol listed in [public-api.md](public-api.md#symbol-checklist). The integration suite owns timing: a test that depends on a timeout uses a short configured bound and a generous assertion bound, never a fixed sleep.

Platform placement: the protocol and public interface suites run on all five platforms, while the integration suite, which binds a loopback listener, runs only on macOS and the iOS simulator, because watchOS, tvOS, and visionOS provide no process or loopback-server semantics. The demo programs are the manual path, not a substitute for any suite.
