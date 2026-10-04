#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
# SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

"""Create a reproducible, versioned distribution from the working tree."""
import argparse
import gzip
import hashlib
from pathlib import Path
import re
import tarfile

FILES = {"README.md", "CHANGELOG.md", "LICENSES.md", "LICENSE", "LICENSE.classpath-exception", "LICENSE-APACHE",
         "SECURITY.md", "CONTRIBUTING.md", "CODE_OF_CONDUCT.md", "CITATION.cff",
         "AGENTS.md", "CLAUDE.md", ".gitignore", "evergreen-compose.asd",
         "evergreen-compose-build.asd", "load.lisp", "load-order.sexp", "run-tests.lisp"}
DIRECTORIES = {"src", "assets", "packaging", "runtime", "examples", "docs",
               "android", "tools", "tests", ".github", ".agents"}
EXCLUDED = {"build", ".gradle", "__pycache__", ".egcl-apk-key", "local.properties"}
# Unfinished next-batch examples are retained in the checkout, not distributed.
UNRELEASED = {"examples/evergreen-survey", "tests/more-samples.lisp"}


def source_files(root):
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root)
        if relative.parts[0] not in DIRECTORIES and str(relative) not in FILES:
            continue
        if any(relative == Path(name) or Path(name) in relative.parents for name in UNRELEASED):
            continue
        # Runtime META-INF/com/android/build is dependency metadata, not a build directory.
        excluded = EXCLUDED - {"build"} if relative.parts[0] == "runtime" else EXCLUDED
        if any(part in excluded for part in relative.parts):
            continue
        nested = relative.parts[1:] if relative.parts[0] in {".github", ".agents"} else relative.parts
        if any(part.startswith(".") and part != ".gitignore" for part in nested):
            continue
        if path.suffix in {".pyc", ".fasl"}:
            continue
        if relative.parts[0] == "assets" and (path.name == "egcl.env" or path.name.startswith("slynk-")):
            continue
        if path.is_symlink():
            raise ValueError(f"Source release cannot contain a symlink: {relative}")
        if path.is_file():
            yield path


def write_archive(root, output):
    """Normalize archive metadata while preserving source and executable bits."""
    relative_output = output.resolve().relative_to(root.resolve()) if output.resolve().is_relative_to(root.resolve()) else None
    if relative_output and (relative_output.parts[0] in DIRECTORIES or str(relative_output) in FILES):
        raise ValueError("Output must be outside the release inputs, e.g. dist/evergreen-compose-0.0.1.tar.gz")
    versions = set(re.findall(r':version "([0-9]+\.[0-9]+\.[0-9]+)"', (root / "evergreen-compose.asd").read_text()))
    if len(versions) != 1:
        raise ValueError("Expected one consistent public version in evergreen-compose.asd")
    prefix = f"evergreen-compose-{versions.pop()}"
    files = list(source_files(root))
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as archive:
                for path in files:
                    entry = archive.gettarinfo(str(path), arcname=f"{prefix}/{path.relative_to(root)}")
                    entry.uid = entry.gid = entry.mtime = 0
                    entry.uname = entry.gname = ""
                    entry.mode = 0o755 if entry.mode & 0o111 else 0o644
                    entry.pax_headers = {}
                    with path.open("rb") as stream:
                        archive.addfile(entry, stream)
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_name(output.name + ".sha256").write_text(f"{digest}  {output.name}\n")
    print(f"Packaged {len(files)} files: {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="Destination .tar.gz (usually under dist/)")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    try:
        write_archive(root, args.output)
    except ValueError as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
