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
