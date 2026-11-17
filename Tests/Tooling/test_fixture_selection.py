"""Exercise selection ownership and finite taps independently of simulator timing."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
BUILD = Path.home() / 'Library/Developer/FiestaBoard/ios/cx-iosnext5-selection-controls'


class FixtureSelectionTests(unittest.TestCase):
    def test_selected_state_and_finite_action_controls(self):
        BUILD.mkdir(parents=True, exist_ok=True)
        main = BUILD / 'main.swift'
        main.write_text('''
var selected = false, taps = 0, waits = 0, actionableCalls = 0
func require(_ value: Bool, _ message: String) { precondition(value, message) }
func run(actionable: () -> Bool = { true }, wait: () -> Bool) throws {
    try FixtureSelection.requireSelected(isSelected: { selected },
        waitUntilActionable: { actionableCalls += 1; return actionable() },
        tap: { taps += 1 }, waitUntilSelected: { waits += 1; return wait() })
}
selected = true
try run { preconditionFailure("already selected must do no work") }
require(taps == 0 && actionableCalls == 0, "already selected: no duplicate action")
selected = false
try run { selected = true; return true }
require(taps == 1 && waits == 1, "successful first action must not repeat")
selected = false; taps = 0; waits = 0
try run { selected = taps == 2; return selected }
require(taps == 2 && waits == 2, "one missed selection permits only one more attempt")
selected = false; taps = 0; waits = 0
do { try run { false }; preconditionFailure("never-selected must fail") }
catch FixtureSelection.Failure.notSelected { require(taps == 2 && waits == 2, "finite two-action bound") }
selected = false; taps = 0; waits = 0
do { try run(actionable: { false }) { true }; preconditionFailure("unavailable must fail") }
catch FixtureSelection.Failure.notActionable { require(taps == 0 && waits == 0, "no tap of unavailable control") }
selected = false; taps = 0; waits = 0
try run(actionable: { selected = true; return true }) { preconditionFailure("late prior selection must not be tapped again") }
require(taps == 0 && waits == 0, "recheck selection after readiness wait")
selected = false; taps = 0; waits = 0
do { try run { true }; preconditionFailure("a completed wait alone is not selection") }
catch FixtureSelection.Failure.notSelected { require(taps == 2, "actual selected state is required") }
print("all selection controls passed")
''')
        binary = BUILD / 'controls'
        compiled = subprocess.run(
            ['swiftc', '-swift-version', '6', '-module-cache-path', str(BUILD / 'modules'),
             str(ROOT / 'Tests/UITests/FixtureSelection.swift'), str(main), '-o', str(binary)],
            text=True, capture_output=True)
        self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
        result = subprocess.run([str(binary)], text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('all selection controls passed', result.stdout)
