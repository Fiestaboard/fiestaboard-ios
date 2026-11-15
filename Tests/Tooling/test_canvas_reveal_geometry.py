"""Run the UI helper's actual Swift geometry against clipped and narrow-fit controls."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CanvasRevealGeometryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='cx-canvas-geometry-')
        cls.addClassCleanup(cls.temporary.cleanup)
        directory = Path(cls.temporary.name)
        harness = directory / 'main.swift'
        harness.write_text('''import Foundation
import CoreGraphics
let values = CommandLine.arguments.dropFirst().map { CGFloat(Double($0)!) }
var target = CGRect(x: 0, y: values[0], width: 20, height: values[1])
let bounds = values.count > 4
    ? CanvasRevealGeometry.panelBounds(
        viewport: CGRect(x: 0, y: values[2], width: 1, height: values[3] - values[2]),
        coveringTop: values[4])
    : (top: values[2], bottom: values[3])
let top = bounds.top, bottom = bounds.bottom
let initial = CanvasRevealGeometry.isExposed(target, top: top, bottom: bottom)
var steps: [Double] = []
while !CanvasRevealGeometry.isExposed(target, top: top, bottom: bottom) && steps.count < 12 {
    let delta = CanvasRevealGeometry.scrollDistance(target, top: top, bottom: bottom)
    if delta == 0 { break }
    steps.append(Double(delta))
    target = target.offsetBy(dx: 0, dy: delta)
}
let result: [String: Any] = [
    "initial": initial,
    "exposed": CanvasRevealGeometry.isExposed(target, top: top, bottom: bottom),
    "steps": steps,
    "minY": Double(target.minY), "maxY": Double(target.maxY)
]
print(String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8)!)
''')
        cls.binary = directory / 'geometry'
        compiled = subprocess.run([
            'xcrun', 'swiftc', '-module-cache-path', str(directory / 'modules'),
            str(ROOT / 'Tests/UITests/CanvasRevealGeometry.swift'), str(harness),
            '-o', str(cls.binary),
        ], capture_output=True, text=True, timeout=60)
        if compiled.returncode:
            raise RuntimeError(compiled.stderr)

    def reveal(self, y, height, top, bottom, covering_top=None):
        values = (y, height, top, bottom)
        if covering_top is not None:
            values += (covering_top,)
        result = subprocess.run(
            [str(self.binary), *map(str, values)],
            check=True, capture_output=True, text=True, timeout=5)
        return json.loads(result.stdout)

    def assert_reached(self, result, maximum_steps=12):
        self.assertTrue(result['exposed'], result)
        self.assertLessEqual(len(result['steps']), maximum_steps, result)

    def test_phone_area_picker_does_not_oscillate_across_its_fit_band(self):
        # Approximate bounds from the failed video; the 326pt target has 26pt slack.
        result = self.reveal(420, 326, 472, 824)
        self.assert_reached(result, 2)
        self.assertGreater(result['steps'][0], 0)
        self.assertLess(result['steps'][0], 160)

    def test_phone_shapes_surface_reaches_the_band_from_below(self):
        result = self.reveal(560, 312, 472, 824)
        self.assert_reached(result, 2)
        self.assertLess(result['steps'][0], 0)

    def test_narrow_fit_does_not_require_a_magic_constant_step(self):
        result = self.reveal(470, 348, 472, 824)
        self.assert_reached(result, 2)
        self.assertGreaterEqual(result['minY'], 472)
        self.assertLessEqual(result['maxY'], 824)

    def test_exact_ipad_clipped_add_shape_becomes_fully_exposed(self):
        # Actual AX frame and rail bounds from the original clipped-control failure.
        result = self.reveal(1141.5, 20.5, 553.5, 1152)
        self.assertFalse(result['initial'])
        self.assert_reached(result, 2)
        self.assertLess(result['steps'][0], 0)

    def test_native_header_at_scroll_limit_is_already_exposed(self):
        # Exact failed-session AX: Undo is fully visible at the clamped content top.
        result = self.reveal(467.3, 18.3, 463.3, 832, covering_top=453.3)
        self.assertTrue(result['initial'])
        self.assertEqual(result['steps'], [])

    def test_panel_bounds_still_reject_clipped_control_and_covering_toggle(self):
        for values in [(1141.5, 20.5, 553.5, 1152, 544.5), (420, 20, 400, 800, 450)]:
            with self.subTest(values=values):
                result = self.reveal(*values)
                self.assertFalse(result['initial'])
                self.assert_reached(result)
                self.assertGreaterEqual(result['minY'], max(values[2], values[4]))
                self.assertLessEqual(result['maxY'], values[3])

    def test_already_exposed_target_does_not_scroll(self):
        result = self.reveal(600, 20, 472, 824)
        self.assertTrue(result['initial'])
        self.assertEqual(result['steps'], [])

    def test_oversized_surface_exposes_its_interaction_center(self):
        result = self.reveal(100, 600, 472, 824)
        self.assert_reached(result, 2)
        center = (result['minY'] + result['maxY']) / 2
        self.assertGreaterEqual(center, 472)
        self.assertLessEqual(center, 824)

    def test_steps_stay_bounded_by_the_rail_even_in_a_short_viewport(self):
        for values in [(-1000, 100, 472, 824), (200, 20, 0, 100)]:
            with self.subTest(values=values):
                result = self.reveal(*values)
                self.assert_reached(result)
                cap = min(160, (values[3] - values[2]) / 2)
                self.assertTrue(all(0 < abs(step) <= cap for step in result['steps']))

    def test_equal_edges_are_exposed_and_invalid_bounds_do_not_scroll(self):
        equal = self.reveal(472, 352, 472, 824)
        self.assertTrue(equal['initial'])
        for values in [(500, 20, 800, 800), (500, 20, 900, 800), (500, 0, 472, 824)]:
            with self.subTest(values=values):
                invalid = self.reveal(*values)
                self.assertFalse(invalid['exposed'])
                self.assertEqual(invalid['steps'], [])
