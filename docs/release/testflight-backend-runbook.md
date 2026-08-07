# TestFlight backend release runbook

This runbook keeps evidence gates separate. A PASS at one gate never implies a
PASS at a later gate. Commands in the current task are read-only; every command
that mutates Google Cloud is reserved for Task 6 and requires fresh user
confirmation immediately before use.

## Fixed scope and identifiers

| Item | Fixed value |
| --- | --- |
| Project | `zhang23-23` |
| Region | `asia-northeast1` |
| Cloud Run service | `kalories` |
| Model | `gemini-3.6-flash` |
| Replacement API key ID | `kalories-gemini-testflight` |
| Secret Manager secret | `kalories-gemini-api-key` |
| Preferred Gemini request limit | 200 requests per day, only after the exact enforceable quota ID is verified |
| Controlled audience | Invited testers who are 18 or older |

Never print, paste, compare, screenshot, or commit an API key value. Do not use
shell tracing. Keep service and log JSON in a `umask 077` temporary directory,
and inspect credentials only by name and boolean structure.

## Read-only baseline

Captured at `2026-08-08 07:14:27 JST (+0900)`.

| Evidence | Observed state | Gate result |
| --- | --- | --- |
| Active gcloud account | present; identity omitted | VERIFIED |
| Ready revision | `kalories-00003-djq` | VERIFIED |
| Production traffic | `kalories-00003-djq=100%` | VERIFIED |
| Service URL | `https://kalories-sxielk4wua-an.a.run.app` | VERIFIED |
| maxScale | `20` | NO-GO; must be exactly `1` |
| `GEMINI_API_KEY` has a plaintext `value` | `true` | NO-GO |
| `GEMINI_API_KEY` has a secret reference | `false` | NO-GO |
| `GEMINI_MODEL` is one compliant direct entry | `false` | NO-GO |
| `GET /health` | HTTP 200 | transport evidence only |
| `GET /privacy/` | HTTP 404 | NO-GO |
| `GET /support/` | HTTP 404 | NO-GO |
| Latest 200 Cloud Run revision log entries | no forbidden literal found | VERIFIED for this snapshot only |

The read-only preflight exited nonzero with these fixed findings:

- `Cloud Run maxScale is not exactly 1`
- `GEMINI_API_KEY is not exactly one secret-backed entry without plaintext value`
- `GEMINI_MODEL is not exactly one direct value set to gemini-3.6-flash`
- `/privacy did not return HTTP 200`
- `/support did not return HTTP 200`

This is the expected baseline, not a failed local implementation. Run it again
immediately before any mutation:

```bash
scripts/check-testflight-backend.sh
```

## Gate ledger

| Gate | Current state | Evidence required to advance |
| --- | --- | --- |
| Local code and pages | PASS, local only | Full backend/page suites, frontend tests, typecheck, build, dependency checks, clean committed revision |
| Read-only production preflight | NO-GO | Script exits 0 with no fixed findings |
| Task 6 mutation authorization | PENDING | User reconfirms project, region, service, key ID, secret name, quota plan, budget amount, and zero-traffic deployment |
| Required APIs | PENDING | Read-only API inventory and successful enablement of only approved missing APIs |
| Restricted key and secret | PENDING | Key restriction, secret version, narrow runtime access, secret-backed candidate, no plaintext value |
| Provider privacy | UNVERIFIED | Paid tier, developer logging disabled, dataset sharing disabled, terms evidence recorded |
| Enforceable provider quota | UNVERIFIED | Exact project/model RPD quota ID and active preference value `200` |
| Budget alert | UNVERIFIED | User-approved amount and project-filtered 50/80/100 percent alerts |
| Zero-traffic candidate | PENDING | Ready tagged revision with zero production traffic and immutable revision ID recorded |
| Candidate pages and transport | PENDING | Candidate `/health`, `/privacy/`, and `/support/` each return 200 |
| Real synthetic-meal contract | UNVERIFIED | HTTP 200, schema, deterministic assessment, latency under 20 seconds, and request cost evidence |
| Candidate logs | UNVERIFIED | No forbidden literal or provider response body in the inspected candidate logs |
| Production promotion | PENDING | Every earlier gate passes before traffic changes |
| Old-key revocation | PENDING | Production remains healthy after promotion, then old resource identity is revoked |
| Rollback | READY AS PROCEDURE ONLY | Prior revision remains identified; rollback constraints are understood |
| TestFlight upload | OUTSIDE THIS BACKEND TASK | Backend production gates pass, then signed build upload is separately verified |
| TestFlight processing/testing | OUTSIDE THIS BACKEND TASK | App Store Connect processing completes and only invited 18+ testers receive access |
| Public App Store release | OUT OF SCOPE / UNRESOLVED | Separate private-support, age, privacy, review, approval, release, propagation, and storefront gates |

No PENDING, UNVERIFIED, or OUT-OF-SCOPE row is a PASS.

## 1. Clean local candidate

Run from the intended worktree and verify the branch/commit before using Cloud
Run source deployment:

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

Local success proves the code and static pages in that checkout. It proves
neither deployment nor provider behavior.

## 2. Explicit Task 6 authorization checkpoint

Stop and obtain fresh user confirmation for exactly:

- project `zhang23-23`, region `asia-northeast1`, service `kalories`;
- replacement key ID `kalories-gemini-testflight`;
- secret `kalories-gemini-api-key`;
- an enforceable Gemini RPD preference of `200`, after its exact quota ID is found;
- a monthly budget amount supplied and approved by the user;
- deployment of a tagged candidate with `--no-traffic` and max instances `1`.

Approval of this document or Tasks 1–5 is not approval to run Task 6.

## 3. Required API evidence

The complete workflow depends on these services:

- `run.googleapis.com`
- `cloudbuild.googleapis.com`
- `artifactregistry.googleapis.com`
- `logging.googleapis.com`
- `apikeys.googleapis.com`
- `generativelanguage.googleapis.com`
- `secretmanager.googleapis.com`
- `cloudquotas.googleapis.com`
- `cloudbilling.googleapis.com`
- `billingbudgets.googleapis.com`

Verify enabled names read-only. A missing service is a NO-GO, not permission to
enable it. The current Task 6 plan permits enabling only the following three
control-plane services after confirmation:

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
    --format='value(config.name)' |
    rg -qx -F "${required_api}"; then
    printf 'CHECK required API enabled: %s\n' "${required_api}"
  else
    printf 'NO-GO: required API missing: %s\n' "${required_api}"
    missing_api=true
  fi
done
if [[ "${missing_api}" == true ]]; then
  exit 1
fi
```

After the inventory records the missing set and the user reconfirms it, the
currently approved enablement command is:

```bash
gcloud services enable \
  cloudquotas.googleapis.com \
  cloudbilling.googleapis.com \
  billingbudgets.googleapis.com \
  --project=zhang23-23
```

If any other required service is missing, stop and reconfirm the expanded API
change rather than broadening this command.

## 4. Restricted key, secret, and runtime identity

After authorization, create or verify the replacement key by resource ID and
Gemini API restriction. Never call `get-key-string` by itself or send its
output to the terminal.

```bash
if ! gcloud services api-keys describe kalories-gemini-testflight \
  --project=zhang23-23 >/dev/null 2>&1; then
  gcloud services api-keys create \
    --project=zhang23-23 \
    --key-id=kalories-gemini-testflight \
    --display-name='Kalories Gemini TestFlight' \
    --api-target=service=generativelanguage.googleapis.com
fi
KALORIES_KEY_RESOURCE="$(gcloud services api-keys describe \
  kalories-gemini-testflight \
  --project=zhang23-23 \
  --format='value(name)')"
test -n "${KALORIES_KEY_RESOURCE}"
if ! gcloud services api-keys describe kalories-gemini-testflight \
  --project=zhang23-23 \
  --format=json |
  jq -e '
    (.restrictions.apiTargets // []) as $targets
    | (($targets | length) == 1
       and $targets[0].service == "generativelanguage.googleapis.com")
  ' >/dev/null; then
  printf '%s\n' 'NO-GO: replacement API key restriction is not exactly Gemini'
  exit 1
fi
```

Pipe the value directly into Secret Manager:

```bash
if ! gcloud secrets describe kalories-gemini-api-key \
  --project=zhang23-23 >/dev/null 2>&1; then
  gcloud secrets create kalories-gemini-api-key \
    --project=zhang23-23 \
    --replication-policy=automatic
fi
gcloud services api-keys get-key-string "${KALORIES_KEY_RESOURCE}" \
  --project=zhang23-23 \
  --format='value(keyString)' |
  gcloud secrets versions add kalories-gemini-api-key \
    --project=zhang23-23 \
    --data-file=-
unset KALORIES_KEY_RESOURCE
```

Resolve the runtime service account. If the service has no explicit identity,
use the default compute service account. Grant access on this secret only:

```bash
KALORIES_RUNTIME_SA="$(gcloud run services describe kalories \
  --project=zhang23-23 \
  --region=asia-northeast1 \
  --format='value(spec.template.spec.serviceAccountName)')"
if [[ -z "${KALORIES_RUNTIME_SA}" ]]; then
  KALORIES_PROJECT_NUMBER="$(gcloud projects describe zhang23-23 \
    --format='value(projectNumber)')"
  test -n "${KALORIES_PROJECT_NUMBER}"
  KALORIES_RUNTIME_SA="${KALORIES_PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
fi
test -n "${KALORIES_RUNTIME_SA}"
gcloud secrets add-iam-policy-binding kalories-gemini-api-key \
  --project=zhang23-23 \
  --member="serviceAccount:${KALORIES_RUNTIME_SA}" \
  --role=roles/secretmanager.secretAccessor
unset KALORIES_PROJECT_NUMBER KALORIES_RUNTIME_SA
```

Record only resource names, boolean restriction/access results, and secret
version identifiers. Do not record a key value.

## 5. Provider privacy gate

Before candidate deployment, verify in the Gemini project and current official
terms that all of the following are true:

1. The project is on a paid Gemini Developer API tier.
2. Developer logging is disabled.
3. Dataset sharing is disabled.
4. Paid-service terms say submitted content is not used to improve Google products.

Record project identity, visible tier label, settings as booleans, terms URLs,
and the verification date. Current paid-tier and logging/sharing state are not
verified by the repository or preflight.

The conservative privacy position remains:

- default abuse-monitoring retention can be up to 55 days;
- ZDR approval is not confirmed, so there is no zero-retention claim;
- App Privacy answers disclose User Content → Photos or Videos for App
  Functionality unless a later project-approved ZDR configuration and fresh
  legal/privacy review change that conclusion.

## 6. Enforceable quota gate

Discover the quota first. Do not guess a quota ID from its display name.

```bash
umask 077
quota_tmp="$(mktemp -d)"
quota_json="${quota_tmp}/gemini-quotas.json"
cleanup_quota() {
  if [[ -f "${quota_json}" ]]; then unlink -- "${quota_json}"; fi
  if [[ -d "${quota_tmp}" ]]; then rmdir -- "${quota_tmp}"; fi
}
trap cleanup_quota EXIT
gcloud beta quotas info list \
  --project=zhang23-23 \
  --service=generativelanguage.googleapis.com \
  --format=json >"${quota_json}"
jq -r '.[] | [.quotaId, (.metric // ""), (.dimensions // {})] | @json' \
  "${quota_json}"
```

An operator must verify that the selected quota is enforceable, project-scoped,
applies to the selected model, and represents requests per day. Only then:

```bash
: "${KALORIES_RPD_QUOTA_ID:?Set only after verifying the exact enforceable RPD quota ID}"
test -n "${KALORIES_RPD_QUOTA_ID}"
gcloud beta quotas preferences create \
  --project=zhang23-23 \
  --service=generativelanguage.googleapis.com \
  --quota-id="${KALORIES_RPD_QUOTA_ID}" \
  --preferred-value=200 \
  --preference-id=kalories-testflight-rpd-200 \
  --allow-high-percentage-quota-decrease \
  --allow-quota-decrease-below-usage
unset KALORIES_RPD_QUOTA_ID
cleanup_quota
trap - EXIT
```

If no enforceable RPD quota exists, external TestFlight remains NO-GO. A budget
alert is not a quota and does not cap spend.

## 7. Budget-alert gate

The monthly amount requires later explicit user approval in the billing
account currency. Validate that it is positive before creating the alert.

```bash
: "${KALORIES_MONTHLY_BUDGET_AMOUNT:?Set the user-approved positive amount}"
if ! awk -v amount="${KALORIES_MONTHLY_BUDGET_AMOUNT}" '
  BEGIN { exit !(amount ~ /^[0-9]+([.][0-9]+)?$/ && amount + 0 > 0) }
'; then
  printf '%s\n' 'NO-GO: budget amount must be a positive number'
  exit 1
fi
KALORIES_BILLING_ACCOUNT="$(gcloud billing projects describe zhang23-23 \
  --format='value(billingAccountName)')"
test -n "${KALORIES_BILLING_ACCOUNT}"
gcloud billing budgets create \
  --billing-account="${KALORIES_BILLING_ACCOUNT}" \
  --display-name='Kalories TestFlight monthly alert' \
  --budget-amount="${KALORIES_MONTHLY_BUDGET_AMOUNT}" \
  --filter-projects=projects/zhang23-23 \
  --calendar-period=month \
  --threshold-rule=percent=0.50 \
  --threshold-rule=percent=0.80 \
  --threshold-rule=percent=1.00
unset KALORIES_BILLING_ACCOUNT KALORIES_MONTHLY_BUDGET_AMOUNT
```

Record the budget display name, approved amount/currency, project filter, and
thresholds. Alerts notify; they do not stop requests or cap cost.

## 8. Zero-traffic candidate

Deploy only the clean committed revision. This creates a candidate and does not
authorize production traffic:

```bash
gcloud run deploy kalories \
  --source . \
  --project=zhang23-23 \
  --region=asia-northeast1 \
  --allow-unauthenticated \
  --set-secrets=GEMINI_API_KEY=kalories-gemini-api-key:latest \
  --set-env-vars=GEMINI_MODEL=gemini-3.6-flash \
  --max-instances=1 \
  --concurrency=4 \
  --timeout=30s \
  --no-traffic \
  --tag=testflight-candidate
```

Resolve candidate URL and immutable revision from service JSON, not free-form
deploy output. Verify zero production traffic, maxScale `1`, one secret-backed
key entry without plaintext `value`, and one direct compliant model entry.
The preflight must reject missing, duplicate, plaintext, or ambiguous entries.

```bash
umask 077
candidate_state_tmp="$(mktemp -d)"
candidate_service_json="${candidate_state_tmp}/service.json"
cleanup_candidate_state() {
  if [[ -f "${candidate_service_json}" ]]; then unlink -- "${candidate_service_json}"; fi
  if [[ -d "${candidate_state_tmp}" ]]; then rmdir -- "${candidate_state_tmp}"; fi
}
trap cleanup_candidate_state EXIT
gcloud run services describe kalories \
  --project=zhang23-23 \
  --region=asia-northeast1 \
  --format=json >"${candidate_service_json}"
KALORIES_CANDIDATE_URL="$(jq -er '
  [.status.traffic[]? | select(.tag == "testflight-candidate")]
  | if length == 1 and ((.[0].percent // 0) == 0)
    then .[0].url
    else empty
    end
' "${candidate_service_json}")"
KALORIES_CANDIDATE_REVISION="$(jq -er '
  [.status.traffic[]? | select(.tag == "testflight-candidate")]
  | if length == 1 and ((.[0].percent // 0) == 0)
    then .[0].revisionName
    else empty
    end
' "${candidate_service_json}")"
test -n "${KALORIES_CANDIDATE_URL}"
test -n "${KALORIES_CANDIDATE_REVISION}"
if ! jq -e '
  def all_env:
    [.spec.template.spec.containers[]?.env[]?, .template.containers[]?.env[]?];
  ([
    .spec.template.metadata.annotations["autoscaling.knative.dev/maxScale"]?,
    .template.scaling.maxInstanceCount?,
    .spec.template.scaling.maxInstanceCount?
  ] | map(select(. != null) | tostring)) as $max_values
  | all_env as $env
  | [$env[] | select(.name? == "GEMINI_API_KEY")] as $key_entries
  | ([$key_entries[0].valueFrom.secretKeyRef?, $key_entries[0].valueSource.secretKeyRef?]
      | map(select(. != null))) as $key_refs
  | [$env[] | select(.name? == "GEMINI_MODEL")] as $model_entries
  | (($max_values | length) == 1 and $max_values[0] == "1")
  and (($key_entries | length) == 1)
  and ($key_entries[0] | has("value") | not)
  and (($key_refs | length) == 1)
  and ($key_refs[0] | type == "object" and length > 0)
  and (($model_entries | length) == 1)
  and ($model_entries[0].value? == "gemini-3.6-flash")
  and ($model_entries[0] | has("valueFrom") | not)
  and ($model_entries[0] | has("valueSource") | not)
' "${candidate_service_json}" >/dev/null; then
  printf '%s\n' 'NO-GO: candidate scaling or environment structure is noncompliant'
  exit 1
fi
unlink -- "${candidate_service_json}"
rmdir -- "${candidate_state_tmp}"
trap - EXIT
```

The model contract is `gemini-3.6-flash`. Deprecated sampling fields including
`temperature`, `top_p`, and `top_k` remain omitted. Local tests do not verify a
live image, provider schema behavior, latency below 20 seconds, or actual cost.

## 9. Candidate request and safe logs

Use only a generated, non-personal synthetic meal image stored outside this
repository: a generic Japanese grilled salmon set with rice, miso soup, and a
spinach side dish; no people, hands, text, brand, or private environment.

Run exactly one request against the candidate tag URL. Keep the request and
response in a private temporary directory and never print the image/base64.
Require:

- HTTP 200 within 20 seconds;
- `food_detected` true;
- all seven nutrient keys and confidence fields;
- deterministic `assessment` and no raw provider field;
- measured latency and a separately recorded cost observation;
- candidate `/health`, `/privacy/`, and `/support/` all HTTP 200.

The operator sets `KALORIES_SYNTHETIC_MEAL_IMAGE` to the generated JPEG outside
the repository. This command prints only fixed checks, HTTP status, and latency:

```bash
: "${KALORIES_CANDIDATE_URL:?Resolve the zero-traffic candidate URL first}"
: "${KALORIES_CANDIDATE_REVISION:?Resolve the immutable candidate revision first}"
: "${KALORIES_SYNTHETIC_MEAL_IMAGE:?Set the synthetic JPEG path outside the repository}"
test -f "${KALORIES_SYNTHETIC_MEAL_IMAGE}"
umask 077
candidate_test_tmp="$(mktemp -d)"
candidate_payload_json="${candidate_test_tmp}/request.json"
candidate_response_json="${candidate_test_tmp}/response.json"
candidate_logs_json="${candidate_test_tmp}/logs.json"
cleanup_candidate_test() {
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
  endpoint_status="$(curl \
    --silent \
    --output /dev/null \
    --write-out '%{http_code}' \
    --connect-timeout 10 \
    --max-time 20 \
    "${KALORIES_CANDIDATE_URL}${endpoint_path}")"
  if [[ "${endpoint_status}" != 200 ]]; then
    printf 'NO-GO: candidate /%s is not HTTP 200\n' "${endpoint_name}"
    exit 1
  fi
  printf 'CHECK candidate /%s: HTTP 200\n' "${endpoint_name}"
done

base64 <"${KALORIES_SYNTHETIC_MEAL_IMAGE}" |
  tr -d '\n' |
  jq -Rs '{image: ("data:image/jpeg;base64," + .)}' >"${candidate_payload_json}"
request_metrics="$(curl \
  --silent \
  --show-error \
  --output "${candidate_response_json}" \
  --write-out '%{http_code} %{time_total}' \
  --connect-timeout 10 \
  --max-time 20 \
  --header 'Content-Type: application/json' \
  --data-binary "@${candidate_payload_json}" \
  "${KALORIES_CANDIDATE_URL}/api/analyze")"
request_status="${request_metrics%% *}"
request_latency_seconds="${request_metrics#* }"
if [[ "${request_status}" != 200 ]] ||
  ! awk -v seconds="${request_latency_seconds}" 'BEGIN { exit !(seconds < 20) }'; then
  printf '%s\n' 'NO-GO: candidate real-image status or latency failed'
  exit 1
fi
jq -e '
  def nutrient_keys:
    ["calories_kcal", "protein_g", "carbs_g", "fat_g", "fiber_g", "sugar_g", "sodium_mg"];
  .food_detected == true
  and ((.nutrients | keys) == (nutrient_keys | sort))
  and ((.confidence.nutrients | keys) == (nutrient_keys | sort))
  and (.assessment | type == "object")
  and (has("provider") | not)
  and (has("raw_provider") | not)
' "${candidate_response_json}" >/dev/null
printf 'CHECK candidate real-image: HTTP 200, schema valid, latency %ss\n' \
  "${request_latency_seconds}"
```

The HTTP result does not prove cost. Record a separate project/model usage and
cost observation from the provider/billing control plane after the request.

Read logs by the immutable candidate revision, store the latest 200 entries in
the private temporary directory, and use `rg -q -F` only. Any literal
`data:image/`, `GEMINI_API_KEY`, `Authorization:`, or `api_key=`, any base64
payload, or any provider response body is NO-GO. A read failure is also NO-GO.
Record only safe boolean findings, then delete the exact temporary files.

```bash
if ! gcloud logging read \
  "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"kalories\" AND resource.labels.location=\"asia-northeast1\" AND resource.labels.revision_name=\"${KALORIES_CANDIDATE_REVISION}\"" \
  --project=zhang23-23 \
  --limit=200 \
  --order=desc \
  --format=json >"${candidate_logs_json}" 2>/dev/null; then
  printf '%s\n' 'NO-GO: candidate log read failed'
  exit 1
fi
set +e
rg -q -F \
  -e 'data:image/' \
  -e 'GEMINI_API_KEY' \
  -e 'Authorization:' \
  -e 'api_key=' \
  "${candidate_logs_json}"
candidate_log_scan_status=$?
set -e
case "${candidate_log_scan_status}" in
  0) printf '%s\n' 'NO-GO: candidate logs contain a forbidden literal'; exit 1 ;;
  1) printf '%s\n' 'CHECK candidate logs: no forbidden literal in latest 200' ;;
  *) printf '%s\n' 'NO-GO: candidate log safety scan failed'; exit 1 ;;
esac
cleanup_candidate_test
trap - EXIT
unset KALORIES_SYNTHETIC_MEAL_IMAGE
```

## 10. Promote, revoke, and roll back

Promotion is allowed only after every gate above passes:

```bash
gcloud run services update-traffic kalories \
  --project=zhang23-23 \
  --region=asia-northeast1 \
  --to-latest
scripts/check-testflight-backend.sh
```

After successful promotion and post-promotion health/real-request/log checks,
identify the old credential by resource identity and creation context, exclude
`kalories-gemini-testflight`, and revoke the old credential. Never compare key
strings. Do not revoke it before promotion succeeds.

The exact prior revision is `kalories-00003-djq`. Traffic rollback is:

```bash
gcloud run services update-traffic kalories \
  --project=zhang23-23 \
  --region=asia-northeast1 \
  --to-revisions=kalories-00003-djq=100
```

This rolls back traffic only. It must not restore a revoked plaintext key. If
the prior revision cannot use the new secret, keep traffic on the candidate and
fix forward, or first create a safe revision of the old code with the new
secret reference.

## 11. Runtime abuse and observability limits

The anonymous global token bucket is process-local. It resets on restart,
provides no per-user fairness, and one caller can starve others. It runs after
image decoding, so CPU and memory can be spent before a 429 response. Therefore:

- maxScale `1` remains required for this controlled TestFlight phase;
- monitor HTTP 429 rate, memory, request latency, concurrency saturation, and
  instance restarts;
- an enforceable provider RPD cap limits provider requests/cost, but it is not
  CPU or memory abuse protection;
- the budget alert is notification only and is distinct from both controls.

## 12. TestFlight and public-release boundary

Backend promotion does not upload a build. TestFlight upload does not prove
processing. Processing does not invite testers. For this phase, distribution is
limited to invited testers who are 18 or older, and only after all backend and
privacy gates pass.

Public App Store distribution remains out of scope and unresolved. It requires
a non-public support channel, age/compliance review, current privacy answers,
App Review approval, any manual release action, propagation, and storefront
visibility as separate evidence gates.

## Evidence record after Task 6

Commit only sanitized evidence: timestamps, old/new revision names, traffic,
boolean secret/model findings, quota ID and value, budget display name and
thresholds, HTTP statuses, latency/cost summary, test counts, and boolean log
scan results. Exclude API key values, billing account ID, personal photos,
request base64, provider response bodies, and credentials.
