"""Pinned renderer integrity and the artwork license boundary."""
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RendererVendorTests(unittest.TestCase):
    def test_vendored_files_match_manifest(self):
        manifest = json.loads((ROOT / 'VENDORED.json').read_text())
        self.assertEqual(manifest['repo'], 'Fiestaboard/fiestaboard-tvos')
        self.assertTrue(manifest['commit'].startswith('f1fc67d'))
        self.assertGreaterEqual(len(manifest['files']), 20)
        for entry in manifest['files']:
            with self.subTest(file=entry['destination']):
                self.assertEqual(hashlib.sha256((ROOT / entry['destination']).read_bytes()).hexdigest(), entry['sha256'])
                self.assertEqual(len(entry['sourceSHA256']), 64)

    def test_root_spec_is_the_exact_bundled_contract(self):
        self.assertEqual((ROOT / 'Spec/board-spec.json').read_bytes(),
                         (ROOT / 'Packages/FiestaBoardRender/Sources/FiestaBoardRender/RenderAssets/board-spec.json').read_bytes())

    def test_taco_art_is_never_mit(self):
        notice = (ROOT / 'ThirdPartyNotices/FiestaBoardTV-MIT.txt').read_text()
        self.assertIn('Taco artwork © FiestaBoard. All rights reserved. Used in this app with permission.', notice)
        self.assertIn('The Taco artwork is not licensed under the MIT License above.', notice)
        self.assertNotIn('Taco artwork is MIT', notice)
