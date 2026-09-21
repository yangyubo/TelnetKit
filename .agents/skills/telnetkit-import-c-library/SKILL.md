---
name: telnetkit-import-c-library
description: Add, pin, verify, or upgrade the libtelnet git submodule behind the TelnetKit Swift package, and fix a failure in the Swift-to-C seam. Use when adding or moving the libtelnet submodule, recording or changing the pinned commit, restoring include/module.modulemap, reproducing a libtelnet behavior, or diagnosing a mismatch between the C header and the Swift wrapper.
---

# Importing the libtelnet C library

English | [中文](SKILL.zh.md)

## Summary

[seanmiddleditch/libtelnet](https://github.com/seanmiddleditch/libtelnet) reaches this package as the git submodule `libtelnet/`, so upstream code, license, and history stay intact and an upgrade is a checkout. This workflow covers adding the submodule, the module map SwiftPM needs, the provenance record, the Swift seam, and the upgrade procedure. It is guidance with a fixed verification path, not a generator.

## Table of Contents

- [Facts that constrain the layout](#facts-that-constrain-the-layout)
- [Workflow: adding the submodule](#workflow-adding-the-submodule)
- [Workflow: upgrading the pin](#workflow-upgrading-the-pin)
- [Writing the Swift seam](#writing-the-swift-seam)
- [Rules](#rules)
- [Validation](#validation)
- [Dev Note](#dev-note)

## Facts that constrain the layout

Verified against upstream `develop` at commit `5f5ecee776b9bdaa4e981e5f807079a9c79d633e` (2020-08-14), header version 0.23:

- The repository contains no `Package.swift`, so the package points a C target at the submodule rather than depending on a Swift package. `libtelnet.c` and `libtelnet.h` are the whole library, and the rest of the checkout is left alone.
- The C source compiles clean with `clang -c libtelnet.c -I include -Wall` and exports 23 `telnet_*` symbols.
- `libtelnet.c` has one optional dependency behind `HAVE_ZLIB` for MCCP2. Do not define it: compression support is out of scope, and the Swift code must answer a COMPRESS2 request with `wont`.
- `libtelnet.h` states `public domain`. Record that in the notice file; do not attach our license to the submodule.
- Three facilities are macros and therefore invisible to Swift: `telnet_finish_sb`, `telnet_finish_newenviron`, `telnet_finish_zmp`. The seam supplies each one.
- Upstream exports no query for negotiated option state. The Swift layer maintains its own ledger; never add a C helper that reaches into `struct telnet_t`.

## Workflow: adding the submodule

1. `git submodule add https://github.com/seanmiddleditch/libtelnet.git libtelnet`, then in `libtelnet/` check out the commit `UPSTREAM.md` records. The gitlink carries the pin, so nothing else has to.
2. Create the two relative symlinks under `Sources/CLibTelnet/` that reach the submodule's source and header, and keep `Sources/CLibTelnet/include/module.modulemap` as a tracked file.
3. Declare the target in `Package.swift` as `.target(name: "CLibTelnet", path: "Sources/CLibTelnet", publicHeadersPath: "include")` with no custom C settings, and keep it out of `products`.
4. Confirm the map resolves its sibling header, and that the symlink targets are relative so a clone reproduces them.
5. Update `Sources/CLibTelnet/UPSTREAM.md` with the submodule path, URL, commit, and header version.
6. Run the [validation](#validation) steps.

## Workflow: upgrading the pin

1. In `libtelnet/`, fetch the upstream remote and check out the target commit.
2. Confirm both symlinks still resolve, because a new commit can rename or move a file a link names.
3. Diff the checkout against the previous pin and read the diff for a changed public signature, a new macro, a changed `telnet_event_t` member, or a new `HAVE_ZLIB` path. Each one is a Swift-side follow-up, not a merge conflict.
4. Update `UPSTREAM.md` and run the full validation; stage the package root so the gitlink and the record land together.
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

- The submodule is read-only. Never commit into it, never write a file there, and never patch it; our module map and the symlinks live under `Sources/CLibTelnet/`. A required behavior change lives in Swift, and a suspected upstream bug is reported and recorded in `UPSTREAM.md`.
- No other file may import `CLibTelnet`. When a second file needs protocol data, widen the core's Swift interface instead.
- Do not call `telnet_send*` from inside the callback. Append to the outbound queue and flush after `telnet_recv` returns.
- Do not read a union member that the event type does not select. Read the member named for the event.
- Do not define `HAVE_ZLIB`. The Apple SDKs ship zlib, so this is a design choice, not a dependency limit. With the switch off, libtelnet compiles its MCCP2 code out: a COMPRESS2 request is answered `wont`, and a compressed payload that arrives without negotiation is treated as application data rather than detected as a violation.

## Validation

Run these in order and keep the observed output:

1. `git -C libtelnet rev-parse HEAD` equals the commit in `UPSTREAM.md`, and `git -C libtelnet status --porcelain` prints nothing.
2. `swift build --target CLibTelnet` succeeds with no warning, and `--triple` repeats it for the iOS 18, watchOS 11, tvOS 18, and visionOS 2 floors; macOS 15 is the host build. `swift test` then covers the protocol path.
3. `swift test` passes, including the negotiation-event and byte-escape cases.
4. A seam test feeds `FF FB 01` (IAC WILL ECHO) then `68 69 0D 0A` and asserts one `.negotiation` event followed by `.data("hi\r\n")`.
5. A seam test calls `telnet_send_text` through the public path with `hi\n`, negotiated ECHO, and asserts the outbound bytes carry `IAC DO ECHO` and a CR LF translation, written as `IOData`.
6. A close test frees the handle and asserts no further event reaches the callback.

## Dev Note

None.
