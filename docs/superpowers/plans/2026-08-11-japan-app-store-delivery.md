# Japan App Store Delivery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver Kalories version 1.0.0 build 1 through Apple's authenticated pipeline, submit it with automatic release, and prove that the approved app is downloadable and functional from the Japan App Store.

**Architecture:** Treat signed archive, upload, processed build, metadata, App Review submission, approval, automatic release, storefront propagation, installation, and production analysis as separate gates. Build from the exact clean production commit, inspect the signed archive before upload, copy product-page values from the committed Japanese metadata contract, and stop before App Review submission for fresh owner confirmation because approval will trigger public release.

**Tech Stack:** Xcode 26.6, iOS 26.5 SDK, Xcode Organizer, App Store Connect, Swift 6, `xcodebuild`, `codesign`, `security`, `plutil`, `jq`, `curl`, Apple App Attest, Firebase App Check.

---

## Dependencies and Scope

Required completed plans:

- `docs/superpowers/plans/2026-08-11-japan-app-store-release-foundation.md`
- `docs/superpowers/plans/2026-08-11-japan-production-backend-release.md`

Fixed delivery identity:

| Item | Value |
| --- | --- |
| App name | `カロスキャン` |
| Apple app ID | `6799957568` |
| Bundle ID | `com.ryuaistudio.kalories` |
| Version/build | `1.0.0 (1)` |
| Team/profile | `YMUG864233` / `Kalories App Store` |
| Firebase iOS app ID | `1:788259830737:ios:a4459f14b5e8046297bef0` |
| Territory/price | Japan only (`JPN`) / Free |
| IAP/subscriptions | None |
| Release option | Automatically release after approval |
| Audience/category | 18+, not Kids / Food & Drink |
| Public contact | `zll6796096@gmail.com` |
| Copyright | `2026 RYU AI Studio` |

This plan authorizes only the exact Kalories app record and Japan public
release. It does not create TestFlight groups, invite testers, add monetization,
distribute outside Japan, change another Apple app, edit the backend, rotate
credentials, or introduce product features.

Automatic release makes App Review submission the last owner-controlled public
release checkpoint. Uploading does not authorize submission; approval does not
prove storefront propagation or a successful installation.

## File Responsibility Map

### Create

- `docs/release/app-store/ExportOptions.plist`
- `docs/release/app-store-delivery-runbook.md`
- `docs/release/app-store-delivery-evidence.md`

### Modify only if an observed gate requires it

- `ios/project.yml`, `ios/Kalories/Resources/Info.plist`,
  `ios/Kalories.xcodeproj/project.pbxproj`, and
  `docs/release/app-store/ja-JP.json` — build-number change only if App Store
  Connect proves build 1 cannot be used.
- `README.md` — canonical Japan App Store link only after public acceptance.
- focused source/tests only for a reproduced archive, validation, or review
  blocker, through a separate test-first change.

### Must not change

- marketing version `1.0.0`, app behavior, analysis schema, consent, privacy,
  production backend, Apple legal/account data, non-Japan availability, price,
  monetization, Kids status, or automatic release selection.

## Task 1: Freeze the submission-ready baseline

**Files:**
- Read: `docs/release/app-store-foundation-evidence.md`
- Read: `docs/release/app-store-production-evidence.md`
- Read: `docs/release/app-store/ja-JP.json`

- [ ] **Step 1: Verify clean source and completed prior gates**

```bash
git status --short --branch
git log -8 --oneline --decorate
test "$(git status --porcelain)" = ''
git diff --check
test -f docs/release/app-store-foundation-evidence.md
test -f docs/release/app-store-production-evidence.md
! rg -n 'NO-GO|UNVERIFIED|NOT CONFIGURED|NOT DEPLOYED|NOT RUN|BLOCKED|FAIL' \
  docs/release/app-store-foundation-evidence.md \
  docs/release/app-store-production-evidence.md
```

Expected: intended release branch, clean worktree, and all required foundation
and production rows PASS.

- [ ] **Step 2: Verify committed identity and screenshot assets**

```bash
jq -e '
  .apple_app_id == "6799957568"
  and .bundle_id == "com.ryuaistudio.kalories"
  and .version == "1.0.0"
  and .build == "1"
  and .territories == ["JPN"]
  and .price == "FREE"
  and .release_type == "AFTER_APPROVAL"
  and .in_app_purchases == false
  and .subscriptions == false
  and .kids_category == false
  and .contact_email == "zll6796096@gmail.com"
  and .copyright == "2026 RYU AI Studio"
' docs/release/app-store/ja-JP.json >/dev/null

test "$(find docs/release/app-store-assets/ja-JP/6.9-inch \
  -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')" = 5
for screenshot in docs/release/app-store-assets/ja-JP/6.9-inch/*.png; do
  test "$(sips -g pixelWidth "${screenshot}" | awk '/pixelWidth/ {print $2}')" = 1260
  test "$(sips -g pixelHeight "${screenshot}" | awk '/pixelHeight/ {print $2}')" = 2736
  test "$(sips -g hasAlpha "${screenshot}" | awk '/hasAlpha/ {print $2}')" = no
done
```

## Task 2: Audit Apple account and app record without mutation

**Files:**
- Create in Task 3: `docs/release/app-store-delivery-evidence.md`

- [ ] **Step 1: Verify authenticated account readiness**

In the official Apple Developer and App Store Connect interfaces, verify active
membership, sufficient app-management/review permissions, no blocking agreement
or notice for this free app, and the intended team. Do not edit account holder,
legal entity, tax, banking, or agreements; report any blocker exactly.

- [ ] **Step 2: Verify app ID `6799957568`**

Read back name `カロスキャン`, bundle `com.ryuaistudio.kalories`, iOS version
`1.0.0`, and that build `1` has not already been accepted. If build 1 cannot be
used, stop before archiving, record the highest processed build, and amend this
plan with a focused build-number commit; never re-upload the same version/build.

- [ ] **Step 3: Verify private App Review contact**

Confirm a reachable contact name, phone, and `zll6796096@gmail.com` are saved.
Do not commit the name or phone. If blank or stale, stop and request the exact
values. Because the app has no login, keep demo credentials absent.

## Task 3: Create export configuration and delivery ledgers

**Files:**
- Create: `docs/release/app-store/ExportOptions.plist`
- Create: `docs/release/app-store-delivery-runbook.md`
- Create: `docs/release/app-store-delivery-evidence.md`

- [ ] **Step 1: Create `ExportOptions.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key><string>export</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>method</key><string>app-store-connect</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>com.ryuaistudio.kalories</key><string>Kalories App Store</string>
  </dict>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>signingStyle</key><string>manual</string>
  <key>stripSwiftSymbols</key><true/>
  <key>teamID</key><string>YMUG864233</string>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
```

- [ ] **Step 2: Create `app-store-delivery-runbook.md`**

Create:

```markdown
# Japan App Store Delivery Runbook

Date: 2026-08-11
Apple app ID: 6799957568
Bundle/version/build: com.ryuaistudio.kalories / 1.0.0 / 1
Team/profile: YMUG864233 / Kalories App Store
Territory/price: Japan only / Free
Release: Automatically after approval

## Gate order

1. Clean foundation and production evidence
2. Apple account and app-record audit
3. Signed archive inspection
4. Export and Apple validation
5. Upload and processed-build selection
6. Screenshots, metadata, pricing, availability, privacy, age, and review data
7. Fresh owner confirmation immediately before App Review submission
8. Submission and review result
9. Automatic release and Japan storefront propagation
10. Clean App Store install and production App Attest analysis

No earlier PASS promotes a later gate.
```

- [ ] **Step 3: Create `app-store-delivery-evidence.md`**

Create:

```markdown
# Japan App Store Delivery Evidence

Date: 2026-08-11
Apple app ID: 6799957568
Bundle/version/build: com.ryuaistudio.kalories / 1.0.0 / 1

| Gate | State |
| --- | --- |
| Foundation evidence | PASS |
| Production backend evidence | PASS |
| Apple account/app record | NOT RUN |
| Signed archive | NOT RUN |
| Export and Apple validation | NOT RUN |
| Uploaded processed build | NOT RUN |
| Japanese screenshots and metadata | NOT RUN |
| Free price and Japan-only availability | NOT RUN |
| App Privacy and compliance | NOT RUN |
| Fresh pre-submit owner confirmation | NOT RUN |
| App Review submission | NOT RUN |
| App Review approval | NOT RUN |
| Automatic release | NOT RUN |
| Japan storefront visibility | NOT RUN |
| Clean App Store installation | NOT RUN |
| Production App Attest analysis | NOT RUN |

This ledger contains no private review contact data, certificate, provisioning
profile, Apple session, token, device identifier, meal image, or provider body.
```

- [ ] **Step 4: Validate and commit**

```bash
plutil -lint docs/release/app-store/ExportOptions.plist
test "$(plutil -extract teamID raw docs/release/app-store/ExportOptions.plist)" = YMUG864233
test "$(plutil -extract method raw docs/release/app-store/ExportOptions.plist)" = app-store-connect
git add -- \
  docs/release/app-store/ExportOptions.plist \
  docs/release/app-store-delivery-runbook.md \
  docs/release/app-store-delivery-evidence.md
git diff --cached --check
git commit -m "docs(release): add App Store delivery runbook"
```

## Task 4: Build and inspect the signed distribution archive

**Files:**
- Modify: `docs/release/app-store-delivery-evidence.md`
- Read: `ios/project.yml`
- Read: `ios/Kalories/Resources/Info.plist`
- Read: `ios/Kalories/Kalories.entitlements`

- [ ] **Step 1: Re-run the immutable-source gate**

```bash
test "$(git status --porcelain)" = ''
npm test
npm run lint
npm run build
.venv/bin/python -m unittest discover -s tests -p 'test_*.py' -v
.venv/bin/python -m compileall -q api lib tests
.venv/bin/python -c "import api.analyze, lib.nutrition, lib.rate_limit, lib.app_check"
uv pip check --python .venv/bin/python
npm run ios:localizations:check
xcodegen generate --spec ios/project.yml --project ios
test "$(git status --porcelain)" = ''
xcodebuild -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  test
scripts/check-ios-app-check-release.sh --local
```

Expected: all pass. Xcode 26.6 and the iOS 26.5 SDK satisfy Apple's current
Xcode 26/iOS 26 SDK upload minimum.

- [ ] **Step 2: Verify signing inputs without exposing them**

```bash
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
security find-identity -v -p codesigning | rg 'Apple Distribution'
xcodebuild -project ios/Kalories.xcodeproj \
  -scheme Kalories -configuration Release -showBuildSettings | rg \
  'CODE_SIGN_STYLE|DEVELOPMENT_TEAM|PRODUCT_BUNDLE_IDENTIFIER|PROVISIONING_PROFILE_SPECIFIER|MARKETING_VERSION|CURRENT_PROJECT_VERSION'
```

Expected: Xcode 26.6, iOS SDK 26.5, Apple Distribution identity, manual signing,
team `YMUG864233`, profile `Kalories App Store`, bundle, version, and build all
match the fixed table.

- [ ] **Step 3: Archive outside the repository**

```bash
delivery_private_tmp="$(mktemp -d)"
chmod 700 "${delivery_private_tmp}"
archive_path="${delivery_private_tmp}/Kalories.xcarchive"
archive_log="${delivery_private_tmp}/archive.log"
xcodebuild -resolvePackageDependencies \
  -project ios/Kalories.xcodeproj -scheme Kalories
xcodebuild -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "${archive_path}" \
  DEVELOPMENT_TEAM=YMUG864233 \
  CODE_SIGN_STYLE=Manual \
  PROVISIONING_PROFILE_SPECIFIER='Kalories App Store' \
  archive >"${archive_log}" 2>&1
test -d "${archive_path}"
```

If signing fails, inspect the private log only long enough to identify the
certificate/profile issue. Do not revoke or regenerate signing assets without
a separate decision.

- [ ] **Step 4: Prove identity, signing, export, and App Attest**

```bash
archive_app="${archive_path}/Products/Applications/Kalories.app"
archive_info="${archive_app}/Info.plist"
archive_entitlements="${delivery_private_tmp}/archive-entitlements.plist"
archive_profile="${delivery_private_tmp}/embedded-profile.plist"
test -d "${archive_app}"
test "$(plutil -extract CFBundleIdentifier raw "${archive_info}")" = com.ryuaistudio.kalories
test "$(plutil -extract CFBundleShortVersionString raw "${archive_info}")" = 1.0.0
test "$(plutil -extract CFBundleVersion raw "${archive_info}")" = 1
test "$(plutil -extract CFBundleDisplayName raw "${archive_info}")" = カロスキャン
test "$(plutil -extract ITSAppUsesNonExemptEncryption raw "${archive_info}")" = false
codesign --verify --deep --strict --verbose=2 "${archive_app}"
codesign -d --entitlements :- "${archive_app}" \
  >"${archive_entitlements}" 2>/dev/null
test "$(plutil -extract com.apple.developer.devicecheck.appattest-environment raw \
  "${archive_entitlements}")" = production
security cms -D -i "${archive_app}/embedded.mobileprovision" \
  >"${archive_profile}"
test "$(plutil -extract Entitlements.com.apple.application-identifier raw \
  "${archive_profile}")" = YMUG864233.com.ryuaistudio.kalories
```

- [ ] **Step 5: Inspect icons, manifests, SDKs, and release scans**

```bash
test "$(find "${archive_app}" -maxdepth 1 -type f -name 'AppIcon*.png' \
  | wc -l | tr -d ' ')" -ge 1
find "${archive_app}" -name PrivacyInfo.xcprivacy -type f -print \
  >"${delivery_private_tmp}/privacy-manifest-paths.txt"
test -s "${delivery_private_tmp}/privacy-manifest-paths.txt"
KALORIES_EXPECTED_FIREBASE_IOS_APP_ID='1:788259830737:ios:a4459f14b5e8046297bef0' \
  scripts/check-ios-app-check-release.sh --app "${archive_app}"
```

Inspect every packaged manifest with `plutil -p`. Expected baseline: app-owned
Photos/Videos for App Functionality; Firebase Installations Other Diagnostic
Data for Analytics; neither linked nor used for tracking; no tracking domain,
advertising SDK, credential, API key, DEBUG provider, or fixture mode. If the
archive differs, reconcile binary, public policy, metadata JSON, and App Privacy
before upload.

- [ ] **Step 6: Record and commit sanitized archive evidence**

Record source commit, Xcode/SDK, bundle/version/build, signing PASS, App Attest
production, privacy categories, icon PASS, and release scan PASS. Do not commit
the archive, profile, entitlements dump, certificate identity, UUID, or log.

```bash
git add -- docs/release/app-store-delivery-evidence.md
git diff --cached --check
git commit -m "docs(release): record signed App Store archive"
```

## Task 5: Export, validate, upload, and select the processed build

**Files:**
- Modify: `docs/release/app-store-delivery-evidence.md`
- Read: `docs/release/app-store/ExportOptions.plist`

- [ ] **Step 1: Export the inspected archive**

```bash
export_path="${delivery_private_tmp}/export"
export_log="${delivery_private_tmp}/export.log"
xcodebuild -exportArchive \
  -archivePath "${archive_path}" \
  -exportPath "${export_path}" \
  -exportOptionsPlist docs/release/app-store/ExportOptions.plist \
  >"${export_log}" 2>&1
ipa_path="${export_path}/Kalories.ipa"
test -f "${ipa_path}"
```

- [ ] **Step 2: Validate and upload through Xcode Organizer**

Open this archive in Organizer. Choose Distribute App → App Store Connect →
Upload, keep automatic signing management disabled, and run Apple validation.
Proceed exactly once only when validation passes for app ID `6799957568`, bundle
`com.ryuaistudio.kalories`, version `1.0.0`, build `1`. Do not ignore privacy,
icon, signing, entitlement, SDK, or export warnings; do not create an API key,
app-specific password, TestFlight group, or invitation.

- [ ] **Step 3: Wait for the processed build**

Wait until build `1` is processed, has no invalid-binary status, and is
selectable for version `1.0.0`. Select it and answer export compliance from the
archive: no non-exempt encryption. A processing failure is not App Review
rejection; record the exact issue and never upload another build 1 binary.

- [ ] **Step 4: Record and commit Apple processing evidence**

Record Organizer validation/upload timestamps, processed build, and source
commit. Do not store Apple session or account data.

```bash
git add -- docs/release/app-store-delivery-evidence.md
git diff --cached --check
git commit -m "docs(release): record processed App Store build"
```

## Task 6: Enter Japanese metadata and screenshots

**Files:**
- Read: `docs/release/app-store/ja-JP.json`
- Read: `docs/release/app-store-assets/ja-JP/6.9-inch/*.png`
- Modify: `docs/release/app-store-delivery-evidence.md`

- [ ] **Step 1: Set exact localization and category**

Use Japanese (`ja-JP`) only. Set primary category Food & Drink and leave the
secondary category empty.

- [ ] **Step 2: Copy committed product-page values**

Copy name, subtitle, promotional text, description, keywords, support URL,
privacy URL, review notes, and copyright verbatim from
`docs/release/app-store/ja-JP.json`. Leave marketing URL empty because its value
is `null`. Confirm the promotional text and description start with the one-time
local confirmation: users must select `18歳以上です`; only that Boolean fact is
stored in the app's on-device preferences, with no birth date, name, or identity
document. Confirm the result is not attached to analysis requests or sent by
Kalories to its backend, Google, or Firebase. State separately that device or
system backup and restore are controlled by Apple and device settings and may
therefore involve Apple processing. Confirm the review notes start with the
same boundary and make confirmation Step 1 of the reviewer flow. Re-read
saved fields after App Store Connect normalization. Any new
medical, measurement-accuracy, weight-loss, or guaranteed-outcome claim is
NO-GO.

- [ ] **Step 3: Upload the five A-order screenshots**

Upload only these 6.9-inch files, in order:

1. `app-store-01-capture.png`
2. `app-store-02-summary.png`
3. `app-store-03-nutrition.png`
4. `app-store-04-consent.png`
5. `app-store-05-uncertainty.png`

Inspect the saved product page at full size for Japanese text, order, crop,
legibility, consent, uncertainty, non-medical wording, and absence of fixture
controls or private data. Do not add mockups, frames, AI retouching, personal
photos, or screenshots from another build.

- [ ] **Step 4: Record and commit the product-page gate**

```bash
git add -- docs/release/app-store-delivery-evidence.md
git diff --cached --check
git commit -m "docs(release): record Japanese product page"
```

## Task 7: Configure price, availability, and release behavior

**Files:**
- Modify: `docs/release/app-store-delivery-evidence.md`

- [ ] **Step 1: Set public Japan-only distribution**

Select public App Store distribution. Select Japan as the only available
territory and remove every other territory. Do not enable pre-order, unlisted
or private distribution, alternative marketplaces, Mac availability, or Apple
Vision Pro availability.

- [ ] **Step 2: Set Free and prove monetization is empty**

Set the base price to Free with no future price change. Verify In-App Purchases
and Subscriptions contain no product, offer, or submitted item.

- [ ] **Step 3: Select automatic release**

For version `1.0.0`, select “Automatically release this version” after App
Review approval. Do not select manual, scheduled, or phased release.

- [ ] **Step 4: Read back and record exact values**

Expected: public distribution, Japan only, Free, no IAP/subscriptions,
automatic release, and version/build `1.0.0 (1)`. Mark pricing/availability
PASS, but automatic release stays NOT RUN until an approved version actually
transitions to distribution.

```bash
git add -- docs/release/app-store-delivery-evidence.md
git diff --cached --check
git commit -m "docs(release): record Japan release configuration"
```

## Task 8: Complete privacy, age, and compliance answers

**Files:**
- Read: `docs/release/app-store/ja-JP.json`
- Read: signed archive privacy manifests from Task 4
- Modify: `docs/release/app-store-delivery-evidence.md`

- [ ] **Step 1: Enter App Privacy from the signed archive**

Set Tracking to No and declare:

| Data type | Purpose | Linked | Tracking |
| --- | --- | --- | --- |
| Photos or Videos | App Functionality | No | No |
| Other Diagnostic Data | Analytics | No | No |

Use `https://kalories-sxielk4wua-an.a.run.app/privacy/`. Verify the page returns
HTTP 200 and discloses explicit Gemini transfer, provider retention, App Check,
no account, no ads, no tracking, and deletion/withdrawal boundaries. Verify
developer logging is described only for the Kalories-used GenerateContent API
path, with Interactions API explicitly outside that statement and unused by the
app. Verify the local confirmation is excluded from analysis requests and from
Kalories backend/Google/Firebase sends, while Apple/device-controlled backup and
restore remain disclosed. If the final archive or Apple's definitions imply a
different answer, stop and reconcile binary, policy, JSON, and questionnaire.

- [ ] **Step 2: Answer the current age questionnaire truthfully**

Set parental controls absent. Treat the Age Assurance field as present/used
because the shipped mandatory `I am 18 or older` self-attestation is a mechanism
used to confirm the age requirement. In the current App Store Connect
questionnaire, select the option that truthfully reports that mechanism, then
read back and record the exact saved field label and value. If the available
options do not permit that truthful answer, stop before saving and record the
interface as a blocker. Set unrestricted web access, UGC distribution, social
media, messaging/chat, and advertising absent. Mark Health or Wellness Topics
present because the app estimates calories and nutrition. Set Medical or
Treatment Information to None because the app does not diagnose or guide
treatment. Set every profanity, horror, alcohol/drug, mature, sexual, violence,
contest, gambling, simulated-gambling, and loot-box descriptor to None/not
present.

Do not select Made for Kids. Under Age Categories and Override choose
**Override to Higher Age Rating**, select `18+`, and leave the Age Suitability
URL empty unless App Store Connect makes it mandatory. Read back the Japan
rating as `18+` for iOS 26 or later; any different value is a NO-GO. In a
separate evidence field, copy the exact legacy age-rating mapping that App Store
Connect displays for earlier OS versions. Do not infer that legacy value, and
do not use it to weaken the in-app 18+ restriction. Do not leave the override
unset or accept a questionnaire-only lower rating as the release target.

- [ ] **Step 3: Complete rights, medical, and export declarations**

Declare no publisher-supplied third-party media catalog requiring distribution
rights; user-selected meal photos are processed for that user and not publicly
redistributed. Declare no regulated medical device, no HealthKit, and no
diagnosis/treatment. Read back `ITSAppUsesNonExemptEncryption=false` and answer
that the app uses no non-exempt encryption; standard Apple HTTPS/TLS does not
require custom encryption documents unless Apple specifically asks.

- [ ] **Step 4: Complete App Review information**

Use the private contact verified in Task 2 and email
`zll6796096@gmail.com`. Keep sign-in information disabled. Copy review notes
from the JSON. They must start with the one-time `18歳以上です` confirmation,
state that only the confirmation Boolean is stored locally and that no birth
date, name, or identity document is collected. They must say the result is not
attached to analysis requests or sent by Kalories to its backend, Google, or
Firebase, while device/system backup and restore follow Apple and device
settings. Make that confirmation Step 1 before explaining capture/select,
explicit Gemini transfer, analysis result, uncertainty, no login, no payment,
and no tracking.

- [ ] **Step 5: Read back and commit boolean evidence**

Compare App Privacy with JSON and archive, and age answers with the product.
Record the higher-age override selection, Japan `18+` readback for iOS 26 or
later, App Store Connect's exact displayed legacy mapping for earlier OS
versions, the exact saved Age Assurance field label/value, and the
questionnaire's other answers; do not commit private contact fields.

```bash
git add -- docs/release/app-store-delivery-evidence.md
git diff --cached --check
git commit -m "docs(release): record App Store compliance"
```

## Task 9: Run the final pre-submission checkpoint

**Files:**
- Modify: `docs/release/app-store-delivery-evidence.md`

- [ ] **Step 1: Reprove production immediately before submission**

```bash
curl --fail --silent --show-error \
  'https://kalories-sxielk4wua-an.a.run.app/health'
curl --fail --silent --show-error \
  'https://kalories-sxielk4wua-an.a.run.app/privacy/' >/dev/null
curl --fail --silent --show-error \
  'https://kalories-sxielk4wua-an.a.run.app/support/' >/dev/null
KALORIES_EXPECTED_FIREBASE_IOS_APP_ID='1:788259830737:ios:a4459f14b5e8046297bef0' \
  scripts/check-testflight-backend.sh
```

- [ ] **Step 2: Review one complete submission snapshot**

Verify together: identity/build, Japanese metadata, five screenshots,
support/privacy/contact, category, Free, Japan only, no monetization, privacy,
the one-time local adult confirmation in metadata and review flow, the
higher-age override with Japan `18+` for iOS 26 or later plus the separately
recorded legacy mapping, the exact Age Assurance self-attestation answer,
rights, medical/export answers, automatic release, review contact/notes, and
absence of warning, missing field, agreement block, or message.

- [ ] **Step 3: Reject unresolved pre-submit rows**

Only Fresh confirmation, App Review submission/approval, Automatic release,
Japan storefront, clean installation, and production App Attest analysis may
remain NOT RUN. Any other unresolved row stops submission.

- [ ] **Step 4: Request fresh automatic-release confirmation**

Present exactly:

```text
カロスキャン 1.0.0 (1) 已完成提交前检查。现在提交 App Review 后，Apple 一旦批准会自动在日本 App Store 公开，不再有手动发布确认。确认现在提交吗？
```

Do not click Add for Review or Submit for Review until the user confirms this
specific consequence in the active execution turn.

- [ ] **Step 5: Record the fresh confirmation**

```bash
git add -- docs/release/app-store-delivery-evidence.md
git diff --cached --check
git commit -m "docs(release): record App Review authorization"
```

## Task 10: Submit App Review and monitor review

**Files:**
- Modify: `docs/release/app-store-delivery-evidence.md`

- [ ] **Step 1: Submit only version 1.0.0 build 1**

Add the prepared version/build to the review submission, inspect the summary,
and submit. Do not include TestFlight, IAP, subscriptions, events, custom
product pages, or another platform. Expected: a real status such as Waiting for
Review; a saved version page is not submission evidence.

- [ ] **Step 2: Record submission without promoting later gates**

Record timestamp and visible status. Mark submission PASS only; leave approval,
release, storefront, installation, and analysis NOT RUN.

```bash
git add -- docs/release/app-store-delivery-evidence.md
git diff --cached --check
git commit -m "docs(release): record App Review submission"
```

- [ ] **Step 3: Monitor and handle messages narrowly**

Answer Apple only from the shipped binary, policy, production evidence, and
review notes. On rejection, record the exact guideline/message, separate
metadata, privacy, functionality, and policy causes, and write a focused fix
plan. Never remove consent, uncertainty, App Check, privacy, or cost controls
or the 18+ access boundary to obtain approval.

- [ ] **Step 4: Record actual approval**

Mark approval PASS only when App Store Connect shows approval for `1.0.0 (1)`.
Record timestamp; automatic release remains separate.

## Task 11: Prove automatic release and Japan availability

**Files:**
- Modify: `docs/release/app-store-delivery-evidence.md`
- Modify after acceptance: `README.md`

- [ ] **Step 1: Wait for automatic distribution**

Do not click a manual release control. Wait for the approved version to
transition automatically to distribution, then wait for Japan propagation.

- [ ] **Step 2: Verify Apple's public Japan records**

```bash
storefront_tmp="$(mktemp -d)"
curl --fail --silent --show-error \
  'https://itunes.apple.com/lookup?id=6799957568&country=jp' \
  >"${storefront_tmp}/lookup-jp.json"
jq -e '
  .resultCount == 1
  and .results[0].trackId == 6799957568
  and .results[0].bundleId == "com.ryuaistudio.kalories"
  and .results[0].trackName == "カロスキャン"
  and .results[0].version == "1.0.0"
  and (.results[0].price | tonumber) == 0
' "${storefront_tmp}/lookup-jp.json" >/dev/null
curl --fail --silent --show-error \
  'https://apps.apple.com/jp/app/id6799957568' \
  >"${storefront_tmp}/product-page.html"
test -s "${storefront_tmp}/product-page.html"
```

- [ ] **Step 3: Inspect the rendered Japan product page**

Open `https://apps.apple.com/jp/app/id6799957568` in a browser. Verify rendered
name, version, free price, Japanese description, five screenshots, the expected
18+ age presentation for iOS 26 or later, privacy link, and support link.
Compare any earlier-OS legacy presentation with the exact mapping recorded from
App Store Connect. Follow both links and confirm HTTP 200 and approved content.
HTTP/lookup success alone is not visual acceptance.

- [ ] **Step 4: Prove non-Japan exclusion**

Reopen Pricing and Availability and verify Japan is the only selected
territory; this saved record is authoritative. Spot-check the United States
lookup without treating CDN/cache behavior as stronger than App Store Connect:

```bash
curl --silent --show-error \
  'https://itunes.apple.com/lookup?id=6799957568&country=us' \
  >"${storefront_tmp}/lookup-us.json"
```

- [ ] **Step 5: Install on a clean physical iPhone**

With a Japan App Store account, download from the canonical page and launch.
Prove this is the App Store build, not development or TestFlight. Verify
the one-time `18歳以上です` gate appears before capture on a clean install,
then verify Japanese capture UI, permissions, privacy/support links, and consent
preview.

- [ ] **Step 6: Prove production App Attest and one safe analysis**

Use a non-personal synthetic meal image, accept the Gemini transfer, and
complete one analysis. Expected: production App Attest-backed App Check,
schema-coherent UI, uncertainty/non-medical wording, safe targeted logs, and
request/cost within quota and budget controls. Simulator, DEBUG token, local
build, or TestFlight does not satisfy this gate.

- [ ] **Step 7: Remove private temporary evidence**

```bash
find "${storefront_tmp}" -type f -delete
rmdir "${storefront_tmp}"
find "${delivery_private_tmp}" -type f -delete
find "${delivery_private_tmp}" -depth -type d -empty -delete
```

## Task 12: Close evidence, README, and Git state

**Files:**
- Modify: `docs/release/app-store-delivery-evidence.md`
- Modify: `README.md`

- [ ] **Step 1: Record terminal gates independently**

Record approval timestamp, automatic transition, Japan lookup/rendered page,
iOS 26-or-later 18+ presentation and earlier-OS legacy mapping, Japan-only
availability, clean-install adult gate, and production App Attest/UI/log/cost
PASS separately. Never collapse these into one release PASS.

- [ ] **Step 2: Add the canonical public link**

Only after Task 11 passes, add to README's release/status area:

```markdown
- Japan App Store: https://apps.apple.com/jp/app/id6799957568
```

- [ ] **Step 3: Review and commit final evidence**

```bash
git diff --check
git status --short --branch
git diff --stat
git diff
git add -- README.md docs/release/app-store-delivery-evidence.md
git diff --cached --check
git commit -m "docs(release): record Japan App Store launch"
git status --short --branch
```

Expected: clean worktree and every delivery row PASS.

- [ ] **Step 4: Report remaining operational risks**

State that the app is Japan-only; the JPY 3,000 budget is an alert rather than
a hard cap; the Gemini daily quota is 200 and may reject excess traffic; and
provider terms, review policy, signing assets, and agreements can change. Any
future source/privacy change needs a new build and truthful metadata update.

## Official Apple References

- App Review Guidelines:
  <https://developer.apple.com/app-store/review/guidelines/>
- Screenshot specifications:
  <https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/>
- App Privacy:
  <https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/>
- Age rating setup:
  <https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating>
- Age rating definitions:
  <https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions>
- Release option:
  <https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option/>
- Build upload:
  <https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/>
- Current SDK upload requirement:
  <https://developer.apple.com/news/upcoming-requirements/?id=02032026a>
