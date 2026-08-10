# カロスキャン Japan App Store Public Release Design

Date: 2026-08-10

Status: Product and release direction approved in conversation. Implementation,
production mutation, build upload, App Review submission, approval, automatic
release, and Japan storefront availability remain separate evidence gates.

## 1. Real Objective

Publish the existing native iPhone app `カロスキャン` as a free public app in
the Japan App Store, with its core photo-to-nutrition flow functional and safe
for real users when Apple approves it.

The objective is not merely to upload an archive, obtain an App Store Connect
status, or display a product page. The terminal state is:

1. the approved version is publicly visible in the Japan storefront;
2. a user can download it without payment, in-app purchase, or subscription;
3. a clean physical iPhone can install and launch it;
4. the user can explicitly consent to sending a non-personal meal image;
5. the production backend verifies the genuine app and returns a coherent
   nutrition estimate; and
6. privacy, support, cost, logging, and incident controls remain valid after
   release.

## 2. First-Principles Rules

- Goal before options: Japan storefront download and a functioning production
  flow are the goal; upload and approval are intermediate states.
- Risk before speed: production safety must pass before App Review submission
  because the selected automatic-release mode removes the later manual-release
  brake.
- Value before effort: the release communicates the existing capture, consent,
  estimation, and review flow; it does not add speculative features.
- Understanding before persuasion: metadata says `推定` and never represents a
  photo estimate as measurement, diagnosis, treatment, or personalized medical
  advice.
- Maintainability before novelty: the existing SwiftUI, FastAPI, Firebase App
  Check, App Attest, and Cloud Run architecture remains intact.
- Evidence before completion: local tests, deployment, upload, processing,
  review, approval, automatic release, propagation, storefront visibility, and
  live-device smoke are separate gates.

## 3. Fixed Decisions and Identifiers

| Item | Fixed value |
| --- | --- |
| Public product name | `カロスキャン` |
| Apple app ID | `6799957568` |
| Bundle ID | `com.ryuaistudio.kalories` |
| Apple Team ID | `YMUG864233` |
| Version | `1.0.0` |
| Build | `1` if App Store Connect still confirms it has never been uploaded; otherwise the next unused integer |
| Platform | Native iPhone app, portrait, iOS 17 or later |
| Distribution | Public App Store |
| Country or region | Japan only |
| Price | Free |
| In-app purchases | None |
| Subscriptions | None |
| Release option | Automatically release after App Review approval |
| Primary language | Japanese |
| Primary category | Food & Drink |
| Secondary category | None for version 1.0.0 |
| App preview video | None for version 1.0.0 |
| Screenshot direction | `A · 機能を先に` |
| Pre-order | None |
| Phased release | Not applicable to the first release |

The app already contains Japanese, Simplified Chinese, and English binary
localizations. Japan-only availability does not require three storefront
metadata localizations for the first release. Japanese is the only required
storefront localization for version 1.0.0.

## 4. Current Evidence and Release Baseline

Repository evidence at design time:

- the native app, tests, Firebase App Check client, App Attest production
  entitlement, privacy manifest, Firebase configuration, App Store signing
  settings, and 1024-pixel App Store icon exist;
- the worktree branch is `codex/kalories-testflight-build1` at `db4e058` before
  this specification commit;
- the app identity is version `1.0.0`, build `1`, bundle
  `com.ryuaistudio.kalories`;
- an App Store Connect app record exists, but no processed upload was visible at
  the last audit;
- an Ad Hoc build was installed and manually accepted on the owner's iPhone;
  that proves device compatibility only, not App Store distribution readiness.

Live evidence at the 2026-08-10 audit:

- `GET /health` returned HTTP 200;
- public `/privacy` and `/support` returned HTTP 404;
- an unauthenticated `POST /api/analyze` returned HTTP 400 instead of the owned
  App Check HTTP 401;
- an exact Japan App Store lookup for the bundle returned no public result.

The public release baseline is therefore `NO-GO`. A fresh read-only preflight
is mandatory immediately before every production or App Store checkpoint.

## 5. Approaches Considered

### 5.1 Selected: production-safe sequential release

1. Close legal, privacy, provider, quota, budget, App Check, and rollback gates.
2. Deploy and validate a zero-traffic backend candidate.
3. Promote only the exact validated immutable revision.
4. Produce real App Store screenshots and complete Japanese metadata.
5. Archive, validate, upload, and wait for processing.
6. Complete all App Store Connect declarations and submit App Review with
   automatic release selected.
7. Verify approval, Japan storefront propagation, clean-device download, and
   one privacy-safe live analysis.

This is selected because App Review sees the same production system users will
receive, while release claims remain evidence-based.

### 5.2 Rejected: submit while production is unfinished

Uploading and submitting while backend hardening continues may reduce elapsed
calendar time, but Apple can review before the service is ready. Automatic
release could then expose a broken or insecure app. This path is rejected.

### 5.3 Rejected: remove the online analysis and submit an offline shell

This would reduce backend risk but remove the product's core value and require
a new product design. It is outside this release.

## 6. Scope

### 6.1 In scope

- Resolve every current production `NO-GO` in the approved Cloud/Firebase
  boundary.
- Verify Gemini paid-service privacy behavior, developer logging, dataset
  sharing, model availability, enforceable quota, and budget controls.
- Deploy a zero-traffic immutable Cloud Run candidate using the pinned secret,
  exact runtime service account, Firebase App Check enforcement, and App Attest
  app identity.
- Validate candidate health, public pages, protected routes, real synthetic
  meal analysis, latency, logs, and cost boundaries before traffic promotion.
- Update the privacy and support pages from controlled TestFlight language to
  truthful public Japan App Store language.
- Add a private owner-approved support contact method; a public GitHub issue is
  not the sole channel for privacy or sensitive support requests.
- Create Japanese App Store metadata and five portrait screenshots from the
  real app UI.
- Verify the app-owned and third-party privacy manifests in the final archive.
- Complete App Privacy, age rating, content rights, export compliance, review
  information, pricing, availability, and release settings in App Store
  Connect.
- Archive, validate, export, securely upload, and wait for Apple processing.
- Submit version 1.0.0 to App Review with automatic release selected.
- Verify the public Japan storefront and a clean-device production smoke.
- Record evidence without exposing credentials, image payloads, provider
  responses, App Check tokens, IAM identities, or sensitive logs.

### 6.2 Out of scope

- Countries or regions other than Japan.
- Paid download, in-app purchase, subscription, advertising, or monetization.
- Accounts, sign-in, cloud meal history, synchronization, analytics,
  attribution, or behavioral tracking.
- iPad, Mac, Apple Watch, Vision Pro, landscape, widgets, or App Clips.
- HealthKit, clinical use, medical diagnosis, treatment, or dietary
  prescription.
- New meal-history, trend, goal, social, recommendation, or coaching features.
- App preview video, pre-order, custom product pages, in-app events, or paid
  marketing campaigns.
- Replacing Gemini or rewriting the nutrition-scoring contract.
- Unrelated frontend, backend, infrastructure, or iOS refactoring.

## 7. Release Architecture and Gate Model

The release is a sequence of independent gates:

```text
approved source
  -> local quality gate
  -> provider and account gate
  -> zero-traffic backend candidate
  -> production traffic promotion
  -> real screenshots and metadata
  -> signed archive and validation
  -> upload and Apple processing
  -> App Review submission
  -> App Review approval
  -> automatic release
  -> Japan storefront propagation
  -> clean-device download and live smoke
```

No later gate may be inferred from an earlier result. In particular:

- an archive is not an upload;
- an upload is not a processed build;
- a processed build is not an App Review submission;
- approval is not storefront propagation;
- storefront visibility is not functional production acceptance.

Because automatic release is selected, App Review submission is the last point
at which this workflow can reliably stop before public availability. The
implementation plan must place a complete evidence review immediately before
submission.

## 8. Production Backend Design

The public App Store build continues to use the existing HTTPS origin:

`https://kalories-sxielk4wua-an.a.run.app`

Public surfaces:

- `GET /health`
- `GET` and `HEAD /privacy/`
- `GET` and `HEAD /support/`
- static product resources

Protected surfaces:

- `POST /api/analyze`
- compatibility `POST /`

Both protected routes must verify an exact Firebase App Check token for the
registered iOS app before image decoding, rate limiting, or Gemini work.
Missing or invalid tokens return only the owned HTTP 401 contract. Verifier
infrastructure failures return the owned HTTP 503 contract. No browser
analysis bypass is restored.

Public release retains defense in depth:

- Release uses Apple App Attest with no debug-provider fallback;
- the replacement Gemini credential is secret-backed and restricted;
- the selected Gemini model is configured explicitly;
- Cloud Run maximum instances, concurrency, timeout, process token bucket,
  provider daily quota, and billing alert are read back from the control plane;
- request and application logs are scanned without printing their contents;
- image bytes, Base64 content, model output, credentials, App Check tokens, and
  decoded claims are never logged;
- only a validated immutable revision may receive production traffic.

The first public release must have a fail-closed incident action. If no
separately validated safe rollback revision exists, the service may disable
analysis with an owned unavailable response; it must never shift traffic back
to the legacy plaintext-secret or unauthenticated revision.

## 9. Public Privacy and Support Design

### 9.1 Privacy policy

`public/privacy/index.html` must be revised before deployment:

- remove controlled-TestFlight-only and public-release-incomplete statements;
- identify the public app as `カロスキャン` while retaining the developer or
  service identity required for legal accuracy;
- describe the exact user action that sends a selected image;
- name Kalories, Google Gemini, Firebase App Check, and Apple App Attest and
  explain their limited purposes;
- state the verified provider retention, paid-service, developer-logging, and
  dataset-sharing behavior without claiming zero retention unless proven;
- describe Cloud Run technical metadata and the absence of Kalories meal
  history, accounts, ads, analytics, and tracking;
- explain withdrawal before future sends and the actual deletion boundary;
- retain the photo-estimate and non-medical limitation;
- provide a private, owner-approved privacy contact method.

Apple's privacy metadata and the public policy must agree with the final binary
and every third-party partner. The App Store form is not derived only from the
app-owned `PrivacyInfo.xcprivacy`; the resolved Firebase manifests and backend
provider behavior are included in the evidence review.

### 9.2 Support page

`public/support/index.html` must:

- replace invited-TestFlight language with public Japan App Store guidance;
- describe capture, photo selection, consent, analysis, retry, and common error
  recovery;
- link to the privacy policy;
- state that results are estimates and are not medical diagnosis or advice;
- provide actual private contact information approved by the owner;
- warn users not to send personal meal photos, secrets, or credentials through
  public issue trackers.

The final support URL must lead to usable contact information. A GitHub issue
may remain as an optional public bug channel, but not the only privacy/support
contact.

### 9.3 In-app access

The app already exposes privacy and support links from the capture flow. The
Release build must prove that both links open the deployed HTTPS pages. If the
links are inaccessible or hidden by a regression, App Review submission stops.

## 10. App Store Product Page Design

### 10.1 Japanese metadata

Proposed version 1.0.0 metadata:

- Name: `カロスキャン`
- Subtitle: `食事写真から栄養をかんたん推定`
- Promotional text:
  `食事の写真から、カロリーと栄養バランスの目安をすばやく確認。送信前に写真の取扱いを確認できます。`
- Keywords:
  `カロリー,栄養,食事,写真,料理,食生活,フード,分析,推定`
- Primary category: Food & Drink
- Marketing URL: omitted for version 1.0.0 unless an accurate maintained
  product page is available
- Privacy policy URL:
  `https://kalories-sxielk4wua-an.a.run.app/privacy/`
- Support URL:
  `https://kalories-sxielk4wua-an.a.run.app/support/`

Proposed description:

```text
カロスキャンは、食事の写真からカロリーと栄養バランスの目安を確認できるアプリです。

主な機能
・カメラで食事を撮影、または写真を選択
・カロリーと主要な栄養情報を推定
・認識した料理、推定の前提、信頼度を確認
・食事バランスの参考情報をわかりやすく表示

写真は、送信内容を確認して「この写真を分析」を選んだ場合にのみ、分析のためKaloriesサービスとGoogle Geminiへ送信されます。

カロスキャンにはアカウント、広告、行動追跡、クラウド上の食事履歴はありません。

表示内容は写真に基づく一食分の推定値です。正確な測定値、医療診断、医療助言、個別の治療・栄養指導ではありません。
```

The implementation phase must count the final App Store fields, recheck the
Japanese wording against the shipped UI, and remove any claim that cannot be
demonstrated in the final build.

### 10.2 Copyright and seller information

The copyright owner, support email, legal contact name, and any App Store
account compliance fields are not inferred from the bundle identifier or a
domain. The exact owner-approved values must be read from the App Store Connect
account or supplied by the owner before submission.

### 10.3 Pricing and availability

- Public distribution method.
- Japan is the only enabled country or region.
- Base price is free.
- No in-app purchases or subscriptions are attached.
- No pre-order.
- Release setting is `Automatically release this version`.

All other regions must be read back as unavailable immediately before
submission and again after release.

## 11. Screenshot Design: A · 機能を先に

Version 1.0.0 uses five Japanese portrait screenshots. They are captured from
the real Release-equivalent app UI with an offline deterministic fixture and a
non-personal synthetic meal image. Marketing text may frame the capture, but
the app UI itself is not invented or materially altered.

Sequence:

1. `写真を撮るだけ` — real capture screen with camera and photo-selection
   choices.
2. `栄養をすぐ把握` — real result summary with calories, score, confidence,
   and main conclusion.
3. `食材と栄養を確認` — real detected-food and nutrition detail portion of
   the result.
4. `送信前に確認` — real selected-photo preview, Gemini transfer disclosure,
   and explicit analysis action.
5. `推定だから、確認しやすい` — real assumptions, confidence, and
   non-medical disclaimer from the result.

The fifth screenshot deliberately replaces the exploratory trend graphic from
the visual comparison. Version 1.0.0 has no history or trend feature, so such a
graphic would misrepresent the product.

Asset requirements:

- use one of Apple's currently accepted 6.9-inch portrait dimensions captured
  from a matching simulator or device; do not upscale a smaller capture;
- PNG or JPEG with no alpha channel;
- one to ten screenshots are allowed; this design uses five;
- preserve correct status-bar, language, safe-area, and Dynamic Type rendering;
- show no personal photo, name, account, device identifier, token, or real
  provider response;
- show no price, medical outcome, guaranteed accuracy, unsupported feature, or
  competitor mark;
- verify every final image at full pixel resolution before upload.

No app-preview video is used. This reduces the first-release asset surface and
avoids video processing becoming a release dependency.

## 12. App Privacy, Age, Content, and Export Declarations

### 12.1 App Privacy

The final App Privacy answers are evidence-derived. At minimum, the review must
consider:

- photos or videos sent for app functionality;
- whether any technical identifier or diagnostic data from Firebase, Apple
  attestation, Cloud Run, or Gemini meets Apple's collection definition;
- whether each data type is linked to a user when the app has no account;
- tracking status, which must remain `No` unless the shipped behavior changes;
- third-party partners integrated into the binary or backend flow.

The source privacy manifest currently declares photos or videos for app
functionality, not linked to the user, not used for tracking, plus the required
UserDefaults API reason. The archived app and dependency manifests are
authoritative for final verification.

### 12.2 Age rating

App Store Connect's current age-rating questionnaire is required. Answers must
describe the shipped app rather than target a desired marketing badge.

The repository's current public documents still impose an adults-only
TestFlight boundary. Whether the public app remains adults-only or changes to a
general-audience policy is an unresolved owner decision. Until resolved, the
workflow is fail-closed and does not submit. If an adults-only policy is kept,
the public policy, support page, metadata, review notes, and any available
higher-age override must agree.

The app is not submitted to the Kids category.

### 12.3 Content rights and medical boundary

- The app displays only user-supplied meal images and generated estimates; it
  does not ship third-party editorial media requiring separate content rights.
- The app does not integrate HealthKit or claim regulated-medical-device use.
- Review notes and metadata repeat the estimate/non-medical boundary.
- If App Store Connect presents a regulated-medical-device declaration, the
  response is based on the shipped function and account eligibility, not
  guessed.

### 12.4 Export compliance

The app uses standard HTTPS/TLS and Firebase networking. Export-compliance
answers must be completed from the archived binary and Apple's current form.
No custom cryptographic algorithm is introduced. Any exemption declaration is
recorded exactly as accepted by App Store Connect.

## 13. App Review Design

Reviewer access requires no account, login, invitation, subscription, or demo
credential.

Proposed review notes:

```text
カロスキャンはログイン不要のiPhone向け食事写真分析アプリです。

確認手順:
1. 「カメラで撮影」または「写真から選択」を選びます。
2. 食事写真を確認します。
3. 写真がKaloriesサービスとGoogle Geminiへ送信される案内を確認し、「この写真を分析」をタップします。
4. カロリー、栄養情報、推定の前提、信頼度、非医療用途の注意書きを確認します。

アカウント、課金、アプリ内購入、サブスクリプション、広告、追跡はありません。
写真に食事が明確に写っていない場合は、食事を認識できない旨を表示します。
```

Before submission, the review notes must be tested by following them on a clean
device against production. If App Attest or the provider cannot serve Apple's
review device, submission stops.

## 14. Release Sequence and External Mutations

### Phase 1: local release candidate

- reconcile the approved public-release branch with the intended source HEAD;
- update legal/support language and release evidence files;
- add deterministic screenshot capture support only if it does not enter the
  Release product;
- pass complete web, backend, iOS, privacy, signing, and source scans;
- review `git diff` and produce scoped commits.

### Phase 2: production service readiness

- run the read-only Cloud/Firebase/provider/account audit;
- complete unresolved provider, quota, budget, and owner-contact evidence;
- deploy the exact source as a zero-traffic immutable candidate;
- test public pages, no-token rejection, valid-token flow, real synthetic image,
  schema, latency, cost, and safe logs;
- promote only that revision and rerun the full production gate;
- revoke legacy credentials only after the replacement path is healthy;
- record a fail-closed incident action and prohibit rollback to the insecure
  legacy revision.

### Phase 3: App Store assets and build

- capture and inspect the five real Japanese screenshots;
- complete and review the Japanese metadata source of truth;
- verify icon, privacy manifests, entitlements, binary dependencies, version,
  build, bundle, and signing;
- archive and export with Xcode 26 or later using the iOS 26 SDK or later;
- validate and upload through an authenticated official Apple path;
- wait for App Store Connect processing and resolve every blocking warning or
  error without weakening release rules.

### Phase 4: submission and automatic release

- select the processed build;
- complete App Privacy, age rating, content rights, export compliance,
  copyright, review contact, review notes, pricing, Japan-only availability,
  and automatic release;
- compare the live App Store Connect record against this design;
- submit App Review only after every pre-submission gate passes;
- monitor review status without treating silence as approval;
- respond to rejection with a scoped diagnosis and a new build only when
  necessary.

### Phase 5: public acceptance

- verify the version status indicates distribution and not merely approval;
- resolve the canonical Japan App Store URL for Apple app ID `6799957568`;
- verify the product page, price, screenshots, privacy link, support link,
  seller information, compatibility, and Japan-only availability;
- download on a clean physical iPhone from the Japan storefront;
- launch and perform one privacy-safe synthetic meal analysis;
- verify production logs and cost controls without exposing their contents;
- record the final Git state and remaining operational risks.

## 15. Error Handling and Recovery

### Upload or processing failure

- Preserve the archive and delivery log.
- Fix the exact signing, metadata, binary, or transporter failure.
- Reuse build `1` only if Apple never accepted it; otherwise increment the build
  number. Never overwrite an accepted build identity.

### App Review rejection

- Treat metadata, privacy, functionality, and policy reasons separately.
- Reply with evidence when the binary already complies.
- Create a new binary only when the shipped behavior must change.
- Do not remove consent, uncertainty, privacy, App Check, or cost controls to
  obtain approval.

### Backend incident before approval

- Stop the release workflow and restore a verified production state.
- Do not submit or continue review while the core flow is unavailable.

### Backend incident after approval or automatic release

- Use only a separately validated safe revision or fail closed with the owned
  unavailable response.
- Never expose an unauthenticated or plaintext-secret fallback.
- Update the support page if user-facing service degradation persists.

### Storefront propagation delay

- Distinguish automatic release from availability.
- Poll the Japan storefront and App Store Connect status within a bounded
  window; do not claim public download until both provide direct evidence.

## 16. Expected Files and External Surfaces

Likely repository changes:

- `public/privacy/index.html`
- `public/support/index.html`
- `tests/test_public_pages.py`
- focused backend or release-gate files only if a verified production blocker
  requires a code correction
- `ios/project.yml` and generated project only if the build number or a verified
  release setting changes
- focused iOS source or tests only if a verified App Review blocker exists
- `scripts/check-testflight-backend.sh` or a new public-release wrapper that
  preserves the existing fail-closed checks
- a deterministic screenshot capture script or UI-test fixture if required
- App Store metadata and review text under `docs/release/`
- final screenshots under a scoped `docs/release/app-store-assets/` path if the
  repository-size review accepts them
- a public App Store release runbook and evidence ledger under `docs/release/`
- `README.md` only where the public distribution status or support path must be
  updated

External surfaces:

- Google Cloud/Firebase control plane and Cloud Run traffic;
- Gemini quota, logging, dataset-sharing, paid-service, and budget controls;
- Apple Developer signing assets only if refresh is required;
- App Store Connect app information, version metadata, privacy, availability,
  pricing, review submission, and release status;
- Japan App Store storefront.

No unrelated repository, branch, Apple app, Firebase app, Cloud project,
service, region, country, or product is in scope.

## 17. Verification Commands

The implementation plan may refine exact output paths but must retain these
gates.

### Repository and web/backend

```bash
git status --short --branch
npm test
npm run lint
npm run build
.venv/bin/python -m unittest discover -s tests -p 'test_*.py' -v
.venv/bin/python -m compileall -q api lib tests
.venv/bin/python -c "import api.analyze, lib.nutrition, lib.rate_limit, lib.app_check"
uv pip check --python .venv/bin/python
docker build .
git diff --check
```

### iOS

```bash
npm run ios:localizations:check
xcodegen generate --spec ios/project.yml --project ios

xcodebuild -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  test

xcodebuild -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build

scripts/check-ios-app-check-release.sh --local
```

The signed gate adds the built `.app` path and exact approved Firebase app ID:

```bash
KALORIES_EXPECTED_FIREBASE_IOS_APP_ID='approved-firebase-ios-app-id' \
  scripts/check-ios-app-check-release.sh --app '/absolute/path/Kalories.app'
```

### Archive and export

```bash
xcodebuild -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath '/absolute/path/Kalories.xcarchive' \
  archive

xcodebuild -exportArchive \
  -archivePath '/absolute/path/Kalories.xcarchive' \
  -exportPath '/absolute/path/export' \
  -exportOptionsPlist '/absolute/path/ExportOptions.plist'
```

Upload is performed only through an authenticated Apple-supported route. The
terminal evidence is the processed build in App Store Connect, not a local
command exit code.

### Live production

```bash
KALORIES_EXPECTED_REVISION='exact-promoted-revision' \
KALORIES_EXPECTED_FIREBASE_IOS_APP_ID='approved-firebase-ios-app-id' \
  scripts/check-testflight-backend.sh

curl --fail --silent --show-error \
  'https://kalories-sxielk4wua-an.a.run.app/health'
curl --fail --silent --show-error \
  'https://kalories-sxielk4wua-an.a.run.app/privacy/' >/dev/null
curl --fail --silent --show-error \
  'https://kalories-sxielk4wua-an.a.run.app/support/' >/dev/null
```

The preflight script owns the no-token POST checks so no image or token is
printed. A valid App Attest production request is verified only on a physical
iPhone.

### Storefront

The implementation uses Apple's public Japan lookup and canonical product URL
for app ID `6799957568`, then verifies the page in a browser and by installing
from the Japan storefront. An HTTP response alone is not visual or functional
acceptance.

## 18. Acceptance Criteria

### 18.1 Submission-ready

- The intended source commit and branch are recorded and clean.
- All repository, backend, web, iOS, privacy, signing, binary, and diff checks
  pass.
- Provider paid-service, logging, dataset-sharing, retention, model, quota, and
  budget evidence is current.
- The exact immutable production revision passes all public, protected,
  real-analysis, latency, log, and cost checks.
- Privacy and support pages return HTTP 200 and match the public app.
- A private owner-approved support contact exists.
- Five real Japanese 6.9-inch screenshots pass full-resolution inspection.
- Japanese metadata contains no unsupported or medical claim.
- The signed archive is valid, contains the correct icon, privacy manifests,
  App Attest production entitlement, Firebase configuration, bundle, version,
  build, and no forbidden SDK or credential.
- The uploaded build is processed and selectable in App Store Connect.
- App Privacy, age rating, content rights, export compliance, copyright,
  review information, free price, Japan-only availability, and automatic
  release are complete and mutually consistent.
- The unresolved age-audience and private-contact decisions are closed.

### 18.2 Publicly released

- App Review approval is recorded.
- The version automatically transitions to distribution without a manual
  release action.
- The Japan App Store page is reachable for app ID `6799957568` and shows the
  approved name, metadata, screenshots, free price, privacy URL, and support
  URL.
- The app is unavailable in every non-Japan storefront checked through the
  configured availability record.
- A clean physical iPhone can download, install, and launch the App Store
  build.
- The App Store build obtains a production App Attest-backed App Check token
  and completes one privacy-safe synthetic meal analysis.
- The response is contract-coherent and the UI retains its estimate and
  non-medical disclosures.
- Post-release logs and cost controls pass without exposing sensitive content.
- Git diff and status are reviewed, remaining risks are recorded, and the next
  operational action is explicit.

## 19. Remaining Owner Decisions

These are intentionally unresolved and must be asked one at a time after this
written design is approved:

1. Public audience policy: adults-only or general audience, followed by the
   truthful App Store age questionnaire and any higher-age override.
2. Private support/privacy contact to publish.
3. Exact copyright owner string from the App Store Connect legal account.
4. Monthly billing-alert amount; the alert is monitoring, not a hard cap.

No unresolved owner decision may be guessed from a repository name, domain,
bundle identifier, or personal account detail.

## 20. Official References

- App Review Guidelines:
  <https://developer.apple.com/app-store/review/guidelines/>
- Screenshot specifications:
  <https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/>
- Upload screenshots and previews:
  <https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots>
- App information properties:
  <https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/>
- Required and localizable properties:
  <https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties>
- App Privacy:
  <https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/>
- Age rating:
  <https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating>
- Release options:
  <https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option/>
- Upload builds:
  <https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/>
- Current SDK upload requirement:
  <https://developer.apple.com/news/upcoming-requirements/?id=02032026a>

Approval of this design authorizes writing the implementation plan. It does
not by itself mark any live gate as passed.
