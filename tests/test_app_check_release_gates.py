from __future__ import annotations

import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
IOS_GATE = ROOT / "scripts" / "check-ios-app-check-release.sh"
FIREBASE_PLIST_VALIDATOR = ROOT / "scripts" / "validate_firebase_plists.py"
BACKEND_GATE = ROOT / "scripts" / "check-testflight-backend.sh"
RUNBOOK = ROOT / "docs" / "release" / "testflight-backend-runbook.md"
README = ROOT / "README.md"


class AppCheckReleaseGateTests(unittest.TestCase):
    def test_ios_local_gate_passes_without_claiming_external_configuration(self) -> None:
        result = subprocess.run(
            [str(IOS_GATE), "--local"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS: local iOS App Check release checks", result.stdout)
        self.assertIn("EXTERNAL CONFIGURATION: not verified", result.stdout)

    def test_ios_distribution_gate_fails_closed_without_expected_firebase_app(self) -> None:
        result = subprocess.run(
            [str(IOS_GATE)],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn(
            "BLOCKED_BY_EXTERNAL_CONFIG: expected Firebase iOS app ID is missing",
            result.stdout,
        )
        self.assertNotIn("PASS: distribution", result.stdout)

    def test_backend_gate_verifies_exact_app_check_runtime_and_no_token_probe(self) -> None:
        source = BACKEND_GATE.read_text(encoding="utf-8")
        for expected in (
            "KALORIES_EXPECTED_FIREBASE_IOS_APP_ID",
            "APP_CHECK_ENFORCEMENT",
            "FIREBASE_PROJECT_ID",
            "FIREBASE_IOS_APP_ID",
            "APP_CHECK_FAILED",
            "HTTP 401",
            "x-firebase-app-check",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, source)
        self.assertIn("for protected_path in '/api/analyze' '/'", source)
        self.assertNotIn(
            "application-layer access protection is not verified", source
        )
        self.assertNotIn(
            "public access or application-layer protection is not compliant", source
        )

    def test_runbook_keeps_external_registration_and_mutations_separately_gated(self) -> None:
        runbook = RUNBOOK.read_text(encoding="utf-8")
        for expected in (
            "Firebase App Check",
            "Apple App Attest",
            "com.ryuaistudio.kalories",
            "KALORIES_EXPECTED_FIREBASE_IOS_APP_ID",
            "APP_CHECK_ENFORCEMENT=required",
            "POST /api/analyze",
            "zero-traffic candidate",
            "separate approval",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, runbook)
        self.assertIn("for protected_path in '/api/analyze' '/'", runbook)

    def test_distribution_gate_validates_the_packaged_signed_app(self) -> None:
        source = IOS_GATE.read_text(encoding="utf-8") + FIREBASE_PLIST_VALIDATOR.read_text(
            encoding="utf-8"
        )
        for expected in (
            "--glob '!**/Kalories/Resources/GoogleService-Info.plist'",
            "distribution app bundle is required",
            "packaged_firebase_plist=",
            "codesign --verify --deep --strict",
            "distribution-entitlements.plist",
            "CFBundleIdentifier",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, source)

    def test_firebase_plist_exception_is_limited_to_a_validated_public_api_key(self) -> None:
        source = FIREBASE_PLIST_VALIDATOR.read_text(encoding="utf-8")
        for expected in (
            'nested_path == ("API_KEY",)',
            '"privatekey"',
            '"serviceaccount"',
            '"firebaseappcheckdebugtoken"',
            "configs[1] != configs[0]",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, source)

    def test_source_firebase_plist_validator_accepts_only_the_public_api_key_exception(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            valid = self._valid_firebase_config()
            source_path = root / "GoogleService-Info.plist"
            self._write_plist(source_path, valid)
            self.assertEqual(self._run_validator(source_path).returncode, 0)

            forbidden_values = (
                {"PRIVATE_KEY": "-----BEGIN PRIVATE KEY-----"},
                {"embedded": {"type": "service_account"}},
                {"FIREBASE_APP_CHECK_DEBUG_TOKEN": "debug-token"},
                {"embedded": {"API_KEY": "AIza" + ("b" * 35)}},
            )
            for forbidden in forbidden_values:
                with self.subTest(forbidden=forbidden):
                    candidate = dict(valid)
                    candidate.update(forbidden)
                    self._write_plist(source_path, candidate)
                    result = self._run_validator(source_path)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn("debug-token", result.stdout + result.stderr)

    def test_distribution_firebase_plist_validator_requires_exact_packaged_copy(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            valid = self._valid_firebase_config()
            source_path = root / "source.plist"
            packaged_path = root / "packaged.plist"
            info_path = root / "Info.plist"
            self._write_plist(source_path, valid)
            self._write_plist(packaged_path, valid)
            self._write_plist(info_path, {"CFBundleIdentifier": "com.ryuaistudio.kalories"})
            self.assertEqual(
                self._run_validator(source_path, packaged_path, info_path).returncode,
                0,
            )

            mismatched = dict(valid)
            mismatched["API_KEY"] = "AIza" + ("c" * 35)
            self._write_plist(packaged_path, mismatched)
            self.assertNotEqual(
                self._run_validator(source_path, packaged_path, info_path).returncode,
                0,
            )

            messaging_enabled = dict(valid)
            messaging_enabled["IS_GCM_ENABLED"] = True
            self._write_plist(source_path, messaging_enabled)
            self._write_plist(packaged_path, messaging_enabled)
            self.assertNotEqual(
                self._run_validator(source_path, packaged_path, info_path).returncode,
                0,
            )

    def test_source_firebase_plist_validation_precedes_local_pass(self) -> None:
        source = IOS_GATE.read_text(encoding="utf-8")
        self.assertLess(
            source.index('validate_firebase_plists.py" --source "${FIREBASE_PLIST}"'),
            source.index('if [[ "${local_only}" == true ]]'),
        )

    @staticmethod
    def _valid_firebase_config() -> dict[str, object]:
        return {
            "API_KEY": "AIza" + ("a" * 35),
            "BUNDLE_ID": "com.ryuaistudio.kalories",
            "PROJECT_ID": "zhang23-23",
            "GOOGLE_APP_ID": "1:123456789:ios:abcdef123456",
            "IS_ANALYTICS_ENABLED": False,
            "IS_ADS_ENABLED": False,
            "IS_SIGNIN_ENABLED": False,
            "IS_GCM_ENABLED": False,
        }

    @staticmethod
    def _write_plist(path: Path, payload: dict[str, object]) -> None:
        with path.open("wb") as destination:
            plistlib.dump(payload, destination)

    @staticmethod
    def _run_validator(
        source: Path,
        packaged: Path | None = None,
        info: Path | None = None,
    ) -> subprocess.CompletedProcess[str]:
        command = [
            sys.executable,
            str(FIREBASE_PLIST_VALIDATOR),
            "--source",
            str(source),
        ]
        if packaged is not None and info is not None:
            command.extend(
                [
                    "--packaged",
                    str(packaged),
                    "--app-info",
                    str(info),
                    "--expected-bundle",
                    "com.ryuaistudio.kalories",
                    "--expected-project",
                    "zhang23-23",
                    "--expected-app",
                    "1:123456789:ios:abcdef123456",
                ]
            )
        return subprocess.run(command, text=True, capture_output=True, check=False)

    def test_readme_documents_local_gate_and_external_configuration_boundary(self) -> None:
        readme = README.read_text(encoding="utf-8")
        for expected in (
            "Firebase App Check",
            "Apple App Attest",
            "scripts/check-ios-app-check-release.sh --local",
            "GoogleService-Info.plist",
            "外部配置",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, readme)


if __name__ == "__main__":
    unittest.main()
