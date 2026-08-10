# カロスキャン Firebase App Check and App Attest Design

Date: 2026-08-08

Status: Approved in conversation; implementation and external mutations remain
separately gated.

## 1. Real Objective

Protect the paid photo-analysis endpoint before the first external TestFlight
build without adding accounts or weakening the existing privacy and release
boundaries.

The objective is not to make a public Cloud Run URL look secure. It is to make
the server machine-verify that each paid analysis request originated from the
registered `com.ryuaistudio.kalories` iOS app, while keeping public health,
privacy, support, and static pages reachable.

## 2. First-Principles Rules

- Goal before options: the target is a working, protected TestFlight build,
  not Firebase adoption for its own sake.
- Risk before speed: a public endpoint with only rate and budget controls is
  not accepted as application access control.
- Maintainability before novelty: use the supported Firebase App Check SDK and
  Admin SDK rather than implementing App Attest certificate or JWT validation
  from scratch.
- Privacy before convenience: do not add Analytics, Auth, Crashlytics, ads, or
  tracking as incidental Firebase dependencies.
- Evidence before completion: simulator tests, a valid debug token, an upload,
  and a real App Attest request are separate gates.

## 3. Selected Approach

Use Firebase App Check with Apple App Attest for the native iOS client and the
Firebase Admin SDK for the FastAPI backend.

- TestFlight and Release use App Attest only.
- There is no DeviceCheck fallback.
- The backend accepts standard App Check tokens. Limited-use replay protection
  remains out of scope because the feature is beta and the Python Admin SDK
  does not support token consumption.
- Firebase App Check proves an authentic app instance, not the identity or
  TestFlight invitation status of a human tester.
- Provider quotas, billing budgets, Cloud Run `maxScale=1`, the process-local
  token bucket, and operational monitoring remain mandatory loss controls.

Primary references:

- <https://firebase.google.com/docs/app-check/ios/app-attest-provider>
- <https://firebase.google.com/docs/app-check/ios/custom-resource>
- <https://firebase.google.com/docs/app-check/custom-resource-backend>
- <https://developer.apple.com/documentation/DeviceCheck/establishing-your-app-s-integrity>

## 4. Minimal Verifiable Deliverable

The minimum deliverable is:

1. Both paid POST routes reject missing, invalid, expired, wrong-project, or
   wrong-app App Check tokens before image decoding, rate limiting, or Gemini.
2. The native client obtains a token before constructing the analysis request
   and sends it only in `X-Firebase-AppCheck` to the analysis origin.
3. TestFlight and Release builds use the production App Attest entitlement and
   contain no debug provider or debug token.
4. UI fixtures remain fully offline and do not initialize Firebase.
5. The public website no longer sends photo-analysis requests.
6. Public health, privacy, support, and static resources remain reachable.
7. Local tests and release scans pass, followed by a separately authorized
   Firebase/Apple/Cloud candidate and a real TestFlight-device check.

## 5. Scope

### 5.1 In scope

- Firebase App Check registration for the existing iOS bundle identifier.
- Apple App Attest production capability and entitlement.
- `FirebaseCore` and `FirebaseAppCheck` only on iOS.
- `firebase-admin` as a direct, locked Python dependency.
- A narrow backend verifier interface and Firebase adapter.
- App Check enforcement on `POST /api/analyze` and the compatibility `POST /`.
- Owned, localized client and server error contracts.
- Removal of browser photo-analysis calls while retaining public pages.
- Privacy-policy, release-runbook, and preflight-gate updates.
- Unit, integration, UI-fixture, Release-build, and sensitive-output tests.
- A zero-traffic backend candidate and controlled TestFlight verification after
  explicit external-mutation approval.

### 5.2 Out of scope

- Firebase Analytics, Authentication, Crashlytics, Performance, Messaging,
  Firestore, Storage, Remote Config, or App Distribution.
- Sign in with Apple, accounts, tester identity, cloud meal history, or
  per-user quota records.
- DeviceCheck fallback.
- Firebase Web App Check or reCAPTCHA Enterprise.
- An unauthenticated browser analysis route.
- Custom App Attest certificate validation, a nonce database, or a Node.js
  limited-use-token gateway.
- App Store Review submission, public release, or storefront visibility.
- Provider, nutrition-scoring, or unrelated infrastructure refactoring.

## 6. Architecture

### 6.1 Protected and public surfaces

The combined service remains publicly reachable because Apple and users need
the legal and support pages. App Check is applied by HTTP method and path, not
as a global site gate.

Protected:

- `POST /api/analyze`
- `POST /`

Public:

- `GET /health`
- `GET` and `HEAD /privacy/`
- `GET` and `HEAD /support/`
- homepage, favicon, JavaScript, CSS, and other static resources

The compatibility POST route remains protected until it is removed in a
separate contract change. Leaving it unprotected would bypass App Check.

### 6.2 Backend components

Add a small `AppCheckVerifier` protocol in `lib/` and a Firebase Admin SDK
adapter. The HTTP protection layer depends on the protocol, not on Firebase
exception types.

Required runtime configuration:

- `FIREBASE_PROJECT_ID`
- `FIREBASE_IOS_APP_ID`
- `APP_CHECK_ENFORCEMENT=required`

The expected Firebase iOS App ID is the Firebase `GOOGLE_APP_ID`, not the Apple
bundle identifier. Both values must be checked during configuration and release
preflight.

Firebase initialization is lazy. A Firebase or ADC configuration failure must
not prevent `/health`, privacy, support, or static pages from starting. A paid
request fails closed if the verifier cannot initialize or refresh verification
keys.

The Admin SDK verifier is synchronous and may refresh verification keys. The
ASGI protection layer runs that operation outside the event loop and preserves
cancellation without starting image or provider work.

The protected request order is:

1. Read the `X-Firebase-AppCheck` header.
2. Verify signature, expiry, issuer, audience/project, and exact iOS app
   subject through the Firebase Admin SDK and the owned adapter.
3. Check Gemini runtime configuration.
4. Decode and validate the image.
5. Acquire the process-local rate-limit token.
6. Call Gemini.
7. Run the existing deterministic assessment.

No token, decoded claim, SDK exception, image body, or provider response may be
logged.

### 6.3 iOS components

Add a `Sendable` token-provider boundary:

```swift
protocol AppCheckTokenProviding: Sendable {
    func token(forcingRefresh: Bool) async throws -> String
}
```

`AnalysisAPIClient` receives the provider through its initializer. It requests
a token before creating or sending the analysis request, sets
`X-Firebase-AppCheck` only on that request, and retains the existing redirect
rejection so neither the token nor image body can be forwarded.

`AppEnvironment.live()` remains the composition root. Its order is mandatory:

1. Resolve DEBUG UI fixtures and return immediately when selected.
2. Load and validate the non-secret API origin.
3. Configure Firebase and the App Check provider factory.
4. Construct the token provider, API client, and flow model.

Firebase initialization must not occur in `KaloriesApp.init`, a global, a
static initializer, or before the fixture branch.

Release and TestFlight use `AppAttestProvider` and the production App Attest
entitlement. A local DEBUG provider is allowed only behind an explicit DEBUG
launch/environment opt-in. Its token is never committed, copied to CI output,
or included in a distributed build.

The Firebase Apple SDK is pinned and resolved through Swift Package Manager.
Only `FirebaseCore` and `FirebaseAppCheck` products may be linked. The generated
Xcode project and `Package.resolved` are committed for reproducibility.

### 6.4 Firebase configuration file

The real `GoogleService-Info.plist` is obtained only after the exact iOS app is
registered. Firebase documents its identifiers as public rather than secret,
but the file still receives the following controls:

- bundle ID must equal `com.ryuaistudio.kalories`;
- project ID and `GOOGLE_APP_ID` must match the approved Firebase resources;
- it belongs only to the app target;
- it must not enable unrelated Firebase products;
- no service-account JSON, private key, debug token, or Gemini key is stored
  beside it;
- its API key restrictions and release-bundle scan are reviewed before upload.

For this single-owner application, the validated file is committed with the
generated project so local and archive builds are reproducible. It is treated
as public configuration, not as authorization. If the repository becomes a
reusable template, the file must be removed and supplied per deployment.

Reference: <https://firebase.google.com/docs/ios/learn-more>

### 6.5 Browser behavior

The public React page remains useful for product explanation and legal/support
navigation, but it no longer constructs or sends an analysis POST. Its capture
or analysis action is replaced by localized copy stating that photo analysis
is available in the iOS version.

No hidden, legacy, or alternate browser call may remain. Re-enabling browser
analysis requires a separate Firebase Web App Check design.

## 7. Error and Retry Contract

Backend responses use the existing owned envelope:

- `401 {"detail":{"code":"APP_CHECK_FAILED"}}` for a missing, empty,
  invalid, expired, wrong-project, or wrong-app token.
- `503 {"detail":{"code":"APP_CHECK_UNAVAILABLE"}}` when Firebase/JWKS/ADC
  verification infrastructure is unavailable or misconfigured.

The response never includes an SDK exception, claim, project number, App ID,
token fragment, or detailed validation reason.

The iOS client maps these codes to localized owned failures. Token acquisition
failure occurs before any image request. On a backend 401, the client may force
refresh the token and retry exactly once. A second 401 stops. A 503 uses manual
retry. Cancellation always wins over authentication and transport errors.

Automatic retry is safe only because the server rejects the request before
image decoding and provider invocation. Tests must prove zero provider calls on
both rejected attempts.

## 8. Privacy and Data Handling

The product still has no analytics, advertising, account, history, or tracking
SDK. Firebase App Check is used only for app-integrity and abuse prevention.

Firebase states that App Check processes attestation material and tokens. It
does not retain attestation material, and standard tokens not used for replay
protection are not retained by Firebase services. Firebase service data may
include IP addresses, app IDs, bundle IDs, and operational usage details.

Reference: <https://firebase.google.com/support/privacy/>

Before upload:

- update the public privacy policy in Japanese, Chinese, and English to name
  Firebase App Check and Apple App Attest, their purpose, data categories, and
  processing boundary;
- inspect the resolved SDK privacy manifests and the built app's merged privacy
  report;
- update the app-owned `PrivacyInfo.xcprivacy` only from the actual packaged
  dependency and runtime behavior;
- keep the existing conservative photo/video disclosure required by Gemini's
  provider-retention boundary;
- do not claim that no technical data is processed;
- do not mark Analytics, advertising, or tracking as enabled.

The final App Store Connect privacy answers are a separate evidence gate and
must include the practices of Firebase, Apple attestation, Gemini, and the app.

## 9. Testing Strategy

### 9.1 Backend

Use a fake verifier in all unit and FastAPI integration tests. No test may call
Firebase, ADC, JWKS, App Attest, Gemini, or a live Cloud service.

Tests cover:

- missing and empty header;
- invalid, expired, wrong-project, and wrong-app tokens;
- verifier initialization and JWKS failures;
- a valid exact-app token;
- both protected POST routes;
- public GET/HEAD routes;
- rejected requests perform zero image decode, limiter acquisition, and Gemini
  calls;
- valid requests preserve existing invalid-image, rate-limit, provider, and
  success behavior;
- errors and logs contain no token, claim, image, or internal exception.

### 9.2 iOS

Use fake token providers and the existing URL protocol stub.

Tests cover:

- exact header attachment;
- token failure produces zero URL requests;
- one forced refresh after 401 and no retry loop;
- verifier 503 mapping and manual-retry policy;
- task cancellation and model deallocation;
- redirects never receive token or image body;
- UI fixtures initialize Firebase zero times;
- Release selects App Attest and contains no debug provider path;
- three-language localization and exhaustive error/retry switches;
- `GoogleService-Info.plist` bundle, project, and app-ID identity.

### 9.3 Web and packaging

Tests prove that the browser bundle has no executable analysis POST path.
Dependency and binary scans reject Analytics, Auth, Crashlytics, debug tokens,
service-account material, and the Gemini key.

The complete backend, frontend, Swift unit, XCUITest, Debug simulator, unsigned
generic Release, localization, privacy-manifest, dependency, and diff gates run
before any external mutation or upload claim.

## 10. External Configuration and Release Sequence

External mutations remain blocked until the user approves their exact resource
identities and effects.

The required sequence is:

1. Approve attaching or enabling Firebase on the existing Google Cloud project.
2. Register one Apple app with bundle ID `com.ryuaistudio.kalories`.
3. Configure Firebase App Check with App Attest and the approved Apple Team ID.
4. Add the App Attest capability to the Apple App ID and refresh signing assets.
5. Obtain and validate the real `GoogleService-Info.plist`.
6. Apply the separately approved backend secret, Firebase config, quota, budget,
   IAM, and `maxScale=1` changes.
7. Deploy an immutable zero-traffic candidate.
8. Prove public pages are 200 and both protected POST routes reject no-token
   requests with the stable 401.
9. Use a separately registered local debug token only to validate the custom
   backend before distribution; never promote a debug provider to Release.
10. Promote only the exact verified revision using the hardened runbook.
11. Build, export, and upload the TestFlight binary without submitting App
    Store Review.
12. On a real iPhone, prove a TestFlight build obtains an App Attest-backed
    token and completes one full analysis.

An upload can precede the final physical-device proof because TestFlight is the
distribution mechanism needed for that proof. Processing success is not the
same as on-device App Attest success. A failed device proof stops tester rollout
and triggers rollback or roll-forward according to the release runbook.

## 11. Risks and Guardrails

| Risk | Guardrail |
| --- | --- |
| Public client token is copied and replayed within its TTL | Standard short-lived token, backend quota, budget, limiter, maxScale, and monitoring; no false claim of replay-proof security |
| Wrong Firebase app in the same project is accepted | Exact `FIREBASE_IOS_APP_ID` subject allowlist |
| App Attest unavailable or misconfigured | Fail closed for analysis; public support and legal pages remain available |
| Debug provider reaches Release | Compilation/configuration separation plus Release binary and bundle scans |
| UI tests contact Firebase | Fixture return precedes every Firebase initializer and is covered by zero-call tests |
| Backend enforcement breaks public pages | Method-and-path-specific protection with GET/HEAD regression tests |
| Browser bypasses iOS protection | Remove all browser analysis calls and protect both POST aliases |
| Firebase dependency expands data collection | Link only Core/AppCheck, inspect privacy manifests, update public disclosure |
| Old client becomes permanently unauthorized | Controlled TestFlight only; no public App Store users exist yet |
| Cloud or Apple mutation is performed under an implicit approval | Exact project, app, Team ID, IAM, environment, candidate, traffic, and upload actions require explicit checkpoints |

## 12. Acceptance Criteria

The implementation is locally complete only when:

- all backend, frontend, and iOS tests pass;
- protected POST requests fail before expensive work without a valid exact-app
  token;
- the iOS client sends no image when local token acquisition fails;
- DEBUG fixtures make zero Firebase calls;
- the web client makes zero analysis POST calls;
- Release links only Firebase Core and App Check, uses production App Attest,
  and contains no debug token/provider or unrelated Firebase SDK;
- the privacy policy, manifest evidence, release runbook, and preflight checks
  are internally consistent;
- generated project files and dependency locks are reproducible;
- `git diff --check` passes and the worktree is clean after scoped commits.

External TestFlight readiness additionally requires:

- approved Firebase, Apple, and Cloud resource configuration;
- a verified zero-traffic candidate and safe promotion;
- privacy/support URLs returning 200;
- no-token requests returning the owned 401;
- a processed TestFlight upload;
- a real iPhone App Attest analysis proof.

No result in this document authorizes App Store Review or public release.

## 13. Verification Commands

The implementation plan may refine paths but must retain these gates:

```bash
.venv/bin/python -m unittest tests.test_app_check tests.test_analyze tests.test_public_pages -v
.venv/bin/python -m unittest discover -s tests -p 'test_*.py' -v
.venv/bin/python -m compileall -q api lib tests
uv pip check --python .venv/bin/python
npm test
npm run lint
npm run build
docker build .
xcodegen generate --spec ios/project.yml --project ios
xcodebuild -project ios/Kalories.xcodeproj -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
xcodebuild -project ios/Kalories.xcodeproj -scheme Kalories \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
git diff --check
git status --short --branch
```

The live preflight remains read-only until the exact external-mutation
checkpoint is approved.
