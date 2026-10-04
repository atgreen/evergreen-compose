# SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
# SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

"""Source releases include the runtime and exclude private/generated files."""
import importlib.util
import hashlib
import os
from pathlib import Path
import tarfile
import tempfile

root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("source_dist", root / "tools/source-dist.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory() as directory:
    fixture = Path(directory)
    wanted = ["README.md", "CHANGELOG.md", "evergreen-compose.asd", "LICENSE", "LICENSE.classpath-exception", "LICENSE-APACHE",
              "SECURITY.md", "CONTRIBUTING.md", "CODE_OF_CONDUCT.md", "CITATION.cff",
              ".github/ISSUE_TEMPLATE/bug.yml", ".github/ISSUE_TEMPLATE/feature.yml",
              ".github/pull_request_template.md", ".github/dependabot.yml",
              "src/package.lisp", "runtime/compose-v1/classes.dex",
              "runtime/compose-v1/META-INF/com/android/build/gradle/app-metadata.properties",
              "android/compose/gradle/wrapper/gradle-wrapper.jar",
              "examples/hello/app.lisp", "tests/compose-no-toolchain.sh"]
    unwanted = [".egcl-apk-key", "examples/hello/.egcl-apk-key",
                "android/compose/build/a.apk", "android/compose/.gradle/cache.bin",
                "android/compose/local.properties", "tools/__pycache__/cache.pyc",
                "assets/egcl.env", "assets/slynk-loader.lisp", "build/old.apk",
                ".beads/interactions.jsonl", ".codex/config.toml",
                "android/compose/.idea/workspace.xml", "src/.private/credentials.txt",
                "examples/evergreen-survey/app.lisp", "tests/more-samples.lisp"]
    for name in wanted + unwanted:
        path = fixture / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("fixture")
    (fixture / "evergreen-compose.asd").write_text(':version "0.0.1"')
    actual = {str(p.relative_to(fixture)) for p in module.source_files(fixture)}
    assert actual == set(wanted), actual
    first = fixture / "dist/first.tar.gz"
    second = fixture / "dist/second.tar.gz"
    module.write_archive(fixture, first)
    # Different file timestamps and destination names must not alter the bytes.
    for name in wanted:
        os.utime(fixture / name, (1234567890, 1234567890))
    module.write_archive(fixture, second)
    assert first.read_bytes() == second.read_bytes()
    with tarfile.open(first) as archive:
        assert set(archive.getnames()) == {f"evergreen-compose-0.0.1/{name}" for name in wanted}
        for entry in archive:
            assert entry.mtime == 0 and entry.uid == 0 and entry.gid == 0
    assert first.with_name(first.name + ".sha256").read_text() == (
        hashlib.sha256(first.read_bytes()).hexdigest() + "  first.tar.gz\n")
    try:
        module.write_archive(fixture, fixture / "src/overwrite.tar.gz")
        raise AssertionError("Release accepted output inside the source inputs")
    except ValueError:
        pass
    (fixture / "src/escape.lisp").symlink_to(fixture / ".egcl-apk-key")
    try:
        list(module.source_files(fixture))
        raise AssertionError("Release accepted a symlink")
    except ValueError:
        pass
print("Source distribution exclusion, checksum and reproducibility checks passed")
