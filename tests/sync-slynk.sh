#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
# SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
mkdir -p "$fixture/project/assets" "$fixture/slynk/backend"
for name in slynk-match slynk-backend slynk-rpc slynk slynk-completion slynk-apropos egcl-prelude egcl-slynk-patch; do
    printf '%s\n' "$name" > "$fixture/slynk/$name.lisp"
done
printf '%s\n' backend > "$fixture/slynk/backend/egcl.lisp"
sh "$root/tools/sync-slynk.sh" "$fixture/project" "$fixture/slynk"
cmp "$fixture/slynk/backend/egcl.lisp" "$fixture/project/assets/slynk-backend-egcl.lisp"
cmp "$fixture/slynk/slynk.lisp" "$fixture/project/assets/slynk-slynk.lisp"
rm -f "$fixture/slynk/egcl-prelude.lisp"
mkdir -p "$fixture/incomplete/assets"
if sh "$root/tools/sync-slynk.sh" "$fixture/incomplete" "$fixture/slynk"; then
    echo 'FAIL: accepted an incomplete Slynk source tree' >&2
    exit 1
fi
[ -z "$(find "$fixture/incomplete/assets" -type f -print)" ]
echo 'Slynk asset checks passed'
