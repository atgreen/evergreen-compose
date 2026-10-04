#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
# SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

# Build three signed apps with fresh caches/configuration and only EGCL on PATH.
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
egcl=$(command -v "${EGCL:-egcl}")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir "$work/bin"
ln -s "$egcl" "$work/bin/egcl"
build() {
  env -i PATH="$work/bin" XDG_CACHE_HOME="$work/cache" \
    XDG_CONFIG_HOME="$work/config" EGCL_HEAP_MB=2048 \
    "$work/bin/egcl" --no-init "$@"
}
build \
  --eval '(require :asdf)' \
  --eval '(asdf:load-asd (truename "evergreen-compose.asd"))' \
  --eval '(asdf:make "evergreen-compose/apk")'
build \
  --eval '(require :asdf)' \
  --eval '(asdf:load-asd (truename "evergreen-compose-build.asd"))' \
  --eval '(asdf:load-system "evergreen-compose-build")' \
  --eval '(asdf:load-asd (truename "examples/hello/hello.asd"))' \
  --eval '(asdf:make "hello/apk")'
build \
  --eval '(require :asdf)' \
  --eval '(asdf:load-asd (truename "evergreen-compose-build.asd"))' \
  --eval '(asdf:load-system "evergreen-compose-build")' \
  --eval '(asdf:load-asd (truename "examples/catalog/catalog.asd"))' \
  --eval '(asdf:make "catalog/apk")'
