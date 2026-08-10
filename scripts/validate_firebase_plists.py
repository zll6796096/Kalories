#!/usr/bin/env python3
"""Fail-closed validation for source and packaged Firebase iOS plists."""

from __future__ import annotations

import argparse
import plistlib
import re
from pathlib import Path
from typing import Any


PUBLIC_API_KEY = re.compile(r"AIza[0-9A-Za-z_-]{35}")
FORBIDDEN_KEYS = {
    "privatekey",
    "privatekeyid",
    "clientsecret",
    "serviceaccount",
    "firebaseappcheckdebugtoken",
    "googleapplicationcredentials",
}
FORBIDDEN_TEXT = re.compile(
    r"-----BEGIN (?:RSA |EC )?PRIVATE KEY-----"
    r"|FIREBASE_APP_CHECK_DEBUG_TOKEN\s*="
    r"|AIza[0-9A-Za-z_-]{35}"
)


class ValidationError(Exception):
    """A safe, non-secret validation failure."""


def validate_value(value: Any, path: tuple[str, ...]) -> None:
    if isinstance(value, dict):
        for key, nested in value.items():
            if not isinstance(key, str):
                raise ValidationError("Firebase plist contains a non-string key")
            nested_path = (*path, key)
            normalized_key = re.sub(r"[^a-z0-9]", "", key.lower())
            if normalized_key in FORBIDDEN_KEYS:
                raise ValidationError("Firebase plist contains forbidden credential material")
            if nested_path == ("API_KEY",):
                if not isinstance(nested, str) or PUBLIC_API_KEY.fullmatch(nested) is None:
                    raise ValidationError("Firebase public API_KEY is invalid")
                continue
            validate_value(nested, nested_path)
    elif isinstance(value, list):
        for index, nested in enumerate(value):
            validate_value(nested, (*path, str(index)))
    elif isinstance(value, str):
        lowered_value = value.lower()
        if (
            "service_account" in lowered_value
            or "firebase_app_check_debug_token" in lowered_value
            or FORBIDDEN_TEXT.search(value)
        ):
            raise ValidationError("Firebase plist contains forbidden credential material")


def load_and_validate(path: Path) -> dict[str, Any]:
    try:
        with path.open("rb") as source:
            config = plistlib.load(source)
    except (OSError, plistlib.InvalidFileException) as error:
        raise ValidationError("Firebase plist is unavailable or invalid") from error
    if not isinstance(config, dict):
        raise ValidationError("Firebase plist root is not a dictionary")
    validate_value(config, ())
    api_key = config.get("API_KEY")
    if not isinstance(api_key, str) or PUBLIC_API_KEY.fullmatch(api_key) is None:
        raise ValidationError("Firebase public API_KEY is missing")
    return config


def validate_distribution(
    source_config: dict[str, Any],
    *,
    packaged_path: Path,
    app_info_path: Path,
    expected_bundle: str,
    expected_project: str,
    expected_app: str,
) -> None:
    packaged_config = load_and_validate(packaged_path)
    configs = [source_config, packaged_config]
    try:
        with app_info_path.open("rb") as source:
            info = plistlib.load(source)
    except (OSError, plistlib.InvalidFileException) as error:
        raise ValidationError("built app Info.plist is unavailable or invalid") from error
    if not isinstance(info, dict) or info.get("CFBundleIdentifier") != expected_bundle:
        raise ValidationError("built app bundle ID is mismatched")

    expected = {
        "BUNDLE_ID": expected_bundle,
        "PROJECT_ID": expected_project,
        "GOOGLE_APP_ID": expected_app,
    }
    for label, config in (("source", configs[0]), ("packaged", configs[1])):
        for key, expected_value in expected.items():
            if config.get(key) != expected_value:
                raise ValidationError(f"{label} Firebase {key} is mismatched")
        for key in (
            "IS_ANALYTICS_ENABLED",
            "IS_ADS_ENABLED",
            "IS_SIGNIN_ENABLED",
            "IS_GCM_ENABLED",
        ):
            if config.get(key) is True:
                raise ValidationError(f"{label} Firebase config enables {key}")
    if configs[1] != configs[0]:
        raise ValidationError("packaged Firebase configuration differs from source")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--packaged", type=Path)
    parser.add_argument("--app-info", type=Path)
    parser.add_argument("--expected-bundle")
    parser.add_argument("--expected-project")
    parser.add_argument("--expected-app")
    arguments = parser.parse_args()
    distribution_values = (
        arguments.packaged,
        arguments.app_info,
        arguments.expected_bundle,
        arguments.expected_project,
        arguments.expected_app,
    )
    if any(value is not None for value in distribution_values) and not all(
        value is not None for value in distribution_values
    ):
        parser.error("distribution validation arguments must be provided together")
    return arguments


def main() -> int:
    arguments = parse_arguments()
    try:
        source_config = load_and_validate(arguments.source)
        if arguments.packaged is not None:
            validate_distribution(
                source_config,
                packaged_path=arguments.packaged,
                app_info_path=arguments.app_info,
                expected_bundle=arguments.expected_bundle,
                expected_project=arguments.expected_project,
                expected_app=arguments.expected_app,
            )
    except ValidationError as error:
        print(f"NO-GO: {error}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
