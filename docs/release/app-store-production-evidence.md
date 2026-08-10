# App Store Production Backend Evidence

Date: 2026-08-11
Project/region/service: zhang23-23 / asia-northeast1 / kalories
Source revision: `6bfbeaed23c7732460bbf1e22736d4d01132f813`

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
