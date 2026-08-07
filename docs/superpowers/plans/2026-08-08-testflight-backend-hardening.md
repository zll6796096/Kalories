# カロスキャン TestFlight Backend Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Harden the existing FastAPI/Gemini service and publish accurate privacy/support surfaces so a controlled native TestFlight build can perform bounded real meal analysis without a plaintext model credential.

**Architecture:** Add a tested process-global token bucket and stable 429 contract, make the stable Gemini model configurable, publish static Japanese legal/support pages through the existing combined Vite/FastAPI image, then deploy a zero-traffic Cloud Run candidate using a restricted API key stored in Secret Manager. Promote only after quota, privacy, live request, and safe-log gates pass.

**Tech Stack:** Python 3.12, FastAPI, google-genai 2.14.0, React/Vite, unittest/Vitest, Cloud Run, Secret Manager, API Keys API, Cloud Quotas API, Cloud Billing Budgets

---

## Execution boundary and observed baseline

This is plan 2 of 3. It may change the public Kalories Cloud Run service only
at the explicit production checkpoint in Task 6. Tasks 1 through 5 are local
and reversible.

Observed read-only cloud state on 2026-08-08:

- project zhang23-23, region asia-northeast1, service kalories;
- latest ready revision kalories-00003-djq at 100 percent traffic;
- service URL https://kalories-sxielk4wua-an.a.run.app;
- maxScale is 20, not the approved TestFlight value 1;
- GEMINI_API_KEY is a plain Cloud Run environment value, not a secret reference;
- API Keys, Gemini, Cloud Run, and Secret Manager APIs are enabled;
- Cloud Billing and Cloud Quotas APIs were disabled or not accessible in the
  read-only probe;
- no Kalories-named secret was proven to exist.

Never print, echo, log, screenshot, or commit the old or new key. A healthy
/health endpoint is transport evidence only.

### Task 1: Add a privacy-preserving global token bucket

**Files:**
- Create: lib/rate_limit.py
- Create: tests/test_rate_limit.py

- [ ] **Step 1: Write failing deterministic limiter tests**

~~~python
import unittest

from lib.rate_limit import TokenBucket


class FakeClock:
    def __init__(self):
        self.value = 0.0

    def __call__(self):
        return self.value


class TokenBucketTests(unittest.TestCase):
    def test_allows_burst_then_refills_at_twelve_per_minute(self):
        clock = FakeClock()
        bucket = TokenBucket(capacity=4, refill_per_second=12 / 60, clock=clock)

        self.assertEqual([True, True, True, True, False], [
            bucket.try_acquire(),
            bucket.try_acquire(),
            bucket.try_acquire(),
            bucket.try_acquire(),
            bucket.try_acquire(),
        ])

        clock.value = 5.0
        self.assertTrue(bucket.try_acquire())
        self.assertFalse(bucket.try_acquire())

    def test_clock_moving_backwards_never_adds_tokens(self):
        clock = FakeClock()
        bucket = TokenBucket(capacity=1, refill_per_second=1, clock=clock)
        self.assertTrue(bucket.try_acquire())
        clock.value = -100
        self.assertFalse(bucket.try_acquire())

    def test_invalid_configuration_fails_closed(self):
        with self.assertRaises(ValueError):
            TokenBucket(capacity=0, refill_per_second=1)
        with self.assertRaises(ValueError):
            TokenBucket(capacity=1, refill_per_second=0)
~~~

- [ ] **Step 2: Run and verify failure**

~~~bash
.venv/bin/python -m unittest tests.test_rate_limit -v
~~~

Expected: ImportError because lib.rate_limit does not exist.

- [ ] **Step 3: Implement the limiter**

~~~python
from __future__ import annotations

from collections.abc import Callable
from threading import Lock
from time import monotonic


class TokenBucket:
    def __init__(
        self,
        *,
        capacity: float,
        refill_per_second: float,
        clock: Callable[[], float] = monotonic,
    ) -> None:
        if capacity <= 0 or refill_per_second <= 0:
            raise ValueError("capacity and refill rate must be positive")
        self._capacity = float(capacity)
        self._refill_per_second = float(refill_per_second)
        self._clock = clock
        self._tokens = float(capacity)
        self._updated_at = clock()
        self._lock = Lock()

    def try_acquire(self) -> bool:
        with self._lock:
            now = self._clock()
            elapsed = max(0.0, now - self._updated_at)
            self._tokens = min(
                self._capacity,
                self._tokens + elapsed * self._refill_per_second,
            )
            self._updated_at = max(self._updated_at, now)
            if self._tokens < 1:
                return False
            self._tokens -= 1
            return True
~~~

The limiter stores no IP, device identifier, account, image, or result.

- [ ] **Step 4: Pass focused and backend suites**

~~~bash
.venv/bin/python -m unittest tests.test_rate_limit -v
.venv/bin/python -m unittest discover -s tests -p 'test_*.py' -v
~~~

Expected: limiter tests and the existing 61+ backend tests pass.

- [ ] **Step 5: Commit**

~~~bash
git add lib/rate_limit.py tests/test_rate_limit.py
git commit -m "feat(api): add bounded analysis rate limiter"
~~~

### Task 2: Enforce the limit and expose a stable client error

**Files:**
- Modify: api/analyze.py
- Modify: tests/test_analyze.py
- Modify: src/types.ts
- Modify: src/api.ts
- Modify: src/i18n.ts
- Modify: src/api.test.ts
- Modify: src/i18n.test.ts

- [ ] **Step 1: Write failing endpoint tests**

Patch ANALYSIS_RATE_LIMITER.try_acquire. After valid image decoding and before
call_gemini, false must produce HTTP 429 with detail code RATE_LIMITED and the
provider must not be called. Invalid images must continue returning their 400
error without consuming a token.

- [ ] **Step 2: Write failing web contract tests**

Add RATE_LIMITED to AppErrorCode and the stable backend-code set. Assert a 429
body maps to RATE_LIMITED. Add localized errorRateLimited strings:

- zh: 请求过于频繁，请稍后再试。
- ja: リクエストが多すぎます。少し待ってからお試しください。
- en: Too many requests. Try again shortly.

- [ ] **Step 3: Run focused tests and verify failure**

~~~bash
.venv/bin/python -m unittest tests.test_analyze.AnalyzeEndpointTests -v
npm test -- --run src/api.test.ts src/i18n.test.ts
~~~

Expected: failures because the endpoint and clients do not know RATE_LIMITED.

- [ ] **Step 4: Integrate the limiter**

At module scope in api/analyze.py:

~~~python
from lib.rate_limit import TokenBucket

ANALYSIS_RATE_LIMITER = TokenBucket(
    capacity=4,
    refill_per_second=12 / 60,
)
~~~

In analyze_food, keep the API-key and image validation behavior, then add:

~~~python
if not ANALYSIS_RATE_LIMITER.try_acquire():
    raise HTTPException(
        status_code=429,
        detail={"code": "RATE_LIMITED"},
    )
~~~

Do not consume a provider token for empty, malformed, unsupported, or oversized
images. Do consume one immediately before a provider call.

Update the React types, code set, switch, and messages without changing other
error behavior.

- [ ] **Step 5: Pass focused and full local suites**

~~~bash
.venv/bin/python -m unittest tests.test_analyze tests.test_rate_limit -v
npm test
npm run lint
npm run build
~~~

Expected: 63+ backend tests, 111+ frontend tests, lint, and build pass.

- [ ] **Step 6: Commit**

~~~bash
git add api/analyze.py tests/test_analyze.py src/types.ts src/api.ts src/i18n.ts src/api.test.ts src/i18n.test.ts
git commit -m "feat(api): enforce analysis request ceiling"
~~~

### Task 3: Move from a preview model literal to stable configuration

**Files:**
- Modify: api/analyze.py
- Modify: tests/test_analyze.py
- Modify: .env.example
- Modify: README.md

- [ ] **Step 1: Write failing model-selection tests**

Assert default model gemini-3.6-flash, trimmed GEMINI_MODEL override, empty
override falling back to default, and call_gemini passing the selected value to
generate_content. Provider responses remain schema validated.

- [ ] **Step 2: Verify failure**

~~~bash
.venv/bin/python -m unittest tests.test_analyze.GeminiProviderTests -v
~~~

Expected: the old gemini-3-flash-preview assertion fails.

- [ ] **Step 3: Implement stable model selection**

~~~python
DEFAULT_GEMINI_MODEL = "gemini-3.6-flash"


def configured_gemini_model() -> str:
    value = os.environ.get("GEMINI_MODEL", "").strip()
    return value or DEFAULT_GEMINI_MODEL
~~~

Change call_gemini to accept an optional model argument for tests and use
configured_gemini_model otherwise. Keep temperature, timeout, prompt, schema,
and local deterministic scoring unchanged.

Add GEMINI_MODEL=gemini-3.6-flash to .env.example. Document that changing the
model requires the full provider contract and real-image gate.

- [ ] **Step 4: Pass provider and full backend suites**

Expected: all tests pass; no real request is made.

- [ ] **Step 5: Commit**

~~~bash
git add api/analyze.py tests/test_analyze.py .env.example README.md
git commit -m "fix(api): pin stable Gemini model"
~~~

### Task 4: Publish privacy and support pages

**Files:**
- Create: public/privacy/index.html
- Create: public/support/index.html
- Create: tests/test_public_pages.py
- Modify: README.md

- [ ] **Step 1: Write failing page-content tests**

Use pathlib and html.parser from the standard library. Assert both files exist,
have html lang ja and UTF-8 metadata, and contain no unfinished markers.
Privacy must include:

- 写真 and Gemini;
- 利用目的;
- 保存期間;
- 第三者提供;
- 同意の撤回;
- 削除;
- 問い合わせ;
- medical/estimate boundary;
- link to Google privacy terms and the support page.

Support must link to the GitHub issues URL for this repository and warn users
not to include personal meal photos or credentials in public issues.

- [ ] **Step 2: Run and verify failure**

~~~bash
.venv/bin/python -m unittest tests.test_public_pages -v
~~~

Expected: failure because the pages are absent.

- [ ] **Step 3: Create the Japanese privacy page**

The final page must state these facts in plain Japanese:

1. A meal photo is sent only after the user taps analysis.
2. It is sent over HTTPS to Kalories and Google Gemini for this request.
3. Kalories does not implement image/result persistence, accounts, ads,
   tracking, or analytics SDKs.
4. Operational Cloud Run metadata may be retained according to Google Cloud
   settings; image bytes and base64 payloads are not intentionally logged.
5. Camera permission can be revoked in iOS Settings; retake discards in-memory
   data; there is no cloud meal history to delete.
6. Photo output is an estimate for one meal and is not medical diagnosis.
7. The paid Gemini Developer API configuration must be verified before
   TestFlight; if provider retention/use differs, the page and declarations are
   updated before distribution.
8. Contact uses /support/ and the public issue form; users must not attach
   private photos or secrets.

Use the existing calm neutral CSS inline so the page is readable without the
React app or JavaScript. No cookie banner is needed because the page sets no
cookie and loads no analytics.

- [ ] **Step 4: Create the support page**

Provide Japanese first, then short Chinese and English help. Cover camera
permission, no-food retake, network/timeout/rate-limit retry, non-medical
boundary, privacy link, and the GitHub issue link:

https://github.com/zll6796096/Kalories/issues/new

- [ ] **Step 5: Build and test local combined serving**

~~~bash
npm run build
.venv/bin/python -m unittest tests.test_public_pages -v
.venv/bin/python -m uvicorn api.analyze:app --host 127.0.0.1 --port 8080
~~~

In a second terminal:

~~~bash
curl -fsS http://127.0.0.1:8080/privacy/ | rg 'プライバシーポリシー'
curl -fsS http://127.0.0.1:8080/support/ | rg 'サポート'
~~~

Expected: both return 200 and expected Japanese headings. Stop uvicorn.

- [ ] **Step 6: Commit**

~~~bash
git add public/privacy public/support tests/test_public_pages.py README.md
git commit -m "feat: publish Kalories privacy and support pages"
~~~

### Task 5: Add a read-only deployment preflight and runbook

**Files:**
- Create: scripts/check-testflight-backend.sh
- Create: docs/release/testflight-backend-runbook.md
- Modify: README.md

- [ ] **Step 1: Create a read-only preflight script**

The script uses set -euo pipefail and fixed project/service/region values. It
must:

- verify active gcloud account without printing tokens;
- describe the service through JSON and jq;
- require maxScale 1;
- require GEMINI_API_KEY to have valueFrom and no plain value;
- require GEMINI_MODEL value gemini-3.6-flash;
- require /health, /privacy/, and /support/ HTTP 200;
- inspect the latest 200 Cloud Run log entries for literal data:image/,
  GEMINI_API_KEY, Authorization:, and api_key=;
- print PASS or a specific NO-GO reason;
- never output any environment value.

Before Task 6 the expected result is NO-GO because current maxScale is 20 and
the key is plaintext.

- [ ] **Step 2: Write the exact runbook checkpoints**

The runbook records:

- baseline revision and traffic;
- APIs to enable;
- new API key resource ID kalories-gemini-testflight;
- Secret Manager secret kalories-gemini-api-key;
- runtime service account resolution;
- quota preference evidence;
- budget-alert evidence;
- zero-traffic candidate deployment;
- real synthetic-meal request;
- safe-log check;
- traffic promotion;
- old-key revocation;
- rollback command.

No secret value appears in the runbook.

- [ ] **Step 3: Validate shell and expected preflight failure**

~~~bash
bash -n scripts/check-testflight-backend.sh
scripts/check-testflight-backend.sh
~~~

Expected: syntax check passes; preflight exits nonzero with explicit findings
for maxScale and plaintext secret. Record this as expected baseline, not a test
failure.

- [ ] **Step 4: Commit**

~~~bash
git add scripts/check-testflight-backend.sh docs/release/testflight-backend-runbook.md README.md
git commit -m "docs: add TestFlight backend gate"
~~~

### Task 6: Create a protected zero-traffic candidate and promote it

**Files:**
- External: Google Cloud project zhang23-23
- Evidence update: docs/release/testflight-backend-runbook.md

This task mutates production infrastructure. Reconfirm the exact project,
service, new key ID, secret name, quota, and candidate-only deployment with the
user immediately before Step 2. Do not interpret design approval as permission
to touch another project or service.

- [ ] **Step 1: Run all local gates on a clean committed revision**

~~~bash
npm test
npm run lint
npm run build
.venv/bin/python -m unittest discover -s tests -p 'test_*.py' -v
.venv/bin/python -m compileall -q api lib tests
.venv/bin/python -c "import api.analyze, lib.nutrition, lib.rate_limit"
uv pip check --python .venv/bin/python
git diff --check
git status --short --branch
~~~

Expected: all checks pass and worktree is clean. If not, stop.

- [ ] **Step 2: Enable only required control-plane APIs**

After confirmation:

~~~bash
gcloud services enable \
  cloudquotas.googleapis.com \
  cloudbilling.googleapis.com \
  billingbudgets.googleapis.com \
  --project=zhang23-23
~~~

Expected: operations complete. Permission denied is NO-GO; do not skip quota or
billing evidence.

- [ ] **Step 3: Create a restricted replacement API key**

~~~bash
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
test -n "$KALORIES_KEY_RESOURCE"
~~~

Expected: one key resource with only the Gemini API target. Do not run
get-key-string to the terminal.

- [ ] **Step 4: Pipe the new key directly into Secret Manager**

~~~bash
if ! gcloud secrets describe kalories-gemini-api-key \
  --project=zhang23-23 >/dev/null 2>&1; then
  gcloud secrets create kalories-gemini-api-key \
    --project=zhang23-23 \
    --replication-policy=automatic
fi
gcloud services api-keys get-key-string "$KALORIES_KEY_RESOURCE" \
  --project=zhang23-23 \
  --format='value(keyString)' |
gcloud secrets versions add kalories-gemini-api-key \
  --project=zhang23-23 \
  --data-file=-
unset KALORIES_KEY_RESOURCE
~~~

Expected: a new enabled secret version; no key text in output or shell history.

Resolve the service account. If Cloud Run has no explicit service account, use
the project's default compute service account. Grant secretAccessor on this
secret only, not project-wide.

~~~bash
KALORIES_RUNTIME_SA="$(gcloud run services describe kalories \
  --project=zhang23-23 \
  --region=asia-northeast1 \
  --format='value(spec.template.spec.serviceAccountName)')"
if [ -z "$KALORIES_RUNTIME_SA" ]; then
  KALORIES_PROJECT_NUMBER="$(gcloud projects describe zhang23-23 \
    --format='value(projectNumber)')"
  KALORIES_RUNTIME_SA="${KALORIES_PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
fi
gcloud secrets add-iam-policy-binding kalories-gemini-api-key \
  --project=zhang23-23 \
  --member="serviceAccount:${KALORIES_RUNTIME_SA}" \
  --role=roles/secretmanager.secretAccessor
unset KALORIES_PROJECT_NUMBER KALORIES_RUNTIME_SA
~~~

- [ ] **Step 5: Enforce the project request-per-day preference**

~~~bash
gcloud beta quotas info list \
  --project=zhang23-23 \
  --service=generativelanguage.googleapis.com \
  --format=json > /tmp/kalories-gemini-quotas.json
jq -r '.[] | [.quotaId, (.metric // ""), (.dimensions // {})] | @json' \
  /tmp/kalories-gemini-quotas.json
~~~

Resolve the exact Gemini request-per-day quota ID from this output, verify it is
project-scoped for the chosen model, then create a preference value 200 using:

~~~bash
gcloud beta quotas preferences create \
  --project=zhang23-23 \
  --service=generativelanguage.googleapis.com \
  --quota-id="$KALORIES_RPD_QUOTA_ID" \
  --preferred-value=200 \
  --preference-id=kalories-testflight-rpd-200 \
  --allow-high-percentage-quota-decrease \
  --allow-quota-decrease-below-usage
~~~

The operator sets KALORIES_RPD_QUOTA_ID only after reading the API output and
runs test -n before the command. If no enforceable RPD quota exists, this plan
is NO-GO under the approved design; a budget alert is not a replacement cap.

Remove the temporary JSON after recording only quota IDs and limits:

~~~bash
rm -f /tmp/kalories-gemini-quotas.json
unset KALORIES_RPD_QUOTA_ID
~~~

- [ ] **Step 6: Verify the paid provider privacy tier**

Open the Gemini API project in Google AI Studio and verify it is a paid tier
whose current terms state submitted content is not used to improve Google
products. Record the project identity, tier label, terms URL, and verification
date without recording the key. If the project is free tier or the data-use
terms cannot be verified, stop before candidate deployment and revise the
privacy design with the user.

- [ ] **Step 7: Create the project-filtered budget alert**

Retrieve the billing account only after the Billing API permission passes.
Have the user provide an amount in the billing account's currency through
KALORIES_MONTHLY_BUDGET_AMOUNT; validate it is a positive number. Create one
monthly project-filtered budget with actual-spend thresholds 50, 80, and 100
percent. Record that budgets alert but do not cap spend; the RPD preference is
the cap.

~~~bash
: "${KALORIES_MONTHLY_BUDGET_AMOUNT:?Set an approved positive amount in the billing account currency}"
KALORIES_BILLING_ACCOUNT="$(gcloud billing projects describe zhang23-23 \
  --format='value(billingAccountName)')"
test -n "$KALORIES_BILLING_ACCOUNT"
gcloud billing budgets create \
  --billing-account="$KALORIES_BILLING_ACCOUNT" \
  --display-name='Kalories TestFlight monthly alert' \
  --budget-amount="$KALORIES_MONTHLY_BUDGET_AMOUNT" \
  --filter-projects=projects/zhang23-23 \
  --calendar-period=month \
  --threshold-rule=percent=0.50 \
  --threshold-rule=percent=0.80 \
  --threshold-rule=percent=1.00
unset KALORIES_BILLING_ACCOUNT KALORIES_MONTHLY_BUDGET_AMOUNT
~~~

- [ ] **Step 8: Deploy a zero-traffic candidate**

~~~bash
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
~~~

Expected: a ready tagged revision with zero production traffic. Confirm JSON
shows secretRef true, no plain key, maxScale 1, and model name only.

- [ ] **Step 9: Verify candidate with a non-personal synthetic meal**

Use imagegen with this prompt and save outside the repository:

~~~text
A realistic overhead photograph of a generic Japanese grilled salmon set meal on a plain table: grilled salmon, white rice, miso soup, spinach side dish. No people, no hands, no text, no brand, no private environment.
~~~

POST it once to the candidate tag URL. Validate HTTP 200, food_detected true,
seven nutrient keys, confidence, deterministic assessment, and no raw provider
field. Inspect candidate logs; reject any data URI, base64 payload, credential,
Authorization header, or provider response body.

Also verify /health, /privacy/, and /support/ return 200 on the candidate.

Resolve the candidate URL without copying it from free-form deploy output:

~~~bash
KALORIES_CANDIDATE_URL="$(gcloud run services describe kalories \
  --project=zhang23-23 \
  --region=asia-northeast1 \
  --format=json | jq -r '.status.traffic[] | select(.tag == "testflight-candidate") | .url')"
test -n "$KALORIES_CANDIDATE_URL"
~~~

- [ ] **Step 10: Promote only the verified revision**

~~~bash
gcloud run services update-traffic kalories \
  --project=zhang23-23 \
  --region=asia-northeast1 \
  --to-latest
~~~

Expected: latest verified revision receives 100 percent. Run
scripts/check-testflight-backend.sh; expected PASS.

- [ ] **Step 11: Revoke the old key and record rollback**

In Google AI Studio/API Keys, resolve the old key by its resource identity and
creation context, explicitly exclude kalories-gemini-testflight, then revoke
the old plaintext-deployed credential. Never compare or print key strings.

Record the prior and new revision names. Rollback, if needed:

~~~bash
gcloud run services update-traffic kalories \
  --project=zhang23-23 \
  --region=asia-northeast1 \
  --to-revisions=kalories-00003-djq=100
~~~

Rollback restores traffic only; it must not restore the revoked key. If rollback
needs the old revision, add the new secret reference to that revision first or
keep traffic on the candidate and fix forward.

- [ ] **Step 12: Commit sanitized evidence**

Update the runbook with revision names, timestamps, quota value, budget name,
HTTP statuses, test counts, and redacted log findings. Include no project secret,
billing account ID, personal photo, API response photo, or credential.

~~~bash
git add docs/release/testflight-backend-runbook.md
git commit -m "docs: record TestFlight backend evidence"
git status --short --branch
~~~

Expected: clean worktree.

## Plan 2 completion gate

Complete only when local tests pass, the new credential is secret-backed, the
old credential is revoked, max instances is 1, the application limiter and
enforceable RPD cap are active, budget alerts are proven, paid-provider data
handling is verified, a synthetic meal succeeds, legal/support pages are live,
logs are clean, and sanitized evidence is committed. Any permission, quota, or
provider-tier gap is NO-GO for external TestFlight distribution.
