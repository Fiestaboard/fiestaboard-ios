"""Required UI journeys may skip only when inapplicable to the device family."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SKIP = re.compile(r'\bXCTSkip(?:Unless|If)?\s*\(')
PLATFORM_SKIP = re.compile(
    r'XCTSkipUnless\(\s*UIDevice\.current\.userInterfaceIdiom\s*==\s*\.(?:pad|phone)\s*,')


def unexpected_skips(source, filename):
    return [source[match.start():].splitlines()[0]
            for match in SKIP.finditer(source)
            if filename != 'IntegrationUITests.swift'
            or not PLATFORM_SKIP.match(source[match.start():])]


class RequiredUICoverageTests(unittest.TestCase):
    def test_required_journeys_cannot_skip_for_fixture_or_runtime_readiness(self):
        for path in (ROOT / 'Tests/UITests').glob('*.swift'):
            with self.subTest(path=path.name):
                self.assertEqual(unexpected_skips(path.read_text(), path.name), [])

    def test_guard_rejects_fixture_and_unconditional_skip_controls(self):
        for source in ['try XCTSkipUnless(ready, "fixture unavailable")',
                       'try XCTSkipIf(!ready, "fixture unavailable")',
                       'throw XCTSkip("fixture unavailable")']:
            with self.subTest(source=source):
                self.assertTrue(unexpected_skips(source, 'IntegrationUITests.swift'))

    def test_only_the_three_existing_device_family_skips_remain(self):
        source = (ROOT / 'Tests/UITests/IntegrationUITests.swift').read_text()
        self.assertEqual(sum(bool(PLATFORM_SKIP.match(source[m.start():]))
                             for m in SKIP.finditer(source)), 3)
