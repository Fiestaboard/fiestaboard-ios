from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class RetiredSurfaceTests(unittest.TestCase):
    def test_no_demo_launch_scheme_or_production_service(self):
        self.assertNotIn('--demo', (ROOT/'project.yml').read_text())
        self.assertNotIn('FiestaBoard Demo', (ROOT/'project.yml').read_text())
        self.assertFalse((ROOT/'Packages/FiestaBoardKit/Sources/FiestaBoardKit/DemoService.swift').exists())
        self.assertFalse((ROOT/'Packages/FiestaBoardKit/Sources/FiestaBoardKit/DemoFixtures').exists())
    def test_retired_types_and_copy_are_absent(self):
        source = '\n'.join(p.read_text() for p in (ROOT/'App').rglob('*.swift'))
        for text in ['LocalPageEditorView', 'LocalPageEditorLoader', 'LocalDraftRecoveryView', 'SetupView', 'Review action', 'Enable changes', 'Apply change setting', 'turned off', 'About this draft', 'Not available', 'Explore Demo', '"Simulate']:
            with self.subTest(text=text): self.assertFalse(text in source, f"Retired surface remains: {text}")
    def test_native_editor_stays(self):
        for file in ['EditorRoot.swift', 'FlexibleWorkspaceView.swift', 'TemplateWorkspaceView.swift']:
            self.assertTrue((ROOT/'App/Features/Editor'/file).exists())
