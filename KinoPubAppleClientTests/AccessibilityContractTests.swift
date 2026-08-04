import XCTest
@testable import KinoPub

final class AccessibilityContractTests: XCTestCase {
  func testPhaseZeroScreenStateIdentifiersAreStableAndUnique() {
    let identifiers = [
      AccessibilityID.authScreen,
      AccessibilityID.authLoading,
      AccessibilityID.authCode,
      AccessibilityID.authActivation,
      AccessibilityID.homeScreen,
      AccessibilityID.homeLoading,
      AccessibilityID.detailScreen,
      AccessibilityID.bookmarkPicker,
      AccessibilityID.playerError
    ]

    XCTAssertEqual(Set(identifiers).count, identifiers.count)
    XCTAssertEqual(AccessibilityID.authScreen, "auth.screen")
    XCTAssertEqual(AccessibilityID.homeScreen, "home.screen")
    XCTAssertEqual(AccessibilityID.detailScreen, "detail.screen")
    XCTAssertEqual(AccessibilityID.playerError, "player.error")
  }
}
