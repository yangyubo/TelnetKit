# AGENTS.md

TelnetKit is a macOS 15+ Swift Package that gives Swift callers an async Telnet terminal session over TCP: SwiftNIO owns the connection, a vendored libtelnet C target owns the protocol state machine, and the public API exposes neither.

Read [docs/architecture.md](docs/architecture.md) before changing `Sources/`. The public surface contract is [docs/public-api.md](docs/public-api.md); do not change a public symbol without updating it in the same change. Write, review, or trim prose by [.agents/skills/telnetkit-prose-standard/SKILL.md](.agents/skills/telnetkit-prose-standard/SKILL.md); place and validate documents by [.agents/skills/telnetkit-doc/SKILL.md](.agents/skills/telnetkit-doc/SKILL.md).

## Design status

The package does not exist yet; [PRD.md](PRD.md) is the requirement source and the documents named above are the design contract for it. A statement in this repository is one of three kinds, and prose states which:

- **Verified.** Reproduced on this machine: libtelnet compiles clean as a SwiftPM C target, Swift calls it through a module map, `FF FB 01` and `FF FA 18 01 FF F0` parse to application data only, and `telnet_send_text("hi\n")` emits `FF FD 01 68 69 0D 0A`.
- **Upstream fact.** Read from the pinned dependency, not from our code: for example libtelnet 0.23 exports no option-status query.
- **Designed.** Planned behavior of code that is not written. Mark designed statements as requirements, never as descriptions of existing behavior, and delete the marker when the behavior ships.

Never present a designed behavior as verified. When design and PRD disagree, fix both or report the conflict.

## Repository layout

```
Package.swift                  swift-tools-version 6.2, platform macOS 15
PRD.md                         requirement source: goals, requirements, acceptance criteria
Sources/CLibTelnet/            vendored libtelnet C source and include/module.modulemap
Sources/TelnetKit/Public/      public types; the only symbols callers may see
Sources/TelnetKit/Protocol/    internal Swift wrapper over telnet_t
Sources/TelnetKit/Transport/   internal SwiftNIO channel handler and bootstrap wiring
Sources/TelnetDemo/            CLI demo executable
Sources/TelnetEchoServer/      local echo server executable, also the integration fixture
Tests/TelnetKitTests/          Swift Testing suites: Protocol/, PublicAPI/, Integration/
Examples/TelnetKitDemoApp/     SwiftUI demo application
docs/                          architecture, public API contract, documentation standard
.agents/skills/                repeatable workflows
```

Package products: library `TelnetKit`, executables `TelnetDemo` and `TelnetEchoServer`. `CLibTelnet` stays internal and never becomes a product.

## Commands

```sh
swift build                       # debug build of every target
swift test                        # Swift Testing suites; must run offline and finish under 60s
swift test --filter TelnetKitTests.Protocol   # one suite while iterating
swift build -Xswiftc -strict-concurrency=complete   # concurrency error check
swift build --configuration release               # release build and binary-size check
swift package describe            # target and product inventory
swift package diagnose-api-breaking-changes baseline.json   # public interface snapshot comparison
swift run TelnetEchoServer        # local fixture on port 2323
swift run TelnetDemo --host 127.0.0.1 --port 2323
```

`swift test` is the local evidence. Report only commands actually run, with their observed result; do not claim a check that did not execute. Coverage is complete for public symbols, not for source lines alone: a public symbol without a test is failing work, not partial work.

## Non-negotiable constraints

- **Platform floor.** Deployment target is macOS 15. Do not add a macOS 16+ API. Do not add an iOS, Linux, or Windows platform entry without an explicit request.
- **Swift 6 language mode.** All targets compile in Swift 6 mode with `StrictConcurrency` complete and zero warnings. A `@unchecked Sendable` conformance needs a comment naming the invariant that makes it safe and a concurrency test that exercises it.
- **Vendored C is read-only.** `Sources/CLibTelnet/libtelnet.c` and `include/libtelnet.h` are byte-identical upstream copies. Never edit them, never add a patch there. When upstream must change, record the new upstream commit in `Sources/CLibTelnet/UPSTREAM.md` and re-copy; a required behavior change belongs in our Swift code instead.
- **One thread owns `telnet_t`.** Every `telnet_*` call for a connection happens on the `EventLoop` that created it. No lock may be added to compensate for a cross-thread call; fix the call site instead.
- **Callback data does not escape.** Buffers, strings, and argument arrays reachable from a `telnet_event_t` are valid only during its callback. Copy inside the callback; never store the pointer.
- **No reentry inside a callback.** A `telnet_send*` call from inside an event callback reenters a state machine that is mid-parse. Queue the outbound bytes and flush after the callback returns.
- **No C leaks into public API.** `TelnetKit` exports no `telnet_*` function, no `TELNET_*` macro constant, no `telnet_t`, `telnet_event_t`, `telnet_telopt_t`, and no `OpaquePointer`. Option and command codes appear as Swift values with the numeric meaning kept in one mapping file.
- **Track option state ourselves.** libtelnet 0.23 exports no option-status query. `optionStatus(_:)` is derived in Swift from observed `WILL`/`WONT`/`DO`/`DONT` events; never read or guess internal C state.
- **Errors are typed values.** `throws(TelnetError)` on every fallible public call. No `fatalError`, no `preconditionFailure`, no force-unwrap on a value that comes from the peer, and no `try!`. Map each `telnet_error_t` case explicitly; no `default:` arm may swallow one.
- **Peer input is hostile.** Every parse path has a length bound and is fuzz-tested. A malformed sequence produces a warning or a typed error, never a crash or an unbounded allocation.

## Conventions

- Layout order inside a Swift file: public type, dependency injection into stored properties, the actor or class body, then `// MARK:` sections for lifecycle, protocol handling, and teardown. Keep the public entry points at the top of the file.
- `Sources/TelnetKit/Public/` holds only caller-visible surface; `internal` implementation lives under `Protocol/` and `Transport/`. Moving a type between the two directories is a public API change.
- Public symbols carry a `///` doc comment that states the caller contract: outcome, throw or finish conditions, ownership, ordering, and cancellation. Internal comments explain non-obvious invariants only; they do not narrate control flow.
- One meaning per term. Use `option`, `negotiation`, `subnegotiation`, `event`, `connection`, and `session` with the definitions in [docs/glossary](docs/public-api.md#glossary); do not introduce a synonym for a term already defined there.
- Prefer an existing dependency over new code when it removes owned code and tests; record the choice in the PRD rather than in a comment.
- Tests describe observable behavior of the public API. A protocol-level test drives the parse layer directly; a connection test drives a real socket against `TelnetEchoServer`. Change obsolete behavior together with its tests.
- Files end with exactly one trailing newline. Keep a `FIXME` for a defect, `TODO` for planned work, and `XXX` for a hazard that must be revisited; do not use a bare marker without a reason.

## Documentation

One home per fact, under the tiers in [docs/AGENTS.md](docs/AGENTS.md). `AGENTS.md` carries standing orders and links; [docs/architecture.md](docs/architecture.md) maps composition; [docs/public-api.md](docs/public-api.md) defines the public contract; [PRD.md](PRD.md) owns requirements, acceptance criteria, and milestone scope; package READMEs serve consumers; [.agents/skills/](.agents/skills/) holds reusable workflows. Generated or copied content is never hand-edited except at its owner.

Update the affected README and the public API contract in the same change as the code. State current behavior in present tense; keep history in commits and the PRD changelog, not in prose.

## Editing these instructions

Keep each rule self-contained: a rule states what to do, names the mechanism, and links its owner. Add a rule only for a constraint that a competent Swift engineer would plausibly violate. Condense when clarity survives. When a new rule needs more words than the ceiling in [docs/AGENTS.md](docs/AGENTS.md) allows, relocate the detail to its owning document and leave the one-line rule here.
