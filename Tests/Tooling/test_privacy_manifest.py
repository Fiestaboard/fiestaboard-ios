"""Release declarations for privacy-sensitive APIs used by the app."""
import plistlib
import json
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]
MANIFESTS = {
    "FiestaBoard": "App/PrivacyInfo.xcprivacy",
    "FiestaBoardAppState": "Packages/FiestaBoardAppState/Sources/FiestaBoardAppState/PrivacyInfo.xcprivacy",
    "FiestaBoardEditorState": "Packages/FiestaBoardEditorState/Sources/FiestaBoardEditorState/PrivacyInfo.xcprivacy",
}


class PrivacyManifestTests(unittest.TestCase):
    def test_release_preferences_have_a_required_reason_in_each_bundle(self):
        # EditorRoot's @AppStorage and ConnectionModel's UserDefaults persist
        # app-only preferences in Release, not just in isolated UI tests.
        # Apple's CA92.1 covers defaults accessible only to the app itself:
        # https://developer.apple.com/documentation/bundleresources/
        # app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype
        for target, path in MANIFESTS.items():
            with self.subTest(target=target):
                with (ROOT / path).open("rb") as manifest_file:
                    manifest = plistlib.load(manifest_file)
                entries = [entry for entry in manifest["NSPrivacyAccessedAPITypes"]
                           if entry["NSPrivacyAccessedAPIType"] ==
                           "NSPrivacyAccessedAPICategoryUserDefaults"]
                self.assertEqual(len(entries), 1, "Declare release UserDefaults access")
                self.assertIn("CA92.1", entries[0]["NSPrivacyAccessedAPITypeReasons"])

    def test_manifests_are_resources_of_the_correct_shipped_targets(self):
        # Parse actual generated target membership, not just filename presence:
        # an app manifest alone does not cover embedded dynamic frameworks.
        project = json.loads(subprocess.check_output([
            "plutil", "-convert", "json", "-o", "-",
            str(ROOT / "FiestaBoard.xcodeproj/project.pbxproj")], text=True))
        objects = project["objects"]
        paths = {}

        def visit(identifier, parent):
            obj = objects[identifier]
            path = parent / obj.get("path", "")
            paths[identifier] = path.as_posix()
            for child in obj.get("children", []):
                visit(child, path)

        visit(objects[project["rootObject"]]["mainGroup"], Path("."))
        targets = {obj["name"]: obj for obj in objects.values()
                   if obj.get("isa") == "PBXNativeTarget"}
        for target, expected in MANIFESTS.items():
            with self.subTest(target=target):
                resources = []
                for phase in targets[target]["buildPhases"]:
                    if objects[phase]["isa"] == "PBXResourcesBuildPhase":
                        for build_file in objects[phase]["files"]:
                            resources.append(paths[objects[build_file]["fileRef"]])
                self.assertEqual(resources.count(expected), 1)


if __name__ == "__main__":
    unittest.main()
