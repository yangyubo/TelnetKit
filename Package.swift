// swift-tools-version: 6.2
import PackageDescription

// TelnetKit builds for five Apple platforms only. Linux, Windows, and Android are
// out of scope, so no platform entry, abstraction, or conditional branch exists for
// them; see AGENTS.md and docs/architecture.md.
//
// The demo executables are not declared in this milestone: the library product and
// its test suites are, and the two executable products arrive with the demo work.
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
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Tests/TelnetKitTests"
        ),
    ]
)
