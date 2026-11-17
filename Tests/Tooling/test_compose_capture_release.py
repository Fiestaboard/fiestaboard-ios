"""Plant DEBUG-only capture/ticket symbols in an archive to prove Release guard."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class ComposeCaptureReleaseTests(unittest.TestCase):
    def run_guard(self, text):
        with tempfile.TemporaryDirectory(prefix='compose-release-guard-') as directory:
            archive=Path(directory)/'Control.xcarchive'
            binary=archive/'Products/Applications/Control.app/Control'
            binary.parent.mkdir(parents=True)
            binary.write_text(text+'\n');binary.chmod(0o700)
            return subprocess.run(['bash',str(ROOT/'scripts/check-release-probes.sh'),str(archive)],capture_output=True,text=True)

    def test_each_new_capture_and_ticket_symbol_is_rejected(self):
        for symbol in ['ComposeCaptureProbeController','ComposeCaptureProbeLifecycle','composeCaptureProbeStart',
                       'fiestaboard.captureComposeCapability','ComposePresentationTicket',
                       'ComposePresentationObservation','enableCapturedPresentationDiagnostics',
                       'capturedPresentationTicket','firstObservedPresentation','recordCapturedPresentation',
                       'presentationSessionID','presentationNowTicks','presentationSecondsPerTick',
                       'presentationInputTicks','presentationReadyTicks','clearCapturedPresentation',
                       'postDebounceUpperBoundSeconds','inputToObservedUpperBoundSeconds',
                       'adoptionToObservedUpperBoundSeconds','postDebouncePreviewSeconds']:
            with self.subTest(symbol=symbol):
                result=self.run_guard(symbol)
                self.assertEqual(result.returncode,1,result.stdout+result.stderr)
                self.assertIn(symbol,result.stderr)

    def test_ordinary_release_content_remains_accepted(self):
        self.assertEqual(self.run_guard('Show now\nYour message stays as a draft').returncode,0)

if __name__=='__main__':unittest.main()
