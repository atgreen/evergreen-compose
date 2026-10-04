#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
# SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

"""Plan releases and assemble/verify the exact downloadable asset set."""
import argparse
import hashlib
import importlib.util
import os
from pathlib import Path
import re
import tarfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('source_dist', ROOT / 'tools/source-dist.py')
source_dist = importlib.util.module_from_spec(spec)
spec.loader.exec_module(source_dist)


def version(root):
    versions = set(re.findall(r':version "([0-9]+\.[0-9]+\.[0-9]+)"',
                              (root / 'evergreen-compose.asd').read_text()))
    if len(versions) != 1:
        raise ValueError('Expected one consistent public version')
    result = versions.pop()
    citation = re.search(r'^version: ([0-9]+\.[0-9]+\.[0-9]+)$',
                         (root / 'CITATION.cff').read_text(), re.M)
    if not citation or citation[1] != result:
        raise ValueError('Citation version must match the public version')
    return result


def make_plan(release_version, event, ref, run_id, attempt, mode):
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', release_version):
        raise ValueError('Version must be major.minor.patch')
    if event == 'push':
        if ref != f'refs/tags/v{release_version}':
            raise ValueError('Release tag must match the public version')
        return dict(version=release_version, tag=f'v{release_version}', publish=True, prerelease=False)
    if event != 'workflow_dispatch' or mode not in ('test', 'build'):
        raise ValueError('Use a matching version tag or manual test/build mode')
    if not re.fullmatch(r'[1-9][0-9]*', run_id) or not re.fullmatch(r'[1-9][0-9]*', attempt):
        raise ValueError('Run ID and attempt must be positive integers')
    return dict(version=release_version, tag=f'test-v{release_version}-{run_id}-{attempt}',
                publish=mode == 'test', prerelease=True)


def asset_names(release_version):
    archive = f'evergreen-compose-{release_version}.tar.gz'
    return {archive, archive + '.sha256', 'RELEASE-NOTES.md', 'SHA256SUMS'}


def notes(root, release_version):
    match = re.search(r'^## ' + re.escape(release_version) + r' - [^\n]+\n.*?(?=^## |\Z)',
                      (root / 'CHANGELOG.md').read_text(), re.M | re.S)
    if not match:
        raise ValueError('Changelog must contain release notes for the public version')
    return match[0].strip() + '\n'


def checksums(directory, names):
    return ''.join(f'{hashlib.sha256((directory / name).read_bytes()).hexdigest()}  {name}\n'
                   for name in sorted(names))


def build(root, destination):
    release_version = version(root)
    release_notes = notes(root, release_version)
    expected = asset_names(release_version)
    destination.mkdir(parents=True, exist_ok=True)
    if {p.name for p in destination.iterdir()} - expected:
        raise ValueError('Release directory contains unexpected files; use a dedicated output directory')
    if any(p.is_symlink() or not p.is_file() for p in destination.iterdir()):
        raise ValueError('Release assets must be regular files')
    source_dist.write_archive(root, destination / f'evergreen-compose-{release_version}.tar.gz')
    (destination / 'RELEASE-NOTES.md').write_text(release_notes)
    (destination / 'SHA256SUMS').write_text(checksums(destination, expected - {'SHA256SUMS'}))
    verify(destination, release_version)


def verify(directory, release_version):
    expected = asset_names(release_version)
    if {p.name for p in directory.iterdir()} != expected:
        raise ValueError('Release assets must be complete, with no unexpected files')
    if any(p.is_symlink() or not p.is_file() for p in directory.iterdir()):
        raise ValueError('Release assets must be regular files')
    if (directory / 'SHA256SUMS').read_text() != checksums(directory, expected - {'SHA256SUMS'}):
        raise ValueError('Release checksum mismatch')
    archive = f'evergreen-compose-{release_version}.tar.gz'
    if (directory / (archive + '.sha256')).read_text() != checksums(directory, {archive}):
        raise ValueError('Archive checksum mismatch')
    prefix = f'evergreen-compose-{release_version}/'
    with tarfile.open(directory / archive) as source:
        members = source.getmembers()
        names = [m.name for m in members]
        required = {'evergreen-compose.asd', 'evergreen-compose-build.asd',
                    'assets/evergreen-compose.lisp', 'LICENSE', 'LICENSE.classpath-exception',
                    'runtime/compose-v1/bundle.sexp', 'runtime/compose-v1/classes.dex'}
        if len(names) != len(set(names)) or not {prefix + n for n in required} <= set(names):
            raise ValueError('Archive lacks required source/runtime files or contains duplicate entries')
        for entry in members:
            if not entry.isfile() or not entry.name.startswith(prefix) or '..' in Path(entry.name).parts:
                raise ValueError('Unsafe archive entry')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('version')
    commands.add_parser('plan')
    builder = commands.add_parser('build')
    builder.add_argument('--output', type=Path, required=True)
    checker = commands.add_parser('verify')
    checker.add_argument('--assets', type=Path, required=True)
    checker.add_argument('--version', required=True)
    args = parser.parse_args()
    if args.command == 'version':
        print(version(ROOT))
    elif args.command == 'plan':
        release_version = version(ROOT)
        notes(ROOT, release_version)
        plan = make_plan(release_version, os.environ.get('GITHUB_EVENT_NAME', ''),
                         os.environ.get('GITHUB_REF', ''), os.environ.get('GITHUB_RUN_ID', ''),
                         os.environ.get('GITHUB_RUN_ATTEMPT', ''), os.environ.get('RELEASE_MODE', ''))
        output = ''.join(f'{key}={str(value).lower() if isinstance(value, bool) else value}\n'
                         for key, value in plan.items())
        print(output, end='')
        if path := os.environ.get('GITHUB_OUTPUT'):
            with open(path, 'a') as stream:
                stream.write(output)
    elif args.command == 'build':
        build(ROOT, args.output.resolve())
    else:
        verify(args.assets, args.version)
        print('Release assets verified')


if __name__ == '__main__':
    main()
