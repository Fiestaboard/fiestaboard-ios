"""Run the UI test's real observation policy with controlled AX readings/time."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
BUILD = Path.home() / 'Library/Developer/FiestaBoard/ios/cx-iosnext5-save-controls'


class SaveObservationTests(unittest.TestCase):
    def test_consistent_save_state_and_fail_closed_controls(self):
        BUILD.mkdir(parents=True, exist_ok=True)
        main = BUILD / 'main.swift'
        main.write_text('''
import Foundation
typealias Sample = SaveObservation.Sample
let explanation = SaveObservation.Reason(label: "Can't save: offline", minY: 100, documentMinY: 300)
let enabled = Sample(enabledBefore: true, enabledAfter: true, reason: nil)
let disabled = Sample(enabledBefore: false, enabledAfter: false, reason: explanation)
let unexplained = Sample(enabledBefore: false, enabledAfter: false, reason: nil)
func require(_ value: Bool, _ message: String) { precondition(value, message) }
@MainActor func observe(_ samples: [Sample], expected: SaveObservation.State?, reads: Int? = nil) {
    var time = 0.0, count = 0
    do {
        let state = try SaveObservation.requireConsistent(timeout: 3, observe: {
            let sample = samples[min(count, samples.count - 1)]; count += 1; return sample
        }, now: { time }, pause: { time += $0 })
        require(state == expected, "unexpected acceptance/state: \\(state)")
        if let reads { require(count == reads, "accepted before consecutive consistent readings: \\(count)") }
    } catch SaveObservation.Failure.noConsistentState {
        require(expected == nil, "valid settled state was rejected")
        require(time == 3, "failure must exhaust only the existing three-second budget")
        require(count <= 31, "polling must remain bounded")
    } catch { preconditionFailure("unexpected error: \\(error)") }
}
observe([enabled], expected: .enabled, reads: 2)
observe([disabled], expected: .disabled(explanation), reads: 2)
// Original failure: a disabled reading must not lock a stale reason-only branch.
observe([unexplained, enabled, enabled], expected: .enabled, reads: 3)
observe([enabled, unexplained, enabled, enabled], expected: .enabled, reads: 4)
observe([enabled, disabled, disabled], expected: .disabled(explanation), reads: 3)
observe([unexplained], expected: nil)
observe([Sample(enabledBefore: nil, enabledAfter: nil, reason: nil)], expected: nil)
observe([Sample(enabledBefore: false, enabledAfter: true, reason: explanation)], expected: nil)
observe([Sample(enabledBefore: true, enabledAfter: false, reason: nil)], expected: nil)
observe([Sample(enabledBefore: true, enabledAfter: true, reason: explanation)], expected: nil)
observe([Sample(enabledBefore: false, enabledAfter: false,
    reason: .init(label: "Offline", minY: 100, documentMinY: 300))], expected: nil)
observe([Sample(enabledBefore: false, enabledAfter: false,
    reason: .init(label: "Can't save: offline", minY: 400, documentMinY: 300))], expected: nil)
// Never settle: valid observations alternating at every read must fail closed.
observe(Array(repeating: [enabled, disabled], count: 16).flatMap { $0 }, expected: nil)
// A query that returns after the deadline cannot earn acceptance.
var time = 0.0, count = 0
do {
    _ = try SaveObservation.requireConsistent(timeout: 3, observe: {
        count += 1; if count == 2 { time = 3.1 }; return enabled
    }, now: { time }, pause: { time += $0 })
    preconditionFailure("late observation accepted")
} catch SaveObservation.Failure.noConsistentState {
    require(count == 2, "late query must stop without more work")
}
print("all 14 Save observation controls passed")
''')
        binary = BUILD / 'controls'
        compiled = subprocess.run(
            ['swiftc', '-swift-version', '6', '-module-cache-path', str(BUILD / 'modules'),
             str(ROOT / 'Tests/UITests/SaveObservation.swift'), str(main), '-o', str(binary)],
            text=True, capture_output=True)
        self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
        result = subprocess.run([str(binary)], text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('all 14 Save observation controls passed', result.stdout)
