# Japan Production Backend Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote one immutable, App Check-protected, secret-backed, quota- and budget-controlled Kalories backend revision that can safely serve App Review and Japan App Store users.

**Architecture:** Reuse the tested FastAPI/Firebase App Check implementation and the fail-closed commands in `docs/release/testflight-backend-runbook.md`. Close provider privacy and cost gates first, deploy the approved source with zero traffic, verify the exact immutable candidate with public/no-token/valid-token/log checks, then promote only that revision and prohibit fallback to the legacy unauthenticated plaintext-secret revision.

**Tech Stack:** Google Cloud Run, Cloud Build, Secret Manager, Cloud Quotas, Cloud Billing Budgets, Firebase App Check, Apple App Attest, Gemini Developer API, `gcloud`, `jq`, `curl`, Python 3.12, Bash.

---

## Dependency and Scope

Required completed plan:

- `docs/superpowers/plans/2026-08-11-japan-app-store-release-foundation.md`

Fixed external scope:

| Item | Value |
| --- | --- |
| Project | `zhang23-23` |
| Project number | `788259830737` |
| Region | `asia-northeast1` |
| Cloud Run service | `kalories` |
| Public origin | `https://kalories-sxielk4wua-an.a.run.app` |
| Firebase iOS app ID | `1:788259830737:ios:a4459f14b5e8046297bef0` |
| Apple bundle | `com.ryuaistudio.kalories` |
| Model | `gemini-3.6-flash` |
| Replacement key ID | `kalories-gemini-testflight-v2` |
| Secret | `kalories-gemini-api-key` version `2` |
| App Check | required; App Attest for distributed builds |
| Maximum instances | `1` |
| Concurrency | `4` |
| Timeout | `30s` |
| Process limiter | 12 requests/minute, burst 4 |
| Provider quota | 200 GenerateContent requests/day for `gemini-3.6-flash` |
| Monthly budget alert | `3000JPY`, current-spend alerts at 50/80/100% |

This plan authorizes only the exact quota, budget, zero-traffic candidate, and
promotion described here after their preceding gates pass. It does not upload
an iOS build, edit App Store Connect, submit App Review, or release the app.
Deletion of the legacy key remains a separate destructive checkpoint.

## File Responsibility Map

### Create

- `docs/release/app-store-production-runbook.md` — public-release wrapper around
  the proven backend runbook with exact approved identities and sequence.
- `docs/release/app-store-production-evidence.md` — sanitized evidence ledger.

### Modify only if the live gate exposes a code defect

- `scripts/check-testflight-backend.sh` — gate logic; preserve safe fixed output.
- `tests/test_testflight_backend_gate.py` — test any gate correction first.
- focused `api/` or `lib/` source and tests — only for a reproduced blocker.

### Must not change

- any other Cloud project, service, region, Firebase app, Apple app, key, or
  secret;
- public IAM policy or service account unless a fresh audit proves it differs
  from the approved exact identity and the user separately authorizes repair;
- App Store Connect or distribution state;
- legacy key before exact promotion and replacement-path evidence pass.

## Current Read-Only Baseline

The 2026-08-11 read-only preflight exited 1 with these safe findings:

- production maxScale is not exactly 1;
- `GEMINI_API_KEY` is not exactly one pinned secret-backed entry;
- `GEMINI_MODEL` is not exactly `gemini-3.6-flash`;
- App Check enforcement/project/app variables are not the approved values;
- `/privacy` and `/support` are not HTTP 200;
- no-token POSTs are not the owned HTTP 401;
- target request logs are missing.

Cloud quota discovery found the exact daily request quota
`GenerateRequestsPerDayPerProjectPerModel` with dimension
`model=gemini-3.6-flash`; its current granted value was 10,000. No quota
preference or billing budget existed at that read-only snapshot.

## Task 1: Reprove the local source before any external mutation

**Files:**
- Read: `docs/release/app-store-foundation-evidence.md`
- Read: `docs/release/testflight-backend-runbook.md`
- Read: `scripts/check-testflight-backend.sh`

- [ ] **Step 1: Verify clean intended source**

```bash
git status --short --branch
git log -5 --oneline --decorate
git diff --check
```

Expected: intended public-release branch, completed foundation commits, and a
clean worktree.

- [ ] **Step 2: Rerun the complete local gate**

```bash
npm test
npm run lint
npm run build
.venv/bin/python -m unittest discover -s tests -p 'test_*.py' -v
.venv/bin/python -m compileall -q api lib tests
.venv/bin/python -c "import api.analyze, lib.nutrition, lib.rate_limit, lib.app_check"
uv pip check --python .venv/bin/python
docker build .
scripts/check-ios-app-check-release.sh --local
```

Expected: all commands pass. If any fails, stop before Cloud mutation and fix
the reproduced local defect through a focused test-first commit.

- [ ] **Step 3: Run a fresh read-only production preflight**

```bash
KALORIES_EXPECTED_FIREBASE_IOS_APP_ID='1:788259830737:ios:a4459f14b5e8046297bef0' \
  scripts/check-testflight-backend.sh
```

Expected before deployment: exit 1 with fixed safe findings only. If it emits a
secret, token, IAM identity, log body, or image content, stop and repair the
gate before continuing.

## Task 2: Create the public production wrapper and evidence ledger

**Files:**
- Create: `docs/release/app-store-production-runbook.md`
- Create: `docs/release/app-store-production-evidence.md`

- [ ] **Step 1: Create the wrapper runbook**

Create `docs/release/app-store-production-runbook.md`:

```markdown
# App Store Production Backend Runbook

Date: 2026-08-11
Design: docs/superpowers/specs/2026-08-10-japan-app-store-public-release-design.md
Command source: docs/release/testflight-backend-runbook.md

## Exact public-release overrides

- Project: zhang23-23
- Region/service: asia-northeast1 / kalories
- Firebase iOS app: 1:788259830737:ios:a4459f14b5e8046297bef0
- Model: gemini-3.6-flash
- Secret: kalories-gemini-api-key version 2
- Candidate tag: app-store-candidate
- Daily quota ID: GenerateRequestsPerDayPerProjectPerModel
- Daily quota dimension: model=gemini-3.6-flash
- Daily preferred/granted value: 200
- Quota preference ID: kalories-public-rpd-200
- Monthly budget: 3000JPY
- Budget display name: Kalories App Store monthly alert

## Required sequence

1. Clean local gate
2. Provider paid-service/privacy settings
3. Exact quota and budget read-back
4. Fresh service/IAM/resourceVersion audit
5. Zero-traffic immutable candidate
6. Candidate public/no-token/valid-token/schema/latency/log checks
7. Exact candidate promotion
8. Production postcheck and physical-iPhone App Attest analysis
9. Separate legacy-key deletion confirmation

No later row passes because an earlier row passes. Never move traffic to
kalories-00003-djq after legacy-key deletion.
```

- [ ] **Step 2: Create the initial sanitized evidence ledger**

Create `docs/release/app-store-production-evidence.md`:

```markdown
# App Store Production Backend Evidence

Date: 2026-08-11
Project/region/service: zhang23-23 / asia-northeast1 / kalories

| Gate | State |
| --- | --- |
| Local source | PASS |
| Fresh production preflight | NO-GO |
| Provider paid-service terms | UNVERIFIED |
| Developer logging disabled | UNVERIFIED |
| Dataset sharing disabled | UNVERIFIED |
| Daily model quota 200 | NOT CONFIGURED |
| Monthly 3000JPY budget alert | NOT CONFIGURED |
| Zero-traffic candidate | NOT DEPLOYED |
| Candidate real analysis | NOT RUN |
| Candidate safe-log scan | NOT RUN |
| Production promotion | NOT RUN |
| Physical-iPhone App Attest analysis | NOT RUN |
| Legacy key deletion | NOT RUN |

This ledger never records credentials, tokens, billing-account IDs, IAM
identities, images, response bodies, or log content.
```

- [ ] **Step 3: Commit the public wrapper and baseline ledger**

```bash
git add -- \
  docs/release/app-store-production-runbook.md \
  docs/release/app-store-production-evidence.md
git diff --cached --check
git commit -m "docs(release): add App Store production runbook"
```

## Task 3: Verify provider privacy and paid-service gates

**Files:**
- Modify: `docs/release/app-store-production-evidence.md`

- [ ] **Step 1: Verify the exact project and billing tier in Google AI Studio**

Use the authenticated official Google AI Studio/Cloud console. Select project
`zhang23-23`, then verify Gemini Developer API requests for
`gemini-3.6-flash` are governed by paid-service terms rather than the free tier.

Expected: exact project identity and paid tier are visible. A successful API
request, active billing account, or nonzero quota alone is not sufficient.

- [ ] **Step 2: Verify developer logging is disabled**

Open the official project logging controls and verify developer logging is
disabled for `zhang23-23`. Do not enable logging to test the switch.

Expected: disabled. If it is enabled, stop; changing it is a privacy mutation
that must be made explicitly and then read back before continuing.

- [ ] **Step 3: Verify dataset sharing is disabled**

Open the official dataset-sharing control for the exact project and verify no
sharing opt-in is active.

Expected: disabled. If enabled, stop and request exact authorization to turn it
off; do not publish while sharing is active.

- [ ] **Step 4: Recheck current official retention/paid-service terms**

Use only current official Google sources linked from
`public/privacy/index.html`. Confirm that the public policy's conservative
maximum-55-day abuse-monitoring statement and no-ZDR claim remain accurate.

Expected: the policy is not more favorable than the current official terms. If
terms changed, update the policy/test through the foundation plan and rerun its
full gate before deployment.

- [ ] **Step 5: Update and commit boolean evidence only**

Change the three provider rows to PASS and append the verification date and
official source URLs. Do not commit account screenshots or control-plane
identifiers.

```bash
git add -- docs/release/app-store-production-evidence.md
git diff --cached --check
git commit -m "docs(release): verify Gemini privacy controls"
```

## Task 4: Create and read back the exact daily quota

**Files:**
- Modify: `docs/release/app-store-production-evidence.md`

- [ ] **Step 1: Re-discover the exact quota before mutation**

```bash
quota_tmp="$(mktemp -d)"
quota_info_json="${quota_tmp}/quota-info.json"
gcloud beta quotas info list \
  --project=zhang23-23 \
  --service=generativelanguage.googleapis.com \
  --format=json >"${quota_info_json}"
jq -e '
  [.[]
   | select(.quotaId == "GenerateRequestsPerDayPerProjectPerModel")
   | select(.refreshInterval == "day")
   | select(.dimensions == ["model"])
   | select(any(.dimensionsInfos[]?;
       .dimensions.model? == "gemini-3.6-flash"))]
  | length == 1
' "${quota_info_json}" >/dev/null
```

Expected: one exact quota match. If not, stop without creating a preference.

- [ ] **Step 2: Prove no conflicting preference exists**

```bash
gcloud beta quotas preferences list \
  --project=zhang23-23 \
  --format='json(name,service,quotaId,dimensions,quotaConfig,reconciling)' \
  >"${quota_tmp}/preferences.json"
jq -e '[.[] | select(.name | endswith("/kalories-public-rpd-200"))] | length == 0' \
  "${quota_tmp}/preferences.json" >/dev/null
```

Expected on first execution: no existing resource. If one exists, describe it;
continue only if service, quota ID, dimension, preferred/granted value 200, and
`reconciling=false` all match exactly.

- [ ] **Step 3: Create the approved quota preference**

```bash
gcloud beta quotas preferences create \
  --project=zhang23-23 \
  --service=generativelanguage.googleapis.com \
  --quota-id=GenerateRequestsPerDayPerProjectPerModel \
  --dimensions=model=gemini-3.6-flash \
  --preferred-value=200 \
  --preference-id=kalories-public-rpd-200 \
  --allow-high-percentage-quota-decrease \
  --allow-quota-decrease-below-usage \
  --format=json >"${quota_tmp}/quota-create.json"
```

- [ ] **Step 4: Read back settled preferred and granted values**

```bash
gcloud beta quotas preferences describe kalories-public-rpd-200 \
  --project=zhang23-23 \
  --format=json >"${quota_tmp}/quota-readback.json"
jq -e '
  .service == "generativelanguage.googleapis.com"
  and .quotaId == "GenerateRequestsPerDayPerProjectPerModel"
  and .dimensions == {"model":"gemini-3.6-flash"}
  and (.quotaConfig.preferredValue | tonumber) == 200
  and (.quotaConfig.grantedValue | tonumber) == 200
  and .reconciling == false
' "${quota_tmp}/quota-readback.json" >/dev/null
```

Expected: exact match. Pending or partial reconciliation is NO-GO.

- [ ] **Step 5: Remove private temporary files and record boolean evidence**

```bash
find "${quota_tmp}" -type f -delete
rmdir "${quota_tmp}"
```

Change only the quota row to PASS and record quota ID, dimension, and value 200.
Commit:

```bash
git add -- docs/release/app-store-production-evidence.md
git commit -m "docs(release): record public Gemini quota"
```

## Task 5: Create and read back the approved monthly budget alert

**Files:**
- Modify: `docs/release/app-store-production-evidence.md`

- [ ] **Step 1: Resolve billing resources privately**

```bash
budget_tmp="$(mktemp -d)"
billing_account_name="$(gcloud billing projects describe zhang23-23 \
  --format='value(billingAccountName)')"
project_number="$(gcloud projects describe zhang23-23 \
  --format='value(projectNumber)')"
test -n "${billing_account_name}"
test "${project_number}" = 788259830737
```

Do not print or commit the billing account name.

- [ ] **Step 2: Prove no conflicting budget exists**

```bash
gcloud billing budgets list \
  --billing-account="${billing_account_name}" \
  --format=json >"${budget_tmp}/budgets.json"
jq -e '[.[] | select(.displayName == "Kalories App Store monthly alert")] | length == 0' \
  "${budget_tmp}/budgets.json" >/dev/null
```

If an exact-name budget exists, describe it and continue only if project filter,
3000 JPY amount, calendar month, and 50/80/100% current-spend rules all match.

- [ ] **Step 3: Create the exact alert**

```bash
gcloud billing budgets create \
  --billing-account="${billing_account_name}" \
  --display-name='Kalories App Store monthly alert' \
  --budget-amount=3000JPY \
  --filter-projects='projects/788259830737' \
  --calendar-period=month \
  --threshold-rule=percent=0.50,basis=current-spend \
  --threshold-rule=percent=0.80,basis=current-spend \
  --threshold-rule=percent=1.00,basis=current-spend \
  --format=json >"${budget_tmp}/budget-create.json"
```

If the billing account rejects JPY, stop and report the account currency; do
not silently convert the approved amount.

- [ ] **Step 4: Read back exact amount, filter, and thresholds**

```bash
budget_resource="$(jq -er '.name' "${budget_tmp}/budget-create.json")"
gcloud billing budgets describe "${budget_resource}" \
  --format=json >"${budget_tmp}/budget-readback.json"
jq -e '
  .displayName == "Kalories App Store monthly alert"
  and .budgetFilter.projects == ["projects/788259830737"]
  and .budgetFilter.calendarPeriod == "MONTH"
  and .amount.specifiedAmount.currencyCode == "JPY"
  and (.amount.specifiedAmount.units | tonumber) == 3000
  and ([.thresholdRules[].thresholdPercent] | sort) == [0.5, 0.8, 1]
  and all(.thresholdRules[]; .spendBasis == "CURRENT_SPEND")
' "${budget_tmp}/budget-readback.json" >/dev/null
```

Expected: exact match. The evidence must state that this alert does not cap
spend.

- [ ] **Step 5: Clean private files and commit boolean evidence**

```bash
find "${budget_tmp}" -type f -delete
rmdir "${budget_tmp}"
git add -- docs/release/app-store-production-evidence.md
git commit -m "docs(release): record public budget alert"
```

## Task 6: Deploy and prove a zero-traffic immutable candidate

**Files:**
- Modify: `docs/release/app-store-production-evidence.md`

- [ ] **Step 1: Run the exact IAM/secret/service pre-audit**

Execute Sections 4 and 5 of
`docs/release/testflight-backend-runbook.md` without alteration. They must prove
required APIs, secret version `2`, replacement key restrictions, exact runtime
secret accessor, inherited-accessor absence, current concurrency, and the live
service `resourceVersion` without printing identities or key material.

Expected: every safe check passes. Keep the private files only until candidate
deployment completes, then delete them with the runbook cleanup traps.

- [ ] **Step 2: Deploy the exact source with zero traffic**

```bash
test "$(git status --porcelain)" = ''
source_commit="$(git rev-parse HEAD)"
test -n "${source_commit}"

gcloud run deploy kalories \
  --source=. \
  --project=zhang23-23 \
  --region=asia-northeast1 \
  --remove-env-vars=GEMINI_API_KEY,GEMINI_MODEL \
  --update-secrets=GEMINI_API_KEY=kalories-gemini-api-key:2 \
  --update-env-vars=GEMINI_MODEL=gemini-3.6-flash,APP_CHECK_ENFORCEMENT=required,FIREBASE_PROJECT_ID=zhang23-23,FIREBASE_IOS_APP_ID=1:788259830737:ios:a4459f14b5e8046297bef0 \
  --max-instances=1 \
  --concurrency=4 \
  --timeout=30s \
  --no-traffic \
  --tag=app-store-candidate
```

The pre-audit must compare the saved service `resourceVersion` immediately
before this command. Do not add `--allow-unauthenticated`; existing public
invocation is unchanged because legal/static pages must remain public.

- [ ] **Step 3: Resolve one immutable revision and prove aggregate traffic 0**

```bash
candidate_tmp="$(mktemp -d)"
gcloud run services describe kalories \
  --project=zhang23-23 --region=asia-northeast1 \
  --format=json >"${candidate_tmp}/service.json"
candidate_revision="$(jq -er '
  [.status.traffic[]? | select(.tag == "app-store-candidate")]
  | if length == 1 then .[0].revisionName else empty end
' "${candidate_tmp}/service.json")"
candidate_url="$(jq -er '
  [.status.traffic[]? | select(.tag == "app-store-candidate")]
  | if length == 1 then .[0].url else empty end
' "${candidate_tmp}/service.json")"
jq -e --arg revision "${candidate_revision}" '
  [.status.traffic[]? | select(.revisionName == $revision) | .percent] | add == 0
' "${candidate_tmp}/service.json" >/dev/null
```

Expected: exactly one tagged immutable revision and aggregate traffic 0.

- [ ] **Step 4: Validate the immutable revision configuration**

```bash
gcloud run revisions describe "${candidate_revision}" \
  --project=zhang23-23 --region=asia-northeast1 \
  --format=json >"${candidate_tmp}/revision.json"
```

Run the immutable-revision jq validator from Section 9 of
`docs/release/testflight-backend-runbook.md`, changing only the tag name used to
resolve the candidate. Expected: pinned secret version 2, exact model/App Check
variables, maxScale 1, concurrency 4, timeout 30s, exact runtime identity, and
digest-pinned image all pass.

- [ ] **Step 5: Commit sanitized candidate identity evidence**

Record the source commit, immutable revision name, candidate tag, aggregate
traffic 0, and boolean configuration results. Do not record environment dumps,
IAM identities, or URLs containing access material.

```bash
git add -- docs/release/app-store-production-evidence.md
git commit -m "docs(release): record zero-traffic App Store candidate"
```

## Task 7: Verify candidate behavior, schema, latency, cost, and logs

**Files:**
- Modify: `docs/release/app-store-production-evidence.md`

- [ ] **Step 1: Create private test inputs outside the repository**

Create one private temporary directory outside the repository, generate one
non-personal synthetic meal JPEG at the exact path below, then obtain one
short-lived App Check token through the already registered DEBUG provider and
write it to the mode-600 token file. Never print either value.

```bash
candidate_private_tmp="$(mktemp -d)"
chmod 700 "${candidate_private_tmp}"
export KALORIES_SYNTHETIC_MEAL_IMAGE="${candidate_private_tmp}/meal.jpg"
export KALORIES_APP_CHECK_TOKEN_FILE="${candidate_private_tmp}/app-check-token"
chmod 600 "${KALORIES_APP_CHECK_TOKEN_FILE}"
test -f "${KALORIES_SYNTHETIC_MEAL_IMAGE}"
test -s "${KALORIES_APP_CHECK_TOKEN_FILE}"
```

- [ ] **Step 2: Execute the complete private candidate block**

Run Section 10 of `docs/release/testflight-backend-runbook.md` with:

```bash
export KALORIES_CANDIDATE_URL="${candidate_url}"
export KALORIES_CANDIDATE_REVISION="${candidate_revision}"
test -f "${KALORIES_SYNTHETIC_MEAL_IMAGE}"
test -s "${KALORIES_APP_CHECK_TOKEN_FILE}"
```

The Section 10 block must prove:

- candidate health/privacy/support HTTP 200;
- no-token POST `/api/analyze` and `/` exact HTTP 401 envelope;
- valid-token synthetic meal exact HTTP 200;
- strict Pydantic response schema and `food_detected=true`;
- latency under 20 seconds;
- a nonempty targeted candidate log set;
- recursive log scan finds no sensitive key/value marker;
- target 401/401/200 request logs are present.

Any failed or unavailable check is NO-GO.

- [ ] **Step 3: Record usage and cost observation**

Use the official project/model metrics for the test interval. Record only the
request count and a non-sensitive cost summary; do not commit billing account
IDs or raw provider response data.

- [ ] **Step 4: Delete private inputs and commit boolean evidence**

Delete the synthetic image, token, request/response, and log files using their
exact temporary paths, then remove the private directory. Update candidate
real-analysis/log rows to PASS and record latency/cost summary.

```bash
find "${candidate_private_tmp}" -type f -delete
rmdir "${candidate_private_tmp}"
```

```bash
git add -- docs/release/app-store-production-evidence.md
git commit -m "docs(release): verify App Store backend candidate"
```

## Task 8: Promote the exact candidate and prove production

**Files:**
- Modify: `docs/release/app-store-production-evidence.md`

- [ ] **Step 1: Recheck every preceding row is PASS**

```bash
rg -n 'NO-GO|UNVERIFIED|NOT CONFIGURED|NOT DEPLOYED|NOT RUN' \
  docs/release/app-store-production-evidence.md
```

Expected before promotion: only the promotion, physical-device, and legacy-key
rows remain not run. Any earlier unresolved row stops promotion.

- [ ] **Step 2: Promote only the immutable candidate**

```bash
gcloud run services update-traffic kalories \
  --project=zhang23-23 \
  --region=asia-northeast1 \
  --to-revisions="${candidate_revision}=100" \
  --format=json >"${candidate_tmp}/promotion.json"
```

- [ ] **Step 3: Run exact production postcheck**

```bash
KALORIES_EXPECTED_REVISION="${candidate_revision}" \
KALORIES_EXPECTED_FIREBASE_IOS_APP_ID='1:788259830737:ios:a4459f14b5e8046297bef0' \
  scripts/check-testflight-backend.sh
```

Expected: PASS; the exact revision owns aggregate production traffic 100% and
all live public/protected/log configuration gates pass.

- [ ] **Step 4: Repeat the private synthetic meal and log gate on production**

Repeat the Section 10 block against the production origin with a new short-lived
token and generated meal image. Expected: HTTP 200, strict schema, under 20
seconds, safe target logs, and current cost observation.

- [ ] **Step 5: Prove real App Attest on the owner's physical iPhone**

Launch the already installed signed app or a newly installed signed Release
candidate on the physical iPhone. Use a non-personal meal image, accept the
explicit Gemini transfer disclosure, and complete one analysis.

Expected: production App Attest-backed App Check succeeds; the result is
coherent and shows uncertainty/non-medical disclosure. A DEBUG token does not
satisfy this step.

- [ ] **Step 6: Commit production evidence**

Record exact revision name, aggregate traffic 100, public/protected statuses,
latency, safe-log boolean, quota/budget booleans, and physical-device PASS.

```bash
git add -- docs/release/app-store-production-evidence.md
git diff --cached --check
git commit -m "docs(release): record production backend promotion"
```

## Task 9: Retire the legacy credential only after fresh confirmation

**Files:**
- Modify: `docs/release/app-store-production-evidence.md`

- [ ] **Step 1: Resolve the old key by metadata identity**

Use Section 11 of `docs/release/testflight-backend-runbook.md` to find the exact
legacy key resource without printing key material. Prove it is not
`kalories-gemini-testflight-v2` and that production remains healthy on secret
version 2.

- [ ] **Step 2: Ask for fresh destructive-action confirmation**

Present the exact old key resource metadata identity, replacement key ID,
current production revision, and consequence: deletion permanently forbids
rollback to `kalories-00003-djq`.

Do not delete until the user explicitly confirms this exact key deletion.

- [ ] **Step 3: Delete only the confirmed old key and read back both states**

Execute the old-key deletion block in Section 11 with
`KALORIES_OLD_KEY_DELETION_CONFIRMED=yes`. Expected: old key has a deletion
timestamp; replacement key remains active; no key value is printed.

- [ ] **Step 4: Run production postcheck again**

```bash
KALORIES_EXPECTED_REVISION="${candidate_revision}" \
KALORIES_EXPECTED_FIREBASE_IOS_APP_ID='1:788259830737:ios:a4459f14b5e8046297bef0' \
  scripts/check-testflight-backend.sh
```

Expected: PASS. `kalories-00003-djq` must never receive traffic after deletion.

- [ ] **Step 5: Commit final backend evidence and verify clean Git state**

```bash
git add -- docs/release/app-store-production-evidence.md
git diff --cached --check
git commit -m "docs(release): close production backend credential gate"
git status --short --branch
```

Expected: clean worktree and every production ledger row PASS. This still does
not prove build upload, App Review, automatic release, storefront visibility,
or user download.
