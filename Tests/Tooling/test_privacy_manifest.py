"""Release declarations for privacy-sensitive APIs used by the app."""
import plistlib
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class PrivacyManifestTests(unittest.TestCase):
    def test_app_preferences_have_a_required_reason(self):
        # EditorRoot's @AppStorage and ConnectionModel's UserDefaults persist
        # app-only preferences in Release, not just in isolated UI tests.
        # Apple's CA92.1 covers defaults accessible only to the app itself:
        # https://developer.apple.com/documentation/bundleresources/
        # app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype
        with (ROOT / "App/PrivacyInfo.xcprivacy").open("rb") as manifest_file:
            manifest = plistlib.load(manifest_file)
        entries = [entry for entry in manifest["NSPrivacyAccessedAPITypes"]
                   if entry["NSPrivacyAccessedAPIType"] ==
                   "NSPrivacyAccessedAPICategoryUserDefaults"]
        self.assertEqual(len(entries), 1, "Declare the app's release UserDefaults access")
        self.assertIn("CA92.1", entries[0]["NSPrivacyAccessedAPITypeReasons"])


if __name__ == "__main__":
    unittest.main()
