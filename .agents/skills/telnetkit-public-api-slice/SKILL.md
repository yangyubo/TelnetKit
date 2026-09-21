---
name: telnetkit-public-api-slice
description: Implement one slice of the TelnetKit public API end to end, from the contract in docs/public-api.md through protocol code, the NIO transport, the public actor, and the tests that prove it. Use when adding or changing a public type, method, event case, error case, or configuration field in TelnetKit, or when a public symbol lacks a passing test.
---

# Implementing a public API slice

## Summary

A slice is one caller-visible capability, complete: contract, protocol handling, transport wiring, public surface, test, and documentation. This workflow keeps the layers in order so a slice never lands as untested public surface. It is guidance, not a checklist to fill mechanically; skip a step only when the slice genuinely does not touch that layer, and say so in the report.

## Table of Contents

- [Inputs and exclusions](#inputs-and-exclusions)
- [Workflow](#workflow)
- [Layer order and what belongs at each](#layer-order-and-what-belongs-at-each)
- [Rules](#rules)
- [Validation](#validation)
- [Dev Note](#dev-note)

## Inputs and exclusions

Require an explicit slice: a named public symbol or a named event case. If the request is "implement the library", propose a slice list from the [milestones](../../../PRD.md#10-里程碑与交付计划) and stop until one is chosen.

Exclude `Sources/CLibTelnet/` from edits, including documentation edits; its owner is [telnetkit-import-c-library](../telnetkit-import-c-library/SKILL.md).

## Workflow

1. Read [docs/public-api.md](../../../docs/public-api.md) for the symbol's contract, [docs/architecture.md](../../../docs/architecture.md) for the layer that owns it, and the [root AGENTS.md](../../../AGENTS.md) for the standing constraints. Read the PRD requirement and acceptance criterion that motivate the slice.
2. Write the contract test first, at the lowest layer that can observe the behavior. A protocol behavior is a byte-in, event-out test in `Tests/TelnetKitTests/Protocol/`; a capability that needs a socket is a test in `Tests/TelnetKitTests/PublicAPI/`.
3. Implement at the protocol layer: add or extend `TelnetProtocolCore` and the wire-coding helper. Feed the C callback, copy its buffers, and produce the Swift event or value. Run the protocol test.
4. Wire the transport: extend `TelnetChannelHandler` or the bootstrap only as the slice requires, keeping the EventLoop ownership rule. Re-run the protocol test plus any transport test.
5. Expose the public surface: add the declaration to `Sources/TelnetKit/Public/`, with a `///` comment stating outcome, throw conditions, ownership, ordering, and cancellation.
6. Write the public API test through `import TelnetKit` only, against `TelnetEchoServer`, and add the symbol to the [symbol checklist](../../../docs/public-api.md#symbol-checklist) if it is new.
7. Update the demo if the slice is caller-visible in the demo scope, per the [demo requirement](../../../PRD.md#9-demo-项目需求).
8. Run the narrow checks, then the full suite; re-read the complete diff for layer violations before reporting.

## Layer order and what belongs at each

| Layer | File | Owns | Must not contain |
|---|---|---|---|
| Protocol | `Sources/TelnetKit/Protocol/TelnetProtocolCore.swift` | `telnet_t` lifecycle, option table, callback, event mapping, option ledger | NIO types, public declarations, async |
| Wire coding | `Sources/TelnetKit/Protocol/TelnetWireCoding.swift` | `0xFF` escaping, NVT line endings, NAWS and NEW-ENVIRON encoding | Protocol state, public declarations |
| Transport | `Sources/TelnetKit/Transport/TelnetChannelHandler.swift` | ByteBuffer in and out, outbound queue flush, buffer bounds, close propagation | Option semantics, public declarations |
| Public | `Sources/TelnetKit/Public/*.swift` | Actor, events, options, errors, configuration, doc comments | `import CLibTelnet`, direct NIO handler calls |

A slice that needs a new Swift type decides its layer first: a type the caller can name is public; a type only the transport uses is internal and lives with its user.

## Rules

- A public symbol lands only with its test in the same change. Public surface without a test is not a completed slice.
- Errors come from the layer that detects them and travel as `TelnetError`. Do not translate an error twice, and do not add a case without a test that reaches it.
- Keep one behavior per slice. A slice that needs an unrelated refactor lands the refactor first.
- When the slice changes an existing signature, update [docs/public-api.md](../../../docs/public-api.md), the demo, and the affected tests in the same change; treat the interface snapshot as the checklist.
- Time-dependent behavior uses a configured bound plus a generous assertion bound. Never assert on a fixed sleep.
- The protocol suite runs without a socket. If a protocol test needs a server, the behavior belongs in the transport layer instead.

## Validation

Match evidence to the slice and report the commands actually run with their observed result:

1. `swift test --filter TelnetKitTests.Protocol` for a protocol or wire-coding slice.
2. `swift test --filter TelnetKitTests.PublicAPI` for a public surface slice.
3. `swift test` before reporting the slice done.
4. `swift build -Xswiftc -strict-concurrency=complete` for any slice that adds a closure, a continuation, or a non-`Sendable` capture.
5. `swift package diagnose-api-breaking-changes baseline.json` when the slice changes an existing public signature.
6. A grep of `Sources/TelnetKit/Public/` for `telnet_`, `TELNET_`, and `OpaquePointer` returning nothing.
7. Re-read the diff for a public-file line that belongs in an internal layer, and for an internal-file line that leaks a C pointer.

## Dev Note

None.
