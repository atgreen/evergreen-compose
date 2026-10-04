#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
# SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

# Matching stable Fedora 44 x86-64 packages; verify bytes before installation.
set -eu
packages=$(mktemp -d)
trap 'rm -rf "$packages"' EXIT HUP INT TERM
base=https://github.com/atgreen/evergreen/releases/download/v0.0.1
curl -fL --retry 3 "$base/egcl-0.0.1-6.fc44.x86_64.rpm" -o "$packages/egcl.rpm"
curl -fL --retry 3 "$base/egcl-target-android-0.0.1-6.fc44.x86_64.rpm" -o "$packages/android.rpm"
printf '%s  %s\n' \
  10e23cd249d766c45636b97b7d546cc4cf94c9015b1cd02b33cc4806bfcc51f0 "$packages/egcl.rpm" \
  cd778ce3d1f393fe7091d57e72b5e443f1afc1d268979522cfb1da1d010e44af "$packages/android.rpm" | sha256sum -c -
dnf -y install "$packages/egcl.rpm" "$packages/android.rpm"
