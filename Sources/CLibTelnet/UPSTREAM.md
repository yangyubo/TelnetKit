# Vendored source provenance

English | [中文](UPSTREAM.zh.md)

libtelnet reaches this package as the git submodule `libtelnet/`, so the upstream sources, the upstream `COPYING`, and the upstream history stay exactly as published, and moving to a new version is a submodule checkout rather than a file copy. This file records the pin and states what, if anything, we add to the submodule. The procedure is [.agents/skills/telnetkit-import-c-library/SKILL.md](../../.agents/skills/telnetkit-import-c-library/SKILL.md).

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

## What we add inside the submodule

One file, written by [.doc-tools/prepare-libtelnet.sh](../../.doc-tools/prepare-libtelnet.sh) and never committed anywhere:

```text
libtelnet/include/module.modulemap     untracked in the submodule, so it does not dirty the pin
```

```c
module CLibTelnet {
    header "../libtelnet.h"
    export *
}
```

SwiftPM compiles the `.c` from the target path and requires the public headers to live under that path, which is why the map is written there instead of into our own tree.

Two details decide whether this builds:

- The `header` path is relative to the module map, not to an include search path, so `../libtelnet.h` is correct here. A bare `libtelnet.h` fails with `header 'libtelnet.h' not found`.
- `libtelnet/include` is the first `-I` path for clang, which is what lets the map reach the sibling header.

Any clone must run `./.doc-tools/prepare-libtelnet.sh` once after `git submodule update --init --recursive`. The script is idempotent and fails loudly when the submodule is absent.

## Build settings

The C target compiles with no custom macro. `HAVE_ZLIB` stays undefined, so libtelnet compiles with its MCCP2 code removed and the linker never needs `-lz`. A COMPRESS2 request is refused rather than half-supported; see the [COMPRESS2 contract](../../docs/public-api.md#events). The Apple SDKs would link zlib, so this is a design choice, not a dependency limit.

## Upgrade checklist

1. In `libtelnet/`, fetch the upstream remote and check out the target commit; then record the new commit and header version here.
2. Re-run `./.doc-tools/prepare-libtelnet.sh`, because a new commit could rename or move the header.
3. Read the diff for a changed public signature, a new macro, a changed `telnet_event_t` member, or a new `HAVE_ZLIB` path; each is a Swift-side follow-up rather than a merge conflict.
4. Re-run the [import skill validation](../../.agents/skills/telnetkit-import-c-library/SKILL.md#validation), then the protocol suite.
5. Stage the package root, so the new gitlink and the record here land in one commit.
