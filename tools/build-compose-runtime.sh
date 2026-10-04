#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
# SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

# Maintainers only. Apps use the checked-in runtime and never call this script.
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
: "${JAVA_HOME:?Set JAVA_HOME to a JDK supported by Gradle 8.7 (for example JDK 21)}"
: "${ANDROID_HOME:=${ANDROID_SDK_ROOT:-}}"
: "${ANDROID_HOME:?Set ANDROID_HOME to an SDK with platform 35 and build-tools 34}"
export ANDROID_HOME
"$root/android/compose/gradlew" -p "$root/android/compose" --no-daemon assembleRelease
python3 "$root/tools/native_alignment.py" "$root/android/compose/build/outputs/apk/release/evergreen-compose-runtime-release-unsigned.apk"
python3 "$root/tools/export-compose-runtime.py" \
    "$root/android/compose/build/outputs/apk/release/evergreen-compose-runtime-release-unsigned.apk" \
    "$root/runtime/compose-v1" \
    "$root/android/compose/build/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml"
