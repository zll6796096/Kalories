#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly EXPECTED_BUNDLE_ID="com.ryuaistudio.kalories"
readonly EXPECTED_PROJECT_ID="zhang23-23"
readonly EXPECTED_FIREBASE_VERSION="12.17.0"
readonly FIREBASE_PLIST="${ROOT_DIR}/ios/Kalories/Resources/GoogleService-Info.plist"

local_only=false
app_bundle=''
while (($# > 0)); do
  case "$1" in
    --local)
      local_only=true
      shift
      ;;
    --app)
      if (($# < 2)); then
        printf '%s\n' 'NO-GO: --app requires one app bundle path'
        exit 64
      fi
      app_bundle="$2"
      shift 2
      ;;
    *)
      printf '%s\n' 'usage: check-ios-app-check-release.sh [--local] [--app APP_BUNDLE]'
      exit 64
      ;;
  esac
done

python_bin="${KALORIES_PYTHON:-}"
if [[ -z "${python_bin}" && -x "${ROOT_DIR}/.venv/bin/python" ]]; then
  python_bin="${ROOT_DIR}/.venv/bin/python"
elif [[ -z "${python_bin}" ]]; then
  python_bin="$(command -v python3 || true)"
fi
if [[ -z "${python_bin}" ]] || ! command -v plutil >/dev/null 2>&1 ||
  ! command -v rg >/dev/null 2>&1; then
  printf '%s\n' 'NO-GO: python3, plutil, and rg are required'
  exit 1
fi

"${python_bin}" - "${ROOT_DIR}" "${EXPECTED_FIREBASE_VERSION}" <<'PY'
from __future__ import annotations

import json
import plistlib
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
expected_version = sys.argv[2]
project_yaml = (root / "ios/project.yml").read_text(encoding="utf-8")
project_file = (
    root / "ios/Kalories.xcodeproj/project.pbxproj"
).read_text(encoding="utf-8")
resolved = json.loads(
    (
        root
        / "ios/Kalories.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    ).read_text(encoding="utf-8")
)

products = sorted(re.findall(r"^\s+product: (Firebase\w+)\s*$", project_yaml, re.M))
if products != ["FirebaseAppCheck", "FirebaseCore"]:
    raise SystemExit("NO-GO: direct Firebase products are not exactly Core and App Check")
if f"exactVersion: {expected_version}" not in project_yaml:
    raise SystemExit("NO-GO: Firebase Apple SDK is not exactly pinned")

firebase_pins = [
    pin for pin in resolved.get("pins", []) if pin.get("identity") == "firebase-ios-sdk"
]
if len(firebase_pins) != 1 or firebase_pins[0].get("state", {}).get("version") != expected_version:
    raise SystemExit("NO-GO: resolved Firebase Apple SDK version is mismatched")

if sorted(set(re.findall(r"productName = (Firebase\w+);", project_file))) != [
    "FirebaseAppCheck",
    "FirebaseCore",
]:
    raise SystemExit("NO-GO: generated project Firebase products are not exact")
if "PrivacyInfo.xcprivacy in Resources" not in project_file:
    raise SystemExit("NO-GO: app privacy manifest is not packaged")

with (root / "ios/Kalories/Kalories.entitlements").open("rb") as source:
    entitlements = plistlib.load(source)
if entitlements != {
    "com.apple.developer.devicecheck.appattest-environment": "production"
}:
    raise SystemExit("NO-GO: App Attest entitlement is not exactly production")

with (
    root / "ios/Kalories/Resources/PrivacyInfo.xcprivacy"
).open("rb") as source:
    privacy = plistlib.load(source)
if privacy.get("NSPrivacyTracking") is not False:
    raise SystemExit("NO-GO: app privacy manifest does not disable tracking")
PY

credential_scan_args=(
  -n
  --hidden
  --glob '!**/*Tests*'
  --glob '!docs/**'
  --glob '!tests/**'
  --glob '!requirements.txt'
  --glob '!package-lock.json'
  -e '-----BEGIN (RSA |EC )?PRIVATE KEY-----'
  -e '"type"[[:space:]]*:[[:space:]]*"service_account"'
  -e 'AIza[0-9A-Za-z_-]{35}'
  -e 'FIREBASE_APP_CHECK_DEBUG_TOKEN[[:space:]]*='
)
if rg "${credential_scan_args[@]}" \
  "${ROOT_DIR}/api" "${ROOT_DIR}/lib" \
  "${ROOT_DIR}/public" "${ROOT_DIR}/src" >/dev/null 2>&1 ||
  rg "${credential_scan_args[@]}" \
    --glob '!Kalories/Resources/GoogleService-Info.plist' \
    "${ROOT_DIR}/ios" >/dev/null 2>&1; then
  printf '%s\n' 'NO-GO: release source contains forbidden credential material'
  exit 1
fi

if [[ -f "${FIREBASE_PLIST}" ]]; then
  "${python_bin}" "${SCRIPT_DIR}/validate_firebase_plists.py" --source "${FIREBASE_PLIST}"
fi

if [[ -n "${app_bundle}" ]]; then
  if [[ ! -d "${app_bundle}" || ! -f "${app_bundle}/Info.plist" ||
    ! -f "${app_bundle}/PrivacyInfo.xcprivacy" ]]; then
    printf '%s\n' 'NO-GO: built app bundle or required manifest is missing'
    exit 1
  fi
  executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${app_bundle}/Info.plist" 2>/dev/null || true)"
  if [[ -z "${executable_name}" || ! -f "${app_bundle}/${executable_name}" ]]; then
    printf '%s\n' 'NO-GO: built app executable is unavailable'
    exit 1
  fi
  if strings "${app_bundle}/${executable_name}" | rg -q \
    'FirebaseAnalytics|FirebaseAuth|FirebaseCrashlytics|AppCheckDebugProviderFactory|FIRAnalytics|FIRAuth|FIRCrashlytics'; then
    printf '%s\n' 'NO-GO: Release binary contains a forbidden Firebase product or debug provider'
    exit 1
  fi
fi

if [[ "${local_only}" == true ]]; then
  printf '%s\n' 'EXTERNAL CONFIGURATION: not verified'
  printf '%s\n' 'PASS: local iOS App Check release checks'
  exit 0
fi

if [[ ! -f "${FIREBASE_PLIST}" ]]; then
  printf '%s\n' 'BLOCKED_BY_EXTERNAL_CONFIG: GoogleService-Info.plist is missing'
  exit 2
fi
if [[ -z "${KALORIES_EXPECTED_FIREBASE_IOS_APP_ID:-}" ]]; then
  printf '%s\n' 'BLOCKED_BY_EXTERNAL_CONFIG: expected Firebase iOS app ID is missing'
  exit 2
fi
if [[ -z "${app_bundle}" ]]; then
  printf '%s\n' 'BLOCKED_BY_EXTERNAL_CONFIG: distribution app bundle is required'
  exit 2
fi
if ! command -v codesign >/dev/null 2>&1; then
  printf '%s\n' 'NO-GO: codesign is required for distribution verification'
  exit 1
fi

packaged_firebase_plist="${app_bundle}/GoogleService-Info.plist"
if [[ ! -f "${packaged_firebase_plist}" ]]; then
  printf '%s\n' 'NO-GO: distribution app does not package Firebase configuration'
  exit 1
fi

"${python_bin}" "${SCRIPT_DIR}/validate_firebase_plists.py" \
  --source "${FIREBASE_PLIST}" \
  --packaged "${packaged_firebase_plist}" \
  --app-info "${app_bundle}/Info.plist" \
  --expected-bundle "${EXPECTED_BUNDLE_ID}" \
  --expected-project "${EXPECTED_PROJECT_ID}" \
  --expected-app "${KALORIES_EXPECTED_FIREBASE_IOS_APP_ID}"

if ! codesign --verify --deep --strict "${app_bundle}" >/dev/null 2>&1; then
  printf '%s\n' 'NO-GO: distribution app signature is invalid'
  exit 1
fi

distribution_tmp="$(mktemp -d)"
distribution_entitlements_plist="${distribution_tmp}/distribution-entitlements.plist"
cleanup_distribution() {
  if [[ -f "${distribution_entitlements_plist}" ]]; then
    unlink -- "${distribution_entitlements_plist}" || true
  fi
  if [[ -d "${distribution_tmp}" ]]; then
    rmdir -- "${distribution_tmp}" || true
  fi
}
trap cleanup_distribution EXIT
if ! codesign --display --entitlements :- "${app_bundle}" \
  >"${distribution_entitlements_plist}" 2>/dev/null; then
  printf '%s\n' 'NO-GO: signed distribution entitlements are unavailable'
  exit 1
fi
"${python_bin}" - "${distribution_entitlements_plist}" <<'PY'
from __future__ import annotations

import plistlib
import sys
from pathlib import Path

with Path(sys.argv[1]).open("rb") as source:
    entitlements = plistlib.load(source)
if entitlements.get(
    "com.apple.developer.devicecheck.appattest-environment"
) != "production":
    raise SystemExit("NO-GO: signed App Attest entitlement is not production")
PY
cleanup_distribution
trap - EXIT

printf '%s\n' 'PASS: distribution iOS App Check release checks'
