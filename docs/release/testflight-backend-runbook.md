# TestFlight backend release runbook

This is a fail-closed evidence ledger, not authorization to deploy. Local code,
the read-only production preflight, access architecture, a zero-traffic
candidate, provider privacy, quota, budget, a real-image request, safe logs,
promotion, credential revocation, rollback, TestFlight upload, TestFlight
processing, and public App Store release are separate gates. A PASS at one gate
never advances another gate.

The Firebase App Check and Apple App Attest design is implemented and tested
locally. That does not authorize attaching Firebase to the Cloud project,
registering an Apple/Firebase app, changing Apple capabilities, deploying,
changing traffic, or uploading TestFlight. Every external mutation below still
requires separate approval of its exact resource identity and effect.

## Fixed scope and identifiers

| Item | Fixed value |
| --- | --- |
| Project | `zhang23-23` |
| Region | `asia-northeast1` |
| Cloud Run service | `kalories` |
| Apple bundle ID | `com.ryuaistudio.kalories` |
| Firebase iOS app ID | `1:788259830737:ios:a4459f14b5e8046297bef0`; pass this exact value as `KALORIES_EXPECTED_FIREBASE_IOS_APP_ID` |
| App Check mode | `APP_CHECK_ENFORCEMENT=required`; App Attest only for TestFlight/Release |
| Model | `gemini-3.6-flash` |
| Replacement API key ID | `kalories-gemini-testflight-v2`; explicitly approved after `kalories-gemini-testflight` was soft-deleted and forbidden from restoration |
| Secret Manager secret | `kalories-gemini-api-key`; version `2` is enabled, version `1` is disabled, and the runtime accessor is exact |
| Preferred Gemini limit | RPD `200`, only after the exact enforceable quota ID and dimensions are verified |
| Controlled audience | Invited testers who are 18 or older |

Never print, paste, manually compare, or screenshot an API key value, request
image, provider response, IAM identity list, or log content. Never commit a
Gemini or other private API key. The only committed key exception is the public
Firebase `API_KEY` inside the validated `GoogleService-Info.plist`; it is public
configuration, not authorization. The only key comparison below is a
private automated equality check over mode-600 files; it emits only a fixed boolean
verdict and deletes both files. Use `set -euo pipefail`, no shell tracing,
`umask 077`, exact temporary paths, fixed safe findings, and cleanup traps.

## Read-only baseline

Captured at `2026-08-08 08:38:28 JST (+0900)`; rerun immediately before any
future checkpoint because live state can drift.

| Evidence | Observed state | Gate result |
| --- | --- | --- |
| Active gcloud account | present; identity omitted | VERIFIED |
| Ready/production revision | `kalories-00003-djq` | VERIFIED |
| Production traffic | `kalories-00003-djq=100%` | VERIFIED |
| Service URL | `https://kalories-sxielk4wua-an.a.run.app` | VERIFIED |
| maxScale | `20` | NO-GO; must be exactly `1` |
| `GEMINI_API_KEY` plaintext/secret-backed | `true` / `false` | NO-GO |
| `GEMINI_MODEL` compliant | `false` | NO-GO |
| Cloud Run public invoker | `true`; policy identities omitted | required for public pages; not sufficient for analysis access |
| Machine-verifiable application-layer access protection | absent in live revision | NO-GO; local Firebase App Check implementation does not change production |
| `GET /health` | HTTP 200 | transport evidence only |
| `GET /privacy/` | HTTP 404 | NO-GO |
| `GET /support/` | HTTP 404 | NO-GO |
| Targeted latest log read after endpoint probes | valid empty array | NO-GO; target request logs were not collected in this snapshot |

The current state is an expected production `NO-GO`, not a failed local task.
Run the safe read-only gate and record only its fixed findings:

```bash
KALORIES_EXPECTED_FIREBASE_IOS_APP_ID='the-approved-firebase-ios-app-id' \
  scripts/check-testflight-backend.sh
```

That snapshot exited `1` with exactly these safe findings:

- `Cloud Run production revision maxScale is not exactly 1`
- `GEMINI_API_KEY is not exactly one pinned secret-backed entry`
- `GEMINI_MODEL is not exactly one direct value set to gemini-3.6-flash`
- `APP_CHECK_ENFORCEMENT is not exactly required`
- `FIREBASE_PROJECT_ID is not exactly zhang23-23`
- `FIREBASE_IOS_APP_ID does not match the approved app`
- `App Check no-token POST did not return HTTP 401 for /api/analyze`
- `App Check no-token POST did not return HTTP 401 for /`
- `/privacy did not return HTTP 200`
- `/support did not return HTTP 200`
- `Cloud Run logs are not a nonempty JSON array`

No environment value, IAM identity/policy, or log entry was printed.

For the post-promotion identity check, the same gate accepts only a specific
expected production revision:

```bash
KALORIES_EXPECTED_REVISION="${KALORIES_CANDIDATE_REVISION}" \
KALORIES_EXPECTED_FIREBASE_IOS_APP_ID="${KALORIES_FIREBASE_IOS_APP_ID}" \
  scripts/check-testflight-backend.sh
```

It describes the immutable revision actually receiving 100% traffic. It does
not trust the mutable service template or `latestReadyRevisionName`.

## Gate ledger

| Gate | Current state | Required evidence |
| --- | --- | --- |
| Local code/pages | PASS, local only | Full backend and frontend suites, typecheck, build, dependency/import checks, clean commit |
| Read-only production preflight | NO-GO | Fixed findings cleared; immutable production revision and targeted logs verified |
| App Check implementation | PASS, local only | Backend/iOS tests and release scans; no external registration implied |
| Firebase iOS registration / App Attest config | PASS | Exact project/app/bundle/team read-back, App Attest TTL `3600s`, validated real configuration file |
| Apple Developer signing assets | BLOCKED | App ID capability and a matching valid App Store profile must be verified separately |
| Required Cloud B1 APIs | PASS | `cloudquotas`, `cloudbilling`, and `billingbudgets` enabled and read back |
| Restricted credential foundation | PASS | v2 active with exactly one Gemini API target; Secret version `2` enabled and privately matched; exact runtime accessor read back |
| Cloud mutation authorization | BLOCKED | Fresh approval of every mutation listed below |
| Provider privacy | UNVERIFIED | Paid tier, developer logging disabled, dataset sharing disabled, official terms evidence |
| Enforceable provider quota | UNVERIFIED | Exact quota ID/dimensions and settled granted/preferred RPD `200` |
| Budget alert | UNVERIFIED | Later user-approved amount and read-back; alert does not cap spend |
| Zero-traffic candidate | PENDING | Tag resolves once to immutable revision; aggregate revision traffic is exactly `0` |
| Real-image/schema/latency/cost | UNVERIFIED | Synthetic image, strict real backend contract, under 20s, usage/cost evidence |
| Candidate logs | UNVERIFIED | Nonempty target request logs and recursive safe scan |
| Promotion | PENDING | Every preceding gate PASS; exact candidate promoted and postchecked |
| Old-key revocation | PENDING | Only after promotion and replacement-key health/log evidence |
| Rollback | LIMITED PRE-REVOCATION ONLY | Legacy revision is unavailable after old-key revocation; no pinned-secret rollback revision exists yet |
| TestFlight upload | OUTSIDE BACKEND TASK | Separate signed-build upload evidence |
| TestFlight processing/invites | OUTSIDE BACKEND TASK | Processing complete; invited 18+ testers only |
| Public App Store | OUT OF SCOPE / UNRESOLVED | Private support, age/compliance, privacy, review, release and storefront gates |

No `PENDING`, `UNVERIFIED`, `BLOCKED`, or out-of-scope row is a PASS.

## 1. Clean local candidate

Run from the intended clean worktree and record the commit:

```bash
npm test
npm run lint
npm run build
.venv/bin/python -m unittest discover -s tests -p 'test_*.py' -v
.venv/bin/python -m compileall -q api lib tests
.venv/bin/python -c "import api.analyze, lib.nutrition, lib.rate_limit"
uv pip check --python .venv/bin/python
git diff --check
git status --short --branch
```

Local success proves neither deployment nor a real provider request.

## 2. App Check access boundary

The combined service is intentionally reachable through `allUsers` because
health, privacy, support, and static pages are public. Public invocation is not
authorization for paid analysis. The application must enforce Firebase App
Check on both `POST /api/analyze` and compatibility `POST /`, before decoding an
image, taking a rate-limit token, or calling Gemini.

The production preflight requires exact runtime configuration, public pages at
HTTP 200, and a no-token POST returning only HTTP 401 with
`APP_CHECK_FAILED`. A valid debug-token request is a separate candidate gate;
a real TestFlight App Attest request on an iPhone is a later distribution gate.

App Check verifies an authentic registered app instance. It does not identify a
human or prove TestFlight invitation status. Age wording, maxScale `1`, RPD
`200`, the budget alert, and the token bucket remain loss controls and are not
access control.

The preflight reads Cloud Run IAM into a private file and emits only a boolean
finding. Never print an IAM policy or its members.

## 3. Exact external-mutation confirmation

Batch A completed the Firebase portions of items 1 and 2 at
`2026-08-08 17:39:30 JST (+0900)`: Firebase was already active on project
`zhang23-23`; exactly one active iOS app was registered for bundle
`com.ryuaistudio.kalories` and Team ID `YMUG864233`; Firebase App Attest was
read back with TTL `3600s`. The generated public Firebase key has a nonempty
API allowlist and does not allow `generativelanguage.googleapis.com`. It has no
iOS application restriction; Batch A did not modify that restriction. The
validated plist disables Analytics, Ads, Sign-In, and GCM flags and is packaged
only in the app target. Do not repeat the registration. Apple Developer signing
asset changes and every later mutation remain separately gated.

Before any remaining external action, stop and ask the user to confirm each mutation
explicitly:

1. completed/no-op: Firebase was already active on project `zhang23-23`;
2. completed, Firebase only: registered bundle `com.ryuaistudio.kalories` and
   configured App Attest for Team ID `YMUG864233`;
3. completed: enabled and read back only the three approved missing APIs;
4. completed: created and restricted API key
   `kalories-gemini-testflight-v2`;
5. completed: added and privately verified pinned Secret version `2`, while
   version `1` remains disabled;
6. completed: added and read back exactly one runtime service account
   `secretAccessor` binding;
7. update only the named Gemini and Firebase/App Check environment entries,
   plus max instances, concurrency, and timeout, in a zero-traffic candidate;
8. create exact verified quota preference RPD `200`;
9. create the user-approved monthly budget alert;
10. promote the exact immutable candidate revision to 100%;
11. revoke the exact old API key only after promotion succeeds.

Approval of this runbook or the local implementation is not approval for any
item above.

## 4. Required APIs

The workflow requires these exact services:

```bash
required_apis=(
  run.googleapis.com
  cloudbuild.googleapis.com
  artifactregistry.googleapis.com
  logging.googleapis.com
  apikeys.googleapis.com
  generativelanguage.googleapis.com
  secretmanager.googleapis.com
  cloudquotas.googleapis.com
  cloudbilling.googleapis.com
  billingbudgets.googleapis.com
  firebaseappcheck.googleapis.com
)
missing_api=false
for required_api in "${required_apis[@]}"; do
  if gcloud services list \
    --enabled \
    --project=zhang23-23 \
    --filter="config.name=${required_api}" \
    --format='value(config.name)' | rg -qx -F "${required_api}"; then
    printf 'CHECK required API enabled: %s\n' "${required_api}"
  else
    printf 'NO-GO: required API missing: %s\n' "${required_api}"
    missing_api=true
  fi
done
if [[ "${missing_api}" == true ]]; then exit 1; fi
```

A missing API is evidence, not permission to enable it. After exact inventory
and fresh approval, enable only the confirmed names; do not copy a broader
placeholder command.

## 5. Restricted key, pinned secret version, and exact IAM

Execution evidence and the controlled rollback are recorded in
[`cloud-b1-evidence.md`](cloud-b1-evidence.md). Do not restore or reuse
`kalories-gemini-testflight`. The replacement ID
`kalories-gemini-testflight-v2` was explicitly approved on `2026-08-08` and is
the only key ID authorized by this block. The secret must receive a new version;
disabled version `1` must never be re-enabled.

This completed Cloud B1 creation block is retained as a sanitized operational
record. It now fails closed when v2 already exists, so rerunning it cannot add
another Secret version. During the approved first run it kept key material in
mode-600 private files, removed any implicit newline, required a nonempty value
without CR/LF, and read back a concrete enabled secret version. It never pipes a
key through a shell without `pipefail` and never uses `latest`.

```bash
set -euo pipefail
umask 077
secret_tmp="$(mktemp -d)"
key_create_log="${secret_tmp}/key-create.log"
key_metadata_json="${secret_tmp}/key-metadata.json"
key_material_json="${secret_tmp}/key-material.json"
key_material_file="${secret_tmp}/key-material"
secret_version_create_json="${secret_tmp}/secret-version-create.json"
secret_version_readback_json="${secret_tmp}/secret-version-readback.json"
cleanup_secret_material() {
  local secret_file
  for secret_file in \
    "${key_create_log}" \
    "${key_metadata_json}" \
    "${key_material_json}" \
    "${key_material_file}" \
    "${secret_version_create_json}" \
    "${secret_version_readback_json}"; do
    if [[ -f "${secret_file}" ]]; then unlink -- "${secret_file}"; fi
  done
  if [[ -d "${secret_tmp}" ]]; then rmdir -- "${secret_tmp}"; fi
}
trap cleanup_secret_material EXIT

if gcloud services api-keys describe kalories-gemini-testflight-v2 \
  --project=zhang23-23 --format=json >"${key_metadata_json}" 2>/dev/null; then
  printf '%s\n' \
    'NO-GO: replacement key already exists; do not add another secret version'
  exit 1
fi
gcloud services api-keys create \
  --project=zhang23-23 \
  --key-id=kalories-gemini-testflight-v2 \
  --display-name='Kalories Gemini TestFlight v2' \
  --api-target=service=generativelanguage.googleapis.com \
  --format=json >"${key_create_log}" 2>&1
gcloud services api-keys describe kalories-gemini-testflight-v2 \
  --project=zhang23-23 --format=json >"${key_metadata_json}" 2>/dev/null
if ! jq -e '
  (.restrictions.apiTargets // []) as $targets
  | (($targets | length) == 1
     and $targets[0].service == "generativelanguage.googleapis.com")
' "${key_metadata_json}" >/dev/null; then
  printf '%s\n' 'NO-GO: replacement key restriction is not exactly Gemini'
  exit 1
fi

gcloud services api-keys get-key-string kalories-gemini-testflight-v2 \
  --project=zhang23-23 --format=json >"${key_material_json}" 2>/dev/null
chmod 600 "${key_material_json}"
if ! jq -je '.keyString | select(type == "string" and length > 0)' \
  "${key_material_json}" >"${key_material_file}"; then
  printf '%s\n' 'NO-GO: replacement key material is unavailable'
  exit 1
fi
chmod 600 "${key_material_file}"
if ! .venv/bin/python - "${key_material_file}" <<'PY'
from pathlib import Path
import sys

value = Path(sys.argv[1]).read_bytes()
raise SystemExit(0 if value and b"\r" not in value and b"\n" not in value else 1)
PY
then
  printf '%s\n' 'NO-GO: private key file is empty or contains a newline'
  exit 1
fi

if ! gcloud secrets describe kalories-gemini-api-key \
  --project=zhang23-23 >/dev/null 2>&1; then
  gcloud secrets create kalories-gemini-api-key \
    --project=zhang23-23 --replication-policy=automatic >/dev/null
fi
gcloud secrets versions add kalories-gemini-api-key \
  --project=zhang23-23 \
  --data-file="${key_material_file}" \
  --format=json >"${secret_version_create_json}" 2>/dev/null
KALORIES_SECRET_VERSION="$(jq -er '
  .name | capture("/versions/(?<version>[1-9][0-9]*)$").version
' "${secret_version_create_json}")"
test -n "${KALORIES_SECRET_VERSION}"
gcloud secrets versions describe "${KALORIES_SECRET_VERSION}" \
  --secret=kalories-gemini-api-key \
  --project=zhang23-23 \
  --format=json >"${secret_version_readback_json}" 2>/dev/null
if ! jq -e --arg version "${KALORIES_SECRET_VERSION}" '
  (.name | endswith("/secrets/kalories-gemini-api-key/versions/" + $version))
  and .state == "ENABLED"
' "${secret_version_readback_json}" >/dev/null; then
  printf '%s\n' 'NO-GO: pinned secret version read-back failed'
  exit 1
fi
printf '%s\n' 'CHECK replacement key is stored in one enabled pinned secret version'
cleanup_secret_material
trap - EXIT
```

Resolve the actual runtime service account from the live service, then make and
read back exactly one secret-level accessor. Mutation output and the IAM policy
remain private; only fixed findings may be printed.

```bash
set -euo pipefail
umask 077
iam_tmp="$(mktemp -d)"
service_before_json="${iam_tmp}/service-before.json"
iam_mutation_json="${iam_tmp}/iam-mutation.json"
iam_readback_json="${iam_tmp}/iam-readback.json"
ancestors_json="${iam_tmp}/ancestors.json"
project_iam_json="${iam_tmp}/project-iam.json"
ancestor_entries_file="${iam_tmp}/ancestor-entries.tsv"
iam_private_files=(
  "${service_before_json}"
  "${iam_mutation_json}"
  "${iam_readback_json}"
  "${ancestors_json}"
  "${project_iam_json}"
  "${ancestor_entries_file}"
)
cleanup_iam() {
  local iam_file
  for iam_file in "${iam_private_files[@]}"; do
    if [[ -f "${iam_file}" ]]; then unlink -- "${iam_file}"; fi
  done
  if [[ -d "${iam_tmp}" ]]; then rmdir -- "${iam_tmp}"; fi
}
trap cleanup_iam EXIT

gcloud run services describe kalories \
  --project=zhang23-23 --region=asia-northeast1 \
  --format=json >"${service_before_json}" 2>/dev/null
KALORIES_SERVICE_RESOURCE_VERSION="$(jq -er '.metadata.resourceVersion' \
  "${service_before_json}")"
KALORIES_RUNTIME_SA="$(jq -er '.spec.template.spec.serviceAccountName' \
  "${service_before_json}")"
test -n "${KALORIES_SERVICE_RESOURCE_VERSION}"
test -n "${KALORIES_RUNTIME_SA}"

gcloud secrets add-iam-policy-binding kalories-gemini-api-key \
  --project=zhang23-23 \
  --member="serviceAccount:${KALORIES_RUNTIME_SA}" \
  --role=roles/secretmanager.secretAccessor \
  --format=json >"${iam_mutation_json}" 2>/dev/null
gcloud secrets get-iam-policy kalories-gemini-api-key \
  --project=zhang23-23 --format=json >"${iam_readback_json}" 2>/dev/null
if ! jq -e --arg member "serviceAccount:${KALORIES_RUNTIME_SA}" '
  [.bindings[]? | select(.role == "roles/secretmanager.secretAccessor")] as $bindings
  | ((.bindings | type) == "array")
  and ((.bindings | length) == 1)
  and (($bindings | length) == 1)
  and ($bindings[0] | has("condition") | not)
  and (($bindings[0].members | type) == "array")
  and (($bindings[0].members | length) == 1)
  and ($bindings[0].members[0] == $member)
' "${iam_readback_json}" >/dev/null; then
  printf '%s\n' 'NO-GO: secret accessor read-back is not exact'
  exit 1
fi

if ! gcloud projects get-ancestors zhang23-23 \
  --format=json >"${ancestors_json}" 2>/dev/null ||
  ! jq -e '
    type == "array" and length > 0
    and all(.[];
      (.type == "project" or .type == "folder" or .type == "organization")
      and (.id | type == "string" and length > 0))
    and ([.[] | select(.type == "project" and .id == "zhang23-23")] | length == 1)
  ' "${ancestors_json}" >/dev/null; then
  printf '%s\n' 'NO-GO: inherited accessor audit unavailable'
  exit 1
fi

inherited_role_index=0
inherited_policy_index=0
audit_inherited_policy() {
  local policy_file="$1"
  local role_name
  local role_json
  local role_id
  local role_names_file
  local role_scope
  if ! jq -e '
    type == "object"
    and ((.bindings // []) | type == "array")
    and all(.bindings[]?;
      (.role | type == "string") and (.members | type == "array"))
  ' "${policy_file}" >/dev/null; then
    return 2
  fi
  if jq -e '[.bindings[]?
    | select(.role == "roles/secretmanager.secretAccessor")
    | select((.members | length) > 0)] | length > 0' \
    "${policy_file}" >/dev/null; then
    return 10
  fi
  role_names_file="${iam_tmp}/policy-roles-${inherited_policy_index}.txt"
  iam_private_files+=("${role_names_file}")
  inherited_policy_index=$((inherited_policy_index + 1))
  : >"${role_names_file}"
  chmod 600 "${role_names_file}"
  if ! jq -r '[.bindings[]?
    | select((.members | length) > 0)
    | .role] | unique[]' "${policy_file}" >"${role_names_file}"; then
    return 2
  fi
  while IFS= read -r role_name; do
    role_json="${iam_tmp}/role-${inherited_role_index}.json"
    iam_private_files+=("${role_json}")
    inherited_role_index=$((inherited_role_index + 1))
    case "${role_name}" in
      roles/*)
        if ! gcloud iam roles describe "${role_name}" \
          --format=json >"${role_json}" 2>/dev/null; then
          return 2
        fi
        ;;
      projects/*/roles/*)
        role_scope="${role_name#projects/}"
        role_scope="${role_scope%%/roles/*}"
        role_id="${role_name##*/}"
        if ! gcloud iam roles describe "${role_id}" \
          --project="${role_scope}" --format=json >"${role_json}" 2>/dev/null; then
          return 2
        fi
        ;;
      organizations/*/roles/*)
        role_scope="${role_name#organizations/}"
        role_scope="${role_scope%%/roles/*}"
        role_id="${role_name##*/}"
        if ! gcloud iam roles describe "${role_id}" \
          --organization="${role_scope}" --format=json >"${role_json}" 2>/dev/null; then
          return 2
        fi
        ;;
      *) return 2 ;;
    esac
    if ! jq -e '
      type == "object"
      and (.deleted? != true)
      and (.stage? != "DISABLED")
      and (.includedPermissions | type == "array")
      and all(.includedPermissions[]; type == "string")
    ' "${role_json}" >/dev/null; then
      return 2
    fi
    if jq -e '
      any(.includedPermissions[]; . == "secretmanager.versions.access")
    ' "${role_json}" >/dev/null; then
      return 10
    fi
  done <"${role_names_file}"
  return 0
}

if ! gcloud projects get-iam-policy zhang23-23 \
  --format=json >"${project_iam_json}" 2>/dev/null; then
  printf '%s\n' 'NO-GO: inherited accessor audit unavailable'
  exit 1
fi
if audit_inherited_policy "${project_iam_json}"; then
  :
else
  inherited_audit_status=$?
  if [[ "${inherited_audit_status}" -eq 10 ]]; then
    printf '%s\n' 'NO-GO: inherited secret accessor exists'
  else
    printf '%s\n' 'NO-GO: inherited accessor audit unavailable'
  fi
  exit 1
fi

ancestor_index=0
: >"${ancestor_entries_file}"
chmod 600 "${ancestor_entries_file}"
if ! jq -r '.[] | select(.type != "project") | [.type, .id] | @tsv' \
  "${ancestors_json}" >"${ancestor_entries_file}"; then
  printf '%s\n' 'NO-GO: inherited accessor audit unavailable'
  exit 1
fi
while IFS=$'\t' read -r ancestor_type ancestor_id; do
  ancestor_policy_json="${iam_tmp}/ancestor-${ancestor_index}.json"
  iam_private_files+=("${ancestor_policy_json}")
  ancestor_index=$((ancestor_index + 1))
  case "${ancestor_type}" in
    folder)
      if ! gcloud resource-manager folders get-iam-policy "${ancestor_id}" \
        --format=json >"${ancestor_policy_json}" 2>/dev/null; then
        printf '%s\n' 'NO-GO: inherited accessor audit unavailable'
        exit 1
      fi
      ;;
    organization)
      if ! gcloud organizations get-iam-policy "${ancestor_id}" \
        --format=json >"${ancestor_policy_json}" 2>/dev/null; then
        printf '%s\n' 'NO-GO: inherited accessor audit unavailable'
        exit 1
      fi
      ;;
    *)
      printf '%s\n' 'NO-GO: inherited accessor audit unavailable'
      exit 1
      ;;
  esac
  if audit_inherited_policy "${ancestor_policy_json}"; then
    :
  else
    inherited_audit_status=$?
    if [[ "${inherited_audit_status}" -eq 10 ]]; then
      printf '%s\n' 'NO-GO: inherited secret accessor exists'
    else
      printf '%s\n' 'NO-GO: inherited accessor audit unavailable'
    fi
    exit 1
  fi
done <"${ancestor_entries_file}"
printf '%s\n' 'CHECK secret accessor is exact; identities omitted'
cleanup_iam
trap - EXIT
```

## 6. Provider privacy gate

Before candidate deployment, verify in the project control plane and current
official terms, with date and project identity:

1. Gemini Developer API is on a paid tier;
2. developer logging is disabled;
3. dataset sharing is disabled;
4. the paid-service content-use terms apply.

None is currently verified. Do not infer them from a 200 response. Default
abuse-monitoring retention may be up to 55 days. ZDR approval is not confirmed,
so make no zero-retention claim. App Privacy answers must disclose User Content
→ Photos or Videos for App Functionality unless later project-approved ZDR and
a fresh privacy review change that conclusion.

## 7. Exact quota preference

First discover the enforceable project/model requests-per-day quota. Do not use
a display name as its ID. Set the exact dimensions JSON only from that evidence.
The example value below is intentionally not supplied because guessing a
dimension is forbidden. The create command accepts service and quota ID, while
the official `preferences describe` command identifies the preference by its
resource ID and project only.

```bash
set -euo pipefail
: "${KALORIES_RPD_QUOTA_ID:?Set the verified enforceable RPD quota ID}"
: "${KALORIES_RPD_DIMENSIONS_JSON:?Set exact verified dimensions as one JSON object}"
if ! jq -e 'type == "object" and length > 0 and all(values[]; type == "string")' \
  <<<"${KALORIES_RPD_DIMENSIONS_JSON}" >/dev/null; then
  printf '%s\n' 'NO-GO: quota dimensions are invalid'
  exit 1
fi
KALORIES_RPD_DIMENSIONS_FLAG="$(jq -jr '
  to_entries | sort_by(.key) | map(.key + "=" + .value) | join(",")
' <<<"${KALORIES_RPD_DIMENSIONS_JSON}")"
test -n "${KALORIES_RPD_DIMENSIONS_FLAG}"
umask 077
quota_tmp="$(mktemp -d)"
quota_create_json="${quota_tmp}/quota-create.json"
quota_readback_json="${quota_tmp}/quota-readback.json"
cleanup_quota() {
  if [[ -f "${quota_create_json}" ]]; then unlink -- "${quota_create_json}"; fi
  if [[ -f "${quota_readback_json}" ]]; then unlink -- "${quota_readback_json}"; fi
  if [[ -d "${quota_tmp}" ]]; then rmdir -- "${quota_tmp}"; fi
}
trap cleanup_quota EXIT

KALORIES_PROJECT_NUMBER="$(gcloud projects describe zhang23-23 \
  --format='value(projectNumber)')"
test -n "${KALORIES_PROJECT_NUMBER}"
gcloud beta quotas preferences create \
  --project=zhang23-23 \
  --service=generativelanguage.googleapis.com \
  --quota-id="${KALORIES_RPD_QUOTA_ID}" \
  --dimensions="${KALORIES_RPD_DIMENSIONS_FLAG}" \
  --preferred-value=200 \
  --preference-id=kalories-testflight-rpd-200 \
  --allow-high-percentage-quota-decrease \
  --allow-quota-decrease-below-usage \
  --format=json >"${quota_create_json}" 2>/dev/null
gcloud beta quotas preferences describe kalories-testflight-rpd-200 \
  --project=zhang23-23 \
  --format=json >"${quota_readback_json}" 2>/dev/null
if ! jq -e \
  --arg project_number "${KALORIES_PROJECT_NUMBER}" \
  --arg expected_quota_id "${KALORIES_RPD_QUOTA_ID}" \
  --argjson expected_dimensions "${KALORIES_RPD_DIMENSIONS_JSON}" '
  .name == ("projects/" + $project_number
    + "/locations/global/quotaPreferences/kalories-testflight-rpd-200")
  and .service == "generativelanguage.googleapis.com"
  and .quotaId == $expected_quota_id
  and .reconciling == false
  and ((.quotaConfig.grantedValue | tonumber) == 200)
  and ((.quotaConfig.preferredValue | tonumber) == 200)
  and .dimensions == $expected_dimensions
' "${quota_readback_json}" >/dev/null; then
  printf '%s\n' 'NO-GO: quota preference is pending, partial, or mismatched'
  exit 1
fi
printf '%s\n' 'CHECK exact quota preference is settled at RPD 200'
cleanup_quota
trap - EXIT
```

If no exact enforceable RPD quota exists, external TestFlight stays `NO-GO`.

## 8. Budget alert

The monthly amount and currency require later user approval. Validate a positive
amount, create project-filtered 50/80/100% alerts, and read them back. A budget
alert notifies; it neither caps spend nor provides CPU abuse protection.

```bash
set -euo pipefail
: "${KALORIES_MONTHLY_BUDGET_AMOUNT:?Set the user-approved amount and currency, for example 1000JPY}"
if [[ ! "${KALORIES_MONTHLY_BUDGET_AMOUNT}" =~ ^[1-9][0-9]*([.][0-9]{1,9})?[A-Z]{3}$ ]]; then
  printf '%s\n' 'NO-GO: budget amount and currency format is invalid'
  exit 1
fi
umask 077
budget_tmp="$(mktemp -d)"
budget_create_json="${budget_tmp}/budget-create.json"
budget_readback_json="${budget_tmp}/budget-readback.json"
cleanup_budget() {
  if [[ -f "${budget_create_json}" ]]; then unlink -- "${budget_create_json}"; fi
  if [[ -f "${budget_readback_json}" ]]; then unlink -- "${budget_readback_json}"; fi
  if [[ -d "${budget_tmp}" ]]; then rmdir -- "${budget_tmp}"; fi
}
trap cleanup_budget EXIT

KALORIES_BILLING_ACCOUNT="$(gcloud billing projects describe zhang23-23 \
  --format='value(billingAccountName)')"
KALORIES_PROJECT_NUMBER="$(gcloud projects describe zhang23-23 \
  --format='value(projectNumber)')"
test -n "${KALORIES_BILLING_ACCOUNT}"
test -n "${KALORIES_PROJECT_NUMBER}"
gcloud billing budgets create \
  --billing-account="${KALORIES_BILLING_ACCOUNT}" \
  --display-name='Kalories TestFlight monthly alert' \
  --budget-amount="${KALORIES_MONTHLY_BUDGET_AMOUNT}" \
  --filter-projects="projects/${KALORIES_PROJECT_NUMBER}" \
  --calendar-period=month \
  --threshold-rule=percent=0.50,basis=current-spend \
  --threshold-rule=percent=0.80,basis=current-spend \
  --threshold-rule=percent=1.00,basis=current-spend \
  --format=json >"${budget_create_json}" 2>/dev/null
KALORIES_BUDGET_RESOURCE="$(jq -er '.name' "${budget_create_json}")"
gcloud billing budgets describe "${KALORIES_BUDGET_RESOURCE}" \
  --format=json >"${budget_readback_json}" 2>/dev/null
if ! .venv/bin/python - \
  "${KALORIES_MONTHLY_BUDGET_AMOUNT}" \
  "${KALORIES_PROJECT_NUMBER}" \
  "${budget_readback_json}" <<'PY'
from decimal import Decimal
import json
from pathlib import Path
import re
import sys

approved, project_number, readback_path = sys.argv[1:]
match = re.fullmatch(r"([1-9][0-9]*(?:\.[0-9]{1,9})?)([A-Z]{3})", approved)
if match is None:
    raise SystemExit(1)
document = json.loads(Path(readback_path).read_text(encoding="utf-8"))
money = document.get("amount", {}).get("specifiedAmount", {})
actual = Decimal(str(money.get("units", "0"))) + (
    Decimal(str(money.get("nanos", 0))) / Decimal("1000000000")
)
thresholds = sorted(
    Decimal(str(rule.get("thresholdPercent")))
    for rule in document.get("thresholdRules", [])
)
threshold_rules = document.get("thresholdRules", [])
valid = (
    document.get("displayName") == "Kalories TestFlight monthly alert"
    and document.get("budgetFilter", {}).get("projects")
    == [f"projects/{project_number}"]
    and document.get("budgetFilter", {}).get("calendarPeriod") == "MONTH"
    and money.get("currencyCode") == match.group(2)
    and actual == Decimal(match.group(1))
    and thresholds == [Decimal("0.5"), Decimal("0.8"), Decimal("1")]
    and all(rule.get("spendBasis") == "CURRENT_SPEND" for rule in threshold_rules)
)
raise SystemExit(0 if valid else 1)
PY
then
  printf '%s\n' 'NO-GO: budget alert read-back is mismatched'
  exit 1
fi
printf '%s\n' 'CHECK user-approved budget alert read-back passed'
cleanup_budget
trap - EXIT
```

## 9. Zero-traffic immutable candidate

Only after all prior gates and confirmation, update named settings without
clearing unrelated configuration. Do not grant public access. The secret env is
pinned to the verified numeric version.

```bash
set -euo pipefail
: "${KALORIES_SECRET_VERSION:?Use the verified numeric secret version}"
: "${KALORIES_SERVICE_RESOURCE_VERSION:?Run the IAM/concurrency pre-audit first}"
: "${KALORIES_FIREBASE_IOS_APP_ID:?Use the exact approved Firebase iOS app ID}"
if [[ ! "${KALORIES_SECRET_VERSION}" =~ ^[1-9][0-9]*$ ]]; then
  printf '%s\n' 'NO-GO: secret version is not pinned'
  exit 1
fi
if [[ ! "${KALORIES_FIREBASE_IOS_APP_ID}" =~ ^1:[0-9]{6,}:ios:[A-Za-z0-9]+$ ]]; then
  printf '%s\n' 'NO-GO: Firebase iOS app ID format is invalid'
  exit 1
fi
umask 077
candidate_deploy_tmp="$(mktemp -d)"
service_now_json="${candidate_deploy_tmp}/service-now.json"
cleanup_candidate_deploy() {
  if [[ -f "${service_now_json}" ]]; then unlink -- "${service_now_json}"; fi
  if [[ -d "${candidate_deploy_tmp}" ]]; then rmdir -- "${candidate_deploy_tmp}"; fi
}
trap cleanup_candidate_deploy EXIT
gcloud run services describe kalories \
  --project=zhang23-23 --region=asia-northeast1 \
  --format=json >"${service_now_json}" 2>/dev/null
if ! jq -e --arg expected "${KALORIES_SERVICE_RESOURCE_VERSION}" '
  .metadata.resourceVersion == $expected
' "${service_now_json}" >/dev/null; then
  printf '%s\n' 'NO-GO: live service changed after concurrency pre-audit'
  exit 1
fi
if ! gcloud run deploy kalories \
  --source=. \
  --project=zhang23-23 \
  --region=asia-northeast1 \
  --remove-env-vars=GEMINI_API_KEY,GEMINI_MODEL \
  --update-secrets=GEMINI_API_KEY=kalories-gemini-api-key:${KALORIES_SECRET_VERSION} \
  --update-env-vars=GEMINI_MODEL=gemini-3.6-flash,APP_CHECK_ENFORCEMENT=required,FIREBASE_PROJECT_ID=zhang23-23,FIREBASE_IOS_APP_ID=${KALORIES_FIREBASE_IOS_APP_ID} \
  --max-instances=1 \
  --concurrency=4 \
  --timeout=30s \
  --no-traffic \
  --tag=testflight-candidate >/dev/null; then
  printf '%s\n' 'NO-GO: zero-traffic candidate deploy failed'
  exit 1
fi
cleanup_candidate_deploy
trap - EXIT
```

Resolve the tag, then describe and validate that immutable revision itself.
Aggregate its percentage across every traffic entry; one zero-valued tag entry
alone is insufficient evidence.

```bash
set -euo pipefail
umask 077
candidate_state_tmp="$(mktemp -d)"
candidate_service_json="${candidate_state_tmp}/service.json"
candidate_revision_json="${candidate_state_tmp}/revision.json"
candidate_deploy_log_json="${candidate_state_tmp}/deploy-log.json"
cleanup_candidate_state() {
  local candidate_file
  for candidate_file in \
    "${candidate_service_json}" \
    "${candidate_revision_json}" \
    "${candidate_deploy_log_json}"; do
    if [[ -f "${candidate_file}" ]]; then unlink -- "${candidate_file}"; fi
  done
  if [[ -d "${candidate_state_tmp}" ]]; then rmdir -- "${candidate_state_tmp}"; fi
}
trap cleanup_candidate_state EXIT

gcloud run services describe kalories \
  --project=zhang23-23 --region=asia-northeast1 \
  --format=json >"${candidate_service_json}" 2>/dev/null
KALORIES_CANDIDATE_REVISION="$(jq -er '
  [.status.traffic[]? | select(.tag == "testflight-candidate")]
  | if length == 1 then .[0].revisionName else empty end
' "${candidate_service_json}")"
KALORIES_CANDIDATE_URL="$(jq -er '
  [.status.traffic[]? | select(.tag == "testflight-candidate")]
  | if length == 1 then .[0].url else empty end
' "${candidate_service_json}")"
if [[ ! "${KALORIES_CANDIDATE_URL}" =~ ^https://([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?[.])+[A-Za-z]{2,63}(:[0-9]{1,5})?(/.*)?$ ]]; then
  printf '%s\n' 'NO-GO: candidate tag URL is invalid'
  exit 1
fi
if ! candidate_traffic_total="$(jq -er \
  --arg revision "${KALORIES_CANDIDATE_REVISION}" '
    [.status.traffic[]? | select(.revisionName == $revision)] as $entries
    | select(($entries | length) > 0)
    | select(all($entries[];
        has("percent")
        and (.percent | type == "number")
        and .percent >= 0
        and .percent <= 100))
    | ($entries | map(.percent) | add)
  ' "${candidate_service_json}")"; then
  printf '%s\n' 'NO-GO: candidate traffic schema is invalid'
  exit 1
fi
if [[ "${candidate_traffic_total}" != 0 ]]; then
  printf '%s\n' 'NO-GO: candidate revision traffic is not zero'
  exit 1
fi

gcloud run revisions describe "${KALORIES_CANDIDATE_REVISION}" \
  --project=zhang23-23 --region=asia-northeast1 \
  --format=json >"${candidate_revision_json}" 2>/dev/null
if ! jq -e \
  --arg revision "${KALORIES_CANDIDATE_REVISION}" \
  --arg secret_version "${KALORIES_SECRET_VERSION}" \
  --arg firebase_app_id "${KALORIES_FIREBASE_IOS_APP_ID}" '
  def all_env: [.spec.containers[]?.env[]?, .containers[]?.env[]?];
  ([
    .metadata.annotations["autoscaling.knative.dev/maxScale"]?,
    .scaling.maxInstanceCount?,
    .spec.scaling.maxInstanceCount?
  ] | map(select(. != null) | tostring)) as $max_values
  | all_env as $env
  | [$env[] | select(.name? == "GEMINI_API_KEY")] as $keys
  | [$env[] | select(.name? == "GEMINI_MODEL")] as $models
  | [$env[] | select(.name? == "APP_CHECK_ENFORCEMENT")] as $enforcement
  | [$env[] | select(.name? == "FIREBASE_PROJECT_ID")] as $projects
  | [$env[] | select(.name? == "FIREBASE_IOS_APP_ID")] as $apps
  | ([.spec.containers[]?.image?, .containers[]?.image?]
     | map(select(type == "string"))) as $images
  | .metadata.name == $revision
  and (($max_values | length) == 1 and $max_values[0] == "1")
  and (($keys | length) == 1)
  and ($keys[0] | has("value") | not)
  and (
    (
      $keys[0].valueFrom.secretKeyRef.name? == "kalories-gemini-api-key"
      and $keys[0].valueFrom.secretKeyRef.key? == $secret_version
      and ($keys[0] | has("valueSource") | not)
    )
    or
    (
      $keys[0].valueSource.secretKeyRef.secret? == "kalories-gemini-api-key"
      and $keys[0].valueSource.secretKeyRef.version? == $secret_version
      and ($keys[0] | has("valueFrom") | not)
    )
  )
  and (($models | length) == 1 and $models[0].value? == "gemini-3.6-flash")
  and ($models[0] | has("valueFrom") | not)
  and ($models[0] | has("valueSource") | not)
  and (($enforcement | length) == 1 and $enforcement[0].value? == "required")
  and ($enforcement[0] | has("valueFrom") | not)
  and ($enforcement[0] | has("valueSource") | not)
  and (($projects | length) == 1 and $projects[0].value? == "zhang23-23")
  and ($projects[0] | has("valueFrom") | not)
  and ($projects[0] | has("valueSource") | not)
  and (($apps | length) == 1 and $apps[0].value? == $firebase_app_id)
  and ($apps[0] | has("valueFrom") | not)
  and ($apps[0] | has("valueSource") | not)
  and (($images | length) == 1 and ($images[0] | test("@sha256:[0-9a-fA-F]{64}$")))
' "${candidate_revision_json}" >/dev/null; then
  printf '%s\n' 'NO-GO: immutable candidate revision is noncompliant'
  exit 1
fi
printf '%s\n' 'CHECK immutable candidate is compliant and has aggregate traffic zero'
cleanup_candidate_state
trap - EXIT
```

The model remains `gemini-3.6-flash`; deprecated sampling fields such as
`temperature`, `top_p`, and `top_k` remain omitted. Live image/schema behavior,
latency under 20 seconds, and cost are still unverified at this point.

## 10. Candidate request, strict schema, and targeted safe logs

Use one generated non-personal synthetic meal image outside the repository and
one short-lived App Check token obtained through the separately registered
local DEBUG provider. Keep the token, request, response, and logs private. The
no-token probe must be HTTP 401; public pages and the token-authenticated image
request must be HTTP 200. Transport failure is always NO-GO.

`AnalyzeResponse.model_validate_json` enforces the production Pydantic
contract: complete nested shape, strict types, enum values, numeric ranges,
nullability, forbidden extras, nonempty food names, unique assumption keys, and
the full deterministic assessment. It rejects string nutrients, invalid
confidence values, and an empty assessment. The HTTP result still does not
prove cost; record a separate project/model usage and cost observation.

This same private block reads logs after the target request, by immutable
candidate revision. A valid nonempty JSON array and a target request log for
`/api/analyze` are mandatory. The recursive scan rejects sensitive keys and
markers in any string, including stringified provider JSON, without printing a
match. This includes `providerResponse` and `provider_response` spellings.

```bash
set -euo pipefail
: "${KALORIES_CANDIDATE_URL:?Resolve candidate URL first}"
: "${KALORIES_CANDIDATE_REVISION:?Resolve candidate revision first}"
: "${KALORIES_SYNTHETIC_MEAL_IMAGE:?Set a generated non-personal JPEG path}"
: "${KALORIES_APP_CHECK_TOKEN_FILE:?Set a mode-600 short-lived App Check token file}"
test -f "${KALORIES_SYNTHETIC_MEAL_IMAGE}"
test -f "${KALORIES_APP_CHECK_TOKEN_FILE}"
if [[ "$(stat -f '%Lp' "${KALORIES_APP_CHECK_TOKEN_FILE}")" != 600 ]]; then
  printf '%s\n' 'NO-GO: App Check token file mode is not 600'
  exit 1
fi
app_check_token="$(<"${KALORIES_APP_CHECK_TOKEN_FILE}")"
if [[ -z "${app_check_token}" || "${app_check_token}" == *$'\n'* ||
  "${app_check_token}" == *$'\r'* ]]; then
  printf '%s\n' 'NO-GO: App Check token file is invalid'
  exit 1
fi
umask 077
candidate_test_tmp="$(mktemp -d)"
candidate_payload_json="${candidate_test_tmp}/request.json"
candidate_response_json="${candidate_test_tmp}/response.json"
candidate_logs_json="${candidate_test_tmp}/logs.json"
candidate_schema_error="${candidate_test_tmp}/schema-error.txt"
candidate_no_token_json="${candidate_test_tmp}/no-token.json"
cleanup_candidate_test() {
  local candidate_test_file
  for candidate_test_file in \
    "${candidate_payload_json}" \
    "${candidate_response_json}" \
    "${candidate_logs_json}" \
    "${candidate_schema_error}" \
    "${candidate_no_token_json}"; do
    if [[ -f "${candidate_test_file}" ]]; then unlink -- "${candidate_test_file}"; fi
  done
  if [[ -d "${candidate_test_tmp}" ]]; then rmdir -- "${candidate_test_tmp}"; fi
}
trap cleanup_candidate_test EXIT
: >"${candidate_schema_error}"
chmod 600 "${candidate_schema_error}"

for endpoint_spec in 'health|/health' 'privacy|/privacy/' 'support|/support/'; do
  endpoint_name="${endpoint_spec%%|*}"
  endpoint_path="${endpoint_spec#*|}"
  endpoint_status=''
  if ! endpoint_status="$(curl \
    --silent --output /dev/null --write-out '%{http_code}' \
    --connect-timeout 10 --max-time 20 \
    "${KALORIES_CANDIDATE_URL}${endpoint_path}")"; then
    printf 'NO-GO: candidate /%s request failed\n' "${endpoint_name}"
    exit 1
  fi
  if [[ "${endpoint_status}" != 200 ]]; then
    printf 'NO-GO: candidate /%s is not HTTP 200\n' "${endpoint_name}"
    exit 1
  fi
done

base64 <"${KALORIES_SYNTHETIC_MEAL_IMAGE}" \
  | tr -d '\n' \
  | jq -Rs '{image: ("data:image/jpeg;base64," + .)}' >"${candidate_payload_json}"
candidate_request_started_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
for protected_path in '/api/analyze' '/'; do
  no_token_status=''
  if ! no_token_status="$(curl \
    --silent --show-error \
    --output "${candidate_no_token_json}" \
    --write-out '%{http_code}' \
    --request POST \
    --connect-timeout 10 --max-time 20 \
    --header 'Content-Type: application/json' \
    --data '{"image":"data:image/jpeg;base64,AA=="}' \
    "${KALORIES_CANDIDATE_URL}${protected_path}")"; then
    printf 'NO-GO: candidate no-token request failed for %s\n' "${protected_path}"
    exit 1
  fi
  if [[ "${no_token_status}" != 401 ]] || ! jq -e '
    type == "object" and keys == ["detail"]
    and (.detail | type == "object") and (.detail | keys == ["code"])
    and .detail.code == "APP_CHECK_FAILED"
  ' "${candidate_no_token_json}" >/dev/null; then
    printf 'NO-GO: candidate no-token contract is invalid for %s\n' "${protected_path}"
    exit 1
  fi
done
request_metrics=''
if ! request_metrics="$(curl \
  --silent --show-error \
  --output "${candidate_response_json}" \
  --write-out '%{http_code} %{time_total}' \
  --connect-timeout 10 --max-time 20 \
  --header 'Content-Type: application/json' \
  --header "X-Firebase-AppCheck: ${app_check_token}" \
  --data-binary "@${candidate_payload_json}" \
  "${KALORIES_CANDIDATE_URL}/api/analyze")"; then
  printf '%s\n' 'NO-GO: candidate real-image request failed'
  exit 1
fi
request_status="${request_metrics%% *}"
request_latency_seconds="${request_metrics#* }"
if [[ "${request_status}" != 200 ]] || ! awk -v seconds="${request_latency_seconds}" \
  'BEGIN { exit !(seconds ~ /^[0-9]+([.][0-9]+)?$/ && seconds < 20) }'; then
  printf '%s\n' 'NO-GO: candidate real-image status or latency failed'
  exit 1
fi
if ! .venv/bin/python - "${candidate_response_json}" 2>"${candidate_schema_error}" <<'PY'
from pathlib import Path
import sys

from api.analyze import AnalyzeResponse

response = AnalyzeResponse.model_validate_json(
    Path(sys.argv[1]).read_text(encoding="utf-8")
)
raise SystemExit(0 if response.food_detected else 1)
PY
then
  printf '%s\n' 'NO-GO: candidate response violates the real backend schema'
  exit 1
fi
printf 'CHECK candidate real-image: HTTP 200, strict schema valid, latency %ss\n' \
  "${request_latency_seconds}"
if ! gcloud logging read \
  "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"kalories\" AND resource.labels.location=\"asia-northeast1\" AND resource.labels.revision_name=\"${KALORIES_CANDIDATE_REVISION}\" AND timestamp>=\"${candidate_request_started_at}\"" \
  --project=zhang23-23 --limit=200 --order=desc --format=json \
  >"${candidate_logs_json}" 2>/dev/null; then
  printf '%s\n' 'NO-GO: candidate log read failed'
  exit 1
fi
if ! jq -e 'type == "array" and length > 0' \
  "${candidate_logs_json}" >/dev/null; then
  printf '%s\n' 'NO-GO: candidate logs are not a nonempty JSON array'
  exit 1
fi
# BEGIN CANDIDATE_LOG_SAFETY_SCAN
candidate_log_scan_status=0
jq -e '
  def normalized_key: ascii_downcase | gsub("[-_]"; "");
  def sensitive_key:
    normalized_key as $key
    | [
        "authorization", "xgoogapikey", "xfirebaseappcheck",
        "appchecktoken", "apikey", "geminiapikey",
        "request", "requestbody", "providerrequest", "providerresponse",
        "response", "responsebody", "assessment", "nutrients",
        "fooddetected", "image", "prompt", "contents", "candidates"
      ]
    | index($key) != null;
  any(.. | objects | keys_unsorted[]?; sensitive_key)
  or any(.. | strings;
    test("(?i)data:image/|bearer[[:space:]]+[A-Za-z0-9._~+/-]+=*|AIza[0-9A-Za-z_-]{35}|[A-Za-z0-9+/]{256,}={0,2}|(^|[^[:alnum:]_])\\\"?(food_detected|nutrients|assessment|request|response|provider[ _-]?(request|response)|authorization|x-goog-api-key|x-firebase-app-check|app[_-]?check[_-]?token|api[_-]?key)\\\"?[[:space:]]*[:=]"))
' "${candidate_logs_json}" >/dev/null || candidate_log_scan_status=$?
case "${candidate_log_scan_status}" in
  0)
    printf '%s\n' 'NO-GO: candidate logs contain sensitive application data'
    exit 1
    ;;
  1) ;;
  *)
    printf '%s\n' 'NO-GO: candidate log safety scan failed'
    exit 1
    ;;
esac
# END CANDIDATE_LOG_SAFETY_SCAN
if ! jq -e \
  --arg revision "${KALORIES_CANDIDATE_REVISION}" \
  --arg candidate_url "${KALORIES_CANDIDATE_URL}" '
  def exact_post($path; $status):
    any(.[];
      .resource.labels.revision_name? == $revision
      and .httpRequest.requestMethod? == "POST"
      and .httpRequest.status? == $status
      and .httpRequest.requestUrl? == ($candidate_url + $path));
  exact_post("/api/analyze"; 401)
  and exact_post("/"; 401)
  and exact_post("/api/analyze"; 200)
' "${candidate_logs_json}" >/dev/null; then
  printf '%s\n' 'NO-GO: candidate target request log is missing'
  exit 1
fi
printf '%s\n' 'CHECK candidate target request log collected; safe scan passed'
cleanup_candidate_test
trap - EXIT
unset KALORIES_SYNTHETIC_MEAL_IMAGE
unset app_check_token
```

## 11. Exact promotion, postcheck, revocation, and rollback

Promote only after every earlier gate is PASS. The command targets the immutable
candidate explicitly and fails immediately; it never means “latest.”

```bash
set -euo pipefail
: "${KALORIES_CANDIDATE_REVISION:?Resolve the verified candidate revision}"
umask 077
promotion_tmp="$(mktemp -d)"
promotion_json="${promotion_tmp}/promotion.json"
cleanup_promotion() {
  if [[ -f "${promotion_json}" ]]; then unlink -- "${promotion_json}"; fi
  if [[ -d "${promotion_tmp}" ]]; then rmdir -- "${promotion_tmp}"; fi
}
trap cleanup_promotion EXIT
if ! gcloud run services update-traffic kalories \
  --project=zhang23-23 \
  --region=asia-northeast1 \
  --to-revisions="${KALORIES_CANDIDATE_REVISION}=100" \
  --format=json >"${promotion_json}" 2>/dev/null; then
  printf '%s\n' 'NO-GO: exact candidate promotion failed'
  exit 1
fi
if ! KALORIES_EXPECTED_REVISION="${KALORIES_CANDIDATE_REVISION}" \
  KALORIES_EXPECTED_FIREBASE_IOS_APP_ID="${KALORIES_FIREBASE_IOS_APP_ID}" \
  scripts/check-testflight-backend.sh; then
  printf '%s\n' 'NO-GO: promoted revision failed exact production postcheck'
  exit 1
fi
cleanup_promotion
trap - EXIT
```

The postcheck proves that the exact candidate revision is the sole production
revision at aggregate 100% traffic, then describes and validates that revision.
A pre-existing compliant production revision cannot make a failed promotion
look successful. Repeat the real-image request and targeted safe-log gate
against production before touching the old credential.

The exact baseline revision `kalories-00003-djq` is known to use a plaintext,
unpinned credential. Its limited pre-revocation rollback window exists only
while the old key is still active. This emergency command must prove the old
key has not been revoked before changing traffic:

```bash
set -euo pipefail
: "${KALORIES_OLD_KEY_RESOURCE:?Set exact old key resource from metadata}"
: "${KALORIES_OLD_KEY_REVOKED:?Set yes or no from the current revocation checkpoint}"
legacy_rollback_guard='kalories-00003-djq'
umask 077
legacy_rollback_tmp="$(mktemp -d)"
old_key_delete_time="${legacy_rollback_tmp}/old-key-delete-time"
legacy_revision_json="${legacy_rollback_tmp}/legacy-revision.json"
legacy_key_response_json="${legacy_rollback_tmp}/legacy-key-material.json"
legacy_revision_key_file="${legacy_rollback_tmp}/legacy-revision-key"
legacy_resource_key_file="${legacy_rollback_tmp}/legacy-resource-key"
cleanup_legacy_rollback() {
  local legacy_private_file
  for legacy_private_file in \
    "${old_key_delete_time}" \
    "${legacy_revision_json}" \
    "${legacy_key_response_json}" \
    "${legacy_revision_key_file}" \
    "${legacy_resource_key_file}"; do
    if [[ -f "${legacy_private_file}" ]]; then unlink -- "${legacy_private_file}"; fi
  done
  if [[ -d "${legacy_rollback_tmp}" ]]; then rmdir -- "${legacy_rollback_tmp}"; fi
}
trap cleanup_legacy_rollback EXIT
if [[ "${KALORIES_OLD_KEY_REVOKED}" == yes ]]; then
  printf '%s\n' 'NO-GO: post-revocation legacy rollback is forbidden'
  exit 1
fi
if [[ "${KALORIES_OLD_KEY_REVOKED}" != no ]]; then
  printf '%s\n' 'NO-GO: old key revocation state is invalid'
  exit 1
fi
if ! KALORIES_PROJECT_NUMBER="$(gcloud projects describe zhang23-23 \
  --format='value(projectNumber)')" ||
  ! KALORIES_REPLACEMENT_KEY_RESOURCE="$(gcloud services api-keys describe \
    kalories-gemini-testflight-v2 --project=zhang23-23 --location=global \
    --format='value(name)')"; then
  printf '%s\n' 'NO-GO: legacy rollback key identity is unavailable'
  exit 1
fi
expected_old_key_prefix="projects/${KALORIES_PROJECT_NUMBER}/locations/global/keys/"
if [[ -z "${KALORIES_PROJECT_NUMBER}" ]] ||
  [[ -z "${KALORIES_REPLACEMENT_KEY_RESOURCE}" ]] ||
  [[ "${KALORIES_OLD_KEY_RESOURCE}" != "${expected_old_key_prefix}"* ]] ||
  [[ "${KALORIES_OLD_KEY_RESOURCE}" == "${KALORIES_REPLACEMENT_KEY_RESOURCE}" ]]; then
  printf '%s\n' 'NO-GO: legacy rollback key identity is invalid'
  exit 1
fi
if ! gcloud services api-keys describe "${KALORIES_OLD_KEY_RESOURCE}" \
  --project=zhang23-23 --location=global \
  --format='value(deleteTime)' >"${old_key_delete_time}" 2>/dev/null; then
  printf '%s\n' 'NO-GO: old API key status is unavailable'
  exit 1
fi
if [[ -s "${old_key_delete_time}" ]]; then
  printf '%s\n' 'NO-GO: post-revocation legacy rollback is forbidden'
  exit 1
fi
if ! gcloud run revisions describe "${legacy_rollback_guard}" \
  --project=zhang23-23 --region=asia-northeast1 \
  --format=json >"${legacy_revision_json}" 2>/dev/null ||
  ! jq -je --arg revision "${legacy_rollback_guard}" '
    select(.metadata.name? == $revision)
    | [.spec.containers[]?.env[]?, .containers[]?.env[]?
       | select(.name? == "GEMINI_API_KEY")] as $keys
    | select(($keys | length) == 1)
    | select($keys[0] | has("value"))
    | select($keys[0] | has("valueFrom") | not)
    | select($keys[0] | has("valueSource") | not)
    | $keys[0].value
    | select(type == "string" and length > 0)
  ' "${legacy_revision_json}" >"${legacy_revision_key_file}"; then
  printf '%s\n' 'NO-GO: legacy revision credential is unavailable or not plaintext'
  exit 1
fi
chmod 600 "${legacy_revision_json}" "${legacy_revision_key_file}"
if ! gcloud services api-keys get-key-string "${KALORIES_OLD_KEY_RESOURCE}" \
  --project=zhang23-23 --location=global \
  --format=json >"${legacy_key_response_json}" 2>/dev/null ||
  ! jq -je '.keyString | select(type == "string" and length > 0)' \
    "${legacy_key_response_json}" >"${legacy_resource_key_file}"; then
  printf '%s\n' 'NO-GO: legacy rollback key material is unavailable'
  exit 1
fi
chmod 600 "${legacy_key_response_json}" "${legacy_resource_key_file}"
if ! cmp -s "${legacy_revision_key_file}" "${legacy_resource_key_file}"; then
  printf '%s\n' 'NO-GO: legacy revision credential does not match rollback key'
  exit 1
fi
if ! gcloud run services update-traffic kalories \
  --project=zhang23-23 \
  --region=asia-northeast1 \
  --to-revisions="${legacy_rollback_guard}=100" >/dev/null; then
  printf '%s\n' 'NO-GO: limited pre-revocation rollback traffic command failed'
  exit 1
fi
printf '%s\n' 'CHECK limited pre-revocation rollback completed; legacy credential still requires retirement'
cleanup_legacy_rollback
trap - EXIT
```

Old-key deletion is a separate, freshly confirmed mutation. Resolve by metadata
identity, never by key value; exclude `kalories-gemini-testflight-v2`. Run only
after successful promotion and replacement-key production checks, accepting
that this permanently closes the legacy rollback window:

```bash
set -euo pipefail
: "${KALORIES_OLD_KEY_RESOURCE:?Set exact old key resource from metadata}"
: "${KALORIES_OLD_KEY_DELETION_CONFIRMED:?Fresh user confirmation must be yes}"
if [[ "${KALORIES_OLD_KEY_DELETION_CONFIRMED}" != yes ]]; then
  printf '%s\n' 'NO-GO: old API key deletion is not confirmed'
  exit 1
fi
KALORIES_PROJECT_NUMBER="$(gcloud projects describe zhang23-23 \
  --format='value(projectNumber)')"
KALORIES_REPLACEMENT_KEY_RESOURCE="$(gcloud services api-keys describe \
  kalories-gemini-testflight-v2 --project=zhang23-23 --location=global \
  --format='value(name)')"
test -n "${KALORIES_REPLACEMENT_KEY_RESOURCE}"
expected_old_key_prefix="projects/${KALORIES_PROJECT_NUMBER}/locations/global/keys/"
if [[ "${KALORIES_OLD_KEY_RESOURCE}" != "${expected_old_key_prefix}"* ]] ||
  [[ "${KALORIES_OLD_KEY_RESOURCE}" == "${KALORIES_REPLACEMENT_KEY_RESOURCE}" ]]; then
  printf '%s\n' 'NO-GO: old API key resource is outside scope or is replacement'
  exit 1
fi
old_delete_time_before="$(gcloud services api-keys describe \
  "${KALORIES_OLD_KEY_RESOURCE}" --project=zhang23-23 --location=global \
  --format='value(deleteTime)')"
replacement_delete_time_before="$(gcloud services api-keys describe \
  kalories-gemini-testflight-v2 --project=zhang23-23 --location=global \
  --format='value(deleteTime)')"
if [[ -n "${old_delete_time_before}" || -n "${replacement_delete_time_before}" ]]; then
  printf '%s\n' 'NO-GO: old or replacement API key is not active'
  exit 1
fi
if ! gcloud services api-keys delete "${KALORIES_OLD_KEY_RESOURCE}" \
  --project=zhang23-23 --location=global --quiet >/dev/null; then
  printf '%s\n' 'NO-GO: old API key deletion failed'
  exit 1
fi
old_delete_time_after="$(gcloud services api-keys describe \
  "${KALORIES_OLD_KEY_RESOURCE}" --project=zhang23-23 --location=global \
  --format='value(deleteTime)')"
replacement_delete_time_after="$(gcloud services api-keys describe \
  kalories-gemini-testflight-v2 --project=zhang23-23 --location=global \
  --format='value(deleteTime)')"
if [[ -z "${old_delete_time_after}" || -n "${replacement_delete_time_after}" ]]; then
  printf '%s\n' 'NO-GO: old API key revocation verification failed'
  exit 1
fi
printf '%s\n' 'CHECK old key revoked; replacement remains active'
```

After revocation, `kalories-00003-djq` is unavailable and must never receive
traffic. There is currently no predeployed, validated pinned-secret rollback
revision. A post-revocation incident must therefore fail closed and roll
forward from the promoted pinned-secret revision. Deploying a future rollback
candidate is a separate zero-traffic action requiring fresh confirmation and
all candidate gates before the old key is revoked; do not improvise traffic
mutation during an incident.

## 12. Runtime limits and monitoring

Firebase App Check runs before image decoding and provider work. The remaining
global token bucket is process-local, resets on restart, and has no per-user
fairness; a caller with a valid app token can still starve others. Therefore
maxScale `1` and monitoring of HTTP 401/429/503, memory, latency, concurrency
saturation, App Attest failures, and restarts remain required. Provider RPD is
a cost/request loss cap, not complete abuse protection; a budget alert is only
notification.

## 13. TestFlight and public App Store boundary

Backend promotion does not upload a build. TestFlight upload does not prove
processing. Processing does not invite testers. Only invited testers aged 18+
may participate after all backend, access, privacy, and cost gates pass.

Public App Store release remains out of scope and unresolved. It requires a
private support channel, age/compliance and privacy review, App Review approval,
any manual release action, propagation, and storefront visibility as separate
evidence gates.

## Sanitized evidence record

Record timestamps, revision names, aggregate traffic, boolean secret/model/IAM
findings, verified quota ID/dimensions/value, approved budget summary, HTTP
statuses, latency/cost summary, test counts, and boolean log scan results. Never
record key values, IAM identities/policies, billing account IDs, images/base64,
provider response bodies, or log content.
