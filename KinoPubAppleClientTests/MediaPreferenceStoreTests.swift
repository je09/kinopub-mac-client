//
//  MediaPreferenceStoreTests.swift
//  KinoPubAppleClientTests
//
//  Phase 6: device-scoped playback preferences (quality + 3D mode) persist through the injected
//  UserDefaults suite, and the defaults match the legacy keys. Audio/subtitle live in the
//  library snapshot and are covered by LibraryRepositoryTests.
//

import XCTest
@testable import KinoPub

@MainActor
final class MediaPreferenceStoreTests: XCTestCase {
  private var suite: UserDefaults!
  private var suiteName = ""

  override func setUp() {
    super.setUp()
    suiteName = "MediaPreferenceStoreTests-\(UUID().uuidString)"
    suite = UserDefaults(suiteName: suiteName)
    suite.removePersistentDomain(forName: suiteName)
  }

  override func tearDown() {
    suite?.removePersistentDomain(forName: suiteName)
    super.tearDown()
  }

  private func makeStore(libraryState: LibraryViewState? = nil) -> MediaPreferenceStore {
    MediaPreferenceStore(
      libraryState: libraryState ?? AppDependencies.preview().libraryState,
      defaults: suite)
  }

  func testStreamQualityDefaultsToAuto() {
    XCTAssertEqual(makeStore().streamQuality, .auto)
  }

  func testStreamQualityRoundTrips() {
    var store = makeStore()
    store.streamQuality = .hd720
    XCTAssertEqual(store.streamQuality, .hd720)
    // Persisted under the legacy key so the settings screen and player agree.
    XCTAssertEqual(suite.string(forKey: StreamQuality.userDefaultsKey), StreamQuality.hd720.rawValue)
  }

  func testInvalidStreamQualityRawValueFallsBackToAuto() {
    suite.set("not-a-quality", forKey: StreamQuality.userDefaultsKey)
    XCTAssertEqual(makeStore().streamQuality, .auto)
  }

  func testThreeDModeDefaultsToSideBySideMono() {
    XCTAssertEqual(makeStore().preferredThreeDMode, .sbsMono)
  }

  func testThreeDModeRoundTrips() {
    var store = makeStore()
    store.preferredThreeDMode = .ouAnaglyph
    XCTAssertEqual(store.preferredThreeDMode, .ouAnaglyph)
    XCTAssertEqual(suite.string(forKey: MediaPreferenceStore.threeDModeKey), ThreeDMode.ouAnaglyph.rawValue)
  }

  func testStaticThreeDModeAccessorsShareTheKey() {
    MediaPreferenceStore.setPreferredThreeDMode(.sbsAnaglyph, in: suite)
    XCTAssertEqual(MediaPreferenceStore.preferredThreeDMode(in: suite), .sbsAnaglyph)
  }
}
