# Changelog

English | [中文](CHANGELOG.zh.md)

All notable changes to TelnetKit are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The `TelnetKit` library: an async `TelnetConnection` over Network.framework through NIOTS, with a pinned libtelnet submodule behind the internal `CLibTelnet` target.
- The public contract: `TelnetEvent`, `TelnetOptions`, `TelnetError`, `TelnetConfiguration`, and the option, command, negotiation, and line-ending value types.
- RFC 1143 negotiation plus TTYPE, NAWS, NEW-ENVIRON, MSSP, and ZMP, each with a structured event.
- Optional swift-log logging: lifecycle at info, negotiation at debug, protocol frames at trace, errors at error; payload bytes are never logged.
- The connect timeout, cancellation, idle close, `waitForConnectivity`, and bounded inbound and subnegotiation buffers.
- Suites: a white-box protocol suite, a black-box public API suite over a loopback fixture, and integration coverage for concurrency, timeouts, cancellation, idle close, and path mapping.
- The `telnetkit-client` CLI: a complete interactive Telnet client that accepts the `telnet(1)` flags, forwards keystrokes, and enters command mode on the escape character.

### Changed

- `TelnetOptions.standardClient` requests ECHO from the peer, no longer offers it locally, and offers TERMINAL-TYPE and NAWS, matching `telnet(1)`.
- `.localEchoChanged(enabled:)` reports whether the local end should echo, as its contract states, rather than the peer's echo state.

### Known limitations

- The `TelnetEchoServer` fixture and the SwiftUI example are not shipped yet.
- MCCP2, Telnet over TLS, proxy mode, and non-Apple platforms are out of scope; see [README.md](README.md#known-limitations).
