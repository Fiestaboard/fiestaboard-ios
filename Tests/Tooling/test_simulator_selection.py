import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
class SimulatorSelectionTests(unittest.TestCase):
    def select(self, devices, name='iPad Air 11-inch (M4)'):
        return subprocess.run(['python3', str(ROOT/'scripts/select-ios-simulator.py'), name], input=json.dumps({'devices': devices}), text=True, capture_output=True)
    def test_exact_runtime_model_and_available_device(self):
        device = {'name':'iPad Air 11-inch (M4)', 'udid':'correct', 'isAvailable':True}
        result = self.select({'com.apple.CoreSimulator.SimRuntime.iOS-27-1':[device | {'udid':'old'}], 'com.apple.CoreSimulator.SimRuntime.iOS-27-2':[device | {'isAvailable':False}, device | {'name':'iPad Air 13-inch (M4)'}, device]})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'correct')
    def test_missing_device_fails_instead_of_falling_back(self):
        self.assertNotEqual(self.select({}).returncode, 0)
