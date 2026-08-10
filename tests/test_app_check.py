"""Unit tests for the Firebase App Check verification boundary."""

from __future__ import annotations

import os
from json import JSONDecodeError
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, call, patch

from jwt import PyJWKClientConnectionError, PyJWKClientError

from lib.app_check import (
    AppCheckRejected,
    AppCheckUnavailable,
    FirebaseAppCheckVerifier,
)


PROJECT_ID = "kalories-project"
IOS_APP_ID = "1:123456789:ios:abcdef123456"
ROOT = Path(__file__).resolve().parents[1]


class FirebaseAppCheckVerifierTests(unittest.TestCase):
    def setUp(self) -> None:
        self.initialize_app = MagicMock(
            return_value=SimpleNamespace(project_id=PROJECT_ID)
        )
        self.verify_token = MagicMock(return_value={"sub": IOS_APP_ID})

    def verifier(self) -> FirebaseAppCheckVerifier:
        return FirebaseAppCheckVerifier(
            initialize_app=self.initialize_app,
            verify_token=self.verify_token,
        )

    def test_missing_or_nonrequired_configuration_fails_closed_without_sdk_calls(self):
        invalid_environments = (
            {},
            {
                "APP_CHECK_ENFORCEMENT": "required",
                "FIREBASE_IOS_APP_ID": IOS_APP_ID,
            },
            {
                "APP_CHECK_ENFORCEMENT": "required",
                "FIREBASE_PROJECT_ID": PROJECT_ID,
            },
            {
                "APP_CHECK_ENFORCEMENT": "optional",
                "FIREBASE_PROJECT_ID": PROJECT_ID,
                "FIREBASE_IOS_APP_ID": IOS_APP_ID,
            },
        )

        for environment in invalid_environments:
            with self.subTest(environment=environment):
                self.initialize_app.reset_mock()
                self.verify_token.reset_mock()
                with patch.dict(os.environ, environment, clear=True):
                    with self.assertRaises(AppCheckUnavailable):
                        self.verifier().verify("opaque-token")

                self.initialize_app.assert_not_called()
                self.verify_token.assert_not_called()

    def test_valid_exact_app_token_uses_named_lazy_project_configuration(self):
        environment = {
            "APP_CHECK_ENFORCEMENT": "required",
            "FIREBASE_PROJECT_ID": f"  {PROJECT_ID}  ",
            "FIREBASE_IOS_APP_ID": f"  {IOS_APP_ID}  ",
        }
        verifier = self.verifier()

        with patch.dict(os.environ, environment, clear=True):
            verifier.verify("first-token")
            verifier.verify("second-token")

        self.initialize_app.assert_called_once_with(
            options={"projectId": PROJECT_ID},
            name="kalories-app-check",
        )
        app = self.initialize_app.return_value
        self.assertEqual(
            [
                call("first-token", app=app),
                call("second-token", app=app),
            ],
            self.verify_token.call_args_list,
        )

    def test_wrong_or_malformed_app_claim_is_rejected(self):
        invalid_claims = (
            {},
            {"sub": ""},
            {"sub": "1:123456789:ios:wrong"},
            {"sub": [IOS_APP_ID]},
            "not-a-mapping",
        )
        environment = {
            "APP_CHECK_ENFORCEMENT": "required",
            "FIREBASE_PROJECT_ID": PROJECT_ID,
            "FIREBASE_IOS_APP_ID": IOS_APP_ID,
        }

        for claims in invalid_claims:
            with self.subTest(claims=claims):
                self.verify_token.return_value = claims
                with patch.dict(os.environ, environment, clear=True):
                    with self.assertRaises(AppCheckRejected):
                        self.verifier().verify("opaque-token")

    def test_invalid_token_is_rejected_but_sdk_or_configuration_failure_is_unavailable(self):
        environment = {
            "APP_CHECK_ENFORCEMENT": "required",
            "FIREBASE_PROJECT_ID": PROJECT_ID,
            "FIREBASE_IOS_APP_ID": IOS_APP_ID,
        }

        with patch.dict(os.environ, environment, clear=True):
            self.verify_token.side_effect = ValueError("invalid token details")
            with self.assertRaises(AppCheckRejected) as rejected:
                self.verifier().verify("opaque-token")

            self.verify_token.side_effect = RuntimeError("jwks unavailable details")
            with self.assertRaises(AppCheckUnavailable) as unavailable:
                self.verifier().verify("opaque-token")

        self.assertEqual("app check rejected", str(rejected.exception))
        self.assertEqual("app check unavailable", str(unavailable.exception))
        self.assertNotIn("details", str(rejected.exception))
        self.assertNotIn("details", str(unavailable.exception))

    def test_unknown_signing_key_is_rejected_but_jwks_connection_failure_is_unavailable(self):
        environment = {
            "APP_CHECK_ENFORCEMENT": "required",
            "FIREBASE_PROJECT_ID": PROJECT_ID,
            "FIREBASE_IOS_APP_ID": IOS_APP_ID,
        }

        with patch.dict(os.environ, environment, clear=True):
            self.verify_token.side_effect = PyJWKClientError(
                'Unable to find a signing key that matches: "unknown-kid"'
            )
            with self.assertRaises(AppCheckRejected):
                self.verifier().verify("opaque-token")

            self.verify_token.side_effect = PyJWKClientError(
                "The JWKS endpoint did not return a JSON object"
            )
            with self.assertRaises(AppCheckUnavailable):
                self.verifier().verify("opaque-token")

            self.verify_token.side_effect = JSONDecodeError(
                "invalid JWKS JSON", "not-json", 0
            )
            with self.assertRaises(AppCheckUnavailable):
                self.verifier().verify("opaque-token")

            self.verify_token.side_effect = PyJWKClientConnectionError(
                "network details"
            )
            with self.assertRaises(AppCheckUnavailable):
                self.verifier().verify("opaque-token")


class FirebaseAdminDependencyTests(unittest.TestCase):
    def test_firebase_admin_is_a_direct_exactly_locked_runtime_dependency(self):
        direct_dependencies = {
            line.strip()
            for line in (ROOT / "requirements.in").read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        }
        deployment_lock = (
            ROOT / "requirements.txt"
        ).read_text(encoding="utf-8").splitlines()

        self.assertIn("firebase-admin==7.5.0", direct_dependencies)
        self.assertEqual(
            ["firebase-admin==7.5.0"],
            [line for line in deployment_lock if line.startswith("firebase-admin==")],
        )


if __name__ == "__main__":
    unittest.main()
