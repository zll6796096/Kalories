from __future__ import annotations

import json
import plistlib
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
METADATA_PATH = ROOT / "docs" / "release" / "app-store" / "ja-JP.json"
PROJECT_YML_PATH = ROOT / "ios" / "project.yml"
PROJECT_PBXPROJ_PATH = ROOT / "ios" / "Kalories.xcodeproj" / "project.pbxproj"
PACKAGE_RESOLVED_PATH = (
    ROOT
    / "ios"
    / "Kalories.xcodeproj"
    / "project.xcworkspace"
    / "xcshareddata"
    / "swiftpm"
    / "Package.resolved"
)
PRIVACY_MANIFEST_PATH = ROOT / "ios" / "Kalories" / "Resources" / "PrivacyInfo.xcprivacy"
ADULT_ACCESS_MODEL_PATH = (
    ROOT / "ios" / "Kalories" / "Features" / "AdultAccess" / "AdultAccessModel.swift"
)
SUPPORT_URL = "https://kalories-sxielk4wua-an.a.run.app/support/"
PRIVACY_POLICY_URL = "https://kalories-sxielk4wua-an.a.run.app/privacy/"


class AppStoreMetadataTests(unittest.TestCase):
    def setUp(self) -> None:
        self.document = json.loads(METADATA_PATH.read_text(encoding="utf-8"))

    def test_schema_is_exact(self) -> None:
        self.assertEqual(
            set(self.document),
            {
                "apple_app_id",
                "bundle_id",
                "version",
                "build",
                "locale",
                "name",
                "subtitle",
                "promotional_text",
                "description",
                "keywords",
                "support_url",
                "privacy_policy_url",
                "marketing_url",
                "contact_email",
                "copyright",
                "primary_category",
                "secondary_category",
                "territories",
                "price",
                "in_app_purchases",
                "subscriptions",
                "kids_category",
                "release_type",
                "review_notes",
                "adult_access",
                "age_rating",
                "health_disclaimer",
                "release_gates",
                "privacy",
                "privacy_evidence",
            },
        )
        self.assertEqual(
            set(self.document["privacy"]),
            {"tracking", "collected_data"},
        )
        for entry in self.document["privacy"]["collected_data"]:
            self.assertEqual(
                set(entry),
                {"type", "purpose", "linked_to_user", "tracking"},
            )

    def test_identity_distribution_and_release_are_exact(self) -> None:
        self.assertEqual(self.document["apple_app_id"], "6799957568")
        self.assertEqual(self.document["bundle_id"], "com.ryuaistudio.kalories")
        self.assertEqual(self.document["version"], "1.0")
        self.assertEqual(self.document["build"], "3")
        self.assertEqual(self.document["territories"], ["JPN"])
        self.assertEqual(self.document["price"], "FREE")
        self.assertEqual(self.document["release_type"], "AFTER_APPROVAL")
        self.assertFalse(self.document["in_app_purchases"])
        self.assertFalse(self.document["subscriptions"])
        self.assertFalse(self.document["kids_category"])
        self.assertEqual(self.document["copyright"], "2026 RYU AI Studio")
        self.assertEqual(self.document["primary_category"], "FOOD_AND_DRINK")
        self.assertIsNone(self.document["secondary_category"])
        self.assertIsNone(self.document["marketing_url"])

        project_yml = PROJECT_YML_PATH.read_text(encoding="utf-8")
        self.assertRegex(project_yml, r"(?m)^    CURRENT_PROJECT_VERSION: 3$")

        project_pbxproj = PROJECT_PBXPROJ_PATH.read_text(encoding="utf-8")
        self.assertEqual(project_pbxproj.count("CURRENT_PROJECT_VERSION = 3;"), 2)

    def test_adult_access_and_age_rating_are_explicit_and_pending_readback(self) -> None:
        self.assertEqual(
            self.document["adult_access"],
            {
                "minimum_age": 18,
                "confirmation_required": True,
                "storage_key": "kalories.adult-access.confirmed.v1",
                "granting_value": True,
                "confirmation_boolean_only": True,
                "birth_date_collected": False,
                "name_collected": False,
                "identity_document_collected": False,
                "confirmation_in_analysis_request": False,
                "confirmation_sent_to_backend_google_or_firebase": False,
                "backup_restore_follows_apple_and_device_settings": True,
            },
        )
        self.assertEqual(
            self.document["age_rating"],
            {
                "age_assurance": True,
                "health_or_wellness_topics": True,
                "higher_age_rating_override_target": "18+",
                "japan_ios_26_or_later_readback": None,
                "japan_earlier_os_readback": None,
            },
        )
        self.assertEqual(
            self.document["health_disclaimer"],
            {
                "medical_diagnosis": False,
                "medical_advice": False,
                "individual_treatment_or_nutrition_guidance": False,
            },
        )
        adult_access_source = ADULT_ACCESS_MODEL_PATH.read_text(encoding="utf-8")
        self.assertIn(
            'static let storageKey = "kalories.adult-access.confirmed.v1"',
            adult_access_source,
        )
        self.assertIn(
            "defaults.set(true, forKey: Self.storageKey)",
            adult_access_source,
        )

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
        self.assertLessEqual(len(self.document["description"]), 4_000)
        self.assertLessEqual(len(self.document["review_notes"].encode("utf-8")), 4_000)

        expected_keywords = "カロリー,栄養管理,食事分析,食事写真,料理写真,栄養分析,健康管理"
        self.assertEqual(self.document["keywords"], expected_keywords)
        self.assertLessEqual(len(self.document["keywords"].encode("utf-8")), 100)
        keywords = self.document["keywords"].split(",")
        self.assertEqual(len(keywords), len(set(keywords)))
        for keyword in keywords:
            self.assertGreater(len(keyword), 2)

        for field in ("description", "review_notes"):
            text = self.document[field]
            for required_statement in (
                "「18歳以上です」を選択した事実だけ",
                "生年月日、氏名、本人確認書類",
                "確認結果を分析リクエストに添付せず",
                "バックアップと復元はAppleおよび端末の設定に従います",
                "医療診断",
                "医療助言",
                "個別の治療・栄養指導",
            ):
                with self.subTest(field=field, required_statement=required_statement):
                    self.assertIn(required_statement, text)

        for required_label in ("カメラを開く", "写真から選ぶ", "推定精度"):
            self.assertIn(required_label, self.document["review_notes"])
        for obsolete_label in ("カメラで撮影", "写真から選択", "信頼度"):
            self.assertNotIn(obsolete_label, self.document["review_notes"])
        for forbidden_claim in ("正確に測定", "診断します", "必ず改善"):
            self.assertNotIn(forbidden_claim, self.document["description"])

    def test_urls_and_production_release_gates_are_exact(self) -> None:
        self.assertEqual(self.document["support_url"], SUPPORT_URL)
        self.assertEqual(self.document["privacy_policy_url"], PRIVACY_POLICY_URL)
        self.assertEqual(self.document["contact_email"], "zll6796096@gmail.com")
        self.assertEqual(
            self.document["release_gates"],
            {
                "support_url": {
                    "http_200": None,
                    "content_verified": None,
                    "status": "PENDING_PRODUCTION",
                },
                "privacy_policy_url": {
                    "http_200": None,
                    "content_verified": None,
                    "status": "PENDING_PRODUCTION",
                },
                "signed_archive_reconciliation_required": True,
                "signed_archive_privacy_reconciliation_verified": None,
                "signed_archive_status": "PENDING_SIGNED_ARCHIVE",
            },
        )

    def test_privacy_answers_are_locked_to_current_local_evidence(self) -> None:
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

        evidence = self.document["privacy_evidence"]
        self.assertEqual(
            set(evidence),
            {
                "sources",
                "firebase_ios_sdk",
                "firebase_diagnostic_data_basis",
                "app_privacy_manifest_photos_contract",
            },
        )
        self.assertEqual(
            evidence["sources"],
            {
                "project": "ios/project.yml",
                "package_resolved": (
                    "ios/Kalories.xcodeproj/project.xcworkspace/xcshareddata/"
                    "swiftpm/Package.resolved"
                ),
                "app_privacy_manifest": "ios/Kalories/Resources/PrivacyInfo.xcprivacy",
            },
        )
        self.assertEqual(
            evidence["firebase_ios_sdk"],
            {
                "project_requirement": "12.17.0",
                "resolved_version": "12.17.0",
                "resolved_revision": "33a468adfdb75b53f05a37e7c886ca7c962b5c17",
            },
        )
        self.assertEqual(
            evidence["firebase_diagnostic_data_basis"],
            "FIREBASE_INSTALLATIONS_PRIVACY_MANIFEST",
        )

        project_yml = PROJECT_YML_PATH.read_text(encoding="utf-8")
        project_version_match = re.search(
            r"(?m)^  Firebase:\n"
            r"    url: https://github\.com/firebase/firebase-ios-sdk\.git\n"
            r"    exactVersion: (?P<version>[^\s]+)$",
            project_yml,
        )
        self.assertIsNotNone(project_version_match)
        self.assertEqual(project_version_match.group("version"), "12.17.0")

        package_resolved = json.loads(PACKAGE_RESOLVED_PATH.read_text(encoding="utf-8"))
        firebase_pin = next(
            pin for pin in package_resolved["pins"] if pin["identity"] == "firebase-ios-sdk"
        )
        self.assertEqual(firebase_pin["state"]["version"], "12.17.0")
        self.assertEqual(
            firebase_pin["state"]["revision"],
            "33a468adfdb75b53f05a37e7c886ca7c962b5c17",
        )

        expected_photos_contract = {
            "type": "NSPrivacyCollectedDataTypePhotosorVideos",
            "purpose": "NSPrivacyCollectedDataTypePurposeAppFunctionality",
            "linked_to_user": False,
            "tracking": False,
        }
        self.assertEqual(
            evidence["app_privacy_manifest_photos_contract"],
            expected_photos_contract,
        )
        with PRIVACY_MANIFEST_PATH.open("rb") as manifest_file:
            manifest = plistlib.load(manifest_file)
        self.assertFalse(manifest["NSPrivacyTracking"])
        self.assertEqual(manifest["NSPrivacyTrackingDomains"], [])
        self.assertEqual(
            manifest["NSPrivacyCollectedDataTypes"],
            [
                {
                    "NSPrivacyCollectedDataType": expected_photos_contract["type"],
                    "NSPrivacyCollectedDataTypePurposes": [
                        expected_photos_contract["purpose"]
                    ],
                    "NSPrivacyCollectedDataTypeLinked": False,
                    "NSPrivacyCollectedDataTypeTracking": False,
                }
            ],
        )


if __name__ == "__main__":
    unittest.main()
