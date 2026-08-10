# カロスキャン 18+ Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restrict the native カロスキャン analysis flow to users who have confirmed they are at least 18, store only that Boolean locally, and make the public pages and App Store release instructions consistent with the shipped boundary.

**Architecture:** A focused observable `AdultAccessModel` reads and writes one versioned `UserDefaults` Boolean. `RootView` renders a localized `AdultAccessView` above every capture/analysis state until confirmation; test fixtures inject only explicit DEBUG state. Static public pages and release plans repeat the same 18+ and data-minimization facts, while App Store delivery uses Apple's higher-age-rating override.

**Tech Stack:** Swift 6, SwiftUI, Observation, Foundation `UserDefaults`, XCTest/XCUITest, Python 3.12 `unittest`, static HTML, XcodeGen, Xcode 27.0 beta with the iOS 26.5 simulator.

---

## Dependency and Scope

Required design:

- `docs/superpowers/specs/2026-08-11-adult-access-design.md`

This plan modifies only Kalories. It does not modify LifeSnapAction, collect a
birth date or identity document, add an account, replace Gemini, change the
photo-transfer consent, deploy a backend, upload a build, edit App Store
Connect, or submit App Review.

The verified local developer runtime is
`/Applications/Xcode-beta.app/Contents/Developer`; the installed destination is
`platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5`. Every native command block
exports that `DEVELOPER_DIR`. A different destination is allowed only if the
verified simulator disappears, and its exact replacement must be recorded.

## File Responsibility Map

### Create

- `ios/Kalories/Features/AdultAccess/AdultAccessModel.swift` — versioned local
  Boolean persistence and observable access state.
- `ios/Kalories/Features/AdultAccess/AdultAccessView.swift` — localized,
  accessible first-launch gate.
- `ios/KaloriesTests/AdultAccessModelTests.swift` — default-deny, persistence,
  and storage-minimization unit tests.
- `ios/KaloriesUITests/AdultAccessUITests.swift` — pre-confirmation boundary,
  transition, and relaunch persistence.

### Modify

- `ios/Kalories/App/AppEnvironment.swift` — inject the access model.
- `ios/Kalories/App/RootView.swift` — gate every existing app screen.
- `ios/Kalories/App/UITestFixtures.swift` — deterministic DEBUG-only confirmed
  and reset states.
- `ios/Kalories/Resources/{ja,zh-Hans,en}.lproj/Localizable.strings` — complete
  age-access copy.
- `ios/KaloriesTests/AppLocalizerTests.swift` — exact three-language copy.
- `ios/KaloriesUITests/KaloriesFlowUITests.swift` and
  `ios/KaloriesUITests/AppLaunchTests.swift` — make existing tests explicit
  about confirmed versus unconfirmed state.
- `tests/test_public_pages.py`, `public/privacy/index.html`, and
  `public/support/index.html` — 18+ disclosure and local-only Boolean boundary.
- `docs/superpowers/plans/2026-08-11-japan-app-store-release-foundation.md` and
  `docs/superpowers/plans/2026-08-11-japan-app-store-delivery.md` — remove the
  obsolete general-audience/9+ instructions.

## Task 1: Add the fail-closed adult-access model with TDD

**Files:**
- Create: `ios/Kalories/Features/AdultAccess/AdultAccessModel.swift`
- Create: `ios/KaloriesTests/AdultAccessModelTests.swift`

- [ ] **Step 1: Write the failing model tests**

Create `AdultAccessModelTests.swift` with a unique `UserDefaults` suite. Test
the exact key, absent/wrong/false values as denied, confirmation persistence,
and that confirmation adds exactly one Boolean:

```swift
import XCTest
@testable import Kalories

@MainActor
final class AdultAccessModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "AdultAccessModelTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testStorageKeyIsVersionedAndMissingValueDeniesAccess() {
        XCTAssertEqual(
            AdultAccessPreference.storageKey,
            "kalories.adult-access.confirmed.v1"
        )
        XCTAssertFalse(AdultAccessModel(preference: .init(defaults: defaults)).isConfirmed)
    }

    func testOnlyLiteralTrueGrantsAccess() {
        for value in [false, "true", 1] as [Any] {
            defaults.set(value, forKey: AdultAccessPreference.storageKey)
            XCTAssertFalse(
                AdultAccessModel(preference: .init(defaults: defaults)).isConfirmed
            )
        }
        defaults.set(true, forKey: AdultAccessPreference.storageKey)
        XCTAssertTrue(AdultAccessModel(preference: .init(defaults: defaults)).isConfirmed)
    }

    func testConfirmPersistsOnlyOneBooleanAndUpdatesState() throws {
        let model = AdultAccessModel(preference: .init(defaults: defaults))
        model.confirm()

        XCTAssertTrue(model.isConfirmed)
        let domain = try XCTUnwrap(defaults.persistentDomain(forName: suiteName))
        XCTAssertEqual(domain.count, 1)
        XCTAssertEqual(domain[AdultAccessPreference.storageKey] as? Bool, true)
    }
}
```

- [ ] **Step 2: Generate the project and verify the tests fail**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd ios
xcodegen generate
xcodebuild test \
  -project Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:KaloriesTests/AdultAccessModelTests
```

Expected: FAIL because `AdultAccessPreference` and `AdultAccessModel` do not
exist. If that simulator is unavailable, use the installed iPhone simulator
reported by `xcrun simctl list devices available` and record its exact name.

- [ ] **Step 3: Implement the minimal model**

Create `AdultAccessModel.swift`:

```swift
import CoreFoundation
import Foundation
import Observation

struct AdultAccessPreference {
    static let storageKey = "kalories.adult-access.confirmed.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Bool {
        guard let value = defaults.object(forKey: Self.storageKey) else {
            return false
        }
        guard CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() else {
            return false
        }
        return (value as? Bool) == true
    }

    func confirm() {
        defaults.set(true, forKey: Self.storageKey)
    }
}

@MainActor
@Observable
final class AdultAccessModel {
    private(set) var isConfirmed: Bool

    @ObservationIgnored
    private let preference: AdultAccessPreference

    init(preference: AdultAccessPreference) {
        self.preference = preference
        isConfirmed = preference.load()
    }

    func confirm() {
        preference.confirm()
        isConfirmed = true
    }
}
```

- [ ] **Step 4: Run the focused tests and commit**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd ios
xcodegen generate
xcodebuild test \
  -project Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:KaloriesTests/AdultAccessModelTests
cd ..
git add -- \
  ios/Kalories/Features/AdultAccess/AdultAccessModel.swift \
  ios/KaloriesTests/AdultAccessModelTests.swift \
  ios/Kalories.xcodeproj/project.pbxproj
git diff --cached --check
git commit -m "feat(ios): persist adult access confirmation"
```

Expected: focused tests PASS; the generated project includes both new files.

## Task 2: Gate the native root and localize the access screen

**Files:**
- Create: `ios/Kalories/Features/AdultAccess/AdultAccessView.swift`
- Modify: `ios/Kalories/App/AppEnvironment.swift`
- Modify: `ios/Kalories/App/RootView.swift`
- Modify: `ios/Kalories/Resources/ja.lproj/Localizable.strings`
- Modify: `ios/Kalories/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `ios/Kalories/Resources/en.lproj/Localizable.strings`
- Modify: `ios/KaloriesTests/AppLocalizerTests.swift`

- [ ] **Step 1: Add failing exact-copy tests**

Add this test to `AppLocalizerTests`:

```swift
func testAdultAccessCopyIsCompleteInEveryLocale() {
    let expected: [AppLocale: [String: String]] = [
        .ja: [
            "adultAccessTitle": "18歳以上の方のみ利用できます",
            "adultAccessBody": "カロスキャンのAI食事分析は18歳以上の方のみ利用できます。食事写真は、別途送信内容を確認して同意した場合にのみ分析サービスへ送信されます。",
            "adultAccessUnderage": "18歳未満の方はこのアプリを利用できません。",
            "adultAccessConfirm": "18歳以上です",
        ],
        .zh: [
            "adultAccessTitle": "仅限18岁以上用户",
            "adultAccessBody": "卡路里扫描的AI饮食分析仅供18岁以上用户使用。只有在您另行确认发送内容并同意后，餐食照片才会发送至分析服务。",
            "adultAccessUnderage": "未满18岁者不能使用本应用。",
            "adultAccessConfirm": "我已满18岁",
        ],
        .en: [
            "adultAccessTitle": "For users aged 18 or older",
            "adultAccessBody": "Kalories AI meal analysis is available only to users aged 18 or older. A meal photo is sent to the analysis service only after you separately review and consent to that transfer.",
            "adultAccessUnderage": "People under 18 cannot use this app.",
            "adultAccessConfirm": "I am 18 or older",
        ],
    ]

    for locale in AppLocale.allCases {
        let localizer = AppLocalizer(locale: locale)
        for (key, value) in expected[locale, default: [:]] {
            XCTAssertEqual(localizer.text(key), value, "\(locale): \(key)")
        }
    }
}
```

- [ ] **Step 2: Run the localizer test and verify it fails**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd ios
xcodebuild test \
  -project Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:KaloriesTests/AppLocalizerTests/testAdultAccessCopyIsCompleteInEveryLocale
```

Expected: FAIL because the four keys are absent.

- [ ] **Step 3: Add the exact four keys to all three string tables**

Add the Japanese, Chinese, and English values from Step 1 to their corresponding
`Localizable.strings` files. Keep UTF-8, one semicolon-terminated entry per key,
and do not add birth-date, identity, account, or provider-guarantee claims.

- [ ] **Step 4: Inject the access model into the environment**

Add `let adultAccess: AdultAccessModel` to `AppEnvironment`. In `live`, create:

```swift
let adultAccess = AdultAccessModel(
    preference: AdultAccessPreference(defaults: .standard)
)
```

Pass it in the returned environment. Update every explicit `AppEnvironment(`
initializer in tests/fixtures with an intentional access model; do not add a
default that can silently bypass the gate.

- [ ] **Step 5: Create the accessible SwiftUI gate**

Create `AdultAccessView.swift` with a scrolling, Dynamic-Type-safe layout. It
must render `app.title`, `adult-access.title`, `adult-access.confirm`, privacy,
and support identifiers; the only state-changing action calls `model.confirm()`:

```swift
import SwiftUI

struct AdultAccessView: View {
    let model: AdultAccessModel
    let localizer: AppLocalizer
    let privacyURL: URL
    let supportURL: URL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(localizer.text("appName"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("app.title")
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(localizer.text("adultAccessTitle"))
                    .font(.largeTitle.bold())
                    .accessibilityIdentifier("adult-access.title")
                Text(localizer.text("adultAccessBody"))
                Text(localizer.text("adultAccessUnderage"))
                    .font(.callout.weight(.semibold))
                Button(localizer.text("adultAccessConfirm")) {
                    model.confirm()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .controlSize(.large)
                .accessibilityIdentifier("adult-access.confirm")
                HStack(spacing: 20) {
                    Link(localizer.text("privacyPolicy"), destination: privacyURL)
                        .accessibilityIdentifier("adult-access.privacy")
                    Link(localizer.text("support"), destination: supportURL)
                        .accessibilityIdentifier("adult-access.support")
                }
                .font(.footnote)
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
```

- [ ] **Step 6: Put the gate above every app screen**

At the top of `RootView.body`, render `AdultAccessView` when
`environment.adultAccess.isConfirmed == false`; only the `else` branch may
switch over `flow.screen`. Do not put the check only around capture buttons.

- [ ] **Step 7: Build, test, and commit**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd ios
xcodegen generate
xcodebuild test \
  -project Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:KaloriesTests/AdultAccessModelTests \
  -only-testing:KaloriesTests/AppLocalizerTests
cd ..
git add -- \
  ios/Kalories/Features/AdultAccess/AdultAccessView.swift \
  ios/Kalories/App/AppEnvironment.swift \
  ios/Kalories/App/RootView.swift \
  ios/Kalories/App/UITestFixtures.swift \
  ios/Kalories/Resources/ja.lproj/Localizable.strings \
  ios/Kalories/Resources/zh-Hans.lproj/Localizable.strings \
  ios/Kalories/Resources/en.lproj/Localizable.strings \
  ios/KaloriesTests/AppLocalizerTests.swift \
  ios/Kalories.xcodeproj/project.pbxproj
git diff --cached --check
git commit -m "feat(ios): gate analysis behind adult confirmation"
```

Expected: focused tests PASS and Debug/Release compilation succeeds.

## Task 3: Prove the UI boundary and one-time behavior

**Files:**
- Create: `ios/KaloriesUITests/AdultAccessUITests.swift`
- Modify: `ios/Kalories/App/UITestFixtures.swift`
- Modify: `ios/KaloriesUITests/KaloriesFlowUITests.swift`
- Modify: `ios/KaloriesUITests/AppLaunchTests.swift`

- [ ] **Step 1: Write the failing UI tests**

Create `AdultAccessUITests.swift`:

```swift
import XCTest

@MainActor
final class AdultAccessUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testConfirmationGatesCaptureAndPersistsAcrossRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--fixture-success",
            "--reset-adult-access",
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["adult-access.title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["capture.camera"].exists)
        XCTAssertFalse(app.buttons["capture.library"].exists)
        XCTAssertFalse(app.buttons["capture.fixture"].exists)
        XCTAssertFalse(app.buttons["capture.analyze"].exists)

        let confirm = app.buttons["adult-access.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 2))
        confirm.tap()
        XCTAssertTrue(app.buttons["capture.fixture"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["adult-access.title"].exists)

        app.terminate()
        app.launchArguments = [
            "--ui-testing",
            "--fixture-success",
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP",
        ]
        app.launch()

        XCTAssertTrue(app.buttons["capture.fixture"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["adult-access.title"].exists)
    }
}
```

Update existing fixture launch helpers to pass `--adult-access-confirmed`.
Update the plain launch test to use `--ui-testing`, `--fixture-success`, and
`--reset-adult-access`, then expect `adult-access.title` and no capture
controls. These explicit states prevent test-order dependence.

- [ ] **Step 2: Run the new UI test and verify it fails**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd ios
xcodegen generate
xcodebuild test \
  -project Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:KaloriesUITests/AdultAccessUITests
```

Expected: FAIL because the fixture arguments do not yet control an explicit
adult-access test state.

- [ ] **Step 3: Implement DEBUG-only fixture control**

In `UITestFixtures.environmentIfRequested`, build the access model from
`AdultAccessPreference(defaults: .standard)`. Recognize exactly these optional
arguments only inside the existing `#if DEBUG` file:

- `--reset-adult-access`: remove only
  `AdultAccessPreference.storageKey` before model creation;
- `--adult-access-confirmed`: call `preference.confirm()` before model creation.

Reject contradictory use of both arguments as `invalidConfiguration`. Do not
parse either argument in Release code. Inject the resulting model into the
fixture `AppEnvironment`.

- [ ] **Step 4: Run all native tests and commit**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd ios
xcodegen generate
xcodebuild test \
  -project Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
cd ..
git add -- \
  ios/Kalories/App/UITestFixtures.swift \
  ios/KaloriesUITests/AdultAccessUITests.swift \
  ios/KaloriesUITests/KaloriesFlowUITests.swift \
  ios/KaloriesUITests/AppLaunchTests.swift \
  ios/Kalories.xcodeproj/project.pbxproj
git diff --cached --check
git commit -m "test(ios): verify one-time adult access gate"
```

Expected: every Kalories unit and UI test PASS.

## Task 4: Align public pages and release contracts

**Files:**
- Modify: `tests/test_public_pages.py`
- Modify: `public/privacy/index.html`
- Modify: `public/support/index.html`
- Modify: `docs/superpowers/plans/2026-08-11-japan-app-store-release-foundation.md`
- Modify: `docs/superpowers/plans/2026-08-11-japan-app-store-delivery.md`

- [ ] **Step 1: Add failing public-page assertions**

Replace the obsolete general-user assertions with exact multilingual adult
requirements. Add these assertions to the existing privacy/support contract
tests:

```python
privacy_text = read_page("privacy")[1].text
for required in (
    "カロスキャンは18歳以上の方のみ利用できます。",
    "初回起動時に「18歳以上です」を選択した事実だけを端末内に保存します。",
    "生年月日、氏名、本人確認書類は収集しません。",
    "年齢確認の結果はKalories、Google、FirebaseまたはAppleへ送信しません。",
):
    self.assertIn(required, privacy_text)

support_text = read_page("support")[1].text
for required in (
    "18歳以上の方のみ利用できます",
    "仅限18岁以上用户",
    "only to users aged 18 or older",
):
    self.assertIn(required, support_text)

for forbidden in ("一般の利用者", "一般用户", "general users"):
    self.assertNotIn(forbidden, privacy_text)
    self.assertNotIn(forbidden, support_text)
```

The privacy page must contain these exact Japanese statements:

```text
カロスキャンは18歳以上の方のみ利用できます。
初回起動時に「18歳以上です」を選択した事実だけを端末内に保存します。
生年月日、氏名、本人確認書類は収集しません。
年齢確認の結果はKalories、Google、FirebaseまたはAppleへ送信しません。
```

The support page must contain the 18+ restriction in Japanese, Simplified
Chinese, and English. Keep the existing exact provider-retention, logging,
dataset-sharing, non-medical, email, URL allowlist, static-page, and contrast
assertions.

- [ ] **Step 2: Run focused tests and verify they fail**

```bash
.venv/bin/python -m unittest tests.test_public_pages -v
```

Expected: FAIL because the current pages still say general users and do not
disclose local-only adult confirmation.

- [ ] **Step 3: Update the privacy and support pages**

Replace general-audience wording with 18+-only wording. Add the four privacy
facts from Step 1 without claiming that the Boolean proves actual age. Retain
the existing no-account, no-ads, no-tracking, explicit-photo-consent,
55-day-abuse-retention, developer-logging-disabled, dataset-sharing-off,
non-clinical, and contact disclosures.

- [ ] **Step 4: Correct future release-plan instructions**

In the foundation plan, replace every instruction that forbids `18歳以上` or
requires general-user wording with the approved three-language 18+ contract.
Change evidence text to “Users aged 18 or older, not Kids category.”

In the delivery plan:

- change Audience/category to `18+, not Kids / Food & Drink`;
- require metadata and review notes to start with the one-time local
  confirmation;
- answer the questionnaire truthfully;
- choose **Override to Higher Age Rating**, select 18+, and read back Japan as
  18+ for iOS 26 or later;
- record Apple's displayed legacy mapping for earlier OS versions without
  weakening the in-app 18+ restriction;
- never use the obsolete `Not Applicable` override or 9+ result as the release
  target.

- [ ] **Step 5: Test and commit**

```bash
.venv/bin/python -m unittest tests.test_public_pages -v
rg -n 'General audience|general users|一般の利用者|do not override|9\+ global' \
  public/privacy/index.html \
  public/support/index.html \
  docs/superpowers/plans/2026-08-11-japan-app-store-release-foundation.md \
  docs/superpowers/plans/2026-08-11-japan-app-store-delivery.md
git add -- \
  tests/test_public_pages.py \
  public/privacy/index.html \
  public/support/index.html \
  docs/superpowers/plans/2026-08-11-japan-app-store-release-foundation.md \
  docs/superpowers/plans/2026-08-11-japan-app-store-delivery.md
git diff --cached --check
git commit -m "docs(release): align public release with 18 plus access"
```

Expected: public-page tests PASS and `rg` returns no obsolete instruction (exit
1 is expected because no match exists).

## Task 5: Run the complete local gate and record the boundary

**Files:**
- Modify only files required by a reproduced failure from this plan.

- [ ] **Step 1: Run web and backend gates**

```bash
npm test
npm run lint
npm run build
.venv/bin/python -m unittest discover -s tests -p 'test_*.py' -v
.venv/bin/python -m compileall -q api lib tests
.venv/bin/python -c "import api.analyze, lib.nutrition, lib.rate_limit, lib.app_check"
uv pip check --python .venv/bin/python
```

Expected: every command PASS. Fix only a reproduced regression caused by this
plan; unrelated failures are reported rather than hidden.

- [ ] **Step 2: Run the complete native gate**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd ios
xcodegen generate
xcodebuild test \
  -project Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
xcodebuild build \
  -project Kalories.xcodeproj \
  -scheme Kalories \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator'
cd ..
```

Expected: all unit/UI tests and the Release configuration build PASS.

- [ ] **Step 3: Review the exact shipped boundary**

```bash
rg -n 'kalories\.adult-access\.confirmed\.v1|adultAccess' ios/Kalories ios/KaloriesTests ios/KaloriesUITests
rg -n 'birth|birthday|dateOfBirth|生年月日|本人確認書類' ios/Kalories --glob '*.swift'
rg -n -- '--adult-access-confirmed|--reset-adult-access' ios/Kalories
git diff --check
git status --short --branch
git log -8 --oneline --decorate
```

Expected: one production Boolean key; no birth/identity collection in Swift;
fixture arguments appear only in the DEBUG-only fixture file; clean diff and
worktree.

- [ ] **Step 4: Report remaining gates honestly**

Record that local implementation is complete but App Store Connect's 18+
override, archive/upload, review, automatic release, Japan propagation, and
clean-device download remain separate external gates. Record LifeSnapAction's
same-provider/no-gate state as a separate follow-up risk without editing it.
