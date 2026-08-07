# カロスキャン TestFlight Delivery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Produce a signed App Store Connect archive for カロスキャン, verify it on a physical iPhone, upload build 1, and stop only after App Store Connect processing is Complete and the build is available to an internal TestFlight group.

**Architecture:** Treat Apple identity, device, archive, export, upload, processing, and tester availability as separate evidence gates. Use automatic Apple signing for team YMUG864233, a committed export configuration, deterministic archive inspection, and sanitized release evidence; never submit App Store Review in this plan.

**Tech Stack:** Xcode 26.6, iOS 26.5 SDK, xcodebuild, codesign, security, altool or Xcode Organizer, App Store Connect, TestFlight

---

## Prerequisites and boundary

This is plan 3 of 3. Start only after plans 1 and 2 are complete with clean
Git state. This plan may register the bundle ID, create the App Store Connect
record, upload the build, and add an internal tester. It must not submit App
Store Review, create an external testing review, release publicly, or change
storefront availability.

Any missing account role, current agreement, bundle-ID ownership, device,
provider visibility, distribution profile, or App Store Connect name is NO-GO.
Do not label a skipped manual check PASS.

### Task 1: Add deterministic export and archive inspection

**Files:**
- Modify: ios/project.yml
- Create: ios/ExportOptions.plist
- Create: scripts/check-ios-archive.sh
- Create: docs/release/testflight-checklist.md
- Modify: ios/KaloriesTests/AppIdentityTests.swift

- [ ] **Step 1: Write failing export-compliance identity test**

Assert the generated Info.plist has:

- bundle identifier com.ryuaistudio.kalories;
- display name カロスキャン;
- version 1.0.0;
- build 1;
- ITSAppUsesNonExemptEncryption false;
- iPhone device family only;
- portrait orientation only.

Run AppIdentityTests and verify the encryption assertion fails before the
project setting exists.

- [ ] **Step 2: Add export-compliance metadata**

Add this property under the app target's Info.plist properties:

~~~yaml
ITSAppUsesNonExemptEncryption: false
~~~

Regenerate ios/Kalories.xcodeproj and pass AppIdentityTests.

- [ ] **Step 3: Create ios/ExportOptions.plist**

~~~xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>YMUG864233</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>stripSwiftSymbols</key><true/>
  <key>uploadSymbols</key><true/>
</dict></plist>
~~~

Validate with plutil.

- [ ] **Step 4: Create scripts/check-ios-archive.sh**

The script accepts exactly one .xcarchive path, resolves Products/Applications/
Kalories.app, and exits nonzero unless all are true:

- application exists;
- CFBundleIdentifier, CFBundleDisplayName, CFBundleShortVersionString, and
  CFBundleVersion match approved values;
- UIDeviceFamily is only 1;
- ITSAppUsesNonExemptEncryption is false;
- embedded.mobileprovision exists and decodes;
- codesign authority contains Apple Distribution;
- application-identifier ends with com.ryuaistudio.kalories;
- PrivacyInfo.xcprivacy exists in the app root;
- AppIcon resource exists;
- no .env, private key, GEMINI_API_KEY string, AuthKey file, or source map is
  present.

It prints values but never provisioning UUIDs, account identifiers, or
certificate bodies.

- [ ] **Step 5: Create the checklist**

Pre-fill fixed metadata:

- name: カロスキャン
- subtitle: 写真でカロリー・食事分析
- primary language: Japanese
- bundle ID: com.ryuaistudio.kalories
- SKU: KALORIES-IOS-2026
- version/build: 1.0.0 (1)
- category: Food & Drink
- privacy URL: https://kalories-sxielk4wua-an.a.run.app/privacy/
- support URL: https://kalories-sxielk4wua-an.a.run.app/support/
- distribution: internal TestFlight only

Include checkbox fields for dynamic Apple and device evidence rather than
claiming them in advance.

- [ ] **Step 6: Test and commit**

~~~bash
plutil -lint ios/ExportOptions.plist
bash -n scripts/check-ios-archive.sh
xcodegen generate --spec ios/project.yml --project ios
xcodebuild -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:KaloriesTests/AppIdentityTests \
  test
git diff --check
git add ios/project.yml ios/Kalories.xcodeproj ios/Kalories/Resources/Info.plist ios/KaloriesTests/AppIdentityTests.swift ios/ExportOptions.plist scripts/check-ios-archive.sh docs/release/testflight-checklist.md
git commit -m "chore(ios): add TestFlight archive gate"
~~~

Expected: tests pass and commit contains no binary/archive.

### Task 2: Verify Apple identity and reserve the app record

**Files:**
- External: Apple Developer and App Store Connect
- Evidence update: docs/release/testflight-checklist.md

This is an external write. Reconfirm the exact name and bundle ID immediately
before creating records. If either already exists under the same team, reuse it
after verifying ownership; do not create a duplicate.

- [ ] **Step 1: Verify local identities without exposing certificates**

~~~bash
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
security find-identity -v -p codesigning
~~~

Expected: Xcode 26.6, iOS SDK 26.5, valid Apple Development and Apple
Distribution identities for team YMUG864233.

- [ ] **Step 2: Verify App Store Connect account gates**

Using App Store Connect and Apple Developer:

- current agreements accepted;
- account role can create apps and upload builds;
- team is YMUG864233;
- no unresolved provider selection;
- no duplicate com.ryuaistudio.kalories identifier;
- name カロスキャン is available.

Do not proceed on an ambiguous team or taken name. Return to the user for a new
approved identity rather than silently altering it.

- [ ] **Step 3: Register or verify the explicit Bundle ID**

Create or verify com.ryuaistudio.kalories as an explicit App ID. Enable no
capabilities beyond those used by the binary. Camera and PhotosPicker require
privacy strings, not entitlements.

- [ ] **Step 4: Create the App Store Connect app record**

Enter the fixed checklist metadata. Choose full user access only if it matches
the user's account policy. Do not create an App Store version submission.

- [ ] **Step 5: Record sanitized evidence**

Record accepted name, bundle ID, team ID, SKU, role result, agreements status,
and timestamps. Do not record Apple Account password, session cookies, API
private key, personal phone number, or billing data.

No Git commit is needed if only unchecked checklist fields remain; commit only
truthful evidence updates.

### Task 3: Run the full local gate and physical-device verification

**Files:**
- Evidence update: docs/release/testflight-checklist.md

- [ ] **Step 1: Run all automated gates**

~~~bash
npm test
npm run lint
npm run build
npm run ios:localizations:check
.venv/bin/python -m unittest discover -s tests -p 'test_*.py' -v
.venv/bin/python -m compileall -q api lib tests
.venv/bin/python -c "import api.analyze, lib.nutrition, lib.rate_limit"
uv pip check --python .venv/bin/python
xcodebuild -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  test
scripts/check-testflight-backend.sh
git diff --check
git status --short --branch
~~~

Expected: every check passes, backend gate PASS, worktree clean. Any failure
blocks archive.

- [ ] **Step 2: Resolve a connected physical iPhone**

~~~bash
xcrun devicectl list devices
~~~

Select only a connected available iPhone owned or authorized by the user.
Record its marketing model and iOS version, not UDID or serial number. If no
device is available, mark device testing SKIPPED and stop; do not archive/upload.

- [ ] **Step 3: Install a Release configuration on the device**

Use Xcode with automatic signing and the verified team, or xcodebuild with the
resolved destination ID kept out of documentation. Confirm the build installed
from the current commit.

- [ ] **Step 4: Execute the physical-device matrix**

Test:

1. first-launch camera explanation;
2. camera allow, capture, preview, explicit analyze;
3. camera deny and Open Settings recovery;
4. system photo selection without broad photo-library permission;
5. Japanese fallback, then Chinese and English switching;
6. real non-personal meal success through the hardened backend;
7. no-food result;
8. airplane-mode network error;
9. timeout/rate-limit wording through a controlled non-production stub, not by
   attacking production;
10. retry reuses only the in-memory image;
11. retake clears the prior image/result;
12. VoiceOver reading order and Dynamic Type at an accessibility size;
13. privacy and support links open successfully;
14. portrait-only behavior;
15. app relaunch contains no meal history.

Record PASS/FAIL per row. Delete the test photo/result from the app flow after
testing. Do not attach the photo to the repository.

- [ ] **Step 5: Commit sanitized device evidence**

~~~bash
git add docs/release/testflight-checklist.md
git commit -m "docs: record iPhone TestFlight checks"
~~~

Expected: no device identifier or personal image in diff.

### Task 4: Archive, inspect, and export the IPA

**Files:**
- Generated/ignored: build/Kalories.xcarchive
- Generated/ignored: build/export/Kalories.ipa
- Evidence update: docs/release/testflight-checklist.md

- [ ] **Step 1: Confirm clean source and unique build number**

~~~bash
git status --short --branch
xcodebuild -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -configuration Release \
  -showBuildSettings | rg 'MARKETING_VERSION|CURRENT_PROJECT_VERSION'
~~~

Expected: clean; build 1 has never been uploaded. If build 1 exists in App
Store Connect, increment CURRENT_PROJECT_VERSION and generated Info.plist in a
focused commit, then rerun all identity tests.

- [ ] **Step 2: Create the signed archive**

~~~bash
xcodebuild -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/Kalories.xcarchive \
  -allowProvisioningUpdates \
  archive
~~~

Expected: ARCHIVE SUCCEEDED. Generic unsigned or simulator build is not a
substitute.

- [ ] **Step 3: Inspect the archive**

~~~bash
scripts/check-ios-archive.sh build/Kalories.xcarchive
~~~

Expected: every archive invariant PASS. Any warning about signing, privacy
manifest, icon, architecture, or bundle identity blocks export.

- [ ] **Step 4: Export App Store Connect IPA**

~~~bash
xcodebuild -exportArchive \
  -archivePath build/Kalories.xcarchive \
  -exportOptionsPlist ios/ExportOptions.plist \
  -exportPath build/export \
  -allowProvisioningUpdates
~~~

Expected: EXPORT SUCCEEDED and one IPA.

- [ ] **Step 5: Inspect the exported IPA without broad deletion**

~~~bash
KALORIES_IPA_PATH="$(find build/export -maxdepth 1 -name '*.ipa' -print -quit)"
test -n "$KALORIES_IPA_PATH"
KALORIES_IPA_AUDIT_DIR="$(mktemp -d)"
unzip -q "$KALORIES_IPA_PATH" -d "$KALORIES_IPA_AUDIT_DIR"
plutil -p "$KALORIES_IPA_AUDIT_DIR/Payload/Kalories.app/Info.plist"
codesign --verify --deep --strict --verbose=2 "$KALORIES_IPA_AUDIT_DIR/Payload/Kalories.app"
find "$KALORIES_IPA_AUDIT_DIR/Payload/Kalories.app" -name 'PrivacyInfo.xcprivacy' -print
rm -rf "$KALORIES_IPA_AUDIT_DIR"
unset KALORIES_IPA_AUDIT_DIR
~~~

Before rm -rf, verify the variable begins with the system temporary directory
and contains Payload/Kalories.app. Expected: codesign valid, one privacy
manifest, exact identity. Keep the IPA ignored; never commit it.

- [ ] **Step 6: Record archive/export evidence**

Record archive commit, version/build, Xcode/SDK, signing team, archive/IPA SHA-256,
archive checker result, and export log path. Do not record provisioning profile
contents.

Commit sanitized evidence.

### Task 5: Prepare TestFlight metadata and privacy answers

**Files:**
- Create: docs/release/testflight-metadata-ja.md
- Evidence update: docs/release/testflight-checklist.md
- External: App Store Connect app record

- [ ] **Step 1: Create exact Japanese beta metadata**

Use:

~~~text
ベータ版の説明:
カロスキャンは、食事の写真からカロリーと栄養バランスを推定するアプリです。推定値、信頼度、単一の食事に対する参考スコアと改善案を表示します。医療診断や正確な栄養測定を行うものではありません。

テストしてほしい内容:
カメラまたは写真選択、分析結果、推定精度の表示、日本語・中国語・英語の切り替え、通信エラー時の再試行をご確認ください。個人情報が写った写真は使用しないでください。

ログイン:
不要

サポートURL:
https://kalories-sxielk4wua-an.a.run.app/support/

プライバシーポリシーURL:
https://kalories-sxielk4wua-an.a.run.app/privacy/
~~~

The user supplies the TestFlight feedback email interactively. Validate its
deliverability and App Store Connect acceptance; do not commit a personal email
unless the user explicitly approves publication.

- [ ] **Step 2: Set export compliance**

Because the binary uses only exempt standard HTTPS encryption and
ITSAppUsesNonExemptEncryption is false, answer the upload export-compliance
question consistently. If archive inspection finds any added non-exempt crypto,
stop and reassess.

- [ ] **Step 3: Set privacy answers from verified provider evidence**

If plan 2 proves photos are discarded after servicing the real-time request by
both Kalories and the paid provider, select Data Not Collected under Apple's
definition and keep the in-app privacy page accurate.

If either party retains readable photos/results longer than the request,
declare Photos or Videos for App Functionality, not linked to identity, not
tracking, and update PrivacyInfo.xcprivacy and the privacy page before upload.
Do not choose the more favorable branch without provider evidence.

- [ ] **Step 4: Complete current age-rating questions**

Answer based on the shipped binary: no unrestricted web access, gambling,
violence, sexual content, drugs, user-generated social content, or medical
treatment. Nutrition estimates are non-medical. Save the calculated rating and
timestamp; do not guess an age number before App Store Connect calculates it.

- [ ] **Step 5: Commit sanitized metadata**

~~~bash
git add docs/release/testflight-metadata-ja.md docs/release/testflight-checklist.md
git commit -m "docs: prepare Japanese TestFlight metadata"
~~~

### Task 6: Validate, upload once, and wait for processing

**Files:**
- External: App Store Connect/TestFlight
- Evidence update: docs/release/testflight-checklist.md

Uploading is an external irreversible version event. Reconfirm version 1.0.0
build 1, bundle ID, app record, and internal-only target immediately before the
upload command.

- [ ] **Step 1: Validate with App Store Connect credentials**

Preferred non-interactive path uses an App Store Connect API key already
authorized for this app. The private key stays in the standard private key
directory and out of shell output. Set only key ID and issuer ID as task-specific
environment variables.

~~~bash
test -n "$KALORIES_ASC_KEY_ID"
test -n "$KALORIES_ASC_ISSUER_ID"
xcrun altool --validate-app \
  -f "$KALORIES_IPA_PATH" \
  -t ios \
  --apiKey "$KALORIES_ASC_KEY_ID" \
  --apiIssuer "$KALORIES_ASC_ISSUER_ID" \
  --output-format json
~~~

Expected: validation success. If API credentials are unavailable, use Xcode
Organizer Validate App while signed into the verified team. Record that the UI
path was used; never pretend CLI validation occurred.

- [ ] **Step 2: Upload exactly once**

CLI path:

~~~bash
xcrun altool --upload-app \
  -f "$KALORIES_IPA_PATH" \
  -t ios \
  --apiKey "$KALORIES_ASC_KEY_ID" \
  --apiIssuer "$KALORIES_ASC_ISSUER_ID" \
  --output-format json
~~~

Alternative: Xcode Organizer Distribute App -> App Store Connect -> Upload with
the same archive. Do not run both after one succeeds.

Expected: delivery accepted with a request/delivery identifier. This is not yet
processing Complete.

- [ ] **Step 3: Wait for App Store Connect processing**

Monitor Build Uploads. Terminal accepted states:

- Complete with no blocking issue: proceed;
- Failed: record exact errors, fix code/metadata, increment build if Apple
  consumed it, then rerun all gates;
- Processing longer than 24 hours: contact Apple as documented;
- warning badge: inspect every warning before tester availability.

Do not upload another build merely because processing is not immediate.

- [ ] **Step 4: Make the processed build available to internal testers**

In TestFlight, select build 1, complete required compliance fields, add it only
to the intended internal group, and verify one authorized internal tester can
see it. Do not create an external group or submit Beta App Review.

- [ ] **Step 5: Verify the installed TestFlight build**

On the physical iPhone, install from TestFlight and re-run the critical path:
launch, camera/selection, explicit consent, one synthetic/non-personal meal
analysis, result, retry, links, and no persisted history. Confirm it is the
TestFlight-signed build 1, not the Xcode-installed build.

### Task 7: Close out with sanitized evidence

**Files:**
- Modify: docs/release/testflight-checklist.md
- Optional create: docs/release/testflight-build-1-evidence.md

- [ ] **Step 1: Record separate gate outcomes**

Record:

- local tests;
- backend gate;
- physical-device test;
- archive;
- export;
- validation;
- upload acceptance;
- processing Complete;
- internal group availability;
- TestFlight installation;
- App Store Review: NOT SUBMITTED;
- public release: NOT STARTED.

Any unrun item is SKIPPED with reason.

- [ ] **Step 2: Review repository and artifacts**

~~~bash
git diff --check
git status --short --branch
git log --oneline --decorate -15
find build -maxdepth 3 -type f -print | sed -n '1,120p'
git check-ignore -v build/Kalories.xcarchive build/export/Kalories.ipa
~~~

Expected: release artifacts are ignored, no credential or personal photo is
tracked, source worktree contains only intended evidence changes.

- [ ] **Step 3: Commit final evidence**

~~~bash
git add docs/release/testflight-checklist.md docs/release/testflight-build-1-evidence.md
git commit -m "docs: record TestFlight build 1"
git status --short --branch
~~~

If the optional evidence file was not created, omit it from git add. Expected:
clean worktree.

- [ ] **Step 4: Preserve source remotely only with explicit branch confirmation**

Push the implementation branch after the user confirms the target remote and
branch. Do not force-push and do not silently merge to main. TestFlight success
does not authorize App Store Review.

## Plan 3 completion gate

Complete only after build 1 is processed as Complete, appears in the intended
internal TestFlight group, and installs/runs from TestFlight on the verified
physical iPhone. Upload acceptance alone is partial. Public App Store readiness
remains NO-GO until App Attest or externally backed abuse protection, App Store
metadata/screenshots, App Review, approval, and release are separately handled.
