# SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
# SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

"""The maintainer exporter must reject native dependencies built for 4 KB pages."""
import importlib.util
import pathlib
import struct

path = pathlib.Path(__file__).resolve().parent.parent / "tools/native_alignment.py"
spec = importlib.util.spec_from_file_location("alignment", path)
alignment = importlib.util.module_from_spec(spec)
spec.loader.exec_module(alignment)

def elf64(align):
    data = bytearray(120)
    data[:6] = b"\x7fELF\x02\x01"
    struct.pack_into("<Q", data, 32, 64)
    struct.pack_into("<HH", data, 54, 56, 1)
    struct.pack_into("<I", data, 64, 1)
    struct.pack_into("<Q", data, 112, align)
    return bytes(data)

alignment.check_elf("lib/arm64-v8a/test.so", elf64(16384))
for data in [elf64(4096), b"truncated", elf64(0)]:
    try:
        alignment.check_elf("lib/arm64-v8a/test.so", data)
    except ValueError:
        pass
    else:
        raise AssertionError("Accepted incompatible ELF")
print("Native 16 KB alignment checks passed")
