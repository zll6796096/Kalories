# カロスキャン Native iOS TestFlight Design

Date: 2026-08-08

## 1. Objective

Prepare Kalories for its first TestFlight upload as a native iPhone app named
`カロスキャン`.

The real objective is not merely to make the existing website run inside an
iOS container. It is to produce a signed, testable, privacy-conscious native
client that preserves the existing nutrition contract and can be processed by
App Store Connect without representing TestFlight readiness as public App
Store readiness.

## 2. First-Principles Rules

- Goal before options: the terminal state is a processed TestFlight build, not
  App Store Review submission or public availability.
- Risk before speed: local tests, a successful simulator build, an archive, an
  upload, App Store Review, and storefront release are separate gates.
- Understanding before persuasion: the app leads with an understandable meal
  conclusion, then shows the evidence and uncertainty.
- Maintainability before novelty: SwiftUI owns device interaction and
  presentation; FastAPI owns provider access and deterministic assessment.
- Evidence before completion: no gate passes without the corresponding test,
  archive, export, device, service, or App Store Connect evidence.

## 3. Selected Product Identity

- App Store product name: `カロスキャン`
- Home-screen display name: `カロスキャン`
- Bundle identifier: `com.ryuaistudio.kalories`
- Version: `1.0.0`
- Initial build number: `1`, increased for every subsequent upload
- Category: Food & Drink
- Distribution target for this project: TestFlight only

The subtitle is separate from the product name and is
`写真でカロリー・食事分析`. Product copy uses `推定` where precision matters;
it must not describe photo-derived nutrition values as laboratory measurement.

App Store Connect name reservation remains an external gate. The selected name
is not treated as available until the app record accepts it.

## 4. Scope

### In scope

- A native SwiftUI iPhone client built with Xcode 26 or later and the iOS 26
  SDK or later.
- iPhone only, portrait only, minimum iOS 17.
- Native camera capture and system photo selection.
- On-device orientation correction, resizing, and compression before upload.
- Explicit user action before every analysis upload.
- Native intro/capture, analyzing, result, and recoverable-error states.
- One continuous, scrollable result page with the health conclusion first.
- Japanese, Simplified Chinese, and English; device-language resolution with
  Japanese fallback.
- Strict Swift models matching the existing `/api/analyze` contract.
- Reuse of the existing FastAPI/Gemini estimation and deterministic Python
  assessment.
- A Japanese privacy policy and support page reachable over HTTPS.
- Backend secret migration, credential rotation, a single-instance global
  token bucket, hard model quotas, and budget controls required for controlled
  TestFlight use.
- Automated Swift unit tests, XCUITest coverage, simulator validation, archive,
  App Store Connect export, on-device verification, and TestFlight upload.

### Out of scope

- App Store Review submission, approval, manual release, or storefront
  availability.
- iPad, Mac, Apple Watch, Apple Vision Pro, landscape layouts, widgets, and App
  Clips.
- Accounts, cloud meal history, cross-device synchronization, subscriptions,
  in-app purchases, ads, or analytics SDKs.
- Medical diagnosis, personalized dietary prescriptions, or promises of
  precise nutrition measurement.
- Replacing Gemini, rewriting the nutrition heuristic, or porting the scoring
  algorithm to Swift.
- App Attest as a first-TestFlight dependency. It remains a separate public
  App Store release gate.
- Unrelated frontend, API, infrastructure, or repository refactoring.

## 5. Architecture

### 5.1 Repository layout

The existing React/Vite and FastAPI application remains intact. A separate
native project is added under `ios/`:

```text
ios/
  Kalories.xcodeproj/
  Kalories/
    App/
    Features/Capture/
    Features/Analysis/
    Features/Result/
    Models/
    Services/
    Resources/
    Assets.xcassets/
    PrivacyInfo.xcprivacy
  KaloriesTests/
  KaloriesUITests/
```

The iOS app contains no embedded web view and no JavaScript runtime. It calls
the production API over HTTPS.

### 5.2 Component responsibilities

- `KaloriesApp`: app entry point and dependency composition.
- `AppFlowModel`: one state machine for capture, analyzing, result, and error.
- `CameraView`: native camera capture with explicit camera authorization.
- `PhotoPicker`: system photo-library picker without broad library access.
- `ImageProcessor`: orientation normalization, pixel bounding, JPEG encoding,
  and the existing three-mebibyte decoded-image boundary.
- `AnalysisAPIClient`: HTTPS request construction, timeout, cancellation,
  status-code mapping, decoding, and strict response validation.
- `AnalysisModels`: Codable representations of all existing estimation,
  confidence, status, assessment, and error fields.
- `ResultView`: localized, health-conclusion-first single-page presentation.
- `Localization`: Japanese, Simplified Chinese, and English strings with
  Japanese fallback.

Each unit has one purpose. View code does not call URLSession directly, the API
client does not calculate health scores, and Swift does not duplicate the
Python assessment rules.

The Release API origin is supplied through a committed non-secret
`KALORIES_API_BASE_URL` build setting. Debug and tests may override it with a
local or mocked origin. No model credential or privileged API token is included
in any configuration file or app bundle.

### 5.3 Data flow

1. The user takes a photo or selects one through a system picker.
2. The image remains in process memory while the app presents a preview.
3. The user explicitly starts analysis.
4. `ImageProcessor` corrects orientation, reduces pixels, and compresses the
   image within the server contract.
5. `AnalysisAPIClient` sends the data URI to `POST /api/analyze` over HTTPS.
6. FastAPI validates the image and sends it to Gemini for observable meal and
   nutrition estimation only.
7. The existing deterministic Python module generates score, tier, statuses,
   reasons, and suggestions.
8. Swift strictly decodes and validates the complete response.
9. `ResultView` renders localized estimates, confidence, uncertainty, and the
   non-medical boundary.
10. Retake or app termination discards the in-memory image and result.

Unknown nutrition values remain `null` and render as unavailable. They are
never rewritten to zero.

## 6. Product Experience

The app preserves the approved health-conclusion-first direction:

1. Localized food name and image.
2. Overall confidence.
3. Estimated score and written tier, or an insufficient-data state.
4. Strongest supported positive and main concern.
5. Calories and the seven nutrition values with statuses and confidence.
6. Up to two deterministic suggestions.
7. Photo-estimate, single-meal, and non-medical disclosure.
8. Analyze another meal.

All required content is visible on one vertically scrollable result screen. It
is not hidden behind tabs or secondary detail pages.

Native controls support VoiceOver, Dynamic Type, adequate contrast, meaningful
accessibility labels, and touch targets of at least 44 by 44 points. Status is
not communicated by color alone.

## 7. Privacy and Data Handling

The first TestFlight version has:

- no account;
- no meal history;
- no advertising or tracking;
- no analytics SDK;
- no location request;
- no background upload;
- no server-side image or result persistence implemented by Kalories.

Images are transmitted only after an explicit analysis action. The app and
FastAPI code do not log image bytes or base64 payloads. Results stay in process
memory and are discarded when the flow resets or the process ends.

The privacy policy must accurately describe transmission to the Kalories
backend and its Gemini provider, transient processing, Cloud Run request
metadata, user choices, contact information, and any provider retention that
applies to the selected Gemini service. Provider behavior must be verified from
the applicable account and terms before the privacy declaration is published.

The native target includes a valid `PrivacyInfo.xcprivacy` describing collected
data and any required-reason APIs actually present in the final archive. Camera
usage text explains that the camera is used to photograph a meal for nutrition
estimation. System photo selection is preferred over requesting broad photo
library access.

App Store Connect privacy answers must match the shipped binary, backend, and
third-party provider. They are not inferred solely from the absence of a local
database.

References:

- <https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/>
- <https://developer.apple.com/documentation/bundleresources/privacy-manifest-files>

## 8. Backend and Infrastructure Gate

Before TestFlight upload:

1. Rotate the currently deployed Gemini credential.
2. Store the replacement as a dedicated Secret Manager secret and inject it by
   secret reference, not as a plain Cloud Run environment-variable value.
3. Restrict the credential to the required model API and the Kalories project
   wherever the provider supports those restrictions.
4. Retain fail-closed behavior when configuration is missing.
5. Enforce image byte, encoded-length, format, pixel, and request-time limits.
6. For the controlled first TestFlight, set Cloud Run to one maximum instance
   and apply a process-global token bucket of 12 analysis requests per minute
   with a burst of four. The limiter uses no account, device, or IP identifier.
7. Set a hard model quota of 200 analysis calls per day and configure billing
   budget alerts. If the provider cannot enforce the hard daily quota, the
   TestFlight backend gate is NO-GO until an equivalent enforceable cost ceiling
   exists.
8. Ensure logs contain neither the credential nor image payloads.
9. Verify a real non-personal meal image end to end after hardening.

A healthy `/health` response proves transport only. TestFlight backend readiness
also requires a successful real analysis response and safe log inspection.

The token bucket resets on process restart, so the hard provider quota is the
authoritative TestFlight cost ceiling. This is intentionally a controlled-beta
control, not a public-release rate limiter. The current public web client also
prevents the API from being restricted to attested iOS clients. Before App Store
Review, adopt App Attest or route the service through externally backed abuse
protection such as Cloud Armor, then re-run privacy and end-to-end review.

## 9. Error Handling

The client maps errors into stable, localized categories:

- camera permission denied;
- photo selection cancelled;
- invalid, unsupported, or oversized image;
- no food detected;
- offline or lost connection;
- request timeout;
- service not configured;
- provider analysis failure;
- malformed or contract-incoherent response;
- unknown recoverable failure.

Recoverable errors are inline and preserve the compressed image in memory so
the user can explicitly retry. Leaving the analyzing state cancels the active
request. Retake discards the prior image and result. Raw provider responses,
stack traces, request payloads, and secret-bearing details are never shown.

## 10. Expected Files and External Changes

Likely repository changes:

- `ios/Kalories.xcodeproj/project.pbxproj`
- `ios/Kalories/**/*.swift`
- `ios/Kalories/Assets.xcassets/**`
- `ios/Kalories/PrivacyInfo.xcprivacy`
- `ios/Configuration/*.xcconfig`
- `ios/KaloriesTests/**`
- `ios/KaloriesUITests/**`
- `public/privacy.html`
- `public/support.html`
- focused `api/` changes only if required by the approved security or legal
  surface
- `README.md`
- focused release documentation under `docs/`

External changes requiring explicit, separately recorded evidence:

- Apple Developer bundle identifier and signing profile;
- App Store Connect app record and product-name reservation;
- Cloud Secret Manager, Cloud Run, quota, rate-control, and budget settings;
- App Store Connect privacy, age-rating, contact, and TestFlight metadata;
- build upload and processing.

No production infrastructure change is implied by committing this design.

## 11. Verification and Acceptance Criteria

### 11.1 Existing application gate

```bash
npm test
npm run lint
npm run build
.venv/bin/python -m unittest discover -s tests -p 'test_*.py' -v
.venv/bin/python -m compileall -q api lib tests
.venv/bin/python -c "import api.analyze, lib.nutrition"
uv pip check --python .venv/bin/python
git diff --check
```

The current baseline is 111 frontend tests and 61 backend tests. The counts may
increase, but no existing test may be silently removed to obtain a pass.

### 11.2 Native automated gate

The final scheme must be read from the created project. The current verified
local simulator is iPhone 17 Pro with iOS 26.5, so the intended commands are:

```bash
xcodebuild -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  test

xcodebuild -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/Kalories.xcarchive \
  archive
```

Swift tests cover image processing, model decoding, contract coherence, state
transitions, cancellation, timeouts, and stable error mapping. XCUITest covers
photo selection with controlled fixtures, analyzing, result rendering, and
retry without invoking the paid provider.

### 11.3 Archive and export gate

- Xcode 26 or later and an iOS 26 SDK or later are selected.
- The archive uses `com.ryuaistudio.kalories`, version `1.0.0`, a unique build
  number, and Apple Distribution signing for the intended team.
- The archive contains the privacy manifest and required icon resources.
- App Store Connect export succeeds using method `app-store-connect`.
- Export validation reports no blocking errors.

Apple's current SDK upload requirement is authoritative:

- <https://developer.apple.com/news/upcoming-requirements/>

### 11.4 Device and service gate

On a physical iPhone:

- camera permission allow and deny paths work;
- system photo selection works without broad library access;
- portrait layout, Japanese fallback, Chinese, English, VoiceOver, and Dynamic
  Type are usable;
- a non-personal meal image produces a coherent real result;
- no-food, offline, timeout, and retry behavior are understandable;
- the privacy and support URLs return successful HTTPS responses;
- relevant service logs contain no photo payload or credential.

### 11.5 TestFlight terminal gate

- The app record accepts the product name and bundle identifier.
- The uploaded build is processed by App Store Connect with upload status
  `Complete`, with all blocking issues resolved.
- The build appears under TestFlight and is available to the intended internal
  tester group.
- No App Store Review submission is created or sent.

Upload success alone does not prove processing success. TestFlight visibility
does not prove App Store Review approval or public availability.

Reference:

- <https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/>

## 12. Risks and Guardrails

- **Product-name conflict:** reserve the name before treating metadata as final.
- **Signing or role gap:** stop at NO-GO if the team, provider, certificate,
  profile, agreement, or App Store Connect role is not verified.
- **Plaintext or leaked credential:** rotate it; do not reuse or print it in
  reports, commands, screenshots, or logs.
- **Public API abuse:** the first-TestFlight global limiter plus hard provider
  quota is not public-release protection; App Store Review remains NO-GO until
  externally backed or attested abuse protection is verified.
- **Misleading health claim:** use estimate and uncertainty language; do not
  call photo output a precise measurement or diagnosis.
- **Provider privacy drift:** verify applicable Gemini data handling before
  publishing the privacy policy and App Store privacy answers.
- **Local-only confidence:** simulator tests do not replace device, export,
  backend, or App Store Connect evidence.
- **Unrelated dirty work:** do not reset, stash, clean, or stage unrelated
  changes; use explicit paths.

## 13. Completion Report Requirements

The implementation handoff must report:

- acceptance criteria and evidence for every gate;
- exact tests, archive, export, device, backend, and upload outcomes;
- any check as `SKIPPED (reason)` rather than PASS when it was not run;
- Git diff review and final Git status;
- remaining public App Store release risks;
- the next explicit action.

This design is complete when it is approved and committed. The application
work is complete only when the TestFlight terminal gate is independently
verified.
