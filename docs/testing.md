# TelnetKit Test Plan

English | [中文](testing.zh.md)

This document owns how every suite runs: the environment, the framework, the exact command per layer, the quality gates, and the CI matrix. Requirement identifiers and acceptance criteria stay in [PRD.md](../PRD.zh.md#8-测试策略与用例清单); the per-test design notes stay in the test source, per the [tier table](AGENTS.md#the-tier-taxonomy-one-home-per-fact). The library suites and the vendored C suite are implemented; the demo and real-server procedures are **Designed** under the [design-status rule](../AGENTS.md#design-status).

## Environment

Facts verified on the development machine (Xcode 27.0, `swift-driver` 1.168.6, Apple Swift 6.4, macOS 27.0):

| Item | Value | Why it matters |
|---|---|---|
| Framework | `Testing.framework` ships in the Xcode SDK beside `XCTest.framework` | Swift Testing needs no package dependency and no `swift-testing` checkout |
| SwiftPM | `swift test` supports `--enable-code-coverage`, `--sanitize`, `--filter`, `--skip`, `--parallel/--no-parallel`, `--list-tests`, `--xunit-output` | Coverage, sanitizers, and per-suite selection run without `xcodebuild` |
| Simulator runtimes | This machine has **only the iOS 26.5 runtime** installed; watchOS, tvOS, and visionOS need a one-time runtime download from Xcode | A device name in a command only works where its runtime is installed, so CI installs the runtimes it names |
| Device names | `xcrun simctl list devices available` | Device names change per runtime; the plan names the family, and each command reads the installed list |

Toolchain floor: Xcode 26 or newer with Swift 6.2 or newer. The deployment floors under test are macOS 15, iOS 18, watchOS 11, tvOS 18, and visionOS 2 (PRD §7).

## What runs where

| Suite | Layer under test | Fixture | macOS 15 | iOS simulator | watchOS, tvOS, visionOS |
|---|---|---|---|---|---|
| `Tests/CLibTelnetTests/` | The vendored libtelnet C library through the `CLibTelnet` module | Bytes in, recorded events out; no socket, no connection | Yes, and this suite passes today | Yes | Yes, build plus run |
| `Tests/TelnetKitTests/Protocol/` | `TelnetProtocolCore` through `@testable import` | Bytes in, `[TelnetEvent]` out; no socket | Yes | Yes | Yes, build plus run |
| `Tests/TelnetKitTests/PublicAPI/` | `TelnetConnection` through `import TelnetKit` only | A `NIOTSListenerBootstrap` fixture in the test target | Yes | Yes | Build only |
| `Tests/TelnetKitTests/Integration/` | Connection behavior: timeout, cancellation, close, concurrency, path events | `NIOTSListenerBootstrap` fixture, injected `NIOTSNetworkEvents` | Yes | Yes | No |
| `Tests/TelnetKitTests/RealServer/` | A real server: connect, first bytes, no negotiation loop, bounded session, close | Apple's `telnetd` from Homebrew, addressed by `TELNETKIT_TEST_SERVER_HOST` and `TELNETKIT_TEST_SERVER_PORT`; skipped when unset | Yes | Yes | No |

This milestone ships the libtelnet suite and the three Swift suites; the real-server suite is listed so its platform placement is fixed now. The protocol suite is the correctness gate and touches no network, so it is the one suite that runs everywhere. The integration and public API suites bind a loopback listener, which watchOS, tvOS, and visionOS do not provide, so those platforms stop at build plus the protocol suite.

## Running each suite

All commands run from the package root. `swift test` is the local evidence for the protocol and public API suites, and both complete offline.

```sh
swift test --filter TelnetKitTests.Protocol        # L1, no network, fastest signal
swift test --filter TelnetKitTests.PublicAPI       # L2, needs the loopback fixture
swift test --filter TelnetKitTests.Integration     # L3, needs a free local port
swift test                                         # all suites; must finish under 60 s
swift test --no-parallel                           # isolate a flaky ordering bug
swift test --list-tests                            # what exists, for the symbol audit
swift test --list-tests | wc -l                    # count for the coverage checklist
swift run telnetkit-client 127.0.0.1 2323           # manual: the CLI client against a server
```

The echo server is a fixture, not a service: a suite binds its own loopback listener and stops it on teardown.

The CLI demo and the standalone echo server are not provided in this milestone; when they ship they are manual entry points, not a substitute for a suite.

Simulator builds and runs use `xcodebuild` against the package, since a SwiftPM test bundle needs a host application on those platforms.

```sh
xcrun simctl list devices available                # read the installed names first
xcodebuild -list                                   # SwiftPM names the sole scheme TelnetKit
xcodebuild build -scheme TelnetKit -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test  -scheme TelnetKit -destination 'platform=iOS Simulator,name=iPhone 17' \
                 -only-testing:CLibTelnetTests
```

`xcodebuild` exposes exactly one scheme for this package, named `TelnetKit`, so every command reads it from `xcodebuild -list` instead of assuming a name.

## Tests against a real Telnet server

The loopback fixture proves the parser; a real server proves the connection. Two servers are used, and they answer different questions.

| Server | What it proves | Where it runs |
|---|---|---|
| `NIOTSListenerBootstrap` fixture in the test target | Deterministic negotiation: the script chooses which options to advertise, so TTYPE, NAWS, and NEW-ENVIRON cases have a fixed expectation | Every integration run, all platforms |
| Apple's `telnetd`, installed through Homebrew | Authentic server behavior: real prompts, real negotiation order, real IAC handling by a server nobody on this project wrote | The `RealServer` suite, plus manual runs |

Homebrew's `telnetd` formula builds Apple's own `remote_cmds` telnetd, which is the same daemon the system shipped before it was removed. `telnetd` normally runs from `inetd`, which macOS no longer has, so tests start it standalone: the `-debug` flag starts it manually and accepts an alternate port, which is what keeps the test server on a high port instead of the privileged 23.

```sh
brew install telnetd
sudo telnetd -debug 2323            # standalone on 2323; needs root, and creates
                                    # a real login session when a client connects
```

The `RealServer` suite is driven by environment variables so that a run without a server skips instead of failing, and so CI stays hermetic:

```sh
TELNETKIT_TEST_SERVER_HOST=127.0.0.1 TELNETKIT_TEST_SERVER_PORT=2323 \
  swift test --filter TelnetKitTests.RealServer
```

The suite asserts only what a foreign server can promise: the TCP connection completes, the first bytes are valid Telnet, negotiation does not loop, the session stays usable for a bounded period, and close behaves. It does not assert a prompt string, a banner, or an exact negotiation sequence, because those are the server's choices and not this library's contract.

## Simulator runs against the Mac host

Every simulator shares the Mac's network stack, so a server on the Mac is reachable from inside any of them. The host address is read from the machine rather than hardcoded, because it differs per network:

```sh
ipconfig getifaddr en0               # the address a simulator connects to
```

| Platform | How the real-server suite runs | Notes |
|---|---|---|
| macOS | `swift test --filter TelnetKitTests.RealServer` | No host application needed; this is the reference run |
| iOS, iPadOS | `xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 17'` | Runs the same suite; the local-network prompt can appear on first connect |
| watchOS | Build plus the protocol suite | Testing needs a paired iPhone simulator, so the real-server case is not planned here |
| tvOS, visionOS | `xcodebuild test` where the destination supports it, otherwise build plus the protocol suite | Treated as a build gate first and a test target second, so a toolchain that refuses to run the bundle does not block a change |

A local-network prompt or a refused connection means the run reports the platform and the address it tried, rather than reporting a protocol failure. No simulator address reaches CI: the matrix job runs the deterministic fixture only, and the real-server suite is a local and manual step.

## Coverage, sanitizers, and concurrency

| Check | Command | Applies to | Owner |
|---|---|---|---|
| Code coverage | `swift test --enable-code-coverage`, then `xcrun llvm-cov report .build/out/Products/Debug/TelnetKitTests.xctest/Contents/MacOS/TelnetKitTests -instr-profile .build/out/Products/Debug/codecov/default.profdata` | macOS | PRD §8.3: protocol lines >= 90% (92.3% now); `llvm-cov` reports no branch data for Swift |
| Memory safety | `swift test --sanitize=address` | macOS | FR-PROTO-08, the callback copy path |
| Data races | `swift test --sanitize=thread` | macOS | The `telnet_t` single-EventLoop rule and the outbound queue |
| Undefined behavior | `swift test --sanitize=undefined` | macOS | The C seam and byte arithmetic |
| Strict concurrency | `swift build -Xswiftc -strict-concurrency=complete` | All five platforms | Zero warnings, no `@unchecked Sendable` without a comment |
| Public interface | `swift package diagnose-api-breaking-changes api-baseline-0.1.0 --products TelnetKit` | macOS | The [symbol checklist](public-api.md#symbol-checklist) with no breaking change |
| Documentation | `xcodebuild docbuild -scheme TelnetKit -destination 'generic/platform=macOS'` | macOS | 0 diagnostics for the TelnetKit target |

Sanitizers run on macOS only: the iOS simulator does not support Thread Sanitizer, and mixing sanitizers with simulator hosts produces noise rather than signal. ASan and TSan jobs are separate CI jobs so one failure does not mask the other.

## Path events and other timing-sensitive behavior

Path events and connectivity waiting are the hardest part of the plan, because a hosted CI runner has one network path and cannot be told to lose it.

| Behavior | How it is tested | Where |
|---|---|---|
| `.pathChanged`, `.betterPathAvailable`, `.betterPathUnavailable`, `.viabilityChanged`, `.waitingForConnectivity` | Inject `NIOTSNetworkEvents` into the pipeline and assert the mapped `TelnetEvent` and the untouched option ledger | Protocol and integration suites |
| `waitForConnectivity` parks a connect attempt with no route (FR-PATH-01) | `NIOTSChannelOptions.waitForActivity` against an unroutable address, asserting the call has not thrown or returned within a bound, then released | macOS integration suite |
| A real cellular-to-Wi-Fi switch and a real suspend/resume | Manual run on a device or simulator, recorded in the M6 checklist | M6 manual verification |
| Timeout and cancellation | A short configured bound plus a generous assertion bound; never a fixed sleep | All suites |

## Quality gates

A change passes when all of the following hold, and the run reports the observed result for each:

1. `swift test` is green on macOS and finishes under 60 s.
2. The protocol and public API suites are green on the iOS simulator.
3. All five platforms build.
4. Every public symbol in the [symbol checklist](public-api.md#symbol-checklist) is reached by a test; a symbol without one fails the gate rather than reporting partial coverage.
5. Coverage thresholds from PRD §8.3 hold, compared against the checklist rather than against line counts alone.
6. The ASan job is green, and the TSan job is green.
7. The `-strict-concurrency=complete` build reports zero warnings.
8. No test reaches the external network, and no test depends on wall-clock sleep for correctness.
9. No target in this package imports `NIOSSL`, `CNIOBORINGSSL`, or `NIOPosix`; the transitive `NIO` umbrella that `NIOTransportServices` pulls in is the only place `NIOPosix` is built.

## CI plan

| Job | Runner | Command | Gates |
|---|---|---|---|
| `macos-suite` | macOS 15 or newer | `swift test` plus `--enable-code-coverage` | Gates 1, 4, 5 |
| `sanitizers` | macOS | `swift test --sanitize=address`, `swift test --sanitize=thread` | Gate 6 |
| `strict-concurrency` | macOS | `swift build -Xswiftc -strict-concurrency=complete` | Gate 7 |
| `platform-matrix` | macOS with all four runtimes | `xcodebuild build` and `xcodebuild test` per platform | Gates 2, 3 |
| `api-surface` | macOS | `swift package diagnose-api-breaking-changes api-baseline-0.1.0 --products TelnetKit` | Gate 4, for the interface snapshot |
| `documentation` | macOS | `xcodebuild docbuild -scheme TelnetKit -destination 'generic/platform=macOS'` | Gate 4, for the DocC build |
| `real-server` | A developer Mac, never CI | `TELNETKIT_TEST_SERVER_HOST=... swift test --filter TelnetKitTests.RealServer` | Manual evidence for the milestone checklist |

The matrix job downloads the watchOS, tvOS, and visionOS runtimes once, caches them, and only runs the protocol suite on those platforms. Runtime download size is the cost driver behind the [R11 risk](../PRD.zh.md#11-风险与对策), so the matrix runs on pull requests that touch `Sources/` and on the default branch, not on every push.

## Manual verification

Four things cannot be automated on a hosted runner and are recorded as evidence in the milestone checklist:

1. Apple's `telnetd` from the section above answers a login prompt, and a command round-trips against it.
2. The `RealServer` suite runs from the iOS simulator against the Mac host, with the platform and the address it used recorded in the log.
3. A public Telnet service over the internet answers a login prompt, which is the only check that leaves the local network.
4. A cellular-to-Wi-Fi switch on a device, and background suspension on iOS or watchOS, show `.pathChanged` and the documented disconnect behavior.
