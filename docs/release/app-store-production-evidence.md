# App Store Production Backend Evidence

Date: 2026-08-11
Project/region/service: zhang23-23 / asia-northeast1 / kalories
Source revision: `6bfbeaed23c7732460bbf1e22736d4d01132f813`

| Gate | State |
| --- | --- |
| Local source | PASS |
| Fresh production preflight | NO-GO |
| Provider paid-service terms | PASS |
| Developer logging disabled | PASS |
| Dataset sharing disabled | PASS |
| Daily model quota 200 | PASS |
| Monthly 3000JPY budget alert | PASS |
| Zero-traffic candidate | NOT DEPLOYED |
| Candidate real analysis | NOT RUN |
| Candidate safe-log scan | NOT RUN |
| Production promotion | NOT RUN |
| Physical-iPhone App Attest analysis | NOT RUN |
| Legacy key deletion | NOT RUN |

## Fresh local source evidence

The intended branch was clean before these documents were created, and
`git diff --check` passed. The complete local gate produced:

- Web tests: PASS — 23/23 tests across 3/3 test files.
- TypeScript check and production web build: PASS.
- Python tests: PASS — 164/164 tests.
- Python bytecode compilation and runtime imports: PASS.
- Python dependency compatibility: PASS — 51 installed packages checked.
- Docker build: PASS — runtime manifest
  `sha256:4cd459c71a3863c1971deb27095160d179097ba14fa5169d29e91288cc77cef1`.
- Local iOS App Check release scan: PASS; external configuration remains
  unverified.

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

## Fresh read-only production preflight

The read-only preflight ran with the exact approved Firebase iOS app ID. Its
exit code was `1`, and its output passed a fixed safe-output allowlist plus a
protected-data pattern scan before being recorded. It reported only these
fixed safe findings:

- Cloud Run production revision maxScale is not exactly 1.
- `GEMINI_API_KEY` is not exactly one pinned secret-backed entry.
- `GEMINI_MODEL` is not exactly one direct value set to `gemini-3.6-flash`.
- `APP_CHECK_ENFORCEMENT` is not exactly `required`.
- `FIREBASE_PROJECT_ID` is not exactly `zhang23-23`.
- `FIREBASE_IOS_APP_ID` does not match the approved app.
- `/privacy` did not return HTTP 200.
- `/support` did not return HTTP 200.
- App Check no-token POST did not return HTTP 401 for `/api/analyze`.
- App Check no-token POST did not return HTTP 401 for `/`.
- Cloud Run logs are not a nonempty JSON array.

This ledger never records credentials, tokens, billing-account IDs, IAM
identities, images, response bodies, or log content.
