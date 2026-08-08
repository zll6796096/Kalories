# Kalories Cloud B1 Evidence

Captured at `2026-08-08 17:58:46 JST (+0900)` for project `zhang23-23`.
This document records real external state, not authorization for later Cloud
Run deployment, traffic, quota, budget, or credential restoration.

## Completed and verified

- `cloudquotas.googleapis.com` is enabled.
- `cloudbilling.googleapis.com` is enabled.
- `billingbudgets.googleapis.com` is enabled.
- The live Cloud Run service still serves revision `kalories-00003-djq` at
  `100%` traffic.
- No Cloud Run service configuration, revision, environment, or traffic was
  changed by Cloud B1.

## Credential incident and rollback

The first `kalories-gemini-testflight` create command wrote its full result to
stderr even though stdout was redirected. That result contained the generated
key value, so the credential was treated as exposed before any deployment.

The controlled rollback was completed and read back:

- API key `kalories-gemini-testflight` is soft-deleted and must not be restored
  or reused.
- Secret `kalories-gemini-api-key` exists, but version `1` is `DISABLED` and
  must never be re-enabled.
- The secret-level `roles/secretmanager.secretAccessor` binding for
  `788259830737-compute@developer.gserviceaccount.com` was removed.
- Production revision and traffic remained unchanged after rollback.

The key value, Secret value, IAM policy, and account identities are not stored
in this repository.

## Required next approval

Before another credential attempt, approve a new API key ID. The recommended
ID is `kalories-gemini-testflight-v2`. A retry must capture both stdout and
stderr privately, read metadata back with a separate describe call, create a
new Secret version, verify private equality, and add only the one exact
secret-level runtime accessor. It must not deploy or change traffic.
