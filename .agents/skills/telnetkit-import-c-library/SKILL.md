---
name: telnetkit-import-c-library
description: Vendor, pin, verify, or upgrade the libtelnet C sources inside the TelnetKit Swift package, and fix a failure in the Swift-to-C seam. Use when adding Sources/CLibTelnet, recording or changing the upstream commit, writing include/module.modulemap, reproducing a libtelnet behavior, or diagnosing a mismatch between the C header and the Swift wrapper.
---

# Importing the libtelnet C library

English | [中文](SKILL.zh.md)

## Summary

`Sources/CLibTelnet` carries an unmodified copy of [seanmiddleditch/libtelnet](https://github.com/seanmiddleditch/libtelnet) so that a Swift Package can build it. This workflow covers the copy, the module map, the provenance record, the Swift seam, and the upgrade procedure. It is guidance with a fixed verification path, not a generator: do not script the copy until the manual path has been reviewed once.

## Table of Contents

- [Facts that constrain the copy](#facts-that-constrain-the-copy)
- [Workflow: initial vendoring](#workflow-initial-vendoring)
- [Workflow: upgrading the pin](#workflow-upgrading-the-pin)
- [Writing the Swift seam](#writing-the-swift-seam)
- [Rules](#rules)
- [Validation](#validation)
- [Dev Note](#dev-note)

## Facts that constrain the copy

Verified against upstream `develop` at commit `5f5ecee776b9bdaa4e981e5f807079a9c79d633e` (2020-08-14), header version 0.23:

- The repository contains no `Package.swift`. `libtelnet.c` and `libtelnet.h` are the whole library; `CMakeLists.txt`, autotools files, `test/`, `doc/`, and `util/` are not needed and must not be copied.
- The C source compiles clean with `clang -c libtelnet.c -I include -Wall` and exports 23 `telnet_*` symbols.
- `libtelnet.c` has one optional dependency behind `HAVE_ZLIB` for MCCP2. Do not define it: compression support is out of scope, and the Swift code must answer a COMPRESS2 request with `wont`.
- `libtelnet.h` states `public domain`. Record that in the notice file; do not attach our license to the vendored files.
- Three facilities are macros and therefore invisible to Swift: `telnet_finish_sb`, `telnet_finish_newenviron`, `telnet_finish_zmp`. The seam supplies each one.
- Upstream exports no query for negotiated option state. The Swift layer maintains its own ledger; never add a C helper that reaches into `struct telnet_t`.

## Workflow: initial vendoring

1. Clone upstream outside the repository and pin the commit: `git clone https://github.com/seanmiddleditch/libtelnet.git` then `git checkout <commit>`.
2. Copy exactly two files: `libtelnet.c` to `Sources/CLibTelnet/libtelnet.c` and `libtelnet.h` to `Sources/CLibTelnet/include/libtelnet.h`. Do not reformat, do not add a license header, do not apply a patch.
3. Write `Sources/CLibTelnet/include/module.modulemap` as `module CLibTelnet { header "libtelnet.h" export * }`.
4. Write `Sources/CLibTelnet/UPSTREAM.md` with the upstream URL, branch, full commit identifier, header version, copy date, and one sentence stating that no local modification exists.
5. Declare the target in `Package.swift` as `.target(name: "CLibTelnet")` with no custom C settings, and keep it out of `products`.
6. Verify the copy is byte-identical to upstream with `shasum -a 256` on both sides, before the first build.
7. Run the [validation](#validation) steps.

## Workflow: upgrading the pin

1. Fetch upstream and identify the new commit and header version.
2. Diff the two files against the vendored copy and record the result in the change description.
3. Read the diff for a changed public signature, a new macro, a changed `telnet_event_t` member, or a new `HAVE_ZLIB` path. Each one is a Swift-side follow-up, not a merge conflict.
4. Copy the files, update `UPSTREAM.md`, and run the full validation.
5. Re-run the protocol suite. A behavior change in `libtelnet.c` surfaces as a failing protocol test; a changed option table appears as a changed negotiation test expectation. Fix the expectation only when the new behavior is correct per the RFC the test cites.

## Writing the Swift seam

One file, `Sources/TelnetKit/Protocol/TelnetProtocolCore.swift`, imports `CLibTelnet`. Nothing else does.

1. Build the option table as `[telnet_telopt_t]` terminated by an entry whose `telopt` is `-1`, then call `telnet_init` inside `withUnsafeBufferPointer` so the table outlives only the call.
2. Pass the owning object as `user_data` with `Unmanaged.passUnretained(self).toOpaque()`. A retained reference would keep the core alive past `telnet_free`.
3. In the callback, recover the core with `Unmanaged<TelnetProtocolCore>.fromOpaque(user).takeUnretainedValue()` and switch on `event.pointee.type`. Copy every buffer, string, and argument array immediately; the pointers expire at callback return.
4. Replace the three macros with `telnet_iac(handle, TELNET_SE)` calls.
5. Free the handle exactly once, from the deinit or the close path, on the owning EventLoop, and set the handle to nil so a second call cannot double-free.
6. Map `TELNET_EV_WARNING` and `TELNET_EV_ERROR` by copying `file`, `func`, `msg`, and `err`.

## Rules

- The vendored files are read-only. A required behavior change lives in Swift, and a suspected upstream bug is reported and recorded in `UPSTREAM.md` rather than patched in place.
- No other file may import `CLibTelnet`. When a second file needs protocol data, widen the core's Swift interface instead.
- Do not call `telnet_send*` from inside the callback. Append to the outbound queue and flush after `telnet_recv` returns.
- Do not read a union member that the event type does not select. Read the member named for the event.
- Do not define `HAVE_ZLIB`. The Apple SDKs ship zlib, so this is a design choice, not a dependency limit. With the switch off, libtelnet compiles its MCCP2 code out: a COMPRESS2 request is answered `wont`, and a compressed payload that arrives without negotiation is treated as application data rather than detected as a violation.

## Validation

Run these in order and keep the observed output:

1. `shasum -a 256` on the vendored files matches the upstream checkout at the recorded commit.
2. `swift build` succeeds with no warning from the C target, and the same target builds for the five platform floors (macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2).
3. `swift test --filter TelnetKitTests.Protocol` passes, including the negotiation-event and byte-escape cases.
4. A seam test feeds `FF FB 01` (IAC WILL ECHO) then `68 69 0D 0A` and asserts one `.negotiation` event followed by `.data("hi\r\n")`.
5. A seam test calls `telnet_send_text` through the public path with `hi\n`, negotiated ECHO, and asserts the outbound bytes carry `IAC DO ECHO` and a CR LF translation, written as `IOData`.
6. A close test frees the handle and asserts no further event reaches the callback.

## Dev Note

None.
