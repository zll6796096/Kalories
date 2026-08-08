"""Regression tests for the read-only TestFlight backend release gate.

The dynamic tests replace gcloud and curl with local fakes.  They never call a
cloud mutation or a real provider, and sentinel payloads must never reach the
gate's output.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "check-testflight-backend.sh"
RUNBOOK = ROOT / "docs" / "release" / "testflight-backend-runbook.md"
README = ROOT / "README.md"

REVISION = "kalories-00042-candidate"
SENTINEL = "SENSITIVE_SENTINEL_MUST_NOT_LEAK"
FIREBASE_IOS_APP_ID = "1:123456789:ios:abcdef123456"


class PreflightBehaviorTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.bin_dir = self.root / "bin"
        self.fixture_dir = self.root / "fixtures"
        self.tmp_dir = self.root / "private-tmp"
        self.bin_dir.mkdir()
        self.fixture_dir.mkdir()
        self.tmp_dir.mkdir()
        self.calls = self.root / "calls.txt"

        self.service = {
            "metadata": {"name": "kalories"},
            "spec": {
                "template": {
                    "metadata": {
                        "annotations": {"autoscaling.knative.dev/maxScale": "1"}
                    },
                    "spec": {"containers": [self._container()]},
                }
            },
            "status": {
                "url": "https://example.invalid",
                "latestReadyRevisionName": REVISION,
                "traffic": [{"revisionName": REVISION, "percent": 100}],
            },
        }
        self.revision = {
            "metadata": {
                "name": REVISION,
                "annotations": {"autoscaling.knative.dev/maxScale": "1"},
            },
            "spec": {"containers": [self._container()]},
        }
        self.iam = {
            "etag": "etag-one",
            "bindings": [
                {"role": "roles/run.invoker", "members": ["allUsers"]}
            ],
        }
        self.logs = [
            {
                "timestamp": "2026-08-08T00:00:03Z",
                "resource": {"labels": {"revision_name": REVISION}},
                "httpRequest": {
                    "requestUrl": "https://example.invalid/health",
                    "status": 200,
                },
            },
            {
                "timestamp": "2026-08-08T00:00:02Z",
                "resource": {"labels": {"revision_name": REVISION}},
                "httpRequest": {
                    "requestUrl": "https://example.invalid/privacy/",
                    "status": 200,
                },
            },
            {
                "timestamp": "2026-08-08T00:00:01Z",
                "resource": {"labels": {"revision_name": REVISION}},
                "httpRequest": {
                    "requestUrl": "https://example.invalid/support/",
                    "status": 200,
                },
            },
            {
                "timestamp": "2026-08-08T00:00:00Z",
                "resource": {"labels": {"revision_name": REVISION}},
                "httpRequest": {
                    "requestUrl": "https://example.invalid/api/analyze",
                    "requestMethod": "POST",
                    "status": 401,
                },
            },
            {
                "timestamp": "2026-08-07T23:59:59Z",
                "resource": {"labels": {"revision_name": REVISION}},
                "httpRequest": {
                    "requestUrl": "https://example.invalid/",
                    "requestMethod": "POST",
                    "status": 401,
                },
            },
        ]
        self._write_fakes()
        self._write_fixtures()

    @staticmethod
    def _container() -> dict[str, object]:
        return {
            "image": "asia-northeast1-docker.pkg.dev/p/r/i@sha256:"
            + ("a" * 64),
            "env": [
                {
                    "name": "GEMINI_API_KEY",
                    "valueFrom": {
                        "secretKeyRef": {
                            "name": "kalories-gemini-api-key",
                            "key": "7",
                        }
                    },
                },
                {"name": "GEMINI_MODEL", "value": "gemini-3.6-flash"},
                {"name": "APP_CHECK_ENFORCEMENT", "value": "required"},
                {"name": "FIREBASE_PROJECT_ID", "value": "zhang23-23"},
                {"name": "FIREBASE_IOS_APP_ID", "value": FIREBASE_IOS_APP_ID},
            ],
        }

    def _write_executable(self, name: str, content: str) -> None:
        path = self.bin_dir / name
        path.write_text(content, encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def _write_fakes(self) -> None:
        self._write_executable(
            "gcloud",
            """#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >>"${FAKE_CALLS}"
if [[ "$1 $2" == "auth list" ]]; then
  printf '%s\\n' 'active-account-present'
elif [[ "$1 $2 $3" == "run services describe" ]]; then
  command cp "${FAKE_FIXTURES}/service.json" /dev/stdout
elif [[ "$1 $2 $3" == "run revisions describe" ]]; then
  command cp "${FAKE_FIXTURES}/revision.json" /dev/stdout
elif [[ "$1 $2 $3" == "run services get-iam-policy" ]]; then
  command cp "${FAKE_FIXTURES}/iam.json" /dev/stdout
elif [[ "$1 $2" == "logging read" ]]; then
  if [[ "${FAKE_LOG_EXIT:-0}" != 0 ]]; then
    exit "${FAKE_LOG_EXIT}"
  fi
  command cp "${FAKE_FIXTURES}/logs.json" /dev/stdout
else
  exit 97
fi
""",
        )
        self._write_executable(
            "curl",
            """#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >>"${FAKE_CALLS}"
if [[ "${FAKE_CURL_EXIT:-0}" != 0 ]]; then
  exit "${FAKE_CURL_EXIT}"
fi
output_file=/dev/null
is_post=false
previous=''
for argument in "$@"; do
  if [[ "${previous}" == --output ]]; then
    output_file="${argument}"
  elif [[ "${previous}" == --request && "${argument}" == POST ]]; then
    is_post=true
  fi
  previous="${argument}"
done
if [[ "${is_post}" == true ]]; then
  printf '%s' '{"detail":{"code":"APP_CHECK_FAILED"}}' >"${output_file}"
  printf '%s' "${FAKE_POST_STATUS:-401}"
else
  printf '%s' "${FAKE_CURL_STATUS:-200}"
fi
""",
        )

    def _write_fixtures(self) -> None:
        for name, value in (
            ("service", self.service),
            ("revision", self.revision),
            ("iam", self.iam),
            ("logs", self.logs),
        ):
            (self.fixture_dir / f"{name}.json").write_text(
                json.dumps(value), encoding="utf-8"
            )

    def _run(self, **overrides: str) -> subprocess.CompletedProcess[str]:
        self._write_fixtures()
        env = os.environ.copy()
        env.update(
            {
                "PATH": f"{self.bin_dir}:{env['PATH']}",
                "FAKE_CALLS": str(self.calls),
                "FAKE_FIXTURES": str(self.fixture_dir),
                "TMPDIR": str(self.tmp_dir),
                "KALORIES_EXPECTED_FIREBASE_IOS_APP_ID": FIREBASE_IOS_APP_ID,
            }
        )
        env.update(overrides)
        before = set(self.tmp_dir.iterdir())
        result = subprocess.run(
            [str(SCRIPT)],
            cwd=ROOT,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(before, set(self.tmp_dir.iterdir()), "private temp leaked")
        self.assertNotIn(SENTINEL, result.stdout)
        self.assertNotIn(SENTINEL, result.stderr)
        return result

    def _assert_pass(self, result: subprocess.CompletedProcess[str]) -> None:
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS: TestFlight backend preflight", result.stdout)
        self.assertNotIn("NO-GO:", result.stdout)

    def test_compliant_revision_and_no_token_probe_pass(self) -> None:
        self._assert_pass(self._run())
        self.assertIn(f"run revisions describe {REVISION}", self.calls.read_text())
        self.assertIn("run services get-iam-policy kalories", self.calls.read_text())
        post_calls = [
            line
            for line in self.calls.read_text().splitlines()
            if "--request POST" in line
        ]
        self.assertEqual(len(post_calls), 2)
        self.assertTrue(
            any(line.endswith("https://example.invalid/api/analyze") for line in post_calls)
        )
        self.assertTrue(
            any(line.endswith("https://example.invalid/") for line in post_calls)
        )

    def test_accepts_unambiguous_v2_revision_fields(self) -> None:
        self.revision = {
            "metadata": {"name": REVISION},
            "scaling": {"maxInstanceCount": 1},
            "containers": [
                {
                    "image": "image@sha256:" + ("b" * 64),
                    "env": [
                        {
                            "name": "GEMINI_API_KEY",
                            "valueSource": {
                                "secretKeyRef": {
                                    "secret": "kalories-gemini-api-key",
                                    "version": "9",
                                }
                            },
                        },
                        {"name": "GEMINI_MODEL", "value": "gemini-3.6-flash"},
                        {"name": "APP_CHECK_ENFORCEMENT", "value": "required"},
                        {"name": "FIREBASE_PROJECT_ID", "value": "zhang23-23"},
                        {"name": "FIREBASE_IOS_APP_ID", "value": FIREBASE_IOS_APP_ID},
                    ],
                }
            ],
        }
        self._assert_pass(self._run())

    def test_uses_serving_revision_not_mutable_service_template(self) -> None:
        self.revision["metadata"]["annotations"][
            "autoscaling.knative.dev/maxScale"
        ] = "20"
        self.revision["spec"]["containers"][0]["env"][0] = {
            "name": "GEMINI_API_KEY",
            "value": SENTINEL,
        }
        result = self._run()
        self.assertIn("NO-GO: Cloud Run production revision maxScale is not exactly 1", result.stdout)
        self.assertIn("NO-GO: GEMINI_API_KEY is not exactly one pinned secret-backed entry", result.stdout)

    def test_requires_exactly_one_immutable_production_revision_at_100_percent(self) -> None:
        self.service["status"]["traffic"] = [
            {"revisionName": REVISION, "percent": 60},
            {"revisionName": "kalories-00041-old", "percent": 40},
        ]
        result = self._run()
        self.assertIn(
            "NO-GO: Cloud Run production traffic is not exactly one revision at 100 percent",
            result.stdout,
        )

    def test_sums_duplicate_traffic_entries_for_same_revision(self) -> None:
        self.service["status"]["traffic"] = [
            {"revisionName": REVISION, "percent": 60},
            {"revisionName": REVISION, "percent": 40, "tag": "candidate"},
        ]
        self._assert_pass(self._run())

    def test_expected_revision_enables_fail_closed_post_promotion_check(self) -> None:
        result = self._run(KALORIES_EXPECTED_REVISION="kalories-99999-wrong")
        self.assertIn(
            "NO-GO: expected production revision is not serving 100 percent",
            result.stdout,
        )
        self._assert_pass(self._run(KALORIES_EXPECTED_REVISION=REVISION))

    def test_rejects_wrong_or_malformed_secret_reference_without_leaking(self) -> None:
        bad_refs = [
            {"name": "wrong-secret", "key": "7"},
            {"unexpected": SENTINEL},
            {"name": "kalories-gemini-api-key", "key": "latest"},
        ]
        for bad_ref in bad_refs:
            with self.subTest(bad_ref=bad_ref):
                self.revision["spec"]["containers"][0]["env"][0] = {
                    "name": "GEMINI_API_KEY",
                    "valueFrom": {"secretKeyRef": bad_ref},
                }
                result = self._run()
                self.assertIn(
                    "NO-GO: GEMINI_API_KEY is not exactly one pinned secret-backed entry",
                    result.stdout,
                )

    def test_rejects_mutable_revision_image(self) -> None:
        self.revision["spec"]["containers"][0]["image"] = "image:latest"
        result = self._run()
        self.assertIn("NO-GO: Cloud Run production revision image is not immutable", result.stdout)

    def test_public_invoker_is_required_for_pages_and_policy_is_never_printed(self) -> None:
        self.iam = {
            "etag": "etag-two",
            "bindings": [
                {
                    "role": "roles/run.invoker",
                    "members": ["allUsers", f"serviceAccount:{SENTINEL}"],
                }
            ],
        }
        self._assert_pass(self._run())

        self.iam = {"etag": "etag-three", "bindings": []}
        result = self._run()
        self.assertIn(
            "NO-GO: Cloud Run public invoker is missing for public pages",
            result.stdout,
        )
        self.assertNotIn("allUsers", result.stdout + result.stderr)
        self.assertNotIn("serviceAccount:", result.stdout + result.stderr)

    def test_iam_read_or_schema_failure_is_no_go(self) -> None:
        self.iam = {"unexpected": SENTINEL}
        result = self._run()
        self.assertIn("NO-GO: Cloud Run IAM policy unavailable", result.stdout)

    def test_curl_nonzero_is_no_go_even_when_http_code_is_200(self) -> None:
        result = self._run(FAKE_CURL_EXIT="18", FAKE_CURL_STATUS="200")
        self.assertIn("NO-GO: /health request failed", result.stdout)
        self.assertIn("NO-GO: /privacy request failed", result.stdout)
        self.assertIn("NO-GO: /support request failed", result.stdout)
        self.assertIn("NO-GO: App Check no-token POST request failed", result.stdout)

    def test_requires_exact_app_check_environment_and_no_token_contract(self) -> None:
        env = self.revision["spec"]["containers"][0]["env"]
        for name, finding in (
            ("APP_CHECK_ENFORCEMENT", "APP_CHECK_ENFORCEMENT is not exactly required"),
            ("FIREBASE_PROJECT_ID", "FIREBASE_PROJECT_ID is not exactly zhang23-23"),
            ("FIREBASE_IOS_APP_ID", "FIREBASE_IOS_APP_ID does not match the approved app"),
        ):
            with self.subTest(name=name):
                original = next(item for item in env if item["name"] == name)
                original["value"] = "wrong"
                result = self._run()
                self.assertIn(f"NO-GO: {finding}", result.stdout)
                original["value"] = (
                    "required" if name == "APP_CHECK_ENFORCEMENT"
                    else "zhang23-23" if name == "FIREBASE_PROJECT_ID"
                    else FIREBASE_IOS_APP_ID
                )

        result = self._run(FAKE_POST_STATUS="200")
        self.assertIn(
            "NO-GO: App Check no-token POST did not return HTTP 401",
            result.stdout,
        )

    def test_logs_must_be_valid_nonempty_json_array(self) -> None:
        (self.fixture_dir / "logs.json").write_text("not-json", encoding="utf-8")
        # Avoid _run's fixture rewrite for the two deliberately raw fixtures.
        saved = self._write_fixtures
        self._write_fixtures = lambda: None  # type: ignore[method-assign]
        try:
            result = self._run()
        finally:
            self._write_fixtures = saved  # type: ignore[method-assign]
        self.assertIn("NO-GO: Cloud Run logs are not a nonempty JSON array", result.stdout)

        self.logs = []
        result = self._run()
        self.assertIn("NO-GO: Cloud Run logs are not a nonempty JSON array", result.stdout)

    def test_logs_must_prove_all_target_requests_were_collected(self) -> None:
        self.logs = [{"textPayload": "safe"}]
        result = self._run()
        self.assertIn("NO-GO: Cloud Run target request logs are missing", result.stdout)

    def test_recursive_log_scan_rejects_sensitive_keys_and_values(self) -> None:
        sensitive_payloads = [
            {"x-goog-api-key": SENTINEL},
            {"message": f"Bearer {SENTINEL}"},
            {"message": "AIza" + ("x" * 35)},
            {"assessment": {"score": 90, "marker": SENTINEL}},
            {"nutrients": {"calories": 500, "marker": SENTINEL}},
            {"providerResponse": {"marker": SENTINEL}},
            {"image": "A" * 600},
            {"x-firebase-app-check": SENTINEL},
        ]
        for payload in sensitive_payloads:
            with self.subTest(payload=list(payload)):
                self.logs = self.logs[:5] + [payload]
                result = self._run()
                self.assertIn(
                    "NO-GO: Cloud Run logs contain sensitive application data",
                    result.stdout,
                )

    def test_short_stringified_provider_json_is_no_go_without_payload_leak(self) -> None:
        sensitive_strings = [
            (
                '{"food_detected":true,"nutrients":{"calories_kcal":640},'
                f'"assessment":{{"marker":"{SENTINEL}"}}}}'
            ),
            f'{{"providerResponse":{{"marker":"{SENTINEL}"}}}}',
            f'request={{"marker":"{SENTINEL}"}}',
            f'response={{"marker":"{SENTINEL}"}}',
            f'authorization=Bearer {SENTINEL}',
            f'x-goog-api-key={SENTINEL}',
            f'x-firebase-app-check={SENTINEL}',
            f'api_key={SENTINEL}',
            "data:image/jpeg;base64," + ("A" * 32),
        ]
        for provider_payload in sensitive_strings:
            with self.subTest(marker=provider_payload.split("=", 1)[0][:32]):
                self.logs = self.logs[:5] + [{"textPayload": provider_payload}]
                result = self._run()
                self.assertIn(
                    "NO-GO: Cloud Run logs contain sensitive application data",
                    result.stdout,
                )
                self.assertNotIn(provider_payload, result.stdout + result.stderr)

    def test_log_read_failure_is_no_go(self) -> None:
        result = self._run(FAKE_LOG_EXIT="3")
        self.assertIn("NO-GO: Cloud Run log read failed", result.stdout)


class ReleaseDocumentationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.runbook = RUNBOOK.read_text(encoding="utf-8")
        cls.readme = README.read_text(encoding="utf-8")

    def test_candidate_is_described_as_an_immutable_revision_and_has_zero_traffic(self) -> None:
        self.assertIn('gcloud run revisions describe "${KALORIES_CANDIDATE_REVISION}"', self.runbook)
        self.assertIn("candidate_traffic_total", self.runbook)
        self.assertIn("candidate revision traffic is not zero", self.runbook)
        self.assertIn("@sha256:", self.runbook)

    def test_promotion_is_exact_and_postchecked_without_to_latest(self) -> None:
        self.assertNotIn("--to-latest", self.runbook)
        self.assertIn(
            '--to-revisions="${KALORIES_CANDIDATE_REVISION}=100"', self.runbook
        )
        self.assertIn("if ! gcloud run services update-traffic", self.runbook)
        self.assertIn(
            'KALORIES_EXPECTED_REVISION="${KALORIES_CANDIDATE_REVISION}"', self.runbook
        )
        self.assertIn(
            '"${KALORIES_OLD_KEY_RESOURCE}" == "${KALORIES_REPLACEMENT_KEY_RESOURCE}"',
            self.runbook,
        )

    def test_public_pages_and_app_check_remain_separate_access_layers(self) -> None:
        self.assertNotIn("--allow-unauthenticated", self.runbook + self.readme)
        self.assertIn("allUsers", self.runbook)
        self.assertRegex(self.runbook, r"not\s+access\s+control")
        self.assertIn("Firebase App Check", self.runbook)
        self.assertIn("for protected_path in '/api/analyze' '/'", self.runbook)

    def test_candidate_logs_are_nonempty_targeted_and_recursively_scanned(self) -> None:
        self.assertIn("candidate_logs_json", self.runbook)
        self.assertIn("type == \"array\" and length > 0", self.runbook)
        self.assertIn("x-goog-api-key", self.runbook)
        self.assertIn("providerResponse", self.runbook)
        self.assertIn("food_detected", self.runbook)
        self.assertIn("candidate_log_scan_status", self.runbook)
        self.assertIn("target request log", self.runbook)

    def test_response_schema_uses_the_real_backend_contract(self) -> None:
        self.assertIn("AnalyzeResponse.model_validate_json", self.runbook)
        self.assertNotIn("has(\"food_detected\")", self.runbook)

    def test_secret_migration_is_newline_safe_and_pins_a_verified_version(self) -> None:
        self.assertIn("set -euo pipefail", self.runbook)
        self.assertIn("chmod 600", self.runbook)
        self.assertIn("jq -je", self.runbook)
        self.assertIn("KALORIES_SECRET_VERSION", self.runbook)
        self.assertIn("secrets versions describe", self.runbook)
        self.assertNotIn("kalories-gemini-api-key:latest", self.runbook)

    def test_deploy_updates_only_named_config_and_has_concurrency_preflight(self) -> None:
        self.assertNotIn("--set-secrets", self.runbook)
        self.assertNotIn("--set-env-vars", self.runbook)
        self.assertIn("--update-secrets", self.runbook)
        self.assertIn("--update-env-vars", self.runbook)
        self.assertIn("resourceVersion", self.runbook)

    def test_iam_mutation_is_private_and_readback_requires_exact_accessor(self) -> None:
        self.assertIn("roles/secretmanager.secretAccessor", self.runbook)
        self.assertIn("iam_mutation_json", self.runbook)
        self.assertIn("iam_readback_json", self.runbook)
        self.assertIn("length == 1", self.runbook)
        self.assertIn("inherited accessor audit", self.runbook)
        self.assertIn("projects get-ancestors", self.runbook)
        self.assertIn("has(\"condition\") | not", self.runbook)

    def test_quota_create_has_complete_fail_closed_readback(self) -> None:
        self.assertIn("quota_readback_json", self.runbook)
        self.assertIn("reconciling == false", self.runbook)
        self.assertIn("grantedValue", self.runbook)
        self.assertIn("preferredValue", self.runbook)
        self.assertIn("dimensions", self.runbook)
        self.assertIn('.service == "generativelanguage.googleapis.com"', self.runbook)
        self.assertIn(".quotaId == $expected_quota_id", self.runbook)
        describe_line = next(
            line
            for line in self.runbook.splitlines()
            if line.startswith("gcloud beta quotas preferences describe")
        )
        self.assertNotIn("--service", describe_line)
        self.assertNotIn("--quota-id", describe_line)

    def test_budget_requires_user_amount_and_exact_readback(self) -> None:
        self.assertIn("KALORIES_MONTHLY_BUDGET_AMOUNT", self.runbook)
        self.assertIn("budget_readback_json", self.runbook)
        self.assertIn("budget alert read-back is mismatched", self.runbook)
        self.assertRegex(self.runbook, r"alert notifies; it neither caps spend")
        self.assertIn('rule.get("spendBasis") == "CURRENT_SPEND"', self.runbook)

    def test_legacy_rollback_is_never_ready_after_old_key_revocation(self) -> None:
        self.assertNotIn("Rollback | READY", self.runbook)
        self.assertIn("limited pre-revocation rollback window", self.runbook)
        self.assertIn("legacy_rollback_guard=", self.runbook)
        self.assertIn("post-revocation legacy rollback is forbidden", self.runbook)
        self.assertIn("private automated equality check", self.runbook)

    def test_sensitive_fences_have_success_cleanup_and_clear_exit_traps(self) -> None:
        for marker in (
            "key_material_json=",
            "iam_mutation_json=",
            "quota_readback_json=",
            "budget_readback_json=",
            "candidate_traffic_total=",
            "candidate_payload_json=",
        ):
            with self.subTest(marker=marker):
                block = RunbookCommandMockTests._block(marker)
                self.assertIn("trap - EXIT", block)

    def test_readme_has_no_direct_production_deploy_and_imports_rate_limit(self) -> None:
        self.assertNotIn("gcloud run deploy kalories", self.readme)
        self.assertIn("lib.rate_limit", self.readme)


class ResponseContractTests(unittest.TestCase):
    """Lock the runbook gate to the backend's real strict Pydantic contract."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.canonical = json.loads(
            (ROOT / "tests" / "fixtures" / "canonical_analysis_result.json").read_text(
                encoding="utf-8"
            )
        )

    def _validates(self, payload: dict[str, object]) -> bool:
        with tempfile.TemporaryDirectory() as directory:
            payload_path = Path(directory) / "response.json"
            payload_path.write_text(json.dumps(payload), encoding="utf-8")
            result = subprocess.run(
                [
                    str(ROOT / ".venv" / "bin" / "python"),
                    "-c",
                    (
                        "from pathlib import Path; import sys; "
                        "from api.analyze import AnalyzeResponse; "
                        "AnalyzeResponse.model_validate_json("
                        "Path(sys.argv[1]).read_text(encoding='utf-8'))"
                    ),
                    str(payload_path),
                ],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
        return result.returncode == 0

    def _copy(self) -> dict[str, object]:
        return json.loads(json.dumps(self.canonical))

    def test_canonical_response_satisfies_real_contract(self) -> None:
        self.assertTrue(self._validates(self._copy()))

    def test_string_nutrient_is_rejected(self) -> None:
        payload = self._copy()
        payload["nutrients"]["calories_kcal"] = "640"  # type: ignore[index]
        self.assertFalse(self._validates(payload))

    def test_invalid_confidence_is_rejected(self) -> None:
        payload = self._copy()
        payload["confidence"]["overall"] = "certain"  # type: ignore[index]
        self.assertFalse(self._validates(payload))

    def test_empty_assessment_is_rejected(self) -> None:
        payload = self._copy()
        payload["assessment"] = {}
        self.assertFalse(self._validates(payload))

    def test_out_of_range_score_and_empty_food_name_are_rejected(self) -> None:
        payload = self._copy()
        payload["assessment"]["score"] = 101  # type: ignore[index]
        self.assertFalse(self._validates(payload))

        payload = self._copy()
        payload["food_names"]["ja"] = ""  # type: ignore[index]
        self.assertFalse(self._validates(payload))


class RunbookCommandMockTests(unittest.TestCase):
    """Execute future mutation blocks only against local command fakes."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.bin_dir = self.root / "bin"
        self.fixture_dir = self.root / "fixtures"
        self.tmp_dir = self.root / "private-tmp"
        self.bin_dir.mkdir()
        self.fixture_dir.mkdir()
        self.tmp_dir.mkdir()
        self.calls = self.root / "calls.txt"
        self.mktemp_paths = self.root / "mktemp-paths.txt"
        self.app_check_token_file = self.root / "app-check-token"
        self.app_check_token_file.write_text("local-test-app-check-token", encoding="utf-8")
        self.app_check_token_file.chmod(0o600)
        self.real_jq = shutil.which("jq")
        if self.real_jq is None:
            self.fail("jq is required for the runbook regression tests")
        self.runtime_sa = f"{SENTINEL}@example.invalid"
        self.dimensions = {"model": "gemini-3.6-flash"}
        self._write_fakes()
        self._write_defaults()

    @staticmethod
    def _block(marker: str) -> str:
        blocks = []
        text = RUNBOOK.read_text(encoding="utf-8")
        start = 0
        while True:
            opening = text.find("```bash\n", start)
            if opening < 0:
                break
            content_start = opening + len("```bash\n")
            closing = text.find("\n```", content_start)
            if closing < 0:
                raise AssertionError("unterminated bash fence")
            block = text[content_start:closing]
            if marker in block:
                blocks.append(block)
            start = closing + len("\n```")
        if len(blocks) != 1:
            raise AssertionError(f"expected one block for {marker!r}, got {len(blocks)}")
        return blocks[0]

    def _write_executable(self, name: str, content: str) -> None:
        path = self.bin_dir / name
        path.write_text(content, encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def _write_fakes(self) -> None:
        self._write_executable(
            "mktemp",
            """#!/usr/bin/env bash
set -euo pipefail
created_path="$(/usr/bin/mktemp "$@")"
printf '%s\\n' "${created_path}" >>"${FAKE_MKTEMP_PATHS}"
printf '%s\\n' "${created_path}"
""",
        )
        self._write_executable(
            "jq",
            """#!/usr/bin/env bash
set -euo pipefail
last_arg=''
for last_arg in "$@"; do :; done
if [[ "${FAKE_JQ_PROJECT_ROLE_ENUM_FAIL:-0}" == 1 ]] &&
  [[ "${last_arg}" == */project-iam.json ]] &&
  [[ "$*" == *"unique[]"* ]]; then
  exit 55
fi
if [[ "${FAKE_JQ_ANCESTOR_ENUM_FAIL:-0}" == 1 ]] &&
  [[ "$*" == *'select(.type != "project")'* ]]; then
  exit 56
fi
exec __REAL_JQ__ "$@"
""".replace("__REAL_JQ__", self.real_jq),
        )
        self._write_executable(
            "curl",
            """#!/usr/bin/env bash
set -euo pipefail
output_file=''
has_app_check=false
while (($# > 0)); do
  case "$1" in
    --output)
      output_file="$2"
      shift 2
      ;;
    --header)
      if [[ "$2" == X-Firebase-AppCheck:* ]]; then
        has_app_check=true
      fi
      shift 2
      ;;
    *) shift ;;
  esac
done
if [[ "${output_file}" == /dev/null ]]; then
  printf '%s' '200'
elif [[ "${has_app_check}" == false ]]; then
  printf '%s' '{"detail":{"code":"APP_CHECK_FAILED"}}' >"${output_file}"
  printf '%s' '401'
else
  command cp "${FAKE_FIXTURES}/candidate-invalid-response.json" "${output_file}"
  printf '%s' '200 0.10'
fi
""",
        )
        self._write_executable(
            "gcloud",
            """#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >>"${FAKE_CALLS}"
case "$*" in
  "services api-keys describe kalories-gemini-testflight"*)
    if [[ "$*" == *"--format=value(name)"* ]]; then
      printf '%s\n' 'projects/123456789/locations/global/keys/replacement-key'
    else
      command cat "${FAKE_FIXTURES}/key-metadata.json"
    fi ;;
  "services api-keys get-key-string kalories-gemini-testflight"*)
    command cat "${FAKE_FIXTURES}/key-material.json" ;;
  "services api-keys get-key-string projects/123456789/locations/global/keys/old-key"*)
    command cat "${FAKE_FIXTURES}/key-material.json" ;;
  "secrets describe kalories-gemini-api-key"*)
    exit 0 ;;
  "secrets versions add kalories-gemini-api-key"*)
    command cat "${FAKE_FIXTURES}/secret-version-create.json" ;;
  "secrets versions describe "*)
    command cat "${FAKE_FIXTURES}/secret-version-readback.json" ;;
  "run services describe kalories"*)
    command cat "${FAKE_FIXTURES}/service.json" ;;
  "projects get-ancestors zhang23-23"*)
    command cat "${FAKE_FIXTURES}/ancestors.json" ;;
  "projects get-iam-policy zhang23-23"*)
    command cat "${FAKE_FIXTURES}/project-iam.json" ;;
  "resource-manager folders get-iam-policy "*)
    if [[ "${FAKE_ANCESTOR_READ_FAIL:-}" == folder ]]; then exit 41; fi
    command cat "${FAKE_FIXTURES}/folder-iam.json" ;;
  "organizations get-iam-policy "*)
    if [[ "${FAKE_ANCESTOR_READ_FAIL:-}" == organization ]]; then exit 42; fi
    command cat "${FAKE_FIXTURES}/organization-iam.json" ;;
  "iam roles describe roles/secretmanager.admin"*)
    command cat "${FAKE_FIXTURES}/admin-role.json" ;;
  "iam roles describe customAccessor --organization=67890"*)
    command cat "${FAKE_FIXTURES}/custom-accessor-role.json" ;;
  "secrets add-iam-policy-binding kalories-gemini-api-key"*)
    command cat "${FAKE_FIXTURES}/iam-mutation.json" ;;
  "secrets get-iam-policy kalories-gemini-api-key"*)
    command cat "${FAKE_FIXTURES}/iam-readback.json" ;;
  "run revisions describe kalories-00003-djq"*)
    command cat "${FAKE_FIXTURES}/legacy-revision.json" ;;
  "run revisions describe "*)
    command cat "${FAKE_FIXTURES}/revision.json" ;;
  "beta quotas preferences create "*)
    command cat "${FAKE_FIXTURES}/quota-create.json" ;;
  "beta quotas preferences describe "*)
    command cat "${FAKE_FIXTURES}/quota-readback.json" ;;
  "billing projects describe zhang23-23"*)
    printf '%s\\n' 'billingAccounts/SAFE-BILLING' ;;
  "projects describe zhang23-23"*)
    printf '%s\\n' '123456789' ;;
  "billing budgets create "*)
    command cat "${FAKE_FIXTURES}/budget-create.json" ;;
  "billing budgets describe "*)
    command cat "${FAKE_FIXTURES}/budget-readback.json" ;;
  "services api-keys describe projects/123456789/locations/global/keys/old-key"*)
    if [[ "${FAKE_OLD_KEY_REVOKED:-0}" == 1 ]]; then
      printf '%s\\n' '2026-08-08T00:00:00Z'
    fi ;;
  "run services update-traffic kalories"*)
    if [[ "${FAKE_PROMOTION_EXIT:-0}" != 0 ]]; then
      exit "${FAKE_PROMOTION_EXIT}"
    fi
    command cat "${FAKE_FIXTURES}/promotion.json" ;;
  *) exit 96 ;;
esac
""",
        )
        self._write_executable(
            "fake-postcheck",
            """#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' 'postcheck-called' >>"${FAKE_CALLS}"
if [[ "${KALORIES_EXPECTED_REVISION:-}" != "${FAKE_EXPECTED_REVISION}" ]]; then
  exit 91
fi
exit "${FAKE_POSTCHECK_EXIT:-0}"
""",
        )

    def _write(self, name: str, value: object) -> None:
        (self.fixture_dir / f"{name}.json").write_text(
            json.dumps(value), encoding="utf-8"
        )

    def _write_defaults(self) -> None:
        self._write(
            "key-metadata",
            {
                "restrictions": {
                    "apiTargets": [
                        {"service": "generativelanguage.googleapis.com"}
                    ]
                }
            },
        )
        self._write("key-material", {"keyString": SENTINEL})
        self._write(
            "secret-version-create",
            {"name": "projects/p/secrets/kalories-gemini-api-key/versions/7"},
        )
        self._write(
            "secret-version-readback",
            {
                "name": "projects/p/secrets/kalories-gemini-api-key/versions/7",
                "state": "ENABLED",
            },
        )
        self._write(
            "service",
            {
                "metadata": {"resourceVersion": "rv-one"},
                "spec": {
                    "template": {
                        "spec": {"serviceAccountName": self.runtime_sa}
                    }
                },
                "status": {
                    "traffic": [
                        {
                            "tag": "testflight-candidate",
                            "revisionName": REVISION,
                            "url": "https://candidate.invalid",
                            "percent": 0,
                        },
                        {"revisionName": "kalories-00041-old", "percent": 100},
                    ]
                },
            },
        )
        self._write(
            "revision",
            {
                "metadata": {
                    "name": REVISION,
                    "annotations": {"autoscaling.knative.dev/maxScale": "1"},
                },
                "spec": {
                    "containers": [
                        {
                            "image": "image@sha256:" + ("c" * 64),
                            "env": [
                                {
                                    "name": "GEMINI_API_KEY",
                                    "valueFrom": {
                                        "secretKeyRef": {
                                            "name": "kalories-gemini-api-key",
                                            "key": "7",
                                        }
                                    },
                                },
                                {
                                    "name": "GEMINI_MODEL",
                                    "value": "gemini-3.6-flash",
                                },
                                {
                                    "name": "APP_CHECK_ENFORCEMENT",
                                    "value": "required",
                                },
                                {
                                    "name": "FIREBASE_PROJECT_ID",
                                    "value": "zhang23-23",
                                },
                                {
                                    "name": "FIREBASE_IOS_APP_ID",
                                    "value": FIREBASE_IOS_APP_ID,
                                },
                            ],
                        }
                    ]
                },
            },
        )
        self._write(
            "legacy-revision",
            {
                "metadata": {"name": "kalories-00003-djq"},
                "spec": {
                    "containers": [
                        {
                            "env": [
                                {"name": "GEMINI_API_KEY", "value": SENTINEL}
                            ]
                        }
                    ]
                },
            },
        )
        exact_policy = {
            "bindings": [
                {
                    "role": "roles/secretmanager.secretAccessor",
                    "members": [f"serviceAccount:{self.runtime_sa}"],
                }
            ]
        }
        self._write("iam-mutation", exact_policy)
        self._write("iam-readback", exact_policy)
        self._write(
            "ancestors",
            [
                {"id": "zhang23-23", "type": "project"},
                {"id": "12345", "type": "folder"},
                {"id": "67890", "type": "organization"},
            ],
        )
        self._write("project-iam", {"etag": "project", "bindings": []})
        self._write("folder-iam", {"etag": "folder", "bindings": []})
        self._write(
            "organization-iam", {"etag": "organization", "bindings": []}
        )
        self._write(
            "admin-role",
            {"includedPermissions": ["secretmanager.versions.access"]},
        )
        self._write(
            "custom-accessor-role",
            {"includedPermissions": ["secretmanager.versions.access"]},
        )
        quota = {
            "name": "projects/123456789/locations/global/quotaPreferences/kalories-testflight-rpd-200",
            "reconciling": False,
            "dimensions": self.dimensions,
            "service": "generativelanguage.googleapis.com",
            "quotaId": "verified-rpd-id",
            "quotaConfig": {"grantedValue": "200", "preferredValue": "200"},
        }
        self._write("quota-create", quota)
        self._write("quota-readback", quota)
        budget = {
            "name": "billingAccounts/SAFE-BILLING/budgets/budget-one",
            "displayName": "Kalories TestFlight monthly alert",
            "budgetFilter": {
                "projects": ["projects/123456789"],
                "calendarPeriod": "MONTH",
            },
            "amount": {
                "specifiedAmount": {
                    "currencyCode": "JPY",
                    "units": "1000",
                    "nanos": 0,
                }
            },
            "thresholdRules": [
                {"thresholdPercent": 0.5, "spendBasis": "CURRENT_SPEND"},
                {"thresholdPercent": 0.8, "spendBasis": "CURRENT_SPEND"},
                {"thresholdPercent": 1.0, "spendBasis": "CURRENT_SPEND"},
            ],
        }
        self._write("budget-create", budget)
        self._write("budget-readback", budget)
        self._write("promotion", {"status": "safe"})
        self._write("candidate-invalid-response", {"private": SENTINEL})

    def _run_block(
        self,
        marker: str,
        *,
        replace: tuple[str, str] | None = None,
        **overrides: str,
    ) -> subprocess.CompletedProcess[str]:
        block = self._block(marker)
        if replace is not None:
            block = block.replace(*replace)
        return self._run_shell(block, **overrides)

    def _run_shell(
        self, script: str, **overrides: str
    ) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env.update(
            {
                "PATH": f"{self.bin_dir}:{env['PATH']}",
                "FAKE_CALLS": str(self.calls),
                "FAKE_FIXTURES": str(self.fixture_dir),
                "FAKE_MKTEMP_PATHS": str(self.mktemp_paths),
                "TMPDIR": str(self.tmp_dir),
                "KALORIES_APP_CHECK_TOKEN_FILE": str(self.app_check_token_file),
                "KALORIES_FIREBASE_IOS_APP_ID": FIREBASE_IOS_APP_ID,
            }
        )
        env.update(overrides)
        self.calls.touch(exist_ok=True)
        before_paths = (
            self.mktemp_paths.read_text(encoding="utf-8").splitlines()
            if self.mktemp_paths.exists()
            else []
        )
        result = subprocess.run(
            ["bash", "-s"],
            input=script,
            cwd=ROOT,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        after_paths = self.mktemp_paths.read_text(encoding="utf-8").splitlines()
        created_paths = after_paths[len(before_paths) :]
        self.assertTrue(created_paths, "runbook block did not create tracked temp state")
        for created_path in created_paths:
            self.assertFalse(Path(created_path).exists(), f"runbook temp leaked: {created_path}")
        self.assertNotIn(SENTINEL, result.stdout + result.stderr)
        return result

    def test_secret_block_closes_key_and_version_failure_paths(self) -> None:
        result = self._run_block("key_material_json=")
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn("CHECK replacement key is stored", result.stdout)

        self._write("key-material", {"keyString": SENTINEL + "\n"})
        result = self._run_block("key_material_json=")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("NO-GO: private key file is empty or contains a newline", result.stdout)

        self._write_defaults()
        self._write(
            "secret-version-readback",
            {
                "name": "projects/p/secrets/kalories-gemini-api-key/versions/7",
                "state": "DISABLED",
            },
        )
        result = self._run_block("key_material_json=")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("NO-GO: pinned secret version read-back failed", result.stdout)

    def test_secret_then_iam_blocks_cleanup_before_trap_is_replaced(self) -> None:
        combined = "\n".join(
            (
                self._block("key_material_json="),
                self._block("iam_mutation_json="),
            )
        )
        result = self._run_shell(combined)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_iam_block_rejects_extra_accessor_without_printing_identity(self) -> None:
        result = self._run_block("iam_mutation_json=")
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

        self._write(
            "iam-readback",
            {
                "bindings": [
                    {
                        "role": "roles/secretmanager.secretAccessor",
                        "members": [
                            f"serviceAccount:{self.runtime_sa}",
                            "serviceAccount:extra@example.invalid",
                        ],
                    }
                ]
            },
        )
        result = self._run_block("iam_mutation_json=")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("NO-GO: secret accessor read-back is not exact", result.stdout)
        self.assertNotIn("extra@example.invalid", result.stdout + result.stderr)

        self._write_defaults()
        extra_binding = json.loads(
            (self.fixture_dir / "iam-readback.json").read_text(encoding="utf-8")
        )
        extra_binding["bindings"].append(
            {
                "role": "roles/secretmanager.admin",
                "members": ["serviceAccount:extra@example.invalid"],
            }
        )
        self._write("iam-readback", extra_binding)
        result = self._run_block("iam_mutation_json=")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("NO-GO: secret accessor read-back is not exact", result.stdout)
        self.assertNotIn("extra@example.invalid", result.stdout + result.stderr)

        self._write_defaults()
        conditional = json.loads(
            (self.fixture_dir / "iam-readback.json").read_text(encoding="utf-8")
        )
        conditional["bindings"][0]["condition"] = {
            "title": "temporary",
            "expression": "request.time < timestamp('2099-01-01T00:00:00Z')",
        }
        self._write("iam-readback", conditional)
        result = self._run_block("iam_mutation_json=")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("NO-GO: secret accessor read-back is not exact", result.stdout)

    def test_iam_block_rejects_inherited_accessor_and_ancestor_read_failure(self) -> None:
        inherited = {
            "etag": "folder",
            "bindings": [
                {
                    "role": "roles/secretmanager.secretAccessor",
                    "members": [f"serviceAccount:{SENTINEL}@ancestor.invalid"],
                }
            ],
        }
        self._write("folder-iam", inherited)
        result = self._run_block("iam_mutation_json=")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("NO-GO: inherited secret accessor exists", result.stdout)

        self._write_defaults()
        self._write(
            "folder-iam",
            {
                "bindings": [
                    {
                        "role": "roles/secretmanager.admin",
                        "members": [f"serviceAccount:{SENTINEL}@ancestor.invalid"],
                    }
                ]
            },
        )
        result = self._run_block("iam_mutation_json=")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("NO-GO: inherited secret accessor exists", result.stdout)

        self._write_defaults()
        self._write(
            "organization-iam",
            {
                "bindings": [
                    {
                        "role": "organizations/67890/roles/customAccessor",
                        "members": [f"serviceAccount:{SENTINEL}@ancestor.invalid"],
                    }
                ]
            },
        )
        result = self._run_block("iam_mutation_json=")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("NO-GO: inherited secret accessor exists", result.stdout)

        self._write_defaults()
        result = self._run_block(
            "iam_mutation_json=", FAKE_ANCESTOR_READ_FAIL="organization"
        )
        self.assertNotEqual(0, result.returncode)
        self.assertIn("NO-GO: inherited accessor audit unavailable", result.stdout)

    def test_iam_jq_enumeration_failures_are_no_go(self) -> None:
        for failure_flag in (
            "FAKE_JQ_PROJECT_ROLE_ENUM_FAIL",
            "FAKE_JQ_ANCESTOR_ENUM_FAIL",
        ):
            with self.subTest(failure=failure_flag):
                self._write_defaults()
                result = self._run_block("iam_mutation_json=", **{failure_flag: "1"})
                self.assertNotEqual(0, result.returncode)
                self.assertIn(
                    "NO-GO: inherited accessor audit unavailable", result.stdout
                )
                self.assertNotIn(
                    "CHECK secret accessor is exact; identities omitted",
                    result.stdout,
                )

    def test_candidate_log_scanner_error_is_no_go(self) -> None:
        block = self._block("candidate_payload_json=")
        begin = block.find("# BEGIN CANDIDATE_LOG_SAFETY_SCAN")
        end = block.find("# END CANDIDATE_LOG_SAFETY_SCAN")
        self.assertGreaterEqual(begin, 0)
        self.assertGreater(end, begin)
        scanner = block[begin:end]
        script = "\n".join(
            (
                "set -euo pipefail",
                "jq() { return 3; }",
                "candidate_logs_json=/dev/null",
                scanner,
            )
        )
        result = subprocess.run(
            ["bash", "-s"],
            input=script,
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertNotEqual(0, result.returncode)
        self.assertIn("NO-GO: candidate log safety scan failed", result.stdout)

    def test_candidate_schema_failure_never_leaks_private_response(self) -> None:
        synthetic_image = self.root / "synthetic.jpg"
        synthetic_image.write_bytes(b"not-a-real-personal-image")
        result = self._run_block(
            "candidate_payload_json=",
            KALORIES_CANDIDATE_URL="https://candidate.invalid",
            KALORIES_CANDIDATE_REVISION=REVISION,
            KALORIES_SYNTHETIC_MEAL_IMAGE=str(synthetic_image),
        )
        self.assertNotEqual(0, result.returncode)
        self.assertIn(
            "NO-GO: candidate response violates the real backend schema",
            result.stdout,
        )
        self.assertNotIn(SENTINEL, result.stdout + result.stderr)
        self.assertNotIn("Traceback", result.stdout + result.stderr)
        self.assertNotIn("input_value", result.stdout + result.stderr)

    def test_candidate_block_checks_aggregate_traffic_and_revision_identity(self) -> None:
        result = self._run_block(
            "candidate_traffic_total=", KALORIES_SECRET_VERSION="7"
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

        service = json.loads((self.fixture_dir / "service.json").read_text())
        service["status"]["traffic"].append(
            {"revisionName": REVISION, "percent": 1}
        )
        self._write("service", service)
        result = self._run_block(
            "candidate_traffic_total=", KALORIES_SECRET_VERSION="7"
        )
        self.assertNotEqual(0, result.returncode)
        self.assertIn("NO-GO: candidate revision traffic is not zero", result.stdout)

        self._write_defaults()
        revision = json.loads((self.fixture_dir / "revision.json").read_text())
        revision["metadata"]["name"] = "kalories-00099-wrong"
        self._write("revision", revision)
        result = self._run_block(
            "candidate_traffic_total=", KALORIES_SECRET_VERSION="7"
        )
        self.assertNotEqual(0, result.returncode)
        self.assertIn("NO-GO: immutable candidate revision is noncompliant", result.stdout)

    def test_candidate_rejects_missing_or_non_numeric_percent_and_bad_tag_url(self) -> None:
        for bad_percent in (None, "0"):
            with self.subTest(percent=bad_percent):
                self._write_defaults()
                service = json.loads(
                    (self.fixture_dir / "service.json").read_text(encoding="utf-8")
                )
                tag_entry = service["status"]["traffic"][0]
                if bad_percent is None:
                    tag_entry.pop("percent")
                else:
                    tag_entry["percent"] = bad_percent
                self._write("service", service)
                result = self._run_block(
                    "candidate_traffic_total=", KALORIES_SECRET_VERSION="7"
                )
                self.assertNotEqual(0, result.returncode)
                self.assertIn("NO-GO: candidate traffic schema is invalid", result.stdout)

        for bad_url in (
            "http://localhost/candidate",
            "https://bad..host.example/candidate",
            "https://-bad.example/candidate",
        ):
            with self.subTest(url=bad_url):
                self._write_defaults()
                service = json.loads(
                    (self.fixture_dir / "service.json").read_text(encoding="utf-8")
                )
                service["status"]["traffic"][0]["url"] = bad_url
                self._write("service", service)
                result = self._run_block(
                    "candidate_traffic_total=", KALORIES_SECRET_VERSION="7"
                )
                self.assertNotEqual(0, result.returncode)
                self.assertIn("NO-GO: candidate tag URL is invalid", result.stdout)

    def test_quota_block_rejects_pending_partial_and_wrong_dimensions(self) -> None:
        base_env = {
            "KALORIES_RPD_QUOTA_ID": "verified-rpd-id",
            "KALORIES_RPD_DIMENSIONS_JSON": json.dumps(self.dimensions),
        }
        result = self._run_block("quota_readback_json=", **base_env)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

        bad_states = [
            {"reconciling": True},
            {"quotaConfig": {"grantedValue": "199", "preferredValue": "200"}},
            {"quotaConfig": {"grantedValue": "200", "preferredValue": "199"}},
            {"dimensions": {"model": "wrong"}},
            {"service": "wrong.googleapis.com"},
            {"quotaId": "wrong-quota-id"},
            {
                "name": (
                    "projects/123456789/locations/global/quotaPreferences/"
                    "wrong-preference"
                )
            },
        ]
        for changes in bad_states:
            with self.subTest(changes=changes):
                self._write_defaults()
                quota = json.loads(
                    (self.fixture_dir / "quota-readback.json").read_text()
                )
                quota.update(changes)
                self._write("quota-readback", quota)
                result = self._run_block("quota_readback_json=", **base_env)
                self.assertNotEqual(0, result.returncode)
                self.assertIn(
                    "NO-GO: quota preference is pending, partial, or mismatched",
                    result.stdout,
                )

        calls = self.calls.read_text(encoding="utf-8")
        describe_call = next(
            line
            for line in calls.splitlines()
            if line.startswith("beta quotas preferences describe ")
        )
        self.assertNotIn("--service", describe_call)
        self.assertNotIn("--quota-id", describe_call)

    def test_budget_rejects_missing_or_forecast_spend_basis(self) -> None:
        result = self._run_block(
            "budget_readback_json=", KALORIES_MONTHLY_BUDGET_AMOUNT="1000JPY"
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

        for basis in (None, "FORECASTED_SPEND"):
            with self.subTest(basis=basis):
                self._write_defaults()
                budget = json.loads(
                    (self.fixture_dir / "budget-readback.json").read_text(
                        encoding="utf-8"
                    )
                )
                if basis is None:
                    budget["thresholdRules"][0].pop("spendBasis")
                else:
                    budget["thresholdRules"][0]["spendBasis"] = basis
                self._write("budget-readback", budget)
                result = self._run_block(
                    "budget_readback_json=",
                    KALORIES_MONTHLY_BUDGET_AMOUNT="1000JPY",
                )
                self.assertNotEqual(0, result.returncode)
                self.assertIn("NO-GO: budget alert read-back is mismatched", result.stdout)

    def test_post_revocation_legacy_rollback_guard_never_changes_traffic(self) -> None:
        env = {
            "KALORIES_OLD_KEY_RESOURCE": (
                "projects/123456789/locations/global/keys/old-key"
            ),
            "KALORIES_OLD_KEY_REVOKED": "yes",
        }
        result = self._run_block("legacy_rollback_guard=", **env)
        self.assertNotEqual(0, result.returncode)
        self.assertIn(
            "NO-GO: post-revocation legacy rollback is forbidden", result.stdout
        )
        self.assertNotIn("run services update-traffic", self.calls.read_text())

        self.calls.write_text("", encoding="utf-8")
        env["KALORIES_OLD_KEY_REVOKED"] = "no"
        result = self._run_block(
            "legacy_rollback_guard=", FAKE_OLD_KEY_REVOKED="1", **env
        )
        self.assertNotEqual(0, result.returncode)
        self.assertIn(
            "NO-GO: post-revocation legacy rollback is forbidden", result.stdout
        )
        self.assertNotIn("run services update-traffic", self.calls.read_text())

        self.calls.write_text("", encoding="utf-8")
        result = self._run_block("legacy_rollback_guard=", **env)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn(
            "--to-revisions=kalories-00003-djq=100",
            self.calls.read_text(encoding="utf-8"),
        )

        self.calls.write_text("", encoding="utf-8")
        legacy_revision = json.loads(
            (self.fixture_dir / "legacy-revision.json").read_text(encoding="utf-8")
        )
        legacy_revision["spec"]["containers"][0]["env"][0]["value"] = (
            SENTINEL + "_OTHER"
        )
        self._write("legacy-revision", legacy_revision)
        result = self._run_block("legacy_rollback_guard=", **env)
        self.assertNotEqual(0, result.returncode)
        self.assertIn(
            "NO-GO: legacy revision credential does not match rollback key",
            result.stdout,
        )
        self.assertNotIn("run services update-traffic", self.calls.read_text())

        self.calls.write_text("", encoding="utf-8")
        self._write_defaults()
        env["KALORIES_OLD_KEY_RESOURCE"] = (
            "projects/123456789/locations/global/keys/replacement-key"
        )
        result = self._run_block("legacy_rollback_guard=", **env)
        self.assertNotEqual(0, result.returncode)
        self.assertIn("NO-GO: legacy rollback key identity is invalid", result.stdout)
        self.assertNotIn("run services update-traffic", self.calls.read_text())

    def test_promotion_failure_stops_before_exact_postcheck(self) -> None:
        replacement = ("scripts/check-testflight-backend.sh", "fake-postcheck")
        env = {
            "KALORIES_CANDIDATE_REVISION": REVISION,
            "FAKE_EXPECTED_REVISION": REVISION,
        }
        result = self._run_block(
            "promotion_json=", replace=replacement, FAKE_PROMOTION_EXIT="4", **env
        )
        self.assertNotEqual(0, result.returncode)
        self.assertIn("NO-GO: exact candidate promotion failed", result.stdout)
        self.assertNotIn("postcheck-called", self.calls.read_text())

        self.calls.write_text("", encoding="utf-8")
        result = self._run_block("promotion_json=", replace=replacement, **env)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn("postcheck-called", self.calls.read_text())


if __name__ == "__main__":
    unittest.main()
