#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
# SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

# Copy a complete EGCL-enabled Slynk source tree into an APK project's assets.
# Usage: tools/sync-slynk.sh <project-dir> [slynk-dir]
set -eu
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || {
    echo "usage: $0 <project-dir> [slynk-dir]" >&2; exit 2;
}
assets="$1/assets"
[ -d "$assets" ] || { echo "no assets directory: $assets" >&2; exit 1; }
slynk=${2:-${SLYNK_DIR:-}}
if [ -z "$slynk" ]; then
    for candidate in "${XDG_DATA_HOME:-$HOME/.local/share}"/icl/slynk-*; do
        [ ! -f "$candidate/backend/egcl.lisp" ] || slynk=$candidate
    done
fi
[ -n "$slynk" ] || {
    echo "pass an EGCL-enabled Slynk directory, or set SLYNK_DIR" >&2; exit 1;
}
# Validate everything before writing anything. The backend, prelude and patch
# belong to Slynk now, so all nine files must come from the same source tree.
files='slynk-match slynk-backend backend/egcl egcl-prelude slynk-rpc slynk slynk-completion slynk-apropos egcl-slynk-patch'
for name in $files; do
    [ -f "$slynk/$name.lisp" ] || {
        echo "missing $slynk/$name.lisp; use an EGCL-enabled Slynk tree" >&2; exit 1;
    }
done
for name in $files; do
    flat=$name
    [ "$name" != backend/egcl ] || flat=backend-egcl
    cp -f "$slynk/$name.lisp" "$assets/slynk-$flat.lisp"
done
echo "synced 9 Slynk files from $slynk to $assets"
