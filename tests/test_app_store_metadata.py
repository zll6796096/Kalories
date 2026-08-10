from __future__ import annotations

import json
import unittest
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[1]
METADATA_PATH = ROOT / "docs" / "release" / "app-store" / "ja-JP.json"


class AppStoreMetadataTests(unittest.TestCase):
    def setUp(self) -> None:
        self.document = json.loads(METADATA_PATH.read_text(encoding="utf-8"))

    def test_identity_distribution_and_release_are_exact(self) -> None:
        self.assertEqual(self.document["apple_app_id"], "6799957568")
        self.assertEqual(self.document["bundle_id"], "com.ryuaistudio.kalories")
        self.assertEqual(self.document["version"], "1.0.0")
        self.assertEqual(self.document["build"], "1")
        self.assertEqual(self.document["territories"], ["JPN"])
        self.assertEqual(self.document["price"], "FREE")
        self.assertEqual(self.document["release_type"], "AFTER_APPROVAL")
        self.assertFalse(self.document["in_app_purchases"])
        self.assertFalse(self.document["subscriptions"])
        self.assertFalse(self.document["kids_category"])
        self.assertEqual(self.document["copyright"], "2026 RYU AI Studio")

    def test_localized_fields_fit_limits_and_match_product(self) -> None:
        self.assertEqual(self.document["locale"], "ja-JP")
        self.assertEqual(self.document["name"], "カロスキャン")
        adult_access_prefix = (
            "カロスキャンは18歳以上の方のみ利用できます。"
            "初回起動時に「18歳以上です」を選択すると、"
        )
        self.assertTrue(self.document["promotional_text"].startswith(adult_access_prefix))
        self.assertTrue(self.document["description"].startswith(adult_access_prefix))
        self.assertTrue(self.document["review_notes"].startswith(adult_access_prefix))
        self.assertLessEqual(len(self.document["name"]), 30)
        self.assertLessEqual(len(self.document["subtitle"]), 30)
        self.assertLessEqual(len(self.document["promotional_text"]), 170)
        self.assertLessEqual(len(self.document["keywords"]), 100)
        self.assertNotIn(" ", self.document["keywords"])
        keywords = self.document["keywords"].split(",")
        self.assertEqual(len(keywords), len(set(keywords)))
        for forbidden_claim in ("正確に測定", "診断します", "必ず改善"):
            self.assertNotIn(forbidden_claim, self.document["description"])

    def test_urls_contact_and_privacy_answers_are_exact(self) -> None:
        for key in ("support_url", "privacy_policy_url"):
            parsed = urlparse(self.document[key])
            self.assertEqual(parsed.scheme, "https")
            self.assertEqual(parsed.netloc, "kalories-sxielk4wua-an.a.run.app")
        self.assertEqual(self.document["contact_email"], "zll6796096@gmail.com")
        self.assertFalse(self.document["privacy"]["tracking"])
        self.assertEqual(
            self.document["privacy"]["collected_data"],
            [
                {
                    "type": "PHOTOS_OR_VIDEOS",
                    "purpose": "APP_FUNCTIONALITY",
                    "linked_to_user": False,
                    "tracking": False,
                },
                {
                    "type": "OTHER_DIAGNOSTIC_DATA",
                    "purpose": "ANALYTICS",
                    "linked_to_user": False,
                    "tracking": False,
                },
            ],
        )


if __name__ == "__main__":
    unittest.main()
