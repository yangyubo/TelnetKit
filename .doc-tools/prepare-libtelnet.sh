#!/usr/bin/env bash
#
# Creates the one file SwiftPM needs inside the libtelnet submodule.
#
# SwiftPM compiles the .c from the target path and requires the public headers to live
# under that path. The submodule is pinned to upstream, so we never commit anything into
# it; this script writes the untracked libtelnet/include/module.modulemap instead, and
# re-running it is safe.
#
# Run from the repository root after cloning:
#
#     ./.doc-tools/prepare-libtelnet.sh
#
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
submodule="$root/libtelnet"

if [ ! -f "$submodule/libtelnet.c" ] || [ ! -f "$submodule/libtelnet.h" ]; then
    echo "error: $submodule is not checked out; run: git submodule update --init --recursive" >&2
    exit 1
fi

mkdir -p "$submodule/include"
cat > "$submodule/include/module.modulemap" <<'MODULEMAP'
// Ours, not upstream: SwiftPM needs public headers under the target path, so this
// directory exists only to expose the sibling header. The include directory must stay
// the first -I path for clang, which is what resolves ../libtelnet.h below.
module CLibTelnet {
    header "../libtelnet.h"
    export *
}
MODULEMAP

echo "wrote $submodule/include/module.modulemap"
