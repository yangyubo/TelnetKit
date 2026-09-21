// swift-tools-version: 6.2
import PackageDescription

// TelnetKit builds for five Apple platforms only. Linux, Windows, and Android are
// out of scope, so no platform entry, abstraction, or conditional branch exists for
// them; see AGENTS.md and docs/architecture.md.
//
// This milestone declares the vendored C target alone. The Swift library, the demo
// executables, and the Network.framework dependencies arrive in later milestones;
// products are declared with the Swift target they belong to.
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
        // The target path is the submodule root because SwiftPM compiles the .c from there
        // and requires the public headers to live under the target path. The include
        // directory therefore exists only to expose the sibling header to the module map;
        // it holds no upstream file.
        .target(
            name: "CLibTelnet",
            path: "libtelnet",
            publicHeadersPath: "include"
        ),
        // The libtelnet suite drives the C library directly so that a parse bug is caught
        // without a socket. It compiles the submodule sources for the host, so it does not
        // need CLibTelnet; the Swift-typed protocol suite replaces it once TelnetProtocolCore
        // can read these same expectations through the public API.
        .testTarget(name: "CLibTelnetTests", path: "Tests/CLibTelnetTests"),
    ]
)
