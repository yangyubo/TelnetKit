# TelnetKit Architecture

English | [中文](architecture.zh.md)

Read this before changing anything under `Sources/`. It is the design contract: the package is not implemented yet, every statement below is **Designed** unless marked otherwise, and status lives in the [design-status rule](../AGENTS.md#design-status) rather than in this file. Requirements and acceptance criteria live in [PRD.md](../PRD.md); caller-visible signatures live in [public-api.md](public-api.md).

## Composition

TelnetKit separates protocol parsing from connection management, so a test can drive either one without the other.

```text
TelnetConnection (actor, Public)            caller-facing session
  AsyncStream<TelnetEvent>                  outbound event delivery
        |
TelnetProtocolCore (internal)               owns telnet_t, maps events
  option table, option status ledger        Swift-side state libtelnet does not export
        |
TelnetChannelHandler (internal)             NIO inbound/outbound handler
  ByteBuffer <-> ProtocolCore               copies callback buffers, queues outbound bytes
        |
NIOAsyncChannel + ClientBootstrap           TCP, timeouts, cancellation, backpressure
        |
CLibTelnet (C target)                       vendored libtelnet 0.23
```

One connection owns exactly one `TelnetProtocolCore`, one handler, one channel, and one EventLoop. No state is shared between connections, so two sessions cannot observe each other's bytes.

## Platform support

**Designed.** The library builds for macOS 15 and iOS 18 from one source tree. SwiftNIO's POSIX transport provides the socket on both, so no transport fork exists and no `#if os(...)` branch is planned; a branch added later must carry a build or test that exercises it.

The tooling targets differ by platform, and the difference is deliberate: `TelnetEchoServer`, the CLI demo, and the SwiftUI demo app are macOS-only executables, because the server accepts a loopback connection under a plain `swift run`. iOS verification uses the simulator for the library build plus the protocol and public interface suites, while integration tests stay on macOS.

## Concurrency model

**Designed.** The protocol state machine is single-threaded, and the design enforces that by ownership rather than by locking.

| Rule | Reason |
|---|---|
| `telnet_t` is created, used, and freed on the EventLoop that owns the channel | libtelnet has no internal synchronization; a lock would serialize two threads inside a parser that also invokes callbacks |
| `TelnetProtocolCore` exposes no method that may be called off its EventLoop | A precondition-free API invites a cross-thread call that only fails under load |
| `TelnetConnection` is an `actor`; public methods are `async` | Callers get `Sendable` access without learning about EventLoop; the actor hops work onto the owning EventLoop |
| Event delivery uses a bounded `AsyncStream` | The caller controls backpressure; a dropped event is reported rather than silently lost |
| The event callback copies and returns | `telnet_event_t` payload pointers expire at callback return |
| Outbound bytes collected during a callback are flushed after it returns | Calling `telnet_send*` inside a callback reenters the parser mid-parse |

Event ordering per connection is: parse inbound bytes, emit events in wire order, flush queued outbound bytes, then complete the write promise. A caller observing `events` sees the same order for every connection, and a `.data` event never overtakes the negotiation that enabled it.

## Event flow

Inbound: NIO delivers a `ByteBuffer` to `TelnetChannelHandler.channelRead`; the handler passes the bytes to `TelnetProtocolCore.feed`, which calls `telnet_recv`; libtelnet invokes the C event callback once per protocol event; the callback copies payload bytes and appends a Swift `TelnetEvent` to the queue; after `telnet_recv` returns, the handler yields the queued events to the `AsyncStream` continuation.

Outbound: a public call such as `send(text:)` enters the actor and hops to the EventLoop; the handler encodes through `telnet_send` or `telnet_send_text`; libtelnet reports the encoded bytes as `TELNET_EV_SEND`, which the callback appends to the outbound queue; the handler writes that queue to the channel and completes the promise; the public call returns when the write completes or throws `TelnetError.transportFailed`.

Negotiation is a three-step exchange, and all three steps are observable:

1. Connect-time negotiation sends the initial `WILL`/`DO` set from `TelnetOptions`.
2. Each received `WILL`/`WONT`/`DO`/`DONT` yields a `.negotiation` event and updates the Swift option ledger.
3. libtelnet answers according to RFC 1143 Q-method rules, and the answer appears as outbound bytes.

Step 3 is libtelnet's; steps 1 and 2 are ours. The option ledger exists because libtelnet 0.23 exports no query for negotiated state, so `optionStatus(_:)` is derived from events the core already sees.

## The C seam

**Verified.** `Sources/CLibTelnet/libtelnet.c` and `include/libtelnet.h` compile with no warnings as a SwiftPM C target when `include/module.modulemap` declares `module CLibTelnet { header "libtelnet.h" export * }`. Swift imports the functions directly.

The seam is narrow on purpose. `TelnetProtocolCore` is the only file in the package that imports `CLibTelnet`; every other file works in Swift types. Three libtelnet facilities are macros and therefore invisible to Swift, so the core supplies them: `telnet_finish_sb` as `telnet_iac(handle, TELNET_SE)`, `telnet_finish_newenviron` and `telnet_finish_zmp` as that same call.

Provenance, copying, and the upstream upgrade procedure are owned by `Sources/CLibTelnet/UPSTREAM.md` and the [import skill](../.agents/skills/telnetkit-import-c-library/SKILL.md).

## Option and command modeling

**Designed.** Wire codes become Swift values in one mapping file, `Sources/TelnetKit/Public/TelnetOption.swift` and `TelnetCommand.swift`, and nowhere else.

`TelnetOption` is a `RawRepresentable` struct wrapping `UInt8` with static constants, not an enum: Telnet assigns over 250 option codes and libtelnet accepts any of them, so an enum would need an unbounded associated-value case and would break `CaseIterable` traversal. A code with no constant stays representable, and `displayName` renders it as `option(<code>)`.

`TelnetCommand` is a closed enum because RFC 854 and its successors fix the command set at 20 values, and an unrecognized command byte is a protocol violation rather than a new command.

`TelnetNegotiation` names the four negotiation verbs with Swift spellings (`will`, `wont`, `do`, `dont`) so no macro constant reaches the public surface. The numeric mapping lives in the same file as a one-way conversion used only by the core.

## Event model

**Designed.** `TelnetEvent` is a closed enum with one case per libtelnet event, plus three structured cases the core derives: `localEchoChanged`, `terminalType(_:)`, and `environment(_:_:)`. A caller that needs only bytes and text matches two cases; a caller that needs protocol detail matches all.

Byte payloads travel as `NIOCore.ByteBuffer` because it is the type NIO already produced, so delivery copies nothing. A convenience accessor exposes bytes and UTF-8 text, so a caller never has to learn NIO to read output.

The union discrimination that C performs with `event.type` happens in one `switch` in the core. Because libtelnet's union zero-fills `type` and reuses the first field as an alias, the core reads the aliased field and must not read a member that the event type does not select. Two events, `TELNET_EV_WARNING` and `TELNET_EV_ERROR`, carry a file, function, and line and are mapped into `TelnetWarning` and `TelnetProtocolError` with the C strings copied into Swift strings.

## Error model

**Designed.** Failures are values, never crashes. `TelnetError` covers connection establishment, transport, protocol, and configuration failures; each libtelnet `telnet_error_t` case maps to exactly one `TelnetError` case, and the mapping is exhaustive with no `default` arm.

Recoverable and fatal stay separate. A `.warning` event leaves the connection usable; a `.protocolError` closes it, finishes the event stream, and makes later calls throw `.notConnected`. Mapping a fatal condition to a warning would strand a caller in a parser that cannot make progress, and mapping a warning to fatal would drop a session over a malformed sequence.

## Resource bounds

**Designed.** Every peer-controlled value has a ceiling with an owner in `TelnetConfiguration`.

| Bound | Default | Owner | Failure |
|---|---|---|---|
| Inbound bytes without a data event | 64 KiB | `inboundBufferLimit` | `.bufferOverflow`, connection closes |
| Subnegotiation payload | 8 KiB | `subnegotiationLimit` | `.subnegotiationTooLarge` |
| Queued events awaiting consumption | 1024 | `eventBufferPolicy` | policy-dependent: `.warning` with a drop count, or stream finish |
| Connect handshake | 10 s | `connectTimeout` | `.connectTimeout` |
| Idle connection | none | `idleTimeout` | connection closes |

## Extension points

**Designed.** A new capability attaches to one of five places, and the choice fixes where its tests go.

| Goal | Place | Consequence |
|---|---|---|
| Support another Telnet option | Add a constant in `TelnetOption.swift` and handle the case in the core; no new public type | Public surface unchanged |
| Add a structured event | Add a `TelnetEvent` case, a `switch` arm in the core, and a test in the protocol suite | Public surface widens; public-api.md updates in the same change |
| Change TCP setup such as TLS | `TelnetConfiguration` plus the bootstrap in `Transport/` | Public surface widens or keeps its shape; connect tests cover the path |
| Add a convenience operation such as window-size reporting | A method on `TelnetConnection` that composes existing core calls | No core change; public-api.md and its test update together |
| Change output text handling | `TelnetWireCoding` | Line-ending and escaping tests in the protocol suite cover it |

No extension point changes the parse layer: `telnet_recv` and the event callback stay the only path from bytes to events.

## Test architecture

Tests mirror the layers, and each layer is reachable without the one above it.

| Suite | Layer under test | Fixture |
|---|---|---|
| `Tests/TelnetKitTests/Protocol/` | `TelnetProtocolCore` through `@testable import` | Byte arrays in, `[TelnetEvent]` out; no socket |
| `Tests/TelnetKitTests/PublicAPI/` | `TelnetConnection` through `import TelnetKit` only | `TelnetEchoServer` on the loopback address |
| `Tests/TelnetKitTests/Integration/` | Transport behavior: timeout, cancellation, close, concurrency | `TelnetEchoServer` plus a raw NIO server for malformed input |

The protocol suite is the correctness gate for RFC behavior; the public API suite is the contract gate, and it touches every public symbol listed in [public-api.md](public-api.md#symbol-checklist). The integration suite owns timing: a test that depends on a timeout uses a short configured bound and a generous assertion bound, never a fixed sleep. The demo executables are the manual path and the fixture, not a substitute for any suite.
