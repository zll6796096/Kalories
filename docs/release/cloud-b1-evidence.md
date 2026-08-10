# Kalories Cloud B1 Evidence

Captured at `2026-08-08 17:58:46 JST (+0900)` for project `zhang23-23`.
This document records real external state, not authorization for later Cloud
Run deployment, traffic, quota, budget, or credential restoration.

Continuation captured at `2026-08-08 18:20:57 JST (+0900)` after explicit
approval of replacement key ID `kalories-gemini-testflight-v2`.

## Completed and verified

- `cloudquotas.googleapis.com` is enabled.
- `cloudbilling.googleapis.com` is enabled.
- `billingbudgets.googleapis.com` is enabled.
- The live Cloud Run service still serves revision `kalories-00003-djq` at
  `100%` traffic.
- No Cloud Run service configuration, revision, environment, or traffic was
  changed by Cloud B1.

## Replacement credential completed

- API key `kalories-gemini-testflight-v2` is active and has exactly one API
  target: `generativelanguage.googleapis.com`.
- Secret `kalories-gemini-api-key` version `2` is enabled and is the only
  enabled version; version `1` remains disabled.
- A private byte-for-byte comparison proved that Secret version `2` contains
  the replacement key. Neither value was printed or persisted in the
  repository.
- The live runtime service account has exactly one unconditional, secret-level
  `roles/secretmanager.secretAccessor` binding. A project/ancestor audit found
  no inherited `secretmanager.versions.access` permission for that identity.
- The production service still serves `kalories-00003-djq` at `100%` traffic.

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

The key value, Secret value, IAM policy, and personal account identities are not
stored in this repository. The non-personal runtime service account is retained
only as the exact authorized resource identity.

## Cleanup incident

After all Cloud B1 read-backs succeeded, the transaction's exit handler used
zsh's reserved variable name `status`. That prevented the private temporary
directory from being deleted during the first cleanup attempt. A constrained
cleanup then located exactly one directory by its expected private filenames,
deleted its files, removed the directory, and verified zero residual Kalories
B1 verification directories. No private file content was displayed.

## Next boundary

Cloud B1 does not authorize Cloud Run deployment, environment changes, traffic,
quota preferences, budget alerts, provider privacy claims, real-image requests,
promotion, old production-key revocation, or TestFlight upload. Each remains a
separate gate.
