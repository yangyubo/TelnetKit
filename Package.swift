// swift-tools-version: 6.2
import PackageDescription

// TelnetKit builds for five Apple platforms only. Linux, Windows, and Android are
// out of scope, so no platform entry, abstraction, or conditional branch exists for
// them; see AGENTS.md and docs/architecture.md.
//
// Both demo executables are declared: telnetkit-client is the interactive client and
// telnetkit-echo-server is the local peer that it and the SwiftUI demo connect to.
// Neither is part of the library product, and the five-platform matrix builds TelnetKit
// alone, so the executables stay macOS commands.
let package = Package(
    name: "TelnetKit",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .watchOS(.v11),
        .tvOS(.v18),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "TelnetKit", targets: ["TelnetKit"]),
        // The CLI telnet client. Its product name is the command a caller types; the
        // target carries a Swift identifier. It is a macOS command: it drives a terminal
        // and is built by `swift run`, so the five-platform matrix builds `TelnetKit`.
        .executable(name: "telnetkit-client", targets: ["TelnetKitClient"]),
        // The local echo server. Its product name is the command a caller types; the target
        // keeps the PRD's `TelnetEchoServer` identifier. It is a macOS command for the same
        // reason the client is: it binds a loopback listener and is built by `swift run`.
        .executable(name: "telnetkit-echo-server", targets: ["TelnetEchoServer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.103.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.20.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    ],
    targets: [
        // libtelnet arrives as the git submodule at libtelnet/, pinned to the commit that
        // Sources/CLibTelnet/UPSTREAM.md records, so the upstream sources and COPYING stay
        // untouched and a version bump is a submodule checkout.
        //
        // SwiftPM looks for a custom module map only in the target's public headers
        // directory, and that directory must live under the target path, so the target is
        // our own Sources/CLibTelnet and the submodule files are reached through two
        // committed relative symlinks: libtelnet.c here and include/libtelnet.h. Nothing is
        // ever written into the submodule. HAVE_ZLIB stays undefined: the first release
        // answers COMPRESS2 with WONT and does not link zlib.
        .target(
            name: "CLibTelnet",
            path: "Sources/CLibTelnet",
            publicHeadersPath: "include"
        ),
        // The only public product. Network.framework through NIOTS is the transport, and
        // swift-log carries the optional logger; no other runtime dependency exists.
        .target(
            name: "TelnetKit",
            dependencies: [
                "CLibTelnet",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/TelnetKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The interactive CLI client: argument compatibility with telnet(1), the event
        // stream printed to stdout, and keystrokes forwarded to the server.
        .executableTarget(
            name: "TelnetKitClient",
            dependencies: ["TelnetKit"],
            path: "Sources/TelnetKitClient"
        ),
        // The local echo server the demo and manual runs connect to. It links neither TelnetKit
        // nor CLibTelnet on purpose: an independent peer cannot share a parser defect with the
        // library it exists to exercise, so it carries its own minimal model of the wire.
        .executableTarget(
            name: "TelnetEchoServer",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
            ],
            path: "Sources/TelnetEchoServer"
        ),
        // The libtelnet suite drives the C library directly through CLibTelnet, so that a
        // parse bug is caught without a socket. The Swift-typed protocol suite in
        // TelnetKitTests is the replacement once TelnetProtocolCore is exercised through the
        // public API.
        .testTarget(
            name: "CLibTelnetTests",
            dependencies: ["CLibTelnet"],
            path: "Tests/CLibTelnetTests"
        ),
        // The protocol suite drives TelnetProtocolCore through @testable import; the public
        // API and integration suites drive a real loopback connection, so the test target
        // depends on the same NIOTS listener the fixture binds.
        .testTarget(
            name: "TelnetKitTests",
            dependencies: [
                "TelnetKit",
                "CLibTelnet",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Tests/TelnetKitTests"
        ),
    ]
)
