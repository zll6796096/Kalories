import Foundation
import XCTest
@testable import Kalories

final class AppLocalizerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "com.ryuaistudio.kalories.tests.AppLocalizer.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testValidSavedLocaleWinsOverPreferredDeviceLocales() {
        XCTAssertEqual(AppLocale.resolve(saved: " zh ", preferred: ["ja-JP", "en-US"]), .zh)
    }

    func testInvalidSavedLocaleFallsThroughToPreferredLocale() {
        XCTAssertEqual(AppLocale.resolve(saved: "fr", preferred: ["en_US", "ja-JP"]), .en)
    }

    func testSupportedPreferredLocaleIdentifiersResolveByBaseLanguage() {
        XCTAssertEqual(AppLocale.resolve(saved: nil, preferred: ["zh-Hans"]), .zh)
        XCTAssertEqual(AppLocale.resolve(saved: nil, preferred: ["en-US"]), .en)
    }

    func testUnsupportedPreferredLocalesFallBackToJapanese() {
        XCTAssertEqual(AppLocale.resolve(saved: nil, preferred: ["fr-FR", "de-DE"]), .ja)
    }

    func testBundleNamesMatchLocalizationDirectories() {
        XCTAssertEqual(AppLocale.ja.bundleName, "ja")
        XCTAssertEqual(AppLocale.zh.bundleName, "zh-Hans")
        XCTAssertEqual(AppLocale.en.bundleName, "en")
    }

    func testAppBundleUsesJapaneseAsDevelopmentLocalization() {
        XCTAssertEqual(Bundle.main.developmentLocalization, "ja")
    }

    func testLocalizedAppNameIsKaroScanInEveryLocale() {
        for locale in AppLocale.allCases {
            XCTAssertEqual(AppLocalizer(locale: locale).text("appName"), "カロスキャン")
        }
    }

    func testInheritedAndNativeKeysMatchGeneratedValuesInEveryLocale() {
        let expected: [(AppLocale, inherited: String, native: String)] = [
            (.zh, "拍摄这一餐", "从照片中选择"),
            (.ja, "食事を撮影", "写真から選ぶ"),
            (.en, "Photograph your meal", "Choose a photo"),
        ]

        for (locale, inherited, native) in expected {
            let localizer = AppLocalizer(locale: locale)
            XCTAssertEqual(localizer.text("cameraTitle"), inherited)
            XCTAssertEqual(localizer.text("choosePhoto"), native)
        }
    }

    func testNativeCameraDenialMessagesUseSettingsWording() {
        let expected: [AppLocale: String] = [
            .zh: "无法使用相机，请在“设置”中允许访问相机。",
            .ja: "カメラを利用できません。「設定」でカメラへのアクセスを許可してください。",
            .en: "Camera access is unavailable. Allow camera access in Settings.",
        ]
        let prohibitedWords = ["浏览器", "ブラウザ", "browser"]

        for locale in AppLocale.allCases {
            let message = AppLocalizer(locale: locale).text("errorCameraDenied")
            XCTAssertEqual(message, expected[locale])
            for word in prohibitedWords {
                XCTAssertFalse(message.localizedCaseInsensitiveContains(word))
            }
        }
    }

    func testAppCheckFailuresHaveOwnedLocalizedMessages() {
        let expected: [AppLocale: (failed: String, unavailable: String)] = [
            .zh: (
                "无法验证此 App，请重新打开后再试。",
                "暂时无法验证 App，请稍后再试。"
            ),
            .ja: (
                "このアプリを確認できませんでした。アプリを開き直してお試しください。",
                "アプリを一時的に確認できません。しばらくしてからお試しください。"
            ),
            .en: (
                "This app could not be verified. Reopen it and try again.",
                "The app cannot be verified right now. Try again shortly."
            ),
        ]

        for locale in AppLocale.allCases {
            let localizer = AppLocalizer(locale: locale)
            XCTAssertEqual(
                localizer.text("errorAppCheckFailed"),
                expected[locale]?.failed
            )
            XCTAssertEqual(
                localizer.text("errorAppCheckUnavailable"),
                expected[locale]?.unavailable
            )
        }
    }

    func testMissingLocalizationKeyReturnsTheKey() {
        XCTAssertEqual(AppLocalizer(locale: .ja).text("missing.localization.key"), "missing.localization.key")
    }

    func testLocalePreferenceRoundTripsSupportedLocalesUsingOnlyAppStorageKey() throws {
        let preference = AppLocalePreference(defaults: defaults)

        for locale in AppLocale.allCases {
            defaults.removePersistentDomain(forName: suiteName)

            preference.save(locale)

            XCTAssertEqual(preference.load(), locale)
            let domain = try XCTUnwrap(defaults.persistentDomain(forName: suiteName))
            XCTAssertEqual(domain.count, 1)
            XCTAssertEqual(domain["kalories.locale"] as? String, locale.rawValue)
        }
    }

    func testLocalizedInfoPlistStringsContainAppNameAndCameraPurpose() throws {
        let expectedCameraPurpose: [AppLocale: String] = [
            .zh: "使用相机拍摄餐食，以估算卡路里和营养。",
            .ja: "食事を撮影し、カロリーと栄養を推定するためにカメラを使用します。",
            .en: "Camera access is used to photograph meals and estimate calories and nutrition.",
        ]

        for locale in AppLocale.allCases {
            let bundle = try localizedBundle(for: locale)
            XCTAssertEqual(
                bundle.localizedString(forKey: "CFBundleDisplayName", value: nil, table: "InfoPlist"),
                "カロスキャン"
            )
            XCTAssertEqual(
                bundle.localizedString(forKey: "NSCameraUsageDescription", value: nil, table: "InfoPlist"),
                expectedCameraPurpose[locale]
            )
        }
    }

    private func localizedBundle(for locale: AppLocale) throws -> Bundle {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: locale.bundleName, ofType: "lproj"),
            "Missing \(locale.bundleName).lproj from the app bundle"
        )
        return try XCTUnwrap(Bundle(path: path))
    }
}
