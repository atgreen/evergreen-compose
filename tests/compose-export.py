# SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
# SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

"""Maintainer exporter must reject unsupported contributions without damaging the bundle."""
import pathlib
import subprocess
import sys
import tempfile
import zipfile
import struct
def elf64():
    data = bytearray(120)
    data[:6] = b"\x7fELF\x02\x01"
    struct.pack_into("<Q", data, 32, 64)
    struct.pack_into("<HH", data, 54, 56, 1)
    struct.pack_into("<I", data, 64, 1)
    struct.pack_into("<Q", data, 112, 16384)
    return data

root = pathlib.Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory() as directory:
    work = pathlib.Path(directory)
    manifest = work / "AndroidManifest.xml"
    manifest.write_text('<manifest><uses-sdk/><application/></manifest>')
    apk = work / "runtime.apk"
    bundle = work / "bundle"
    def run(extra=None):
        with zipfile.ZipFile(apk, "w") as out:
            out.writestr("classes.dex", b"test dex")
            out.writestr("resources.arsc", b"test resources")
            if extra:
                out.writestr(extra, elf64() if extra.endswith("libmaplibre.so") else b"unsupported")
        return subprocess.run([sys.executable, str(root / "tools/export-compose-runtime.py"),
                               str(apk), str(bundle), str(manifest)], capture_output=True)
    assert run().returncode == 0
    assert run("classes10.dex").returncode == 0
    assert (bundle / "classes10.dex").exists()
    assert run("lib/arm64-v8a/libmaplibre.so").returncode == 0
    assert (bundle / "lib/arm64-v8a/libmaplibre.so").exists()
    original = (bundle / "bundle.sexp").read_bytes()
    for extra in ["lib/arm64-v8a/custom.so", "assets/required.bin", "../escape"]:
        assert run(extra).returncode != 0
        assert (bundle / "bundle.sexp").read_bytes() == original
    manifest.write_text('<manifest><application><provider/></application></manifest>')
    assert run().returncode != 0
    assert (bundle / "bundle.sexp").read_bytes() == original
print("Compose exporter rejection checks passed")
