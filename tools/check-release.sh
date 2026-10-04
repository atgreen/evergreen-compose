#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
# SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

# The shared local/CI gate verifies the actual archive that will be uploaded.
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
assets=${1:-"$root/dist/release"}
mkdir -p "$assets"
assets=$(CDPATH='' cd -- "$assets" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
export EGCL_HEAP_MB=2048
export XDG_CACHE_HOME="$work/cache"
sh tools/check.sh
shellcheck tools/*.sh tests/*.sh
version=$(python3 tools/release.py version)
python3 tools/release.py build --output "$assets"
python3 tools/source-dist.py "$work/reproduced.tar.gz"
cmp "$assets/evergreen-compose-$version.tar.gz" "$work/reproduced.tar.gz"
tar -xzf "$assets/evergreen-compose-$version.tar.gz" -C "$work"
cd "$work/evergreen-compose-$version"
"${EGCL:-egcl}" --no-init --load tests/asdf.lisp
sh tests/compose-no-toolchain.sh
python3 tools/native_alignment.py build/evergreen-compose.apk \
  examples/hello/build/hello.apk examples/catalog/build/catalog.apk
python3 tools/release.py verify --assets "$assets" --version "$version"
