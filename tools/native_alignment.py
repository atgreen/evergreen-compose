# SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
# SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

"""Validate native ELF segments and uncompressed APK offsets for 16 KB Android."""
import pathlib
import struct
import sys
import zipfile


def check_elf(name, data):
    if len(data) < 64 or data[:4] != b"\x7fELF" or data[5] != 1:
        raise ValueError(f"Invalid little-endian ELF: {name}")
    is64 = data[4] == 2
    if data[4] not in (1, 2):
        raise ValueError(f"Invalid ELF class: {name}")
    offset = struct.unpack_from("<Q" if is64 else "<I", data, 32 if is64 else 28)[0]
    stride, count = struct.unpack_from("<HH", data, 54 if is64 else 42)
    size = 56 if is64 else 32
    if stride < size or offset + count * stride > len(data) or count == 0:
        raise ValueError(f"Invalid ELF program headers: {name}")
    loads = 0
    for i in range(count):
        at = offset + i * stride
        if struct.unpack_from("<I", data, at)[0] == 1:
            loads += 1
            align = struct.unpack_from("<Q" if is64 else "<I", data, at + (48 if is64 else 28))[0]
            # Android only supports 16 KB pages on 64-bit ABIs.
            if is64 and (align < 16384 or align & (align - 1)):
                raise ValueError(f"Native library lacks 16 KB ELF alignment: {name} ({align})")
    if not loads:
        raise ValueError(f"ELF has no load segments: {name}")


def check_apk(path):
    with zipfile.ZipFile(path) as apk, open(path, "rb") as source:
        count = 0
        for item in apk.infolist():
            if item.filename.startswith("lib/") and item.filename.endswith(".so"):
                check_elf(item.filename, apk.read(item))
                source.seek(item.header_offset)
                header = source.read(30)
                offset = item.header_offset + 30 + sum(struct.unpack_from("<HH", header, 26))
                if item.compress_type != zipfile.ZIP_STORED or offset % 16384:
                    raise ValueError(f"Native APK entry is not uncompressed/16 KB aligned: {item.filename}")
                count += 1
        if not count:
            raise ValueError(f"No native libraries in {path}")
        print(f"{path}: {count} native libraries pass ELF and APK 16 KB checks")


if __name__ == "__main__":
    for path in sys.argv[1:]:
        check_apk(pathlib.Path(path))
