import XCTest
@testable import Kalories

final class AppIdentityTests: XCTestCase {
    func testInfoPlistIdentity() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.ryuaistudio.kalories")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "カロスキャン")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "KaloriesAPIHost") as? String, "kalories-sxielk4wua-an.a.run.app")
    }
}
