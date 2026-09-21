// swift-tools-version: 6.2
import PackageDescription

// TelnetKit builds for five Apple platforms only. Linux, Windows, and Android are
// out of scope, so no platform entry, abstraction, or conditional branch exists for
// them; see AGENTS.md and docs/architecture.md.
//
// This milestone declares the vendored C target and its protocol suite alone. The Swift
// library, the demo executables, and the Network.framework dependencies arrive in later
// milestones; products are declared with the Swift target they belong to.
let package = Package(
    name: "TelnetKit",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .watchOS(.v11),
        .tvOS(.v18),
        .visionOS(.v2),
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
        // ever written into the submodule.
        .target(
            name: "CLibTelnet",
            path: "Sources/CLibTelnet",
            publicHeadersPath: "include"
        ),
        // The libtelnet suite drives the C library directly through CLibTelnet, so that a
        // parse bug is caught without a socket. The dependency is what lets the compiler
        // resolve the import; without it the test target fails with "unable to resolve
        // module dependency: 'CLibTelnet'". The Swift-typed protocol suite replaces this
        // one once TelnetProtocolCore can read the same expectations through the public API.
        .testTarget(
            name: "CLibTelnetTests",
            dependencies: ["CLibTelnet"],
            path: "Tests/CLibTelnetTests"
        ),
    ]
)
