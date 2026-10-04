#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
# SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

"""Maintainer tool: export linked DEX/resources, never app manifest/signatures."""
import hashlib
import pathlib
import re
import sys
import xml.etree.ElementTree as ET
import zipfile
from native_alignment import check_elf

source, destination, manifest_path = map(pathlib.Path, sys.argv[1:])
manifest = ET.parse(manifest_path).getroot()
for child in manifest:
    if child.tag not in ("uses-sdk", "application") or child.tag == "application" and len(child):
        raise SystemExit("Runtime has manifest contributions requiring explicit packager support")

# Validate everything before replacing the last usable bundle.
entries = {}
with zipfile.ZipFile(source) as apk:
    for name in sorted(apk.namelist()):
        if name.endswith("/"):
            continue
        parts = pathlib.PurePosixPath(name).parts
        if name.startswith("/") or ".." in parts or "\\" in name:
            raise SystemExit(f"Unsafe bundle path: {name}")
        native = re.fullmatch(r"lib/(?:arm64-v8a|armeabi-v7a|x86|x86_64)/lib(?:maplibre|androidx\.graphics\.path|image_processing_util_jni|surface_util_jni)\.so", name)
        if name.startswith(("assets/", "lib/")) and not name.startswith("assets/dexopt/") and not native:
            raise SystemExit(f"Runtime entry needs explicit packaging support: {name}")
        if (native or re.fullmatch(r"classes(?:[2-9]|[1-9][0-9]+)?\.dex", name) or
                name == "resources.arsc" or name.startswith("res/") or
                name.startswith("META-INF/") and not name.endswith((".RSA", ".SF", ".MF"))):
            entries[name] = apk.read(name)
            if native:
                check_elf(name, entries[name])
if not {"classes.dex", "resources.arsc"}.issubset(entries):
    raise SystemExit("Runtime lacks classes.dex or resources.arsc")

destination.mkdir(parents=True, exist_ok=True)
previous = destination / "bundle.sexp"
if previous.exists():
    for name in re.findall(r'\("([^"\n]+)" "[0-9a-f]{64}"\)', previous.read_text()):
        old = destination / name
        if name not in entries and old.is_relative_to(destination) and ".." not in pathlib.Path(name).parts:
            old.unlink(missing_ok=True)
records = []
for name, data in entries.items():
    path = destination / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    records.append(f'    ("{name}" "{hashlib.sha256(data).hexdigest()}")')
previous.write_text('(:protocol 1 :version "1.4.0" :min-sdk 28\n :files (\n' + '\n'.join(records) + '))\n')
print(f"Exported {len(entries)} entries to {destination}")
