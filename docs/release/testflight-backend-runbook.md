# TestFlight backend release runbook

This is a fail-closed evidence ledger, not authorization to deploy. Local code,
the read-only production preflight, access architecture, a zero-traffic
candidate, provider privacy, quota, budget, a real-image request, safe logs,
promotion, credential revocation, rollback, TestFlight upload, TestFlight
processing, and public App Store release are separate gates. A PASS at one gate
never advances another gate.

All Google Cloud mutations below are reserved for Task 6. Task 6 itself and any
external TestFlight distribution remain blocked until the user separately
approves an access/abuse-protection architecture and that architecture is
implemented and machine-verifiable. This runbook does not invent App Attest,
Firebase, accounts, or another identity design.

## Fixed scope and identifiers

| Item | Fixed value |
| --- | --- |
| Project | `zhang23-23` |
| Region | `asia-northeast1` |
| Cloud Run service | `kalories` |
| Model | `gemini-3.6-flash` |
| Replacement API key ID | `kalories-gemini-testflight` |
| Secret Manager secret | `kalories-gemini-api-key` |
| Preferred Gemini limit | RPD `200`, only after the exact enforceable quota ID and dimensions are verified |
| Controlled audience | Invited testers who are 18 or older |

Never print, paste, compare, screenshot, or commit an API key value, request
image, provider response, IAM identity list, or log content. Use `set -euo
pipefail`, no shell tracing, `umask 077`, exact temporary paths, fixed safe
findings, and cleanup traps.

## Read-only baseline

Captured at `2026-08-08 08:00:38 JST (+0900)`; rerun immediately before any
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
| Cloud Run public invoker | `true`; policy identities omitted | NO-GO |
| Machine-verifiable application-layer access protection | absent | NO-GO |
| `GET /health` | HTTP 200 | transport evidence only |
| `GET /privacy/` | HTTP 404 | NO-GO |
| `GET /support/` | HTTP 404 | NO-GO |
| Targeted latest log read after endpoint probes | valid empty array | NO-GO; target request logs were not collected in this snapshot |

The current state is an expected production `NO-GO`, not a failed local task.
Run the safe read-only gate and record only its fixed findings:

```bash
scripts/check-testflight-backend.sh
```

That snapshot exited `1` with exactly these safe findings:

- `Cloud Run production revision maxScale is not exactly 1`
- `GEMINI_API_KEY is not exactly one pinned secret-backed entry`
- `GEMINI_MODEL is not exactly one direct value set to gemini-3.6-flash`
- `public access or application-layer protection is not compliant`
- `/privacy did not return HTTP 200`
- `/support did not return HTTP 200`
- `Cloud Run logs are not a nonempty JSON array`

No environment value, IAM identity/policy, or log entry was printed.

For the post-promotion identity check, the same gate accepts only a specific
expected production revision:

```bash
KALORIES_EXPECTED_REVISION="${KALORIES_CANDIDATE_REVISION}" \
  scripts/check-testflight-backend.sh
```

It describes the immutable revision actually receiving 100% traffic. It does
not trust the mutable service template or `latestReadyRevisionName`.

## Gate ledger

| Gate | Current state | Required evidence |
| --- | --- | --- |
| Local code/pages | PASS, local only | Full backend and frontend suites, typecheck, build, dependency/import checks, clean commit |
| Read-only production preflight | NO-GO | Fixed findings cleared; immutable production revision and targeted logs verified |
| Access/abuse-protection architecture | NO-GO | Separate user-approved design, implementation, tests, and machine-verifiable gate |
| Task 6 mutation authorization | BLOCKED | Access gate first; then fresh approval of every mutation listed below |
| Provider privacy | UNVERIFIED | Paid tier, developer logging disabled, dataset sharing disabled, official terms evidence |
| Enforceable provider quota | UNVERIFIED | Exact quota ID/dimensions and settled granted/preferred RPD `200` |
| Budget alert | UNVERIFIED | Later user-approved amount and read-back; alert does not cap spend |
| Zero-traffic candidate | PENDING | Tag resolves once to immutable revision; aggregate revision traffic is exactly `0` |
| Real-image/schema/latency/cost | UNVERIFIED | Synthetic image, strict real backend contract, under 20s, usage/cost evidence |
| Candidate logs | UNVERIFIED | Nonempty target request logs and recursive safe scan |
| Promotion | PENDING | Every preceding gate PASS; exact candidate promoted and postchecked |
| Old-key revocation | PENDING | Only after promotion and replacement-key health/log evidence |
| Rollback | READY AS PROCEDURE ONLY | Exact prior revision and no return to revoked plaintext credential |
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

## 2. Access architecture hard stop

The service currently grants `allUsers` invocation and the repository has no
machine-verifiable application-layer access protection. Therefore Task 6 and
external TestFlight are hard `NO-GO`. Do not add or preserve public access via
a deploy flag. The later security design requires its own user confirmation,
implementation, threat review, and acceptance evidence.

Invited-testers-only wording, age `18+`, maxScale `1`, RPD `200`, a budget
alert, and the process-local token bucket are loss controls; they are not access
control and do not identify or authorize a caller.

The preflight reads Cloud Run IAM into a private file and emits only a boolean
finding. Never print an IAM policy or its members.

## 3. Exact Task 6 confirmation

After the access architecture passes, stop again and ask the user to confirm
each mutation explicitly:

1. enable only the individually listed missing APIs;
2. create/restrict API key `kalories-gemini-testflight` if absent;
3. create secret `kalories-gemini-api-key` if absent and add one pinned version;
4. add exactly one runtime service account `secretAccessor` binding;
5. update only `GEMINI_API_KEY` and `GEMINI_MODEL`, plus max instances,
   concurrency and timeout, in a zero-traffic candidate;
6. create exact verified quota preference RPD `200`;
7. create the user-approved monthly budget alert;
8. promote the exact immutable candidate revision to 100%;
9. revoke the exact old API key only after promotion succeeds.

Approval of this runbook or Tasks 1–5 is not Task 6 approval.

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

These future Task 6 commands keep key material in mode-600 private files,
remove any implicit newline, require a nonempty value without CR/LF, and read
back a concrete enabled secret version. They never pipe a key through a shell
without `pipefail` and never use `latest`.

```bash
set -euo pipefail
umask 077
secret_tmp="$(mktemp -d)"
key_metadata_json="${secret_tmp}/key-metadata.json"
key_material_json="${secret_tmp}/key-material.json"
key_material_file="${secret_tmp}/key-material"
secret_version_create_json="${secret_tmp}/secret-version-create.json"
secret_version_readback_json="${secret_tmp}/secret-version-readback.json"
cleanup_secret_material() {
  local secret_file
  for secret_file in \
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

if ! gcloud services api-keys describe kalories-gemini-testflight \
  --project=zhang23-23 --format=json >"${key_metadata_json}" 2>/dev/null; then
  gcloud services api-keys create \
    --project=zhang23-23 \
    --key-id=kalories-gemini-testflight \
    --display-name='Kalories Gemini TestFlight' \
    --api-target=service=generativelanguage.googleapis.com \
    --format=json >"${key_metadata_json}"
fi
if ! jq -e '
  (.restrictions.apiTargets // []) as $targets
  | (($targets | length) == 1
     and $targets[0].service == "generativelanguage.googleapis.com")
' "${key_metadata_json}" >/dev/null; then
  printf '%s\n' 'NO-GO: replacement key restriction is not exactly Gemini'
  exit 1
fi

gcloud services api-keys get-key-string kalories-gemini-testflight \
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
```

Resolve the actual runtime service account from the live service, then make and
read back exactly one secret-level accessor. Mutation output and the IAM policy
remain private; only fixed findings may be printed.

```bash
set -euo pipefail
umask 077
iam_tmp="$(mktemp -d)"
service_before_json="${iam_tmp}/service-before.json"
service_now_json="${iam_tmp}/service-now.json"
iam_mutation_json="${iam_tmp}/iam-mutation.json"
iam_readback_json="${iam_tmp}/iam-readback.json"
cleanup_iam() {
  local iam_file
  for iam_file in \
    "${service_before_json}" \
    "${service_now_json}" \
    "${iam_mutation_json}" \
    "${iam_readback_json}"; do
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
  [.bindings[]?
   | select(.role == "roles/secretmanager.secretAccessor")
   | .members[]?] as $accessors
  | (($accessors | length) == 1 and $accessors[0] == $member)
' "${iam_readback_json}" >/dev/null; then
  printf '%s\n' 'NO-GO: secret accessor read-back is not exact'
  exit 1
fi
printf '%s\n' 'CHECK secret accessor is exact; identities omitted'
```

Immediately before deployment, repeat the service describe and compare
`resourceVersion`; any drift aborts the candidate deployment:

```bash
gcloud run services describe kalories \
  --project=zhang23-23 --region=asia-northeast1 \
  --format=json >"${service_now_json}" 2>/dev/null
if ! jq -e --arg expected "${KALORIES_SERVICE_RESOURCE_VERSION}" '
  .metadata.resourceVersion == $expected
' "${service_now_json}" >/dev/null; then
  printf '%s\n' 'NO-GO: live service changed after concurrency pre-audit'
  exit 1
fi
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
dimension is forbidden.

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
  --service=generativelanguage.googleapis.com \
  --quota-id="${KALORIES_RPD_QUOTA_ID}" \
  --format=json >"${quota_readback_json}" 2>/dev/null
if ! jq -e --argjson expected_dimensions "${KALORIES_RPD_DIMENSIONS_JSON}" '
  (.name | endswith("/quotaPreferences/kalories-testflight-rpd-200"))
  and .reconciling == false
  and ((.quotaConfig.grantedValue | tonumber) == 200)
  and ((.quotaConfig.preferredValue | tonumber) == 200)
  and .dimensions == $expected_dimensions
' "${quota_readback_json}" >/dev/null; then
  printf '%s\n' 'NO-GO: quota preference is pending, partial, or mismatched'
  exit 1
fi
printf '%s\n' 'CHECK exact quota preference is settled at RPD 200'
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
  --threshold-rule=percent=0.50 \
  --threshold-rule=percent=0.80 \
  --threshold-rule=percent=1.00 \
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
valid = (
    document.get("displayName") == "Kalories TestFlight monthly alert"
    and document.get("budgetFilter", {}).get("projects")
    == [f"projects/{project_number}"]
    and document.get("budgetFilter", {}).get("calendarPeriod") == "MONTH"
    and money.get("currencyCode") == match.group(2)
    and actual == Decimal(match.group(1))
    and thresholds == [Decimal("0.5"), Decimal("0.8"), Decimal("1")]
)
raise SystemExit(0 if valid else 1)
PY
then
  printf '%s\n' 'NO-GO: budget alert read-back is mismatched'
  exit 1
fi
printf '%s\n' 'CHECK user-approved budget alert read-back passed'
```

## 9. Zero-traffic immutable candidate

Only after all prior gates and confirmation, update named settings without
clearing unrelated configuration. Do not grant public access. The secret env is
pinned to the verified numeric version.

```bash
set -euo pipefail
: "${KALORIES_SECRET_VERSION:?Use the verified numeric secret version}"
if [[ ! "${KALORIES_SECRET_VERSION}" =~ ^[1-9][0-9]*$ ]]; then
  printf '%s\n' 'NO-GO: secret version is not pinned'
  exit 1
fi
if ! gcloud run deploy kalories \
  --source=. \
  --project=zhang23-23 \
  --region=asia-northeast1 \
  --remove-env-vars=GEMINI_API_KEY,GEMINI_MODEL \
  --update-secrets=GEMINI_API_KEY=kalories-gemini-api-key:${KALORIES_SECRET_VERSION} \
  --update-env-vars=GEMINI_MODEL=gemini-3.6-flash \
  --max-instances=1 \
  --concurrency=4 \
  --timeout=30s \
  --no-traffic \
  --tag=testflight-candidate >/dev/null; then
  printf '%s\n' 'NO-GO: zero-traffic candidate deploy failed'
  exit 1
fi
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
candidate_traffic_total="$(jq -er --arg revision "${KALORIES_CANDIDATE_REVISION}" '
  [.status.traffic[]?
   | select(.revisionName == $revision)
   | (.percent // 0)]
  | add // 0
' "${candidate_service_json}")"
if [[ "${candidate_traffic_total}" != 0 ]]; then
  printf '%s\n' 'NO-GO: candidate revision traffic is not zero'
  exit 1
fi

gcloud run revisions describe "${KALORIES_CANDIDATE_REVISION}" \
  --project=zhang23-23 --region=asia-northeast1 \
  --format=json >"${candidate_revision_json}" 2>/dev/null
if ! jq -e \
  --arg revision "${KALORIES_CANDIDATE_REVISION}" \
  --arg secret_version "${KALORIES_SECRET_VERSION}" '
  def all_env: [.spec.containers[]?.env[]?, .containers[]?.env[]?];
  ([
    .metadata.annotations["autoscaling.knative.dev/maxScale"]?,
    .scaling.maxInstanceCount?,
    .spec.scaling.maxInstanceCount?
  ] | map(select(. != null) | tostring)) as $max_values
  | all_env as $env
  | [$env[] | select(.name? == "GEMINI_API_KEY")] as $keys
  | [$env[] | select(.name? == "GEMINI_MODEL")] as $models
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
  and (($images | length) == 1 and ($images[0] | test("@sha256:[0-9a-fA-F]{64}$")))
' "${candidate_revision_json}" >/dev/null; then
  printf '%s\n' 'NO-GO: immutable candidate revision is noncompliant'
  exit 1
fi
printf '%s\n' 'CHECK immutable candidate is compliant and has aggregate traffic zero'
```

The model remains `gemini-3.6-flash`; deprecated sampling fields such as
`temperature`, `top_p`, and `top_k` remain omitted. Live image/schema behavior,
latency under 20 seconds, and cost are still unverified at this point.

## 10. Candidate request, strict schema, and targeted safe logs

Use one generated non-personal synthetic meal image outside the repository.
Keep request, response and logs private. Every curl command must succeed at the
transport layer as well as return HTTP 200.

```bash
set -euo pipefail
: "${KALORIES_CANDIDATE_URL:?Resolve candidate URL first}"
: "${KALORIES_CANDIDATE_REVISION:?Resolve candidate revision first}"
: "${KALORIES_SYNTHETIC_MEAL_IMAGE:?Set a generated non-personal JPEG path}"
test -f "${KALORIES_SYNTHETIC_MEAL_IMAGE}"
umask 077
candidate_test_tmp="$(mktemp -d)"
candidate_payload_json="${candidate_test_tmp}/request.json"
candidate_response_json="${candidate_test_tmp}/response.json"
candidate_logs_json="${candidate_test_tmp}/logs.json"
cleanup_candidate_test() {
  local candidate_test_file
  for candidate_test_file in \
    "${candidate_payload_json}" \
    "${candidate_response_json}" \
    "${candidate_logs_json}"; do
    if [[ -f "${candidate_test_file}" ]]; then unlink -- "${candidate_test_file}"; fi
  done
  if [[ -d "${candidate_test_tmp}" ]]; then rmdir -- "${candidate_test_tmp}"; fi
}
trap cleanup_candidate_test EXIT

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
request_metrics=''
if ! request_metrics="$(curl \
  --silent --show-error \
  --output "${candidate_response_json}" \
  --write-out '%{http_code} %{time_total}' \
  --connect-timeout 10 --max-time 20 \
  --header 'Content-Type: application/json' \
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
if ! .venv/bin/python - "${candidate_response_json}" <<'PY'
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
```

`AnalyzeResponse.model_validate_json` enforces the production Pydantic
contract: complete nested shape, strict types, enum values, numeric ranges,
nullability, forbidden extras, nonempty food names, unique assumption keys, and
the full deterministic assessment. It rejects string nutrients, invalid
confidence values, and an empty assessment. The HTTP result still does not
prove cost; record a separate project/model usage and cost observation.

Read logs after the target request, by immutable candidate revision. A valid
nonempty JSON array and a target request log for `/api/analyze` are mandatory.
The recursive scan rejects sensitive keys or values including Authorization,
`x-goog-api-key`, API key shapes, Bearer values, long base64/image data,
request/providerResponse bodies, assessment, and nutrients. It never prints a
match.

```bash
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
if jq -e '
  def normalized_key: ascii_downcase | gsub("[-_]"; "");
  def sensitive_key:
    normalized_key as $key
    | [
        "authorization", "xgoogapikey", "apikey", "geminiapikey",
        "request", "requestbody", "providerrequest", "providerresponse",
        "responsebody", "assessment", "nutrients", "image", "prompt",
        "contents", "candidates"
      ]
    | index($key) != null;
  any(.. | objects | keys_unsorted[]?; sensitive_key)
  or any(.. | strings;
    test("(?i)data:image/|authorization:|api[_-]?key[=:]|bearer[[:space:]]+[A-Za-z0-9._~+/-]+=*|AIza[0-9A-Za-z_-]{35}|[A-Za-z0-9+/]{256,}={0,2}"))
' "${candidate_logs_json}" >/dev/null; then
  printf '%s\n' 'NO-GO: candidate logs contain sensitive application data'
  exit 1
fi
if ! jq -e --arg revision "${KALORIES_CANDIDATE_REVISION}" '
  any(.[];
    .resource.labels.revision_name? == $revision
    and ((.httpRequest.requestUrl? // "") | endswith("/api/analyze"))
    and .httpRequest.status? == 200)
' "${candidate_logs_json}" >/dev/null; then
  printf '%s\n' 'NO-GO: candidate target request log is missing'
  exit 1
fi
printf '%s\n' 'CHECK candidate target request log collected; safe scan passed'
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
  scripts/check-testflight-backend.sh; then
  printf '%s\n' 'NO-GO: promoted revision failed exact production postcheck'
  exit 1
fi
```

The postcheck proves that the exact candidate revision is the sole production
revision at aggregate 100% traffic, then describes and validates that revision.
A pre-existing compliant production revision cannot make a failed promotion
look successful. Repeat the real-image request and targeted safe-log gate
against production before touching the old credential.

Old-key deletion is a separate, freshly confirmed mutation. Resolve by metadata
identity, never by key value; exclude `kalories-gemini-testflight`. Run only
after successful promotion and replacement-key production checks:

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
  kalories-gemini-testflight --project=zhang23-23 --location=global \
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
  kalories-gemini-testflight --project=zhang23-23 --location=global \
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
  kalories-gemini-testflight --project=zhang23-23 --location=global \
  --format='value(deleteTime)')"
if [[ -z "${old_delete_time_after}" || -n "${replacement_delete_time_after}" ]]; then
  printf '%s\n' 'NO-GO: old API key revocation verification failed'
  exit 1
fi
printf '%s\n' 'CHECK old key revoked; replacement remains active'
```

The exact prior production revision in this baseline is
`kalories-00003-djq`. Traffic rollback is:

```bash
if ! gcloud run services update-traffic kalories \
  --project=zhang23-23 \
  --region=asia-northeast1 \
  --to-revisions=kalories-00003-djq=100 >/dev/null; then
  printf '%s\n' 'NO-GO: rollback traffic command failed'
  exit 1
fi
KALORIES_EXPECTED_REVISION=kalories-00003-djq \
  scripts/check-testflight-backend.sh
```

Rollback changes traffic only. It must never restore a revoked plaintext key.
If the prior code cannot use the new pinned secret, keep the safe revision and
fix forward.

## 12. Runtime limits and monitoring

The anonymous global token bucket is process-local, resets on restart, and has
no per-user fairness; one caller can starve others. It runs after image decode,
so CPU and memory may be spent before a 429. Therefore maxScale `1` and
monitoring of HTTP 429, memory, latency, concurrency saturation, and restarts
remain required for the controlled phase. Provider RPD is a cost/request loss
cap, not CPU protection; a budget alert is only notification. None is access
control.

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
