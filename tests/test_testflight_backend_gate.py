"""Regression tests for the read-only TestFlight backend release gate.

The dynamic tests replace gcloud and curl with local fakes.  They never call a
cloud mutation or a real provider, and sentinel payloads must never reach the
gate's output.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
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
ACCESS_FINDING = "application-layer access protection is not verified"
PUBLIC_ACCESS_FINDING = "public access or application-layer protection is not compliant"


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
        self.iam = {"etag": "etag-one", "bindings": []}
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
printf '%s' "${FAKE_CURL_STATUS:-200}"
exit "${FAKE_CURL_EXIT:-0}"
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

    def _assert_only_access_no_go(self, result: subprocess.CompletedProcess[str]) -> None:
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(f"NO-GO: {ACCESS_FINDING}", result.stdout)
        reasons = [line for line in result.stdout.splitlines() if line.startswith("NO-GO: ")]
        self.assertEqual(
            reasons,
            [
                "NO-GO: TestFlight backend preflight",
                f"NO-GO: {ACCESS_FINDING}",
            ],
        )

    def test_compliant_revision_still_blocks_without_verified_access_architecture(self) -> None:
        self._assert_only_access_no_go(self._run())
        self.assertIn(f"run revisions describe {REVISION}", self.calls.read_text())
        self.assertIn("run services get-iam-policy kalories", self.calls.read_text())

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
                    ],
                }
            ],
        }
        self._assert_only_access_no_go(self._run())

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
        self._assert_only_access_no_go(self._run())

    def test_expected_revision_enables_fail_closed_post_promotion_check(self) -> None:
        result = self._run(KALORIES_EXPECTED_REVISION="kalories-99999-wrong")
        self.assertIn(
            "NO-GO: expected production revision is not serving 100 percent",
            result.stdout,
        )
        self._assert_only_access_no_go(self._run(KALORIES_EXPECTED_REVISION=REVISION))

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

    def test_public_invoker_is_boolean_no_go_and_policy_is_never_printed(self) -> None:
        self.iam = {
            "etag": "etag-two",
            "bindings": [
                {
                    "role": "roles/run.invoker",
                    "members": ["allUsers", f"serviceAccount:{SENTINEL}"],
                }
            ],
        }
        result = self._run()
        self.assertIn(f"NO-GO: {PUBLIC_ACCESS_FINDING}", result.stdout)
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
        ]
        for payload in sensitive_payloads:
            with self.subTest(payload=list(payload)):
                self.logs = self.logs[:3] + [payload]
                result = self._run()
                self.assertIn(
                    "NO-GO: Cloud Run logs contain sensitive application data",
                    result.stdout,
                )

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

    def test_no_automatic_public_access_or_unconfirmed_identity_architecture(self) -> None:
        self.assertNotIn("--allow-unauthenticated", self.runbook + self.readme)
        self.assertIn("allUsers", self.runbook)
        self.assertRegex(self.runbook, r"not access\s+control")
        self.assertIn("Task 6", self.runbook)

    def test_candidate_logs_are_nonempty_targeted_and_recursively_scanned(self) -> None:
        self.assertIn("candidate_logs_json", self.runbook)
        self.assertIn("type == \"array\" and length > 0", self.runbook)
        self.assertIn("x-goog-api-key", self.runbook)
        self.assertIn("providerResponse", self.runbook)
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

    def test_quota_create_has_complete_fail_closed_readback(self) -> None:
        self.assertIn("quota_readback_json", self.runbook)
        self.assertIn("reconciling == false", self.runbook)
        self.assertIn("grantedValue", self.runbook)
        self.assertIn("preferredValue", self.runbook)
        self.assertIn("dimensions", self.runbook)

    def test_budget_requires_user_amount_and_exact_readback(self) -> None:
        self.assertIn("KALORIES_MONTHLY_BUDGET_AMOUNT", self.runbook)
        self.assertIn("budget_readback_json", self.runbook)
        self.assertIn("budget alert read-back is mismatched", self.runbook)
        self.assertRegex(self.runbook, r"alert notifies; it neither caps spend")

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
            "gcloud",
            """#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >>"${FAKE_CALLS}"
case "$*" in
  "services api-keys describe kalories-gemini-testflight"*)
    command cat "${FAKE_FIXTURES}/key-metadata.json" ;;
  "services api-keys get-key-string kalories-gemini-testflight"*)
    command cat "${FAKE_FIXTURES}/key-material.json" ;;
  "secrets describe kalories-gemini-api-key"*)
    exit 0 ;;
  "secrets versions add kalories-gemini-api-key"*)
    command cat "${FAKE_FIXTURES}/secret-version-create.json" ;;
  "secrets versions describe "*)
    command cat "${FAKE_FIXTURES}/secret-version-readback.json" ;;
  "run services describe kalories"*)
    command cat "${FAKE_FIXTURES}/service.json" ;;
  "secrets add-iam-policy-binding kalories-gemini-api-key"*)
    command cat "${FAKE_FIXTURES}/iam-mutation.json" ;;
  "secrets get-iam-policy kalories-gemini-api-key"*)
    command cat "${FAKE_FIXTURES}/iam-readback.json" ;;
  "run revisions describe "*)
    command cat "${FAKE_FIXTURES}/revision.json" ;;
  "beta quotas preferences create "*)
    command cat "${FAKE_FIXTURES}/quota-create.json" ;;
  "beta quotas preferences describe "*)
    command cat "${FAKE_FIXTURES}/quota-readback.json" ;;
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
                            ],
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
        quota = {
            "name": (
                "projects/p/locations/global/services/generativelanguage.googleapis.com/"
                "quotaPreferences/kalories-testflight-rpd-200"
            ),
            "reconciling": False,
            "dimensions": self.dimensions,
            "quotaConfig": {"grantedValue": "200", "preferredValue": "200"},
        }
        self._write("quota-create", quota)
        self._write("quota-readback", quota)
        self._write("promotion", {"status": "safe"})

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
        env = os.environ.copy()
        env.update(
            {
                "PATH": f"{self.bin_dir}:{env['PATH']}",
                "FAKE_CALLS": str(self.calls),
                "FAKE_FIXTURES": str(self.fixture_dir),
                "TMPDIR": str(self.tmp_dir),
            }
        )
        env.update(overrides)
        before = set(self.tmp_dir.iterdir())
        result = subprocess.run(
            ["bash", "-s"],
            input=block,
            cwd=ROOT,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(before, set(self.tmp_dir.iterdir()), "runbook temp leaked")
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
