# TelnetKit

An async Telnet terminal session for Swift, built on SwiftNIO and a vendored libtelnet.

TelnetKit gives you one `async` object per connection. You await the connection, consume a stream of parsed events, and send text; SwiftNIO owns the socket, and the RFC 1143 option state machine stays behind the public API.

[中文](README.zh.md)

## Status

The package is designed but not implemented. The requirement source is [PRD.md](PRD.md); the design contract is [docs/architecture.md](docs/architecture.md) and [docs/public-api.md](docs/public-api.md). Do not depend on this package yet.

## Requirements

| Item | Requirement |
|---|---|
| Platform | macOS 15 or later |
| Toolchain | Swift 6.2 or later; the package builds in Swift 6 language mode |
| Dependencies | [swift-nio](https://github.com/apple/swift-nio) 2.103.0+, [swift-log](https://github.com/apple/swift-log) 1.6.0+ |

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

Run the local echo server, then the demo client:

```sh
swift run TelnetEchoServer          # listens on 127.0.0.1:2323
swift run TelnetDemo --host 127.0.0.1 --port 2323
```

The demo connects, prints every event it receives, sends a command, and closes the connection.

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
        case .data(let buffer):
            print(buffer.text ?? "", terminator: "")
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
| Connection | TCP connect with address resolution, a configurable timeout, cancellation, and idempotent close |
| Parsing | Strips negotiation and restores escaped `0xFF`; `.data` carries application bytes only |
| Options | `WILL`/`WONT`/`DO`/`DONT` with RFC 1143 Q-method answers, driven by a declared option set |
| Terminal | Terminal type, window size, NEW-ENVIRON, MSSP, and ZMP |
| Text | UTF-8 text sends with `CR LF`, `CR NUL`, `LF`, or no translation, and NVT escaping |

## Known limitations

- Terminal emulation is out of scope. TelnetKit delivers bytes and protocol events; screen models, cursor handling, and color rendering are the caller's job.
- MCCP2 compression is not built in. A COMPRESS2 request is refused with `wont`, and forcing compression reports an unsupported feature.
- TLS is not implemented in the first version. The configuration reserves the field.
- macOS only. No iOS, Linux, or Windows platform entry exists.
- SSH, RLogin, and BBS file-transfer protocols are out of scope.

## Security

Telnet is plaintext: credentials and session content travel unencrypted, and anyone on the path can read or alter them. Use it on a trusted network, or wait for a TLS-capable release before sending a secret.

The library treats peer input as hostile: every parse path has a length bound, a malformed sequence produces a warning or a typed error rather than a crash, and log output never contains payload bytes or peer-supplied values.

## Documentation

- [PRD.md](PRD.md): goals, requirements, acceptance criteria, test inventory, demo scope, milestones, risks.
- [docs/architecture.md](docs/architecture.md): layers, concurrency model, event flow, extension points.
- [docs/public-api.md](docs/public-api.md): the caller contract for every public symbol.
- [AGENTS.md](AGENTS.md): contributor standing orders.

## License

TelnetKit is MIT licensed. The vendored libtelnet sources in `Sources/CLibTelnet/` are public domain; see [Sources/CLibTelnet/UPSTREAM.md](Sources/CLibTelnet/UPSTREAM.md) and `NOTICE`.
