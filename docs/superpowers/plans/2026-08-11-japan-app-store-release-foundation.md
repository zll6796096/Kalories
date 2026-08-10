# Japan App Store Release Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a tested local release foundation for the Japan-only free public App Store release: public legal/support pages, structured Japanese metadata, deterministic real-UI screenshots, and a clean local quality gate.

**Architecture:** Keep the Release product unchanged unless a verified blocker appears. Public legal copy remains static HTML served by the existing FastAPI/Vite image, App Store metadata becomes a committed JSON source of truth with tests, and screenshot states stay DEBUG-only behind exact launch arguments so no fixture code or provider call enters the distributed flow.

**Tech Stack:** Python 3.12 `unittest`, static HTML, JSON, Swift 6, SwiftUI, XCUITest, `xcresulttool`, `sips`, Xcode 26.6, iOS 26.5 simulator.

---

## Dependency and Scope

Required design:

- `docs/superpowers/specs/2026-08-10-japan-app-store-public-release-design.md`

This plan produces local code, documentation, and screenshot evidence only. It
does not deploy Cloud Run, change traffic, upload a build, edit App Store
Connect, submit App Review, or trigger public release.

Execution order:

1. Complete this plan.
2. Complete `2026-08-11-japan-production-backend-release.md`.
3. Complete `2026-08-11-japan-app-store-delivery.md`.

## File Responsibility Map

### Modify

- `tests/test_public_pages.py` — enforce public legal/support content and the
  exact approved contact.
- `public/privacy/index.html` — public privacy disclosure for `カロスキャン`.
- `public/support/index.html` — public support instructions and private contact.
- `ios/Kalories/App/UITestFixtures.swift` — DEBUG-only deterministic capture,
  preview, and result launch states.
- `ios/Kalories/Features/Capture/CaptureView.swift` — hide the fixture-only
  control from screenshot states.
- `ios/Kalories/Resources/Info.plist` — declare that the app does not use
  non-exempt encryption.
- `ios/KaloriesTests/AppIdentityTests.swift` — enforce export-compliance
  metadata in the built bundle.
- `ios/KaloriesTests/UITestFixturesTests.swift` — prove screenshot modes remain
  explicit, offline, and before Firebase bootstrap.
- `ios/project.yml` — keep export-compliance metadata reproducible through
  XcodeGen.

### Create

- `docs/release/app-store/ja-JP.json` — Japanese product-page and submission
  source of truth.
- `tests/test_app_store_metadata.py` — exact schema and field-limit tests.
- `ios/KaloriesUITests/AppStoreScreenshotTests.swift` — five named real UI
  screenshot attachments.
- `scripts/export-app-store-screenshots.sh` — export and validate screenshots.
- `docs/release/app-store-assets/ja-JP/6.9-inch/*.png` — five opaque 1260 × 2736
  assets.
- `docs/release/app-store-foundation-evidence.md` — sanitized local gate ledger.

### Must not change

- API schema or nutrition scoring.
- Release Firebase/App Attest composition.
- production Cloud configuration or traffic.
- version/build unless App Store Connect later proves build `1` was accepted.
- accounts, analytics, payment, history, or unrelated features.

## Task 1: Freeze the local baseline

**Files:**
- Read: `docs/superpowers/specs/2026-08-10-japan-app-store-public-release-design.md`
- Read: `ios/project.yml`
- Read: `ios/Kalories/Resources/PrivacyInfo.xcprivacy`

- [ ] **Step 1: Verify the intended branch and clean starting state**

Run:

```bash
set -euo pipefail

git status --short --branch
git log -3 --oneline --decorate
git diff --check

test "$(git branch --show-current)" = "codex/kalories-testflight-build1"
test -z "$(git status --porcelain=v1)"
git diff --quiet
git diff --cached --quiet
git merge-base --is-ancestor 0ab02b5 HEAD
git merge-base --is-ancestor 9a30e07 HEAD
```

Expected: branch `codex/kalories-testflight-build1`, approved design/decisions
as ancestors of `HEAD`, clean worktree and index, and exit 0. The `test`,
`diff --quiet`, and `merge-base --is-ancestor` assertions are mandatory: a
wrong branch, untracked/staged/unstaged change, or missing approved commit must
fail the step.

- [ ] **Step 2: Verify immutable app identity inputs**

Run:

```bash
set -euo pipefail

rg -n 'MARKETING_VERSION|CURRENT_PROJECT_VERSION|PRODUCT_BUNDLE_IDENTIFIER|DEVELOPMENT_TEAM|CODE_SIGN_STYLE|PROVISIONING_PROFILE_SPECIFIER' ios/project.yml
plutil -p ios/Kalories/Resources/PrivacyInfo.xcprivacy
sips -g pixelWidth -g pixelHeight -g hasAlpha \
  ios/Kalories/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png

rg -q '^    DEVELOPMENT_TEAM: YMUG864233$' ios/project.yml
rg -q '^    MARKETING_VERSION: 1\.0\.0$' ios/project.yml
rg -q '^    CURRENT_PROJECT_VERSION: 1$' ios/project.yml
rg -q '^        PRODUCT_BUNDLE_IDENTIFIER: com\.ryuaistudio\.kalories$' \
  ios/project.yml
rg -q '^          CODE_SIGN_STYLE: Manual$' ios/project.yml
rg -q '^          PROVISIONING_PROFILE_SPECIFIER: Kalories App Store$' \
  ios/project.yml
test "$(plutil -extract NSPrivacyTracking raw -o - \
  ios/Kalories/Resources/PrivacyInfo.xcprivacy)" = "false"
test "$(plutil -extract NSPrivacyCollectedDataTypes.0.NSPrivacyCollectedDataType raw -o - \
  ios/Kalories/Resources/PrivacyInfo.xcprivacy)" = "NSPrivacyCollectedDataTypePhotosorVideos"
test "$(plutil -extract NSPrivacyCollectedDataTypes.0.NSPrivacyCollectedDataTypeTracking raw -o - \
  ios/Kalories/Resources/PrivacyInfo.xcprivacy)" = "false"
icon_info="$(sips -g pixelWidth -g pixelHeight -g hasAlpha \
  ios/Kalories/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png)"
echo "$icon_info"
echo "$icon_info" | rg -q 'pixelWidth: 1024$'
echo "$icon_info" | rg -q 'pixelHeight: 1024$'
echo "$icon_info" | rg -q 'hasAlpha: no$'
```

Expected: version `1.0.0`, build `1`, bundle
`com.ryuaistudio.kalories`, team `YMUG864233`, Release manual signing and
profile `Kalories App Store`, top-level and Photos/Videos collected-data
tracking `false`, and an opaque 1024 × 1024 icon. The
`rg`, `test`, and icon assertions are mandatory and fail the step if any
immutable input differs.

## Task 2: Replace TestFlight legal assertions with a failing public contract

**Files:**
- Modify: `tests/test_public_pages.py`
- Test: `tests/test_public_pages.py`

- [ ] **Step 1: Add the approved private contact to `APPROVED_HREFS`**

```python
"mailto:zll6796096@gmail.com",
```

- [ ] **Step 2: Replace TestFlight-specific privacy assertions**

In `test_privacy_page_states_the_complete_conservative_provider_contract`,
remove `TestFlight` and `18歳以上` from `required_terms`, then add:

```python
for forbidden_public_term in (
    "TestFlight",
    "18歳以上",
    "一般公開のApp Store配布には別途審査と確認が必要",
    "まだ確認済みではありません",
):
    self.assertNotIn(forbidden_public_term, text)

for required_public_term in (
    "カロスキャン",
    "一般の利用者",
    "zll6796096@gmail.com",
    "Google Gemini",
    "Firebase App Check",
    "Apple App Attest",
    "55日間",
    "開発者ログを無効",
    "データセット共有を利用しません",
    "医療診断",
    "医療助言",
):
    self.assertIn(required_public_term, text)

self.assertRegex(text, r"写真.+この写真を分析.+送信")
self.assertRegex(text, r"アカウント.+広告.+行動追跡.+ありません")
```

Keep the existing retention, deletion, safe-log, App Check, multilingual,
contrast, and approved-link assertions.

- [ ] **Step 3: Replace TestFlight-specific support assertions**

Remove `TestFlight` and `18歳以上` from the old support `required_terms`, then
add:

```python
for forbidden_public_term in ("TestFlight", "18歳以上", "invited testers"):
    self.assertNotIn(forbidden_public_term, text)

for required_public_term in (
    "App Store",
    "一般の利用者",
    "zll6796096@gmail.com",
    "一般用户",
    "general users",
    "医療診断",
    "medical diagnosis",
):
    self.assertIn(required_public_term, text)
```

- [ ] **Step 4: Run the focused test and verify the old pages fail**

```bash
.venv/bin/python -m unittest tests.test_public_pages -v
```

Expected: FAIL because the pages still contain controlled-TestFlight and
adults-only wording and lack the mail contact.

## Task 3: Implement public privacy and support pages

**Files:**
- Modify: `public/privacy/index.html`
- Modify: `public/support/index.html`
- Test: `tests/test_public_pages.py`

- [ ] **Step 1: Replace the privacy title and header**

```html
<title>カロスキャン プライバシーポリシー</title>
```

```html
<header>
  <h1>カロスキャン プライバシーポリシー</h1>
  <p class="updated">最終更新日：2026年8月11日</p>
  <p>
    このポリシーは、日本のApp Storeで公開するカロスキャンを利用する
    一般の利用者を対象とします。カロスキャンは子ども向けカテゴリの
    アプリではありません。
  </p>
</header>
```

- [ ] **Step 2: Make provider operation public and fail-closed**

Replace the unverified/TestFlight paragraphs in the third-party section with:

```html
<p>
  カロスキャンは、Google Geminiの有料サービス条件を前提として運用し、
  Google AI Studioの開発者ログを無効にし、データセット共有を利用しません。
  有料サービス条件、開発者ログ、データセット共有または保持条件に変更が
  確認された場合は、内容を再確認し、必要に応じて分析機能を停止して本ポリシーを更新します。
</p>
<p>
  Googleは、不正使用の検出および防止のため、プロンプト、コンテキスト情報、
  出力を最大55日間保持する場合があります。写真入力と分析出力がこの対象に
  含まれるため、カロスキャンはゼロデータ保持の適用を主張しません。
</p>
```

Keep explicit consent, App Check/App Attest, Cloud Run metadata, deletion,
withdrawal, and no-history disclosures.

- [ ] **Step 3: Replace the privacy estimate and contact sections**

```html
<section class="warning">
  <h2>推定結果について</h2>
  <p>
    結果は一食分の参考推定であり、正確な測定値、医療診断、医療助言、
    個別の治療方針または栄養指導ではありません。臨床用途には使用しないでください。
  </p>
</section>

<section>
  <h2>問い合わせ</h2>
  <p>
    利用方法は<a href="/support/">サポートページ</a>をご覧ください。
    プライバシーに関する問い合わせは
    <a href="mailto:zll6796096@gmail.com">zll6796096@gmail.com</a>へお送りください。
    個人的な食事写真、認証情報、APIキーまたは秘密情報を送信しないでください。
  </p>
</section>
```

- [ ] **Step 4: Replace the support identity, audience, and contact**

Use this title/header:

```html
<title>カロスキャン サポート</title>
```

```html
<header>
  <h1>カロスキャン サポート</h1>
  <p class="lede">日本のApp Storeで公開するカロスキャンの利用案内です。</p>
</header>
```

Use these audience statements in the existing Japanese, Chinese, and English
sections:

```html
<p>
  カロスキャンは一般の利用者向けですが、子ども向けカテゴリのアプリではありません。
  栄養結果は一食分の推定であり、医療診断または医療助言ではありません。
  臨床用途には使用しないでください。データの送信と保持については
  <a href="/privacy/">プライバシーポリシー</a>をご確認ください。
</p>
```

```html
<li>本 App 面向一般用户，但不属于儿童专区；结果只是单餐估算，不是医疗诊断或建议。</li>
```

```html
<li>The App Store version is for general users but is not in the Kids category. Results are single-meal estimates, not medical diagnosis or advice.</li>
```

Use this contact section:

```html
<section>
  <h2>問い合わせ・Contact</h2>
  <p>
    個人情報を含めずに
    <a href="mailto:zll6796096@gmail.com">zll6796096@gmail.com</a>へご連絡ください。
    公開できる不具合報告には
    <a href="https://github.com/zll6796096/Kalories/issues/new">GitHub Issue</a>も利用できます。
  </p>
</section>
```

- [ ] **Step 5: Run focused tests and package the pages**

```bash
.venv/bin/python -m unittest tests.test_public_pages -v
npm run build
test -f dist/privacy/index.html
test -f dist/support/index.html
rg -n 'zll6796096@gmail.com|カロスキャン' dist/privacy/index.html dist/support/index.html
```

Expected: all page tests pass and both packaged pages contain the approved
identity/contact.

- [ ] **Step 6: Commit the legal/support change**

```bash
git add -- tests/test_public_pages.py public/privacy/index.html public/support/index.html
git diff --cached --check
git commit -m "feat(release): publish App Store privacy and support pages"
```

## Task 4: Create and test the App Store metadata source of truth

**Files:**
- Create: `tests/test_app_store_metadata.py`
- Create: `docs/release/app-store/ja-JP.json`

- [ ] **Step 1: Write the metadata test before the JSON exists**

Create `tests/test_app_store_metadata.py`:

```python
from __future__ import annotations

import json
import unittest
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[1]
METADATA_PATH = ROOT / "docs" / "release" / "app-store" / "ja-JP.json"


class AppStoreMetadataTests(unittest.TestCase):
    def setUp(self) -> None:
        self.document = json.loads(METADATA_PATH.read_text(encoding="utf-8"))

    def test_identity_distribution_and_release_are_exact(self) -> None:
        self.assertEqual(self.document["apple_app_id"], "6799957568")
        self.assertEqual(self.document["bundle_id"], "com.ryuaistudio.kalories")
        self.assertEqual(self.document["version"], "1.0.0")
        self.assertEqual(self.document["build"], "1")
        self.assertEqual(self.document["territories"], ["JPN"])
        self.assertEqual(self.document["price"], "FREE")
        self.assertEqual(self.document["release_type"], "AFTER_APPROVAL")
        self.assertFalse(self.document["in_app_purchases"])
        self.assertFalse(self.document["subscriptions"])
        self.assertFalse(self.document["kids_category"])
        self.assertEqual(self.document["copyright"], "2026 RYU AI Studio")

    def test_localized_fields_fit_limits_and_match_product(self) -> None:
        self.assertEqual(self.document["locale"], "ja-JP")
        self.assertEqual(self.document["name"], "カロスキャン")
        self.assertLessEqual(len(self.document["name"]), 30)
        self.assertLessEqual(len(self.document["subtitle"]), 30)
        self.assertLessEqual(len(self.document["promotional_text"]), 170)
        self.assertLessEqual(len(self.document["keywords"]), 100)
        self.assertNotIn(" ", self.document["keywords"])
        keywords = self.document["keywords"].split(",")
        self.assertEqual(len(keywords), len(set(keywords)))
        for forbidden_claim in ("正確に測定", "診断します", "必ず改善"):
            self.assertNotIn(forbidden_claim, self.document["description"])

    def test_urls_contact_and_privacy_answers_are_exact(self) -> None:
        for key in ("support_url", "privacy_policy_url"):
            parsed = urlparse(self.document[key])
            self.assertEqual(parsed.scheme, "https")
            self.assertEqual(parsed.netloc, "kalories-sxielk4wua-an.a.run.app")
        self.assertEqual(self.document["contact_email"], "zll6796096@gmail.com")
        self.assertFalse(self.document["privacy"]["tracking"])
        self.assertEqual(
            self.document["privacy"]["collected_data"],
            [
                {
                    "type": "PHOTOS_OR_VIDEOS",
                    "purpose": "APP_FUNCTIONALITY",
                    "linked_to_user": False,
                    "tracking": False,
                },
                {
                    "type": "OTHER_DIAGNOSTIC_DATA",
                    "purpose": "ANALYTICS",
                    "linked_to_user": False,
                    "tracking": False,
                },
            ],
        )


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test and verify the JSON is absent**

```bash
.venv/bin/python -m unittest tests.test_app_store_metadata -v
```

Expected: ERROR with `FileNotFoundError` for
`docs/release/app-store/ja-JP.json`.

- [ ] **Step 3: Create `docs/release/app-store/ja-JP.json`**

```json
{
  "apple_app_id": "6799957568",
  "bundle_id": "com.ryuaistudio.kalories",
  "version": "1.0.0",
  "build": "1",
  "locale": "ja-JP",
  "name": "カロスキャン",
  "subtitle": "食事写真から栄養をかんたん推定",
  "promotional_text": "食事の写真から、カロリーと栄養バランスの目安をすばやく確認。送信前に写真の取扱いを確認できます。",
  "description": "カロスキャンは、食事の写真からカロリーと栄養バランスの目安を確認できるアプリです。\n\n主な機能\n・カメラで食事を撮影、または写真を選択\n・カロリーと主要な栄養情報を推定\n・認識した料理、推定の前提、信頼度を確認\n・食事バランスの参考情報をわかりやすく表示\n\n写真は、送信内容を確認して「この写真を分析」を選んだ場合にのみ、分析のためKaloriesサービスとGoogle Geminiへ送信されます。\n\nカロスキャンにはアカウント、広告、行動追跡、クラウド上の食事履歴はありません。\n\n表示内容は写真に基づく一食分の推定値です。正確な測定値、医療診断、医療助言、個別の治療・栄養指導ではありません。",
  "keywords": "カロリー,栄養,食事,写真,料理,食生活,フード,分析,推定",
  "support_url": "https://kalories-sxielk4wua-an.a.run.app/support/",
  "privacy_policy_url": "https://kalories-sxielk4wua-an.a.run.app/privacy/",
  "marketing_url": null,
  "contact_email": "zll6796096@gmail.com",
  "copyright": "2026 RYU AI Studio",
  "primary_category": "FOOD_AND_DRINK",
  "secondary_category": null,
  "territories": ["JPN"],
  "price": "FREE",
  "in_app_purchases": false,
  "subscriptions": false,
  "kids_category": false,
  "release_type": "AFTER_APPROVAL",
  "review_notes": "カロスキャンはログイン不要のiPhone向け食事写真分析アプリです。\n\n確認手順:\n1. 「カメラで撮影」または「写真から選択」を選びます。\n2. 食事写真を確認します。\n3. 写真がKaloriesサービスとGoogle Geminiへ送信される案内を確認し、「この写真を分析」をタップします。\n4. カロリー、栄養情報、推定の前提、信頼度、非医療用途の注意書きを確認します。\n\nアカウント、課金、アプリ内購入、サブスクリプション、広告、追跡はありません。写真に食事が明確に写っていない場合は、食事を認識できない旨を表示します。",
  "privacy": {
    "tracking": false,
    "collected_data": [
      {"type": "PHOTOS_OR_VIDEOS", "purpose": "APP_FUNCTIONALITY", "linked_to_user": false, "tracking": false},
      {"type": "OTHER_DIAGNOSTIC_DATA", "purpose": "ANALYTICS", "linked_to_user": false, "tracking": false}
    ]
  }
}
```

The diagnostic-data entry comes from the resolved Firebase Installations
privacy manifest. The signed-archive gate must stop if packaged manifests
differ.

- [ ] **Step 4: Run tests and commit the contract**

```bash
.venv/bin/python -m unittest tests.test_app_store_metadata -v
git add -- tests/test_app_store_metadata.py docs/release/app-store/ja-JP.json
git diff --cached --check
git commit -m "feat(release): define Japanese App Store metadata"
```

Expected: 3 tests pass and the scoped commit succeeds.

## Task 5: Declare and test standard-only encryption

**Files:**
- Modify: `ios/KaloriesTests/AppIdentityTests.swift`
- Modify: `ios/project.yml`
- Modify: `ios/Kalories/Resources/Info.plist`
- Test: `ios/KaloriesTests/AppIdentityTests.swift`

- [ ] **Step 1: Add the failing built-bundle assertion**

Add inside `AppIdentityTests`:

```swift
func testAppUsesNoNonExemptEncryption() {
    XCTAssertEqual(
        Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption") as? Bool,
        false
    )
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

```bash
xcodebuild -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:KaloriesTests/AppIdentityTests \
  test
```

Expected: FAIL because the built bundle has no
`ITSAppUsesNonExemptEncryption` boolean.

- [ ] **Step 3: Add the reproducible declaration and regenerate**

Under `targets.Kalories.info.properties` in `ios/project.yml`, add:

```yaml
ITSAppUsesNonExemptEncryption: false
```

Regenerate the project and generated Info.plist:

```bash
xcodegen generate --spec ios/project.yml --project ios
plutil -extract ITSAppUsesNonExemptEncryption raw ios/Kalories/Resources/Info.plist
```

Expected: `false`. The app uses Apple networking/TLS and no custom or
non-exempt cryptography.

- [ ] **Step 4: Rerun the focused test and commit**

```bash
xcodebuild -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:KaloriesTests/AppIdentityTests \
  test
git add -- \
  ios/project.yml \
  ios/Kalories/Resources/Info.plist \
  ios/KaloriesTests/AppIdentityTests.swift \
  ios/Kalories.xcodeproj/project.pbxproj
git diff --cached --check
git commit -m "chore(ios): declare export compliance"
```

Expected: the focused test passes and XcodeGen leaves no untracked project
drift.

## Task 6: Add failing tests for private screenshot launch states

**Files:**
- Modify: `ios/KaloriesTests/UITestFixturesTests.swift`
- Test: `ios/KaloriesTests/UITestFixturesTests.swift`

- [ ] **Step 1: Add screenshot-mode expectations**

Add inside `UITestFixturesTests`:

```swift
func testScreenshotModesReturnBeforeFirebaseBootstrap() throws {
    let modes = [
        "--fixture-screenshot-capture",
        "--fixture-screenshot-preview",
        "--fixture-screenshot-result",
    ]

    for mode in modes {
        var bootstrapCalls = 0
        let environment = try AppEnvironment.live(
            bundle: Bundle(for: Self.self),
            arguments: ["Kalories", "--ui-testing", mode],
            appCheckBootstrap: {
                bootstrapCalls += 1
                throw AppFailure.appCheckUnavailable
            }
        )

        XCTAssertEqual(bootstrapCalls, 0, mode)
        XCTAssertTrue(UITestFixtures.isScreenshotMode(arguments: [mode]), mode)
        XCTAssertEqual(environment.privacyURL.host, "kalories.invalid", mode)
    }
}

func testScreenshotModeRecognitionIsExact() {
    XCTAssertFalse(UITestFixtures.isScreenshotMode(arguments: []))
    XCTAssertFalse(UITestFixtures.isScreenshotMode(arguments: ["--fixture-success"]))
    XCTAssertFalse(
        UITestFixtures.isScreenshotMode(arguments: ["--fixture-screenshot-unknown"])
    )
    XCTAssertTrue(
        UITestFixtures.isScreenshotMode(arguments: ["--fixture-screenshot-result"])
    )
}
```

Extend `testEnvironmentRejectsMissingDuplicateUnknownAndAmbiguousFixtureModes`
with:

```swift
["Kalories", "--ui-testing", "--fixture-screenshot-capture", "--fixture-success"],
["Kalories", "--ui-testing", "--fixture-screenshot-preview", "--fixture-screenshot-result"],
```

- [ ] **Step 2: Run the focused test and verify compilation fails**

```bash
xcodebuild -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:KaloriesTests/UITestFixturesTests \
  test
```

Expected: FAIL because `isScreenshotMode(arguments:)` and the three modes do
not exist.

## Task 7: Implement offline screenshot states and capture tests

**Files:**
- Modify: `ios/Kalories/App/UITestFixtures.swift`
- Modify: `ios/Kalories/Features/Capture/CaptureView.swift`
- Create: `ios/KaloriesUITests/AppStoreScreenshotTests.swift`
- Test: `ios/KaloriesTests/UITestFixturesTests.swift`
- Test: `ios/KaloriesUITests/AppStoreScreenshotTests.swift`

- [ ] **Step 1: Extend the DEBUG fixture modes**

Replace the private `Mode` enum with:

```swift
private enum Mode: Equatable {
    case success
    case timeout
    case screenshotCapture
    case screenshotPreview
    case screenshotResult

    var isScreenshot: Bool {
        switch self {
        case .screenshotCapture, .screenshotPreview, .screenshotResult:
            true
        case .success, .timeout:
            false
        }
    }
}
```

Add:

```swift
static func isScreenshotMode(
    arguments: [String] = ProcessInfo.processInfo.arguments
) -> Bool {
    fixtureMode(in: arguments)?.isScreenshot == true
}
```

Extend the exact switch in `fixtureMode(in:)`:

```swift
case "--fixture-screenshot-capture":
    return .screenshotCapture
case "--fixture-screenshot-preview":
    return .screenshotPreview
case "--fixture-screenshot-result":
    return .screenshotResult
```

- [ ] **Step 2: Prepare preview/result without network or Firebase**

In `environmentIfRequested`, construct `flow` separately and prepare exact
screenshot states:

```swift
let flow = AppFlowModel(service: service, processor: ImageProcessor())
switch mode {
case .screenshotPreview:
    selectImage(into: flow)
case .screenshotResult:
    selectImage(into: flow)
    flow.analyze()
case .success, .timeout, .screenshotCapture:
    break
}

return AppEnvironment(
    flow: flow,
    localizer: AppLocalizer(locale: .ja),
    cameraPresentation: CameraPresentationController(
        authorization: CameraAuthorizationService()
    ),
    privacyURL: privacyURL,
    supportURL: supportURL
)
```

Keep the fake `UITestAnalysisService`; no screenshot mode may initialize
Firebase or make a URL request.

- [ ] **Step 3: Hide the fixture-only button in screenshot modes**

In the DEBUG block in `CaptureView.captureOptions`, use:

```swift
if UITestFixtures.isActive && !UITestFixtures.isScreenshotMode() {
```

- [ ] **Step 4: Create the screenshot UI test**

Create `ios/KaloriesUITests/AppStoreScreenshotTests.swift`:

```swift
import XCTest

@MainActor
final class AppStoreScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCapturesFiveJapaneseAppStoreScreenshots() {
        let capture = launch(mode: "--fixture-screenshot-capture")
        XCTAssertTrue(capture.buttons["capture.camera"].waitForExistence(timeout: 5))
        attach(name: "app-store-01-capture")
        capture.terminate()

        let result = launch(mode: "--fixture-screenshot-result")
        XCTAssertTrue(element(in: result, id: "result.page").waitForExistence(timeout: 5))
        XCTAssertTrue(result.staticTexts["焼き鮭定食"].waitForExistence(timeout: 2))
        attach(name: "app-store-02-summary")

        let calories = result.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "カロリー,")
        ).firstMatch
        scrollToDiscover(calories, in: result)
        attach(name: "app-store-03-nutrition")
        result.terminate()

        let preview = launch(mode: "--fixture-screenshot-preview")
        XCTAssertTrue(preview.buttons["capture.analyze"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            preview.staticTexts[
                "分析を開始すると、写真は今回の食事分析のために Kalories サービスと Gemini へ送信されます。"
            ].waitForExistence(timeout: 2)
        )
        attach(name: "app-store-04-consent")
        preview.terminate()

        let uncertainty = launch(mode: "--fixture-screenshot-result")
        let disclaimer = uncertainty.staticTexts[
            "写真からの推定値です。1食の参考であり、医療上の診断ではありません。"
        ]
        scrollToDiscover(disclaimer, in: uncertainty)
        attach(name: "app-store-05-uncertainty")
    }

    private func launch(mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            mode,
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP",
        ]
        app.launch()
        return app
    }

    private func element(in app: XCUIApplication, id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func scrollToDiscover(_ element: XCUIElement, in app: XCUIApplication) {
        var attempts = 0
        while !element.isHittable, attempts < 10 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(element.exists)
        XCTAssertTrue(element.isHittable)
    }

    private func attach(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
```

- [ ] **Step 5: Run unit and screenshot tests**

```bash
xcodebuild -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:KaloriesTests/UITestFixturesTests \
  test

release_tmp="$(mktemp -d)"
xcodebuild -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.5' \
  -only-testing:KaloriesUITests/AppStoreScreenshotTests \
  -resultBundlePath "${release_tmp}/AppStoreScreenshots.xcresult" \
  test
```

Expected: both commands pass and the result bundle exists. Keep `release_tmp`
for Task 8.

- [ ] **Step 6: Commit deterministic screenshot states**

```bash
git add -- \
  ios/Kalories/App/UITestFixtures.swift \
  ios/Kalories/Features/Capture/CaptureView.swift \
  ios/KaloriesTests/UITestFixturesTests.swift \
  ios/KaloriesUITests/AppStoreScreenshotTests.swift
git diff --cached --check
git commit -m "test(ios): add App Store screenshot states"
```

## Task 8: Export and validate five real UI screenshots

**Files:**
- Create: `scripts/export-app-store-screenshots.sh`
- Create: `docs/release/app-store-assets/ja-JP/6.9-inch/*.png`

- [ ] **Step 1: Create the export script**

Create `scripts/export-app-store-screenshots.sh`:

```bash
#!/usr/bin/env bash

set -euo pipefail

if (($# != 2)); then
  printf '%s\n' 'usage: export-app-store-screenshots.sh RESULT_BUNDLE OUTPUT_DIR'
  exit 64
fi

result_bundle="$1"
output_dir="$2"
test -d "${result_bundle}"
mkdir -p "${output_dir}"

export_tmp="$(mktemp -d)"
cleanup_export() {
  find "${export_tmp}" -type f -delete
  rmdir "${export_tmp}"
}
trap cleanup_export EXIT

xcrun xcresulttool export attachments \
  --path "${result_bundle}" \
  --output-path "${export_tmp}"

names=(
  app-store-01-capture
  app-store-02-summary
  app-store-03-nutrition
  app-store-04-consent
  app-store-05-uncertainty
)

for name in "${names[@]}"; do
  exported_name="$(jq -er --arg name "${name}" '
    [.[].attachments[] | select(.suggestedHumanReadableName == $name)]
    | if length == 1 then .[0].exportedFileName else empty end
  ' "${export_tmp}/manifest.json")"
  source_path="${export_tmp}/${exported_name}"
  destination_path="${output_dir}/${name}.png"
  test -f "${source_path}"
  cp "${source_path}" "${destination_path}"

  width="$(sips -g pixelWidth "${destination_path}" | awk '/pixelWidth/ {print $2}')"
  height="$(sips -g pixelHeight "${destination_path}" | awk '/pixelHeight/ {print $2}')"
  alpha="$(sips -g hasAlpha "${destination_path}" | awk '/hasAlpha/ {print $2}')"
  if [[ "${width}" != 1260 || "${height}" != 2736 || "${alpha}" != no ]]; then
    printf 'NO-GO: %s is not an opaque 1260x2736 screenshot\n' "${name}"
    exit 1
  fi
done

if [[ "$(find "${output_dir}" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')" != 5 ]]; then
  printf '%s\n' 'NO-GO: screenshot output count is not exactly five'
  exit 1
fi

printf '%s\n' 'PASS: five opaque 6.9-inch App Store screenshots exported'
```

- [ ] **Step 2: Export from the result bundle**

```bash
chmod 755 scripts/export-app-store-screenshots.sh
scripts/export-app-store-screenshots.sh \
  "${release_tmp}/AppStoreScreenshots.xcresult" \
  docs/release/app-store-assets/ja-JP/6.9-inch
```

Expected: `PASS: five opaque 6.9-inch App Store screenshots exported`.

- [ ] **Step 3: Inspect every PNG at original resolution**

Verify Japanese UI; exact A-order states; no fixture button, personal image,
device identifier, token, secret, real provider response, trend/history UI,
clipping, overlap, or transparency. If any visual is wrong, fix the fixture or
test and rerun; do not invent or retouch product UI.

- [ ] **Step 4: Commit script and accepted assets**

```bash
git add -- \
  scripts/export-app-store-screenshots.sh \
  docs/release/app-store-assets/ja-JP/6.9-inch
git diff --cached --check
git commit -m "docs(release): add Japanese App Store screenshots"
```

## Task 9: Run the complete local gate and record evidence

**Files:**
- Create: `docs/release/app-store-foundation-evidence.md`

- [ ] **Step 1: Run complete web/backend checks**

```bash
npm test
npm run lint
npm run build
.venv/bin/python -m unittest discover -s tests -p 'test_*.py' -v
.venv/bin/python -m compileall -q api lib tests
.venv/bin/python -c "import api.analyze, lib.nutrition, lib.rate_limit, lib.app_check"
uv pip check --python .venv/bin/python
docker build .
```

Expected: every command exits 0. Record current test counts, not historic ones.

- [ ] **Step 2: Run complete iOS checks**

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

Expected: all commands pass; local App Check release check reports PASS while
external configuration remains a separate gate.

- [ ] **Step 3: Create the evidence ledger with observed counts**

Create `docs/release/app-store-foundation-evidence.md`:

```markdown
# App Store Release Foundation Evidence

Date: 2026-08-11
Scope: local source, tests, metadata, public-page package, and screenshots only

## Approved identity

- App: カロスキャン
- Apple app ID: 6799957568
- Bundle: com.ryuaistudio.kalories
- Version/build: 1.0.0 (1)
- Territory: Japan only
- Price: Free
- Release: Automatic after approval
- Audience: General audience, not Kids category
- Contact: zll6796096@gmail.com
- Copyright: 2026 RYU AI Studio

## Local gates

- Web tests: PASS
- Python tests: PASS
- Typecheck/build/import/dependency checks: PASS
- iOS unit/UI tests: PASS
- Unsigned generic Release build: PASS
- Local App Check release scan: PASS
- Public privacy/support package: PASS
- Japanese metadata contract: PASS
- Five opaque 1260 x 2736 real-UI screenshots: PASS
- Git diff check: PASS

## Boundaries

- Production deployment: NOT RUN
- Cloud traffic mutation: NOT RUN
- Signed App Store archive: NOT RUN
- App Store Connect upload: NOT RUN
- App Review submission: NOT RUN
- Public availability: NOT RUN
```

Append the exact current web, Python, and Xcode test counts immediately below
their PASS rows before committing. Never copy counts from an older document.

- [ ] **Step 4: Review diff and commit evidence**

```bash
git diff --check
git status --short --branch
git diff --stat
git diff
git add -- docs/release/app-store-foundation-evidence.md
git diff --cached --check
git commit -m "docs(release): record App Store foundation evidence"
git status --short --branch
```

Expected: only scoped foundation changes and a clean worktree. This proves no
production, upload, review, or storefront gate.
