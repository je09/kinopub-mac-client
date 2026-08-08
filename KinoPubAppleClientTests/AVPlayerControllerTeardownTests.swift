//
//  AVPlayerControllerTeardownTests.swift
//  KinoPubAppleClientTests
//
//  Phase 6: the AVPlayer adapter installs one observer per concern and removes them exactly once
//  on teardown (idempotent). White-box observer counting keeps this deterministic — no reliance
//  on AVPlayer timing. Items are constructed from bogus URLs, so no network or real media is
//  involved.
//

import XCTest
import AVFoundation
import KinoPubBackend
@testable import KinoPub

@MainActor
final class AVPlayerControllerTeardownTests: XCTestCase {
  private var dependencies: AppDependencies!

  override func setUp() {
    super.setUp()
    dependencies = AppDependencies.preview()
  }

  private func makeController() -> AVPlayerController {
    AVPlayerController(preferences: MediaPreferenceStore(libraryState: dependencies.libraryState))
  }

  private func makeSource() -> PlaybackSource {
    PlaybackSource(url: URL(fileURLWithPath: "/tmp/does-not-exist.mp4"), kind: .localFile)
  }

  func testInitInstallsRateObservationAndTimeObserver() {
    let controller = makeController()
    XCTAssertEqual(controller.liveObservationCount, 1)
    XCTAssertNotNil(controller.player)
  }

  func testReplaceItemInstallsItemObservationsAndTeardownRemovesThemExactlyOnce() {
    let controller = makeController()
    controller.replaceItem(
      with: makeSource(),
      itemID: 42,
      is3D: false,
      maxResolution: nil,
      appliesMediaSelection: true)
    // rate + status + audio status + media-selection notification + end-of-playback notification.
    XCTAssertEqual(controller.liveObservationCount, 5)

    controller.teardown()
    XCTAssertEqual(controller.liveObservationCount, 0)

    // Idempotent: a second teardown must not crash and must not re-register anything.
    controller.teardown()
    XCTAssertEqual(controller.liveObservationCount, 0)
  }

  func testReplaceItemWithoutMediaSelectionInstallsFewerObservers() {
    let controller = makeController()
    controller.replaceItem(
      with: makeSource(),
      itemID: 42,
      is3D: false,
      maxResolution: nil,
      appliesMediaSelection: false)
    // rate + status (no audio-status restore, no selection capture, no end-of-playback).
    XCTAssertEqual(controller.liveObservationCount, 2)

    controller.teardown()
    XCTAssertEqual(controller.liveObservationCount, 0)
  }

  func testDetachCurrentItemRemovesItemObservations() {
    let controller = makeController()
    controller.replaceItem(
      with: makeSource(),
      itemID: 42,
      is3D: false,
      maxResolution: nil,
      appliesMediaSelection: true)
    XCTAssertEqual(controller.liveObservationCount, 5)
    controller.detachCurrentItem()
    XCTAssertEqual(controller.liveObservationCount, 1)
    XCTAssertNil(controller.player.currentItem)
  }

  func testFailureDiagnosisDescribesUnknownErrors() {
    let controller = makeController()
    controller.replaceItem(
      with: makeSource(),
      itemID: 42,
      is3D: false,
      maxResolution: nil,
      appliesMediaSelection: true)
    guard let item = controller.player.currentItem else {
      return XCTFail("expected an item")
    }
    let diagnosis = controller.failureDiagnosis(for: item)
    XCTAssertFalse(diagnosis.isForbidden403)
    XCTAssertFalse(diagnosis.message.isEmpty)
  }

  func testSeekWhenReadyWithoutItemDoesNotCrash() {
    let controller = makeController()
    controller.seekWhenReady(to: 30)
    // No item installed: the ready-wait observation is never attached.
    XCTAssertEqual(controller.liveObservationCount, 1)
  }
}
