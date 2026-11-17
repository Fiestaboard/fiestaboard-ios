"""Exercise CI selection through the real runner, without booting simulators."""
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SHARDS = {
    'ui-a': ['BoardVisualsUITests', 'LaunchUITests', 'OnboardingUITests', 'ParityFoundationUITests', 'BoardViewportUITests', 'ShellUITests'],
    'ui-b': [f'EditorUITests/{method}' for method in [
        'testAlignAndWrapFollowCaretRow', 'testBoardStaysBigAndAllRowsShow',
        'testCompactChipCalloutShowsTheFullName', 'testDisabledSaveSaysWhy',
        'testGeometryChangeAndShrinkConfirmation', 'testHomeControlActionsAndPlainPageScreen',
        'testInsertChipsFromTheKeyboardAccessory']],
    'ui-f': [f'EditorUITests/{method}' for method in [
        'testNewPageIsBoardShaped', 'testNotePageOpensOnAFittingDisplay',
        'testPlainModeShowsPrefixes', 'testReturnMovesToTheNextEmptyRow',
        'testShortMetadataNoteOpensInTheDocumentEditor', 'testTypingReachesTheBoard',
        'testTypingReachesTheBoardThroughFixtureRender']],
    'ui-c': ['BarEvidenceUITests', 'CanvasUITests', 'IntegrationUITests', 'SaveUITests'],
    'ui-d': ['FormulaUITests'],
    'ui-e': [f'PolishUITests/{method}' for method in [
        'testCharsetIssuesAreGroupedWithShowAll', 'testDocumentFillsTheHeightOnIPad',
        'testOverrideBadgeCancel', 'testRecordKillAndReopen',
        'testShowWhenAndPriorityAreAdvanced', 'testVoiceOverLabelDump']],
    'ui-g': ['PolishUITests/testRecordCaretOverChips'],
    'ui-h': ['PolishUITests/testRecordTypingUndoRedo'],
}
MODELS = {'iPhone 17': 'phone-id', 'iPad Air 11-inch (M4)': 'pad-id'}


class CIShardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='cx-ci-shards-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'scripts').mkdir()
        (self.root / 'Tests/UITests').mkdir(parents=True)
        (self.root / 'bin').mkdir()
        for name in ['test.sh', 'select-ios-simulator.py', 'ios-ui-shards.json']:
            source = ROOT / 'scripts' / name
            if source.exists():
                shutil.copy2(source, self.root / 'scripts' / name)
        runner = self.root / 'scripts/test.sh'
        original = 'ios_build_root="$HOME/Library/Developer/FiestaBoard/ios"'
        runner_source = runner.read_text()
        self.assertEqual(runner_source.count(original), 1)
        runner.write_text(runner_source.replace(
            original, 'ios_build_root=' + shlex.quote(str(self.root / 'build'))))
        stub = '''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
with open(os.environ['CX_COMMAND_LOG'], 'a') as log:
    log.write(json.dumps([name] + sys.argv[1:]) + '\\n')
if name == 'xcrun' and sys.argv[1:3] == ['simctl', 'list']:
    cleanup = any(entry[1:3] == ['simctl', 'shutdown']
                  for entry in map(json.loads, pathlib.Path(os.environ['CX_COMMAND_LOG']).read_text().splitlines()))
    if cleanup:
        status_exit = int(os.environ.get('CX_STATUS_LIST_EXIT', '0'))
        if status_exit: sys.exit(status_exit)
    state = os.environ.get('CX_FINAL_STATE', 'Shutdown')
    print(json.dumps({'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-27-2': [
        {'name': 'iPhone 17', 'udid': 'phone-id', 'isAvailable': True, 'state': state},
        {'name': 'iPad Air 11-inch (M4)', 'udid': 'pad-id', 'isAvailable': True, 'state': 'Shutdown'}
    ]}}))
if name == 'xcrun' and sys.argv[1:3] == ['simctl', 'shutdown']:
    sys.exit(int(os.environ.get('CX_SHUTDOWN_EXIT', '0')))
if name == 'xcodebuild':
    sys.exit(int(os.environ.get('CX_XCODE_EXIT', '0')))
'''
        for name in ['xcrun', 'xcodebuild', 'curl']:
            path = self.root / 'bin' / name
            path.write_text(stub)
            path.chmod(0o755)
        self.log = self.root / 'commands.jsonl'

    def run_runner(self, **overrides):
        env = os.environ.copy()
        for key in ['IOS_TEST_SHARD', 'IOS_TEST_MODEL']:
            env.pop(key, None)
        env.update(IOS_SLICE='shard-test',
                   CX_COMMAND_LOG=str(self.log),
                   PATH=str(self.root / 'bin') + os.pathsep + env['PATH'])
        env.update(overrides)
        result = subprocess.run(['bash', str(self.root / 'scripts/test.sh'), 'simulators'],
                                env=env, capture_output=True, text=True, timeout=15)
        self.commands = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return result

    def builds(self):
        return [entry[1:] for entry in self.commands if entry[0] == 'xcodebuild']

    def assert_serial(self, args):
        self.assertEqual(args[args.index('-parallel-testing-enabled') + 1], 'NO')
        self.assertEqual(args[args.index('-maximum-concurrent-test-simulator-destinations') + 1], '1')

    def test_each_ui_shard_selects_exact_classes_and_one_model(self):
        for shard, classes in SHARDS.items():
            with self.subTest(shard=shard):
                self.log.unlink(missing_ok=True)
                result = self.run_runner(IOS_TEST_SHARD=shard, IOS_TEST_MODEL='iPhone 17')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(len(self.builds()), 1)
                args = self.builds()[0]
                self.assertEqual({a for a in args if a.startswith('-only-testing:')},
                                 {f'-only-testing:FiestaBoardUITests/{name}' for name in classes})
                self.assertIn('platform=iOS Simulator,id=phone-id', args)
                self.assertIn('test', args)
                self.assert_serial(args)

    def test_units_excludes_ui_and_respects_ipad_model(self):
        result = self.run_runner(IOS_TEST_SHARD='units', IOS_TEST_MODEL='iPad Air 11-inch (M4)')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.builds()), 1)
        args = self.builds()[0]
        self.assertIn('-skip-testing:FiestaBoardUITests', args)
        self.assertIn('platform=iOS Simulator,id=pad-id', args)
        self.assert_serial(args)

    def test_default_retains_units_then_all_ui_on_both_devices(self):
        result = self.run_runner()
        self.assertEqual(result.returncode, 0, result.stderr)
        builds = self.builds()
        self.assertEqual(len(builds), 4)
        for offset, udid in [(0, 'phone-id'), (2, 'pad-id')]:
            self.assertIn('-skip-testing:FiestaBoardUITests', builds[offset])
            self.assertIn('-only-testing:FiestaBoardUITests', builds[offset + 1])
            self.assertIn('test-without-building', builds[offset + 1])
            for args in builds[offset:offset + 2]:
                self.assertIn(f'platform=iOS Simulator,id={udid}', args)
                self.assert_serial(args)

    def test_xcode_failure_propagates_and_other_device_still_runs(self):
        result = self.run_runner(IOS_TEST_SHARD='ui-a', CX_XCODE_EXIT='65')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.builds()), 2)
        destinations = {a for args in self.builds() for a in args if a.startswith('platform=')}
        self.assertEqual(destinations, {f'platform=iOS Simulator,id={udid}' for udid in MODELS.values()})

    def test_invalid_selection_fails_before_fixture_or_simulator_commands(self):
        for overrides in [{'IOS_TEST_SHARD': 'ui-unknown'}, {'IOS_TEST_MODEL': 'iPhone 16'}]:
            with self.subTest(overrides=overrides):
                self.log.unlink(missing_ok=True)
                result = self.run_runner(**overrides)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.commands, [])

    def test_already_shutdown_cleanup_preserves_success_and_continues(self):
        result = self.run_runner(IOS_TEST_SHARD='ui-a', CX_SHUTDOWN_EXIT='149')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.builds()), 2)

    def test_shutdown_failure_requires_the_selected_device_to_be_shutdown(self):
        for overrides in [{'CX_FINAL_STATE': 'Booted'}, {'CX_STATUS_LIST_EXIT': '7'}]:
            with self.subTest(overrides=overrides):
                self.log.unlink(missing_ok=True)
                result = self.run_runner(IOS_TEST_SHARD='ui-a', IOS_TEST_MODEL='iPhone 17',
                                         CX_SHUTDOWN_EXIT='149', **overrides)
                self.assertEqual(result.returncode, 149, result.stderr)

    def test_already_shutdown_cleanup_cannot_mask_test_failure(self):
        result = self.run_runner(IOS_TEST_SHARD='ui-a', IOS_TEST_MODEL='iPhone 17',
                                 CX_SHUTDOWN_EXIT='149', CX_XCODE_EXIT='65')
        self.assertEqual(result.returncode, 1, result.stderr)

    def test_manifest_covers_every_ui_test_method_exactly_once(self):
        manifest = json.loads((ROOT / 'scripts/ios-ui-shards.json').read_text())
        self.assertEqual(manifest, SHARDS)
        methods = {}
        for path in (ROOT / 'Tests/UITests').glob('*.swift'):
            source = path.read_text()
            classes = re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', source)
            if classes:
                self.assertEqual(len(classes), 1)
                methods[classes[0]] = [f'{classes[0]}/{name}' for name in
                                      re.findall(r'\bfunc\s+(test\w+)\s*\(', source)]
        assigned = []
        for group in manifest.values():
            for selector in group:
                assigned.extend([selector] if '/' in selector else methods[selector])
        self.assertCountEqual(assigned, [name for group in methods.values() for name in group])
        self.assertEqual(len(assigned), len(set(assigned)))


if __name__ == '__main__':
    unittest.main()
