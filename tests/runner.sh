#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
# SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

# Exercise the real command-line runner with controlled test results.
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
egcl=${EGCL:-egcl}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
mkdir "$fixture/tests"
cp -f "$root/run-tests.lisp" "$fixture/run-tests.lisp"
printf '%s\n' '(defpackage :evergreen-compose (:use :cl))' > "$fixture/load.lisp"
for failures in 0 1; do
    printf '(defun evergreen-compose::run-tests () %s)\n' "$failures" > "$fixture/tests/tests.lisp"
    status=0
    "$egcl" --no-init --load "$fixture/run-tests.lisp" > "$fixture/log" 2>&1 || status=$?
    if [ "$failures" -eq 0 ]; then
        [ "$status" -eq 0 ] && grep -q 'EVERGREEN-COMPOSE-TESTS-PASS' "$fixture/log"
    else
        if [ "$status" -eq 0 ]; then
            cat "$fixture/log"
            echo 'FAIL: a failing suite exited successfully' >&2
            exit 1
        fi
        grep -q 'EVERGREEN-COMPOSE-TESTS-FAIL' "$fixture/log"
    fi
done
printf '%s\n' '(error "injected load failure")' > "$fixture/tests/tests.lisp"
if "$egcl" --no-init --load "$fixture/run-tests.lisp" > "$fixture/log" 2>&1; then
    echo 'FAIL: a load error exited successfully' >&2
    exit 1
fi
grep -q 'injected load failure' "$fixture/log"
echo 'Runner exit-status checks passed'
