#!/bin/sh
# Copy the nine slynk files a live REPL needs into an Android project's assets.
#
#   tools/sync-slynk.sh <android-project-dir> [slynk-dir]
#
# APK assets are one flat directory, so backend/egcl.lisp ships as
# backend-egcl.lisp and everything gains a slynk- prefix, which is what
# BLISS:START-LIVE-REPL expects.
#
# SLYNK COMES FROM ICL when a slynk directory is not given. icl unpacks it under
# ~/.local/share/icl/slynk-*/, and egcl's lib/slynk is that same source plus
# three files -- a backend, a prelude of shims, and a patch. Taking the common
# part from icl means there is no forked slynk to fall out of step.
#
# 265 KB, against 1.1 MB for the whole slynk tree: the other backends and the
# files this load order never touches are left behind.
set -eu
[ $# -ge 1 ] || { echo "usage: $0 <android-project-dir> [slynk-dir]" >&2; exit 2; }
here=$(cd "$(dirname "$0")/.." && pwd)
assets="$1/assets"
[ -d "$assets" ] || { echo "no assets directory: $assets" >&2; exit 1; }

if [ $# -ge 2 ]; then
  slynk="$2"
else
  slynk=$(ls -d "$HOME"/.local/share/icl/slynk-* 2>/dev/null | sort | tail -1 || true)
fi
[ -n "$slynk" ] && [ -d "$slynk" ] || {
  echo "no slynk found -- run icl once, or pass a directory" >&2; exit 1; }

# The egcl-specific three come from this repo; the rest from icl's copy.
egcl_bits="$here/../../evergreen/lib/slynk"
[ -f "$egcl_bits/backend/egcl.lisp" ] || egcl_bits="$HOME/git/evergreen/lib/slynk"
[ -f "$egcl_bits/backend/egcl.lisp" ] || {
  echo "no egcl slynk backend found (looked in $egcl_bits)" >&2; exit 1; }

copy() { cp "$1" "$assets/slynk-$2.lisp"; }
copy "$slynk/slynk-match.lisp"      slynk-match
copy "$slynk/slynk-backend.lisp"    slynk-backend
copy "$egcl_bits/backend/egcl.lisp"      backend-egcl
copy "$egcl_bits/egcl-prelude.lisp"      egcl-prelude
copy "$slynk/slynk-rpc.lisp"        slynk-rpc
copy "$slynk/slynk.lisp"            slynk
copy "$slynk/slynk-completion.lisp" slynk-completion
copy "$slynk/slynk-apropos.lisp"    slynk-apropos
copy "$egcl_bits/egcl-slynk-patch.lisp"  egcl-slynk-patch

echo "synced 9 slynk files ($(du -ch "$assets"/slynk-*.lisp | tail -1 | cut -f1)) to $assets"
echo "  from $slynk"
echo "  plus the egcl backend/prelude/patch from $egcl_bits"
