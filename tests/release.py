# SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
# SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

"""Release modes fail closed; only complete, unmodified assets can publish."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('release', ROOT / 'tools/release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def test_tag_matches_version(self):
        plan = release.make_plan('0.0.1', 'push', 'refs/tags/v0.0.1', '12', '1', '')
        self.assertTrue(plan['publish'])
        self.assertFalse(plan['prerelease'])
        self.assertEqual(plan['tag'], 'v0.0.1')
        for ref in ['refs/tags/v0.0.2', 'refs/heads/main']:
            with self.assertRaises(ValueError):
                release.make_plan('0.0.1', 'push', ref, '12', '1', '')

    def test_manual_modes(self):
        for mode in ['build', 'test']:
            plan = release.make_plan('0.0.1', 'workflow_dispatch', 'refs/heads/main', '12', '2', mode)
            self.assertEqual(plan['tag'], 'test-v0.0.1-12-2')
            self.assertTrue(plan['prerelease'])
            self.assertEqual(plan['publish'], mode == 'test')

    def test_untrusted_or_unknown_inputs_are_rejected(self):
        for event, run, mode in [('pull_request', '12', 'test'),
                                 ('workflow_dispatch', '12\npublish=true', 'test'),
                                 ('workflow_dispatch', '12', 'release')]:
            with self.assertRaises(ValueError):
                release.make_plan('0.0.1', event, 'refs/heads/main', run, '1', mode)
        with self.assertRaises(ValueError):
            release.make_plan('../escape', 'push', 'refs/tags/v../escape', '12', '1', '')

    def fixture(self, root):
        (root / 'evergreen-compose.asd').write_text(':version "0.0.1"')
        (root / 'CHANGELOG.md').write_text('# Changelog\n\n## 0.0.1 - 2026-10-04\n\nFirst release.\n\n## 0.0.0\nOld.\n')
        (root / 'CITATION.cff').write_text('version: 0.0.1\n')
        for name in ['runtime/compose-v1/bundle.sexp', 'runtime/compose-v1/classes.dex',
                     'LICENSE', 'LICENSE.classpath-exception', 'evergreen-compose-build.asd',
                     'assets/evergreen-compose.lisp']:
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('fixture')

    def test_complete_artifacts_and_notes(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            self.fixture(root)
            assets = root / 'dist/release'
            release.build(root, assets)
            release.verify(assets, '0.0.1')
            self.assertIn('First release.', (assets / 'RELEASE-NOTES.md').read_text())
            self.assertNotIn('Old.', (assets / 'RELEASE-NOTES.md').read_text())
            for name in release.asset_names('0.0.1'):
                data = (assets / name).read_bytes()
                (assets / name).unlink()
                with self.assertRaises(ValueError):
                    release.verify(assets, '0.0.1')
                (assets / name).write_bytes(data)
            (assets / 'RELEASE-NOTES.md').write_text('tampered')
            with self.assertRaises(ValueError):
                release.verify(assets, '0.0.1')
            release.build(root, assets)
            (assets / 'private-key').write_text('must not upload')
            with self.assertRaises(ValueError):
                release.verify(assets, '0.0.1')
            with self.assertRaises(ValueError):
                release.build(root, assets)

    def test_metadata_drift_is_rejected(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            self.fixture(root)
            (root / 'CITATION.cff').write_text('version: 0.0.2\n')
            with self.assertRaises(ValueError):
                release.version(root)
            (root / 'CITATION.cff').write_text('version: 0.0.1\n')
            (root / 'CHANGELOG.md').write_text('# Changelog\n')
            with self.assertRaises(ValueError):
                release.build(root, root / 'dist/release')


if __name__ == '__main__':
    unittest.main()
