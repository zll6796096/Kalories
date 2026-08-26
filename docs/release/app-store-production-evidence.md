# App Store Production Backend Evidence

Date: 2026-08-27
Project/region/service: zhang23-23 / asia-northeast1 / kalories
Production source revision: `22d99e1d970913494ed8e11b63fe1cef41188328`

| Gate | State |
| --- | --- |
| Local source | PASS |
| Fresh production preflight | PASS |
| Provider paid-service terms | PASS |
| Developer logging disabled | PASS |
| Dataset sharing disabled | PASS |
| Daily model quota 200 | PASS |
| Monthly 3000JPY budget alert | PASS |
| Zero-traffic candidate | PASS |
| Candidate real analysis | PASS |
| Candidate safe-log scan | PASS |
| Production promotion | PASS |
| Physical-iPhone App Attest analysis | NOT RUN |
| Legacy key deletion | NOT RUN |

## Fresh local source evidence

The intended branch was clean before these documents were created. The complete
local gate was repeated after the evidence and bounded Cloud Logging polling
change on 2026-08-27, and `git diff --check` passed:

- Web tests: PASS — 23/23 tests across 3/3 test files.
- TypeScript check and production web build: PASS.
- Python tests: PASS — 168/168 tests.
- Python bytecode compilation and runtime imports: PASS.
- Python dependency compatibility: PASS — 51 installed packages checked.
- Docker build: PASS — runtime manifest
  `sha256:4cd459c71a3863c1971deb27095160d179097ba14fa5169d29e91288cc77cef1`.
- iOS unit and UI tests: PASS — 140 passed, 1 screenshot-generation test
  skipped because the selected iPhone 17 Pro destination is not the required
  Pro Max logical size.
- Local iOS App Check release scan: PASS; external configuration remains
  separately evidenced by the live production checks below.

These results prove the local source only. They do not prove provider, quota,
budget, deployment, traffic, Firebase, App Attest, or production behavior.

## Provider privacy and paid-service evidence

Verified read-only on 2026-08-11 in the authenticated Google AI Studio controls
for the exact project:

- The project is on Gemini API `Tier 1` with the prepaid billing plan, so API
  access through that billing-enabled project is governed as a Paid Service.
- GenerateContent API request storage is disabled. Kalories uses
  GenerateContent, not the separately configured Interactions API.
- The project has no developer logs or datasets, so no dataset-sharing opt-in
  is active.
- Google's current official terms still state that Paid Service prompts and
  responses are not used to improve Google products. The current abuse
  monitoring policy still states a 55-day retention period, and the ZDR guide
  still requires a separately approved project configuration. The public
  privacy policy's conservative 55-day maximum and no-ZDR claim remain
  accurate.

Official sources checked on 2026-08-11:

- https://ai.google.dev/gemini-api/terms
- https://ai.google.dev/gemini-api/docs/billing
- https://ai.google.dev/gemini-api/docs/logs-policy
- https://ai.google.dev/gemini-api/docs/usage-policies
- https://ai.google.dev/gemini-api/docs/zdr

## Daily Gemini model quota evidence

Configured and read back on 2026-08-11:

- Quota ID: `GenerateRequestsPerDayPerProjectPerModel`
- Dimension: `model=gemini-3.6-flash`
- Preferred value: 200 requests per day
- Granted value: 200 requests per day
- Reconciliation: settled. The API omitted the false-valued `reconciling`
  field, which Google's Cloud Quotas documentation defines as a final granted
  value; the reconciling-only preference list contained no matching resource.

Official reconciliation semantics checked on 2026-08-11:

- https://docs.cloud.google.com/docs/quotas/implement-common-use-cases

## Monthly budget alert evidence

Configured and read back on 2026-08-11:

- Display name: `Kalories App Store monthly alert`
- Project filter: Kalories project only
- Calendar period: month
- Amount: JPY 3,000
- Alert thresholds: 50%, 80%, and 100% of current spend

This budget is an alert, not a hard spending cap. The daily model quota and
application rate limiter remain the controls that restrict request volume.

## Zero-traffic immutable candidate evidence

Deployed and read back on 2026-08-11:

- Source commit: `22d99e1d970913494ed8e11b63fe1cef41188328`
- Immutable revision: `kalories-00004-nan`
- Candidate tag: `app-store-candidate`
- Aggregate production traffic: 0%

The fresh pre-audit verified all required APIs, the replacement key's single
Gemini API restriction, Secret version 2 as the only enabled version, disabled
version 1, the exact unconditional secret-level runtime accessor, and no
project/ancestor Secret access for the runtime identity. The live service
resource version was read back again immediately before deployment.

The immutable revision read-back passed every required configuration check:
pinned Secret version 2, `gemini-3.6-flash`, App Check required, the exact
Firebase project and iOS app, unchanged runtime identity, maxScale 1,
concurrency 4, timeout 30 seconds, and a digest-pinned image. Cloud Run omitted
the candidate tag's zero-valued `percent` field; its official API defines an
unspecified traffic percentage as zero, and the candidate revision's aggregate
traffic was verified as 0%.

Official traffic-default semantics checked on 2026-08-11:

- https://docs.cloud.google.com/run/docs/reference/rest/v2/projects.locations.services

## Fresh read-only production preflight

The read-only preflight was repeated on 2026-08-27 with the exact approved
Firebase iOS app ID and expected immutable revision. It returned:

`PASS: TestFlight backend preflight`

The live read-back proved that `kalories-00004-nan` owns 100% of aggregate
production traffic, the required configuration remains pinned, `/health`,
`/privacy/`, and `/support/` return HTTP 200, and both protected POST paths
return the exact HTTP 401 App Check envelope when the token is absent. The
preflight's target log query also passed after bounded polling for Cloud
Logging's normal ingestion delay.

## Candidate and production behavior evidence

The private candidate check completed on 2026-08-27 against the immutable
candidate-tag URL before promotion:

- Synthetic non-personal meal analysis: HTTP 200.
- Strict Pydantic response schema and `food_detected=true`: PASS.
- End-to-end request latency: 7.823700933 seconds, below the 20-second gate.
- Exact revision request logs: PASS.
- Recursive sensitive-log scan: PASS.

The exact immutable revision was then promoted to 100% production traffic.
After promotion, a new temporary Firebase App Check debug token was created
for the approved Firebase iOS app, exchanged once, used for one generated
non-personal synthetic meal request, and revoked. The production result was:

- Production `/api/analyze`: HTTP 200.
- Strict Pydantic response schema and `food_detected=true`: PASS.
- Client-observed latency: 6.465034 seconds; Cloud Run recorded
  6.244399179 seconds, both below the 20-second gate.
- Exact `kalories-00004-nan` production request log: PASS.
- Recursive sensitive-log scan: PASS.
- Registered App Check debug-token count after cleanup: 0.

This DEBUG-provider evidence proves the protected application-layer production
path without retaining a debug credential. It does not replace the separate
physical-iPhone App Attest gate, which remains NOT RUN.

This ledger never records credentials, tokens, billing-account IDs, IAM
identities, images, response bodies, or log content.
