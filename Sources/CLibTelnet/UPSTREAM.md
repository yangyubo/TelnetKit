# Vendored source provenance

English | [中文](UPSTREAM.zh.md)

libtelnet reaches this package as the git submodule `libtelnet/`, so the upstream sources, the upstream `COPYING`, and the upstream history stay exactly as published, and moving to a new version is a submodule checkout rather than a file copy. This file records the pin and states how our own tree reaches those files. The procedure is [.agents/skills/telnetkit-import-c-library/SKILL.md](../../.agents/skills/telnetkit-import-c-library/SKILL.md).

## Submodule pin

| Field | Value |
|---|---|
| Upstream | https://github.com/seanmiddleditch/libtelnet |
| Submodule path | `libtelnet` |
| URL recorded in | the package root `.gitmodules` |
| Commit | `5f5ecee776b9bdaa4e981e5f807079a9c79d633e`, recorded as the gitlink in the package root |
| Branch | `develop` at clone time |
| Header version | `0.23`, from the `\version` tag in `libtelnet.h` |
| License | Public domain dedication, shipped in the submodule as `COPYING` |

The submodule is never written to. Nothing is generated inside it, so `git -C libtelnet status` stays clean and a version bump cannot conflict with a local file.

## How our tree reaches the submodule

SwiftPM looks for a custom module map only in the target's public headers directory, and SwiftPM's `PackageBuilder` requires that directory to be a descendant of the target path while the `.c` compiles from that same path. The target is therefore our own `Sources/CLibTelnet`, and the submodule files are reached through two committed relative symlinks:

```text
Sources/CLibTelnet/libtelnet.c                    -> ../../libtelnet/libtelnet.c
Sources/CLibTelnet/include/libtelnet.h            -> ../../../libtelnet/libtelnet.h
Sources/CLibTelnet/include/module.modulemap       our file, tracked
```

```c
module CLibTelnet {
    umbrella header "libtelnet.h"
    export *
}
```

- The symlinks are relative, so a clone resolves them without any absolute path baked in.
- `umbrella header` rather than `header` keeps SwiftPM's generated-map rules in view; both work here because the map and the header share a directory.
- `Sources/CLibTelnet/include` is the first `-I` path for clang, which is how the compiler resolves `#include "libtelnet.h"` inside the source.
- A clone needs one command, `git submodule update --init --recursive`, and nothing else: the symlinks are tracked, so no generation step exists.

## Build settings

The C target compiles with no custom macro, verified by `swift build --target CLibTelnet` and by the same build for the iOS, watchOS, tvOS, and visionOS floors. `HAVE_ZLIB` stays undefined, so libtelnet compiles with its MCCP2 code removed and the linker never needs `-lz`. A COMPRESS2 request is refused rather than half-supported; see the [COMPRESS2 contract](../../docs/public-api.md#events). The Apple SDKs would link zlib, so this is a design choice, not a dependency limit.

## Upgrade checklist

1. In `libtelnet/`, fetch the upstream remote and check out the target commit; then record the new commit and header version here.
2. Confirm both symlinks still resolve, because a new commit could rename or move a file that a link names.
3. Read the diff for a changed public signature, a new macro, a changed `telnet_event_t` member, or a new `HAVE_ZLIB` path; each is a Swift-side follow-up rather than a merge conflict.
4. Re-run the [import skill validation](../../.agents/skills/telnetkit-import-c-library/SKILL.md#validation), then the protocol suite.
5. Stage the package root, so the new gitlink and the record here land in one commit.
