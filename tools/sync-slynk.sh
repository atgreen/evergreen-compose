#!/bin/sh
# Copy the nine slynk files a live REPL needs into an Android project's assets.
#
#   tools/sync-slynk.sh <android-project-dir> [slynk-dir]
#
# APK assets are one flat directory, so backend/torcl.lisp ships as
# backend-torcl.lisp and everything gains a slynk- prefix, which is what
# BLISS:START-LIVE-REPL expects.
#
# SLYNK COMES FROM ICL when a slynk directory is not given. icl unpacks it under
# ~/.local/share/icl/slynk-*/, and torcl's lib/slynk is that same source plus
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

# The torcl-specific three come from this repo; the rest from icl's copy.
torcl_bits="$here/../../bliss/lib/slynk"
[ -f "$torcl_bits/backend/torcl.lisp" ] || torcl_bits="$HOME/git/bliss/lib/slynk"
[ -f "$torcl_bits/backend/torcl.lisp" ] || {
  echo "no torcl slynk backend found (looked in $torcl_bits)" >&2; exit 1; }

copy() { cp "$1" "$assets/slynk-$2.lisp"; }
copy "$slynk/slynk-match.lisp"      slynk-match
copy "$slynk/slynk-backend.lisp"    slynk-backend
copy "$torcl_bits/backend/torcl.lisp"      backend-torcl
copy "$torcl_bits/torcl-prelude.lisp"      torcl-prelude
copy "$slynk/slynk-rpc.lisp"        slynk-rpc
copy "$slynk/slynk.lisp"            slynk
copy "$slynk/slynk-completion.lisp" slynk-completion
copy "$slynk/slynk-apropos.lisp"    slynk-apropos
copy "$torcl_bits/torcl-slynk-patch.lisp"  torcl-slynk-patch

echo "synced 9 slynk files ($(du -ch "$assets"/slynk-*.lisp | tail -1 | cut -f1)) to $assets"
echo "  from $slynk"
echo "  plus the torcl backend/prelude/patch from $torcl_bits"
