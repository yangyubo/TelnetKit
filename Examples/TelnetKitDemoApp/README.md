# TelnetKitDemoApp

English | [中文](README.zh.md)

A SwiftUI app for macOS 15+ and iOS 18+ that drives `TelnetKit`: the manual demo [PRD.md](../../PRD.md#9-demo-project-requirements) asks for, and the reference for how a caller uses every public interface.

It lives in `Examples/` as its own Xcode project, so nothing here is a package target and `swift test` never builds SwiftUI. The app consumes the library the way a caller does: a local Swift package reference and `import TelnetKit`.

## Run it

Initialise the libtelnet submodule once, then start the local echo server from the repository root:

```sh
git submodule update --init --recursive
swift run telnetkit-echo-server
```

Open `TelnetKitDemoApp.xcodeproj`, choose a scheme, and Run:

| Scheme | Destination |
|---|---|
| `TelnetKitDemoApp` | This Mac, macOS 15 or later |
| `TelnetKitDemoApp-iOS` | An iOS 18 or later simulator |

Both targets share the sources under `TelnetKitDemoApp/`. The iOS simulator reaches the Mac's loopback, so the default host and port `127.0.0.1:2323` work there unchanged.

## What to try

1. Press **Connect**. The status bar shows `remoteAddress` and `localAddress`, and the option table fills from `optionStatus(_:)` as negotiation arrives. A real telnetd withholds its login prompt until TERMINAL-TYPE is answered, so the demo answers `TERMINAL-TYPE SEND` and `NEW-ENVIRON SEND` immediately; each has a switch in the **Protocol** tab that hands the answer back to the buttons.
2. Type a line and press Return. The demo appends the newline that ends the line, because `send(text:lineEnding:)` translates the newlines a string already carries rather than adding one; the picker chooses CR LF, CR NUL, or LF, the **send(text:)** button takes the `send(text:)` default, and the hexadecimal field drives `send(_:)` and `sendRaw(_:)`.
3. Resize the window. Once the peer answers `do windowSize`, each size change is reported with `sendWindowSize(columns:rows:)` and the echo server prints `NAWS <columns>x<rows>`.
4. Open the **Protocol** tab for `negotiate(_:option:)`, `requestOption(_:)`, `subnegotiate(option:payload:)`, `send(command:)`, `replyTerminalType(_:)`, `sendEnvironment(_:scope:)`, and a manual `sendWindowSize(columns:rows:)`.
5. Press an **Error injection** button: each one reaches a real `TelnetError` path, and **Public values** renders every error, warning, and code case, including the three this build cannot trigger.
6. Turn on **Inject a swift-log Logger**, switch the log level, and watch the library's records in the **Log** tab.

`swift run telnetkit-echo-server --inject all` makes the peer send its malformed exchanges after negotiation, so the **Events** tab can also show `.warning` and `.protocolError` rows.

## The project file

`TelnetKitDemoApp.xcodeproj` is generated from `project.yml` and committed, so opening or building the app needs no extra tool. Change the structure in `project.yml` and regenerate in this directory:

```sh
xcodegen generate
```

## Acceptance

**Verified on this machine.** Both schemes build with zero warnings: `-scheme TelnetKitDemoApp -destination 'generic/platform=macOS'`, and `-scheme TelnetKitDemoApp-iOS -destination 'platform=iOS Simulator,name=iPhone 17'` with the Xcode 27 toolchain.

The interactive steps of PRD §9.3 are manual and are not recorded as evidence: a session against a real public service, and the window resize that the echo server prints as `NAWS <columns>x<rows>`.

## Documentation

- [PRD.md](../../PRD.md#9-demo-project-requirements) owns the demo's required interfaces and acceptance criteria.
- [docs/public-api.md](../../docs/public-api.md) is the caller contract this app exercises.
- [README.md](../../README.md) covers installing and using the library.
