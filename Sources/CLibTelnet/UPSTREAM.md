# Vendored source provenance

`Sources/CLibTelnet/` carries an unmodified copy of libtelnet so that a Swift Package can build it. This file records the pin and states whether the copy differs from upstream. The copying, verification, and upgrade procedure is [.agents/skills/telnetkit-import-c-library/SKILL.md](../../.agents/skills/telnetkit-import-c-library/SKILL.md).

## Pin

| Field | Value |
|---|---|
| Upstream | https://github.com/seanmiddleditch/libtelnet |
| Branch | `develop` |
| Commit | `5f5ecee776b9bdaa4e981e5f807079a9c79d633e` (2020-08-14) |
| Header version | `0.23`, from the `\version` tag in `libtelnet.h` |
| Files copied | `libtelnet.c`, `libtelnet.h` |
| Destination | `libtelnet.c`; `include/libtelnet.h` |
| License | Public domain dedication, from the upstream `COPYING` file |

## Local modifications

None. When the copy lands, the two files are byte-identical to upstream at the pinned commit, and the SHA-256 digest of each file matches the upstream checkout.

`include/module.modulemap` is ours and is not part of upstream:

```c
module CLibTelnet {
    header "libtelnet.h"
    export *
}
```

## Build settings

The C target compiles with no custom macro. `HAVE_ZLIB` stays undefined, so MCCP2 support is absent and a COMPRESS2 request is refused rather than half-supported. See the [COMPRESS2 contract](../../docs/public-api.md#events) for the resulting behavior.

## Upgrade checklist

1. Fetch upstream and record the new commit and header version in the pin table.
2. Diff both files and read the diff for a changed public signature, a new macro, a changed `telnet_event_t` member, or a new `HAVE_ZLIB` path.
3. Copy the two files and confirm no local modification is reintroduced.
4. Re-run the [import skill validation](../../.agents/skills/telnetkit-import-c-library/SKILL.md#validation), then the protocol suite.
