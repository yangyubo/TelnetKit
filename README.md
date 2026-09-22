# TelnetKit

English | [中文](README.zh.md)

An async Telnet terminal session for Swift, built on Network.framework through NIOTS and a pinned libtelnet submodule.

TelnetKit gives you one `async` object per connection. You await the connection, consume a stream of parsed events, and send text; SwiftNIO owns the socket, and the RFC 1143 option state machine stays behind the public API.

[中文](README.zh.md)

## Status

The library is implemented and tested on macOS; the CLI client and echo server ship as macOS executables, and the SwiftUI demo app ships in [`Examples/`](Examples/TelnetKitDemoApp/README.md). The requirement source is [PRD.md](PRD.md); the design contract is [docs/architecture.md](docs/architecture.md) and [docs/public-api.md](docs/public-api.md).

## Requirements

| Item | Requirement |
|---|---|
| Platform | macOS 15+, iOS 18+, watchOS 11+, tvOS 18+, visionOS 2+ (Apple platforms only) |
| Toolchain | Swift 6.2 or later; the package builds in Swift 6 language mode |
| Dependencies | [swift-nio](https://github.com/apple/swift-nio) 2.103.0+, [swift-nio-transport-services](https://github.com/apple/swift-nio-transport-services) 1.20.0+, [swift-log](https://github.com/apple/swift-log) 1.6.0+ |

## Install

Add the package to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/<owner>/TelnetKit.git", from: "0.1.0"),
],
targets: [
    .target(name: "YourTarget", dependencies: ["TelnetKit"]),
]
```

## Quick start

After cloning, initialise the submodule once; the first build fails without it:

```sh
git submodule update --init --recursive
```

The package ships the `TelnetKit` library and two macOS executables. Start the echo server, then the client against it:

```sh
swift run telnetkit-echo-server
swift run telnetkit-client 127.0.0.1 2323
```

The client prints server data, forwards keystrokes, and enters command mode on `^]`; library use is one `await` (see [Use the library](#use-the-library)). The SwiftUI demo in [`Examples/`](Examples/TelnetKitDemoApp/README.md) builds the same calls into a macOS and iOS app.

## Use the library

```swift
import TelnetKit

let connection = try await TelnetConnection.connect(
    host: "127.0.0.1",
    port: 2323,
    options: .standardClient,
    configuration: .init(connectTimeout: .seconds(5))
)

Task {
    for await event in connection.events {
        switch event {
        case .data:
            print(event.text ?? "", terminator: "")
        case .negotiation(let action, let option, let remote):
            print(remote ? "remote" : "local", action, option.displayName)
        case .terminalTypeRequested:
            try? await connection.replyTerminalType("xterm-256color")
        default:
            print(event)
        }
    }
}

try await connection.send(text: "hello telnet")
try await connection.sendWindowSize(columns: 120, rows: 40)
await connection.close()
```

`connect` throws a `TelnetError` case: `.invalidHost` when resolution fails, `.connectionRefused`, `.connectTimeout`, or `.cancelled`. After close, every sending and negotiation call throws `.notConnected`, and the event stream finishes.

## What it does

| Capability | Detail |
|---|---|
| Connection | Network.framework connect through NIOTS, with a configurable timeout, connectivity waiting, path reporting, cancellation, and idempotent close |
| Parsing | Strips negotiation and restores escaped `0xFF`; `.data` carries application bytes only |
| Options | `WILL`/`WONT`/`DO`/`DONT` with RFC 1143 Q-method answers, driven by a declared option set |
| Terminal | Terminal type, window size, NEW-ENVIRON, MSSP, and ZMP |
| Text | UTF-8 text sends with `CR LF`, `CR NUL`, `LF`, or no translation, and NVT escaping |

## Known limitations

- Terminal emulation is out of scope. TelnetKit delivers bytes and protocol events; screen models, cursor handling, and color rendering are the caller's job.
- MCCP2 compression is not built in: a COMPRESS2 request is refused with `wont`. The Apple SDKs ship zlib, so this is a scope decision rather than a dependency gap; enabling it needs an inflation bound and compressed-state contracts first.
- Proxy mode is not supported: transparent forwarding between two peers is a middle-man and debug-tool use, and this library is a Telnet endpoint.
- Telnet over TLS/SSL is out of scope: not `telnets`/992, not START-TLS, not the TELNET ENCRYPT or AUTHENTICATION options. Apple's own telnet and Homebrew's netkit-telnet support neither, upstream libtelnet implements neither option, and the IETF drafts never became RFCs.
- Apple platforms only: macOS, iOS, iPadOS, watchOS, tvOS, and visionOS. Linux, Windows, and Android are out of scope, and no abstraction is kept for them.
- The `telnetkit-client` CLI and the `telnetkit-echo-server` peer ship as macOS executables, and the SwiftUI demo app targets macOS 15+ and iOS 18+. The library core itself builds for all five.
- An iOS session is a foreground session: the system suspends the app in the background and the connection drops. Reconnect from the app when it returns to the foreground.
- SSH, RLogin, and BBS file-transfer protocols are out of scope.

## Security

Telnet is plaintext: credentials and session content travel unencrypted, and anyone on the path can read or alter them. This library adds no encryption, so put the connection inside a VPN or reach it through a bastion host before sending a secret. This applies on iOS too, where a mobile network is far less trustworthy than a wired LAN.

The library treats peer input as hostile: every parse path has a length bound, a malformed sequence produces a warning or a typed error rather than a crash, and log output never contains payload bytes or peer-supplied values.

## Documentation

- [PRD.md](PRD.md): goals, requirements, acceptance criteria, test inventory, demo scope, milestones, risks.
- [docs/architecture.md](docs/architecture.md): layers, concurrency model, event flow, extension points.
- [docs/public-api.md](docs/public-api.md): the caller contract for every public symbol.
- [AGENTS.md](AGENTS.md): contributor standing orders.
- Every document is a bilingual pair: this README pairs with [README.zh.md](README.zh.md), and [PRD.md](PRD.md) pairs with [PRD.zh.md](PRD.zh.md).

## License

TelnetKit is MIT licensed. libtelnet arrives as the `libtelnet/` submodule and is public domain; its pin is recorded in [Sources/CLibTelnet/UPSTREAM.md](Sources/CLibTelnet/UPSTREAM.md), and `NOTICE` repeats the license.
