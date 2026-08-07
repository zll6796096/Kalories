# カロスキャン Native iOS Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Build a native, iPhone-only SwiftUI client for カロスキャン that reproduces the approved capture-to-analysis-to-result flow against mocked or injected services and passes simulator tests without changing production infrastructure.

**Architecture:** Add a deterministic XcodeGen project under ios. SwiftUI owns camera/photo selection, localization, bounded image processing, state, and presentation; a protocol-backed API client owns HTTPS transport; strict decoding preserves the existing FastAPI contract without duplicating Python scoring.

**Tech Stack:** Xcode 26.6, iOS 26.5 SDK, Swift 6, SwiftUI, PhotosUI, AVFoundation, UIKit, URLSession, XCTest, XCUITest, XcodeGen 2.45.4

---

## Execution boundary

This is plan 1 of 3. It creates and tests the native client. It does not
mutate Cloud Run, rotate credentials, create an App Store Connect record,
archive for distribution, or upload a build.

Execute from an isolated worktree created through the using-git-worktrees
skill. Preserve unrelated changes and stage only named files. The design source
is docs/superpowers/specs/2026-08-08-ios-testflight-design.md.

Verified local baseline:

- Xcode 26.6, build 17F113
- iOS SDK 26.5
- iPhone 17 Pro simulator on iOS 26.5
- XcodeGen 2.45.4 at /opt/homebrew/bin/xcodegen
- Apple team YMUG864233 has valid Development and Distribution identities

## File map

- ios/project.yml: deterministic project, targets, scheme, and build settings.
- ios/Configuration/*.xcconfig: non-secret API origin.
- ios/Kalories/App: dependency composition and root routing.
- ios/Kalories/Models: Codable contract and strict validation.
- ios/Kalories/Services: API, image processing, locale, and configuration.
- ios/Kalories/Features: capture, analysis, and result UI.
- ios/Kalories/Resources: generated localized strings and Info.plist.
- ios/Kalories/Assets.xcassets: accent and app icon.
- ios/Kalories/PrivacyInfo.xcprivacy: required-reason declaration.
- ios/KaloriesTests and ios/KaloriesUITests: automated native evidence.
- scripts/generate-ios-localizations.ts: reproducible native strings.

### Task 1: Scaffold the deterministic native project

**Files:**
- Create: ios/project.yml
- Create: ios/Configuration/Debug.xcconfig
- Create: ios/Configuration/Release.xcconfig
- Create: ios/Kalories/App/KaloriesApp.swift
- Create: ios/KaloriesTests/AppIdentityTests.swift
- Generate: ios/Kalories.xcodeproj/**

- [ ] **Step 1: Confirm the target is absent**

Run:

~~~bash
test ! -d ios/Kalories.xcodeproj
~~~

Expected: exit 0. If it exists, stop and inspect instead of overwriting it.

- [ ] **Step 2: Create ios/project.yml**

~~~yaml
name: Kalories
options:
  minimumXcodeGenVersion: 2.45.4
  deploymentTarget:
    iOS: "17.0"
configs:
  Debug: debug
  Release: release
settings:
  base:
    DEVELOPMENT_TEAM: YMUG864233
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    MARKETING_VERSION: "1.0.0"
    CURRENT_PROJECT_VERSION: "1"
    IPHONEOS_DEPLOYMENT_TARGET: "17.0"
    TARGETED_DEVICE_FAMILY: "1"
    SUPPORTS_MACCATALYST: NO
    SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO
targets:
  Kalories:
    type: application
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: Kalories
    configFiles:
      Debug: Configuration/Debug.xcconfig
      Release: Configuration/Release.xcconfig
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.ryuaistudio.kalories
        PRODUCT_NAME: Kalories
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        GENERATE_INFOPLIST_FILE: NO
    info:
      path: Kalories/Resources/Info.plist
      properties:
        CFBundleDisplayName: カロスキャン
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        LSRequiresIPhoneOS: true
        NSCameraUsageDescription: 食事を撮影し、カロリーと栄養を推定するためにカメラを使用します。
        KaloriesAPIScheme: $(KALORIES_API_SCHEME)
        KaloriesAPIHost: $(KALORIES_API_HOST)
        UIApplicationSceneManifest:
          UIApplicationSupportsMultipleScenes: false
        UILaunchScreen: {}
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
        NSAppTransportSecurity:
          NSAllowsLocalNetworking: true
    scheme:
      testTargets:
        - KaloriesTests
        - KaloriesUITests
      gatherCoverageData: true
  KaloriesTests:
    type: bundle.unit-test
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: KaloriesTests
    resources:
      - path: ../tests/fixtures/canonical_analysis_result.json
    dependencies:
      - target: Kalories
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.ryuaistudio.kalories.tests
  KaloriesUITests:
    type: bundle.ui-testing
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: KaloriesUITests
    dependencies:
      - target: Kalories
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.ryuaistudio.kalories.uitests
~~~

- [ ] **Step 3: Create non-secret configuration**

~~~xcconfig
// ios/Configuration/Debug.xcconfig
KALORIES_API_SCHEME = https
KALORIES_API_HOST = kalories-sxielk4wua-an.a.run.app
SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) DEBUG
~~~

~~~xcconfig
// ios/Configuration/Release.xcconfig
KALORIES_API_SCHEME = https
KALORIES_API_HOST = kalories-sxielk4wua-an.a.run.app
~~~

- [ ] **Step 4: Add the smallest compiling app and failing identity test**

KaloriesApp.swift:

~~~swift
import SwiftUI

@main
struct KaloriesApp: App {
    var body: some Scene {
        WindowGroup {
            Text("カロスキャン")
                .accessibilityIdentifier("app.title")
        }
    }
}
~~~

AppIdentityTests.swift:

~~~swift
import XCTest
@testable import Kalories

final class AppIdentityTests: XCTestCase {
    func testInfoPlistIdentity() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.ryuaistudio.kalories")
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            "カロスキャン"
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "KaloriesAPIHost") as? String,
            "kalories-sxielk4wua-an.a.run.app"
        )
    }
}
~~~

- [ ] **Step 5: Generate and test**

~~~bash
xcodegen generate --spec ios/project.yml --project ios
xcodebuild -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  test
~~~

Expected: TEST SUCCEEDED and AppIdentityTests passes. If Bundle.main resolves
to the test bundle in this Xcode runtime, move the identity assertion to an
XCUIApplication test; never weaken the production build settings.

- [ ] **Step 6: Commit**

~~~bash
git add ios/project.yml ios/Configuration ios/Kalories.xcodeproj ios/Kalories/App/KaloriesApp.swift ios/Kalories/Resources/Info.plist ios/KaloriesTests/AppIdentityTests.swift
git commit -m "feat(ios): scaffold native Kalories app"
~~~

### Task 2: Define and strictly validate the API contract

**Files:**
- Create: ios/Kalories/Models/AnalysisModels.swift
- Create: ios/Kalories/Models/StrictAnalysisDecoder.swift
- Create: ios/KaloriesTests/AnalysisContractTests.swift

- [ ] **Step 1: Write failing contract tests**

The test loads canonical_analysis_result.json from the test bundle and asserts:

~~~swift
let result = try StrictAnalysisDecoder().decode(canonicalData)
XCTAssertTrue(result.foodDetected)
XCTAssertEqual(result.foodNames?.ja, "焼き鮭定食")
XCTAssertEqual(result.assessment.score, 64)
XCTAssertEqual(result.assessment.tier, .mostlyBalanced)
XCTAssertEqual(result.assessment.suggestionKeys, [.reduceSauce, .adjustStaple])
XCTAssertEqual(result.nutrients.sodiumMg, 980)
~~~

Add three mutations and assert AnalysisContractError:

1. extra root key unexpected;
2. score 79 with tier balanced;
3. no-food response with any non-null nutrient.

- [ ] **Step 2: Run to verify failure**

~~~bash
xcodebuild -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:KaloriesTests/AnalysisContractTests \
  test
~~~

Expected: compilation failure because the models and decoder do not exist.

- [ ] **Step 3: Implement the closed model surface**

AnalysisModels.swift must define these exact raw-value enums:

~~~swift
enum ConfidenceLevel: String, Codable, CaseIterable, Sendable { case low, medium, high }
enum NutrientStatus: String, Codable, CaseIterable, Sendable { case low, appropriate, high, indeterminate }
enum AssessmentTier: String, Codable, CaseIterable, Sendable {
    case balanced
    case mostlyBalanced = "mostly_balanced"
    case needsAttention = "needs_attention"
    case indeterminate
}
enum AssumptionKey: String, Codable, CaseIterable, Sendable {
    case visiblePortionOnly = "visible_portion_only"
    case portionEstimated = "portion_estimated"
    case seasoningEstimated = "seasoning_estimated"
    case hiddenIngredientsPossible = "hidden_ingredients_possible"
}
enum SuggestionKey: String, Codable, CaseIterable, Sendable {
    case addVegetables = "add_vegetables"
    case reduceSauce = "reduce_sauce"
    case reduceSweetItems = "reduce_sweet_items"
    case reduceFat = "reduce_fat"
    case addProtein = "add_protein"
    case adjustStaple = "adjust_staple"
    case reducePortion = "reduce_portion"
}
enum ScoringReason: String, Codable, CaseIterable, Sendable {
    case caloriesLow = "calories_low", caloriesHigh = "calories_high"
    case proteinLow = "protein_g_low", proteinHigh = "protein_g_high"
    case carbsLow = "carbs_g_low", carbsHigh = "carbs_g_high"
    case fatLow = "fat_g_low", fatHigh = "fat_g_high"
    case fiberLow = "fiber_low", sugarHigh = "sugar_high"
    case sodiumElevated = "sodium_elevated", sodiumHigh = "sodium_high"
}
enum NutrientKey: String, CaseIterable, Sendable {
    case caloriesKcal = "calories_kcal", proteinG = "protein_g"
    case carbsG = "carbs_g", fatG = "fat_g", fiberG = "fiber_g"
    case sugarG = "sugar_g", sodiumMg = "sodium_mg"
}
~~~

Define Codable, Equatable, Sendable structs FoodNames, NutrientValues,
NutrientConfidence, Confidence, NutrientStatuses, Assessment, and AnalysisResult.
Use CodingKeys for every snake_case field. NutrientValues and NutrientStatuses
must provide an exhaustive NutrientKey subscript.

- [ ] **Step 4: Implement StrictAnalysisDecoder**

Before JSONDecoder, JSONSerialization must enforce these exact key sets:

~~~swift
let root = Set(["food_detected","food_names","portion_grams","nutrients","confidence","assumption_keys","assessment"])
let nutrientKeys = Set(NutrientKey.allCases.map(\.rawValue))
let confidenceKeys = Set(["overall","portion","nutrients"])
let assessmentKeys = Set(["score","tier","statuses","suggestion_keys","scoring_reasons","insufficient_data"])
~~~

Then validate:

- portion 0 through 10,000;
- calories 0 through 10,000;
- every gram nutrient 0 through 2,000;
- sodium 0 through 100,000;
- finite numbers only;
- trimmed food names 1 through 120 characters;
- unique assumptions, maximum 4;
- unique suggestions, maximum 2;
- unique scoring reasons, maximum 7;
- normalized no-food values;
- macro status coherence;
- score availability requires calories, all macros, positive macro energy, and
  medium/high overall confidence;
- tier is balanced at 80+, mostly balanced at 60-79, otherwise needs attention;
- unavailable score requires indeterminate tier and insufficient_data true.

Use errors not assertions:

~~~swift
enum AnalysisContractError: Error, Equatable {
    case notJSONObject, unexpectedKeys, invalidValue, incoherentAssessment
}
~~~

- [ ] **Step 5: Pass focused and full tests**

Run the Task 2 command, then the full Task 1 xcodebuild test command.

Expected: both succeed and the shared canonical fixture remains score 64.

- [ ] **Step 6: Commit**

~~~bash
git add ios/Kalories/Models ios/KaloriesTests/AnalysisContractTests.swift ios/Kalories.xcodeproj
git commit -m "feat(ios): add strict analysis contract"
~~~

### Task 3: Add cancellable HTTPS transport

**Files:**
- Create: ios/Kalories/Services/AppConfiguration.swift
- Create: ios/Kalories/Services/AnalysisAPIClient.swift
- Create: ios/KaloriesTests/AnalysisAPIClientTests.swift
- Create: ios/KaloriesTests/URLProtocolStub.swift

- [ ] **Step 1: Write failing URLProtocol tests**

Cover POST /api/analyze, application/json, canonical success, INVALID_IMAGE,
RATE_LIMITED, SERVICE_NOT_CONFIGURED, malformed 200 JSON, URLError.timedOut,
and cancellation. URLProtocolStub must clear its synchronized handler in
tearDown so tests cannot leak state.

- [ ] **Step 2: Run and verify missing symbols**

Use the Task 2 command with
-only-testing:KaloriesTests/AnalysisAPIClientTests.

Expected: compilation fails for AnalysisAPIClient and AppFailure.

- [ ] **Step 3: Implement configuration and stable errors**

~~~swift
struct AppConfiguration: Sendable {
    let apiBaseURL: URL

    static func from(bundle: Bundle = .main) throws -> AppConfiguration {
        guard
            let scheme = bundle.object(forInfoDictionaryKey: "KaloriesAPIScheme") as? String,
            let host = bundle.object(forInfoDictionaryKey: "KaloriesAPIHost") as? String,
            scheme == "https",
            let url = URL(string: "\(scheme)://\(host)")
        else { throw AppFailure.invalidConfiguration }
        return AppConfiguration(apiBaseURL: url)
    }
}

enum AppFailure: Error, Equatable, Sendable {
    case cameraDenied, captureFailed, invalidImage, unsupportedImage
    case imageTooLarge, noFood, serviceNotConfigured, analysisFailed
    case network, timeout, rateLimited, malformedResponse, invalidConfiguration
}

protocol AnalysisServing: Sendable {
    func analyze(dataURI: String) async throws -> AnalysisResult
}
~~~

- [ ] **Step 4: Implement AnalysisAPIClient**

Use an actor with injected URLSession, 25-second URLRequest timeout, no request
logging, and StrictAnalysisDecoder. Map backend codes exactly:

~~~swift
private static func map(code: String?, status: Int) -> AppFailure {
    switch code {
    case "INVALID_IMAGE": .invalidImage
    case "UNSUPPORTED_IMAGE": .unsupportedImage
    case "IMAGE_TOO_LARGE": .imageTooLarge
    case "SERVICE_NOT_CONFIGURED": .serviceNotConfigured
    case "RATE_LIMITED": .rateLimited
    case "ANALYSIS_FAILED": .analysisFailed
    default: status == 429 ? .rateLimited : .analysisFailed
    }
}
~~~

Rethrow CancellationError, map URLError.timedOut to timeout, other transport
errors to network, and any 2xx contract failure to malformedResponse.

- [ ] **Step 5: Pass focused and full tests**

Expected: all tests pass and no test reaches the live service.

- [ ] **Step 6: Commit**

~~~bash
git add ios/Kalories/Services/AppConfiguration.swift ios/Kalories/Services/AnalysisAPIClient.swift ios/KaloriesTests/AnalysisAPIClientTests.swift ios/KaloriesTests/URLProtocolStub.swift ios/Kalories.xcodeproj
git commit -m "feat(ios): add analysis API client"
~~~

### Task 4: Add orientation-safe bounded image processing

**Files:**
- Create: ios/Kalories/Services/ImageProcessor.swift
- Create: ios/KaloriesTests/ImageProcessorTests.swift

- [ ] **Step 1: Write failing tests**

Generate UIImages in memory. Assert a 4000x3000 image is redrawn to at most
2048 pixels, output starts with the JPEG signature after base64 decoding, and
decoded bytes are at most 3 MiB. Inject an encoder returning 3 MiB plus one byte
and expect imageTooLarge. UIImage() must return invalidImage.

- [ ] **Step 2: Run and verify failure**

Run only KaloriesTests/ImageProcessorTests. Expected: missing ImageProcessor.

- [ ] **Step 3: Implement ImageProcessor**

~~~swift
protocol ImageProcessing {
    @MainActor func dataURI(for image: UIImage) throws -> String
}

struct ImageProcessor: ImageProcessing {
    static let maximumBytes = 3 * 1024 * 1024
    static let maximumDimension: CGFloat = 2048
    var encoder: (UIImage, CGFloat) -> Data? = {
        $0.jpegData(compressionQuality: $1)
    }

    @MainActor
    func dataURI(for image: UIImage) throws -> String {
        guard image.size.width > 0, image.size.height > 0 else {
            throw AppFailure.invalidImage
        }
        var dimension = Self.maximumDimension
        while dimension >= 768 {
            let normalized = redraw(image, maximumDimension: dimension)
            for quality in [0.85, 0.75, 0.65, 0.55, 0.45, 0.35, 0.25] {
                guard let data = encoder(normalized, quality) else {
                    throw AppFailure.invalidImage
                }
                if data.count <= Self.maximumBytes {
                    return "data:image/jpeg;base64," + data.base64EncodedString()
                }
            }
            dimension *= 0.75
        }
        throw AppFailure.imageTooLarge
    }

    @MainActor
    private func redraw(_ image: UIImage, maximumDimension: CGFloat) -> UIImage {
        let scale = min(1, maximumDimension / max(image.size.width, image.size.height))
        let size = CGSize(
            width: max(1, floor(image.size.width * scale)),
            height: max(1, floor(image.size.height * scale))
        )
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
~~~

Redrawing through UIKit normalizes orientation; do not preserve photo metadata.

- [ ] **Step 4: Pass focused and full tests**

Expected: all image and full iOS tests pass; no generated image is written.

- [ ] **Step 5: Commit**

~~~bash
git add ios/Kalories/Services/ImageProcessor.swift ios/KaloriesTests/ImageProcessorTests.swift ios/Kalories.xcodeproj
git commit -m "feat(ios): add bounded meal image processing"
~~~

### Task 5: Generate native localization from the existing dictionaries

**Files:**
- Create: scripts/generate-ios-localizations.ts
- Modify: package.json
- Create: ios/Kalories/Resources/{ja,zh-Hans,en}.lproj/Localizable.strings
- Create: matching InfoPlist.strings
- Create: ios/Kalories/Services/AppLocalizer.swift
- Create: ios/KaloriesTests/AppLocalizerTests.swift

- [ ] **Step 1: Write failing resolution and lookup tests**

Test saved-locale precedence, zh-Hans and en-US device resolution, Japanese
fallback, all three app-name lookups, and native camera permission text without
the web-only word ブラウザ.

- [ ] **Step 2: Create the generator**

Import messages from src/i18n.ts. Override appName with カロスキャン. Override
native permission wording. Add these exact keys:

~~~typescript
const native = {
  zh: {
    choosePhoto: '从照片中选择',
    analyzePhoto: '分析这张照片',
    cancel: '取消',
    openSettings: '打开设置',
    privacyPolicy: '隐私政策',
    support: '支持',
    consentNotice: '点击分析后，照片将发送至 Kalories 服务和 Gemini，仅用于本次食物分析。',
    errorRateLimited: '请求过于频繁，请稍后再试。',
    errorTimeout: '分析超时，请重试。'
  },
  ja: {
    choosePhoto: '写真から選ぶ',
    analyzePhoto: 'この写真を分析',
    cancel: 'キャンセル',
    openSettings: '設定を開く',
    privacyPolicy: 'プライバシーポリシー',
    support: 'サポート',
    consentNotice: '分析を開始すると、写真は今回の食事分析のために Kalories サービスと Gemini へ送信されます。',
    errorRateLimited: 'リクエストが多すぎます。少し待ってからお試しください。',
    errorTimeout: '分析がタイムアウトしました。もう一度お試しください。'
  },
  en: {
    choosePhoto: 'Choose a photo',
    analyzePhoto: 'Analyze this photo',
    cancel: 'Cancel',
    openSettings: 'Open Settings',
    privacyPolicy: 'Privacy Policy',
    support: 'Support',
    consentNotice: 'When you analyze, the photo is sent to the Kalories service and Gemini only for this meal analysis.',
    errorRateLimited: 'Too many requests. Try again shortly.',
    errorTimeout: 'Analysis timed out. Please try again.'
  }
} as const;
~~~

The script key-sorts output, escapes quotes/backslashes, writes UTF-8 .strings,
writes localized NSCameraUsageDescription, and supports --check by comparing
generated bytes with committed files and exiting 1 on drift.

Add package scripts:

~~~json
"ios:localizations": "tsx scripts/generate-ios-localizations.ts",
"ios:localizations:check": "tsx scripts/generate-ios-localizations.ts --check"
~~~

No dependency or lockfile change is expected.

- [ ] **Step 3: Implement locale resolution**

~~~swift
enum AppLocale: String, CaseIterable, Identifiable, Sendable {
    case ja, zh, en
    var id: String { rawValue }
    var bundleName: String { self == .zh ? "zh-Hans" : rawValue }

    static func resolve(saved: String?, preferred: [String]) -> AppLocale {
        if let saved, let locale = AppLocale(rawValue: saved) { return locale }
        for value in preferred {
            let base = value.lowercased().split(separator: "-").first.map(String.init)
            if let base, let locale = AppLocale(rawValue: base) { return locale }
        }
        return .ja
    }
}

struct AppLocalizer: Sendable {
    let locale: AppLocale
    func text(_ key: String) -> String {
        guard
            let path = Bundle.main.path(forResource: locale.bundleName, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
~~~

Persist only kalories.locale in app-only UserDefaults.

- [ ] **Step 4: Generate, check, and test**

~~~bash
npm run ios:localizations
npm run ios:localizations:check
xcodegen generate --spec ios/project.yml --project ios
xcodebuild -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:KaloriesTests/AppLocalizerTests \
  test
~~~

Expected: generation check and tests pass.

- [ ] **Step 5: Commit**

~~~bash
git add scripts/generate-ios-localizations.ts package.json ios/Kalories/Resources ios/Kalories/Services/AppLocalizer.swift ios/KaloriesTests/AppLocalizerTests.swift ios/Kalories.xcodeproj
git commit -m "feat(ios): add native localization"
~~~

### Task 6: Implement the app-flow state machine

**Files:**
- Create: ios/Kalories/Features/Analysis/AppFlowModel.swift
- Create: ios/KaloriesTests/AppFlowModelTests.swift

- [ ] **Step 1: Write failing state tests**

Mock AnalysisServing and ImageProcessing. Cover image selection, analyzing,
success, normalized no-food, retry with the same image, retake clearing memory,
network/timeout/rate-limit/malformed errors, and cancellation without a new
visible error.

- [ ] **Step 2: Verify failure**

Run only AppFlowModelTests. Expected: missing AppFlowModel and AppScreen.

- [ ] **Step 3: Implement the state machine**

~~~swift
enum AppScreen {
    case capture, preview, analyzing
    case result(AnalysisResult)
    case failure(AppFailure)
}

@MainActor
@Observable
final class AppFlowModel {
    private(set) var screen: AppScreen = .capture
    private(set) var selectedImage: UIImage?
    private var analysisTask: Task<Void, Never>?
    private let service: any AnalysisServing
    private let processor: any ImageProcessing

    init(service: any AnalysisServing, processor: any ImageProcessing) {
        self.service = service
        self.processor = processor
    }

    func select(_ image: UIImage) {
        selectedImage = image
        screen = .preview
    }

    func analyze() {
        guard let image = selectedImage else {
            screen = .failure(.invalidImage)
            return
        }
        analysisTask?.cancel()
        screen = .analyzing
        analysisTask = Task { [weak self] in
            guard let self else { return }
            do {
                let dataURI = try processor.dataURI(for: image)
                let result = try await service.analyze(dataURI: dataURI)
                try Task.checkCancellation()
                screen = result.foodDetected ? .result(result) : .failure(.noFood)
            } catch is CancellationError {
                return
            } catch let failure as AppFailure {
                screen = .failure(failure)
            } catch {
                screen = .failure(.analysisFailed)
            }
        }
    }

    func retry() { analyze() }
    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        screen = selectedImage == nil ? .capture : .preview
    }
    func retake() {
        analysisTask?.cancel()
        analysisTask = nil
        selectedImage = nil
        screen = .capture
    }
}
~~~

- [ ] **Step 4: Pass normal and Thread Sanitizer runs**

~~~bash
xcodebuild -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -enableThreadSanitizer YES \
  -only-testing:KaloriesTests/AppFlowModelTests \
  test
~~~

Expected: tests pass with no sanitizer finding.

- [ ] **Step 5: Commit**

~~~bash
git add ios/Kalories/Features/Analysis/AppFlowModel.swift ios/KaloriesTests/AppFlowModelTests.swift ios/Kalories.xcodeproj
git commit -m "feat(ios): add analysis flow state"
~~~

### Task 7: Build native capture, preview, and analyzing UI

**Files:**
- Create: ios/Kalories/App/AppEnvironment.swift
- Create: ios/Kalories/App/RootView.swift
- Modify: ios/Kalories/App/KaloriesApp.swift
- Create: ios/Kalories/Features/Capture/CaptureView.swift
- Create: ios/Kalories/Features/Capture/CameraPicker.swift
- Create: ios/Kalories/Features/Capture/CameraAuthorizationService.swift
- Create: ios/Kalories/Features/Analysis/AnalyzingView.swift
- Create: ios/KaloriesTests/CameraAuthorizationTests.swift

- [ ] **Step 1: Write failing authorization tests**

Inject authorized, denied, and notDetermined. Denied maps to cameraDenied;
requestAccess result is honored; CameraPicker is never presented on denial.

- [ ] **Step 2: Implement native capture adapters**

CameraAuthorizationService wraps only AVCaptureDevice authorizationStatus and
requestAccess for video. CameraPicker wraps UIImagePickerController with camera
source, emits one completion, and dismisses on cancel. PhotosPicker loads one
image and never requests broad library access.

- [ ] **Step 3: Implement explicit-consent preview**

CaptureView must include:

- capture.camera button;
- capture.library PhotosPicker;
- scaled-to-fit preview;
- localized consentNotice;
- capture.analyze button as the only analysis trigger;
- cancel/retake without upload;
- privacy and support links at the verified production origin.

Unreadable data maps to captureFailed. It is never written to disk.

- [ ] **Step 4: Compose dependencies and root state**

AppEnvironment.live validates AppConfiguration and creates one
AnalysisAPIClient, ImageProcessor, and AppFlowModel. RootView switches
exhaustively over AppScreen. AnalyzingView has a cancel button and does not
start work from body rerenders.

- [ ] **Step 5: Build and test**

Regenerate the project and run the full simulator suite.

Expected: TEST SUCCEEDED, no camera crash on simulator, photo picker available.

- [ ] **Step 6: Commit**

~~~bash
git add ios/Kalories/App ios/Kalories/Features/Capture ios/Kalories/Features/Analysis/AnalyzingView.swift ios/KaloriesTests/CameraAuthorizationTests.swift ios/Kalories.xcodeproj
git commit -m "feat(ios): add native meal capture flow"
~~~

### Task 8: Build the deterministic result screen

**Files:**
- Create: ios/Kalories/Features/Result/ResultPresenter.swift
- Create: ios/Kalories/Features/Result/ResultView.swift
- Create: ios/Kalories/Features/Result/NutritionMetricView.swift
- Create: ios/Kalories/Features/Result/ScoreCard.swift
- Create: ios/KaloriesTests/ResultPresenterTests.swift

- [ ] **Step 1: Write failing canonical presentation tests**

Assert Japanese name 焼き鮭定食, score 64, tier おおむね良好, eight numeric
strings, all confidence labels, strongest positive エネルギー · 適量, concern
ナトリウム · 多め, two suggestions, and disclaimer. Set sugar null and assert
an em dash, not 0 g. Set score null and assert no /100.

- [ ] **Step 2: Implement pure presenter rules**

Use stable priorities:

~~~swift
let positivePriority: [NutrientKey] = [
    .proteinG, .carbsG, .fatG, .fiberG, .caloriesKcal, .sugarG, .sodiumMg
]
let concernPriority: [NutrientKey] = [
    .sodiumMg, .sugarG, .caloriesKcal, .proteinG, .carbsG, .fatG, .fiberG
]
~~~

A positive requires appropriate status and medium/high field confidence. A
concern requires low/high status. Unknown raw strings can never reach UI because
decoding is closed. Advice is limited to two known keys. NumberFormatter uses
at most one fraction digit.

- [ ] **Step 3: Implement one continuous accessible ResultView**

Use one ScrollView ordered as: image/name/confidence, score, findings, calories,
macros, secondary nutrients/portion, advice, assumptions, disclaimer/reference,
retake. Use no TabView, sheet, DisclosureGroup, or second route. Every status
has text and symbol; color is supplementary. Use Dynamic Type and at least
44-point targets. Add stable identifiers result.page and result.retake.

- [ ] **Step 4: Pass focused and full tests**

Expected: presenter and full suites pass. Record Accessibility Inspector as
manual evidence; if not run, mark SKIPPED rather than PASS.

- [ ] **Step 5: Commit**

~~~bash
git add ios/Kalories/Features/Result ios/KaloriesTests/ResultPresenterTests.swift ios/Kalories.xcodeproj
git commit -m "feat(ios): add nutrition result experience"
~~~

### Task 9: Add DEBUG-only fixtures and XCUITest

**Files:**
- Modify: ios/Kalories/App/AppEnvironment.swift
- Create: ios/Kalories/App/UITestFixtures.swift
- Create: ios/KaloriesUITests/KaloriesFlowUITests.swift

- [ ] **Step 1: Write failing UI tests**

Success launches with --ui-testing --fixture-success, taps capture.fixture,
taps capture.analyze, waits for result.page, and asserts 焼き鮭定食, 64,
おおむね良好, disclaimer, and result.retake.

Retry launches with --ui-testing --fixture-timeout, reaches error.timeout, taps
error.retry, then reaches result.page.

- [ ] **Step 2: Run and verify failure**

~~~bash
xcodebuild -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:KaloriesUITests/KaloriesFlowUITests \
  test
~~~

Expected: failure because fixture support is absent.

- [ ] **Step 3: Add DEBUG-only fixtures**

Under #if DEBUG, expose capture.fixture only for --ui-testing. The success
fixture contains the canonical salmon values and score 64. The timeout service
fails once then succeeds. Release code must not inspect UI-test arguments
because the fixture implementation is excluded from Release compilation.

- [ ] **Step 4: Pass UI tests twice**

Run the Task 9 command twice. Both runs must pass with no live network request.

- [ ] **Step 5: Commit**

~~~bash
git add ios/Kalories/App/AppEnvironment.swift ios/Kalories/App/UITestFixtures.swift ios/KaloriesUITests/KaloriesFlowUITests.swift ios/Kalories.xcodeproj
git commit -m "test(ios): cover native analysis flow"
~~~

### Task 10: Add privacy manifest, app icon, and local release gate

**Files:**
- Create: ios/Kalories/PrivacyInfo.xcprivacy
- Create: ios/Kalories/Assets.xcassets/Contents.json
- Create: ios/Kalories/Assets.xcassets/AccentColor.colorset/Contents.json
- Create: ios/Kalories/Assets.xcassets/AppIcon.appiconset/Contents.json
- Create: ios/Kalories/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
- Modify: README.md

- [ ] **Step 1: Add PrivacyInfo.xcprivacy**

~~~xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>NSPrivacyTracking</key><false/>
  <key>NSPrivacyTrackingDomains</key><array/>
  <key>NSPrivacyCollectedDataTypes</key><array/>
  <key>NSPrivacyAccessedAPITypes</key><array><dict>
    <key>NSPrivacyAccessedAPIType</key>
    <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
    <key>NSPrivacyAccessedAPITypeReasons</key>
    <array><string>CA92.1</string></array>
  </dict></array>
</dict></plist>
~~~

The empty collection declaration is valid only after plan 2 verifies that the
paid provider retains no image beyond real-time processing. Otherwise stop and
update the manifest and App Store privacy answers.

- [ ] **Step 2: Generate the icon with the imagegen skill**

Use this exact prompt:

~~~text
Create a production iOS app icon, exactly square, no text, no letters, no numbers, no transparency, no rounded-corner mask. A vivid persimmon-orange background with a centered minimal white plate that also reads as a camera lens; one small dark-green nutrition gauge tick at the upper-right of the plate. Calm Japanese utility-app character, bold silhouette readable at 40 px, flat vector-like shapes, high contrast, no gradients, no shadows, no food photograph, no Apple logo.
~~~

Inspect and reject text, alpha, or an embedded rounded mask. Resize the accepted
source to exactly 1024x1024 PNG without using Python. Contents.json declares one
universal iOS 1024x1024 image named AppIcon-1024.png.

- [ ] **Step 3: Validate resources and unsigned Release build**

~~~bash
plutil -lint ios/Kalories/PrivacyInfo.xcprivacy
sips -g pixelWidth -g pixelHeight -g hasAlpha ios/Kalories/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
xcodegen generate --spec ios/project.yml --project ios
xcodebuild -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
~~~

Expected: plist OK; icon 1024x1024 with hasAlpha no; BUILD SUCCEEDED with no
missing-icon warning.

- [ ] **Step 4: Run the complete local gate**

~~~bash
npm test
npm run lint
npm run build
npm run ios:localizations:check
.venv/bin/python -m unittest discover -s tests -p 'test_*.py' -v
.venv/bin/python -m compileall -q api lib tests
.venv/bin/python -c "import api.analyze, lib.nutrition"
uv pip check --python .venv/bin/python
xcodebuild -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  test
git diff --check
git status --short --branch
~~~

Expected: at least 111 frontend and 61 backend tests pass; every iOS test,
TypeScript/build/import/dependency check passes; diff check is silent; only
intended files are modified.

- [ ] **Step 5: Document and commit**

Document XcodeGen, localization generation, simulator tests, non-secret API
configuration, permission/privacy boundaries, and the statement that local
success is not TestFlight success.

~~~bash
git add ios README.md scripts/generate-ios-localizations.ts package.json
git commit -m "feat(ios): complete native TestFlight client"
git status --short --branch
~~~

Expected: clean worktree. Do not push or begin production changes in this plan.

## Plan 1 completion gate

Complete only when the project is reproducible from ios/project.yml, all
existing and native tests pass, the unsigned generic Release build succeeds,
assets/privacy resources validate, the diff is reviewed, and Git status is
clean. Archive, signing, live-provider, device, and TestFlight gates remain
unverified until plans 2 and 3.
