from __future__ import annotations

import plistlib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "ios" / "Kalories" / "Resources" / "PrivacyInfo.xcprivacy"
PROJECT = ROOT / "ios" / "Kalories.xcodeproj" / "project.pbxproj"


class IOSPrivacyManifestTests(unittest.TestCase):
    def test_app_manifest_declares_only_observed_app_owned_behavior(self) -> None:
        self.assertTrue(MANIFEST.is_file())
        with MANIFEST.open("rb") as source:
            manifest = plistlib.load(source)

        self.assertEqual(manifest["NSPrivacyTracking"], False)
        self.assertEqual(manifest["NSPrivacyTrackingDomains"], [])
        self.assertEqual(
            manifest["NSPrivacyAccessedAPITypes"],
            [
                {
                    "NSPrivacyAccessedAPIType": (
                        "NSPrivacyAccessedAPICategoryUserDefaults"
                    ),
                    "NSPrivacyAccessedAPITypeReasons": ["CA92.1"],
                }
            ],
        )
        self.assertEqual(
            manifest["NSPrivacyCollectedDataTypes"],
            [
                {
                    "NSPrivacyCollectedDataType": (
                        "NSPrivacyCollectedDataTypePhotosorVideos"
                    ),
                    "NSPrivacyCollectedDataTypeLinked": False,
                    "NSPrivacyCollectedDataTypeTracking": False,
                    "NSPrivacyCollectedDataTypePurposes": [
                        "NSPrivacyCollectedDataTypePurposeAppFunctionality"
                    ],
                }
            ],
        )

    def test_generated_project_packages_the_app_manifest(self) -> None:
        self.assertIn("PrivacyInfo.xcprivacy", PROJECT.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
