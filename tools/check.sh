#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
# SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

# The same host gate runs locally and in CI. No Android SDK or device needed.
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
egcl=${EGCL:-egcl}
sh tests/runner.sh
sh tests/sync-slynk.sh
"$egcl" --no-init --load run-tests.lisp


python3 tests/compose-export.py
python3 tests/native-alignment.py
python3 tests/source-dist.py
python3 tests/release.py
