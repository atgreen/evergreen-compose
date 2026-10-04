#!/bin/sh
# Convert named Material icons to Lisp path data.
#
#   tools/make-icons.sh <material-design-icons> <output.lisp> <name>...
#
# The icons live at <repo>/src/<category>/<name>/materialicons/24px.svg and the
# category is not knowable from the name, so it is searched for.
set -eu
[ $# -ge 3 ] || { echo "usage: $0 <material-repo> <output.lisp> <name>..." >&2; exit 2; }
repo=$1; out=$2; shift 2
here=$(cd "$(dirname "$0")/.." && pwd)
egcl=${EGCL:-egcl}
manifest=$(mktemp)
trap 'rm -f "$manifest"' EXIT
missing=0
for name in "$@"; do
  svg=$(find "$repo/src" -mindepth 2 -maxdepth 2 -type d -name "$name" -print -quit)/materialicons/24px.svg
  if [ -f "$svg" ]; then
    printf '%s\t%s\n' "$name" "$svg" >> "$manifest"
  else
    echo "no such icon: $name" >&2
    missing=$((missing + 1))
  fi
done
[ "$missing" -eq 0 ] || { echo "$missing icon(s) not found" >&2; exit 1; }
# --eval and --load are contradictory in egcl, so the call goes in a file too.
driver=$(mktemp /tmp/make-icons-XXXXXX.lisp)
trap 'rm -f "$manifest" "$driver"' EXIT
cat > "$driver" <<EOF
(load "$here/tools/make-icons.lisp")
(bliss::make-icons "$manifest" "$out")
EOF
"$egcl" --no-init --load "$driver"
