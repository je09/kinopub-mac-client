//
//  PlaybackSessionTests.swift
//  KinoPubAppleClientTests
//
//  Phase 6: the playback state machine runs without AVPlayer or network. Covers phase
//  transitions (including rejected ones), episode-queue navigation, and the recovery ladder.
//

import XCTest
import KinoPubBackend
@testable import KinoPub

final class PlaybackSessionTests: XCTestCase {
  private let queue = [
    PlaybackTestFixtures.episode(id: 1, number: 1),
    PlaybackTestFixtures.episode(id: 2, number: 2),
    PlaybackTestFixtures.episode(id: 3, number: 3),
  ]

  func testInitialPhaseIsIdle() {
    let session = PlaybackSession(playItem: PlaybackTestItem(id: 1), episodeQueue: [])
    XCTAssertEqual(session.phase, .idle)
  }

  func testHappyPathTransitions() async {
    let session = PlaybackSession(playItem: PlaybackTestItem(id: 1), episodeQueue: [])
    session.prepare()
    XCTAssertEqual(session.phase, .preparing)
    session.markReady()
    XCTAssertEqual(session.phase, .ready)
    session.play()
    XCTAssertEqual(session.phase, .playing)
    session.pause()
    XCTAssertEqual(session.phase, .paused)
    session.play()
    XCTAssertEqual(session.phase, .playing)
    session.buffer()
    XCTAssertEqual(session.phase, .buffering)
    session.fail("boom")
    XCTAssertEqual(session.phase, .failed("boom"))
    session.beginRecovery()
    XCTAssertEqual(session.phase, .recovering)
    session.markReady()
    XCTAssertEqual(session.phase, .ready)
    session.play()
    XCTAssertEqual(session.phase, .playing)
    session.finish()
    XCTAssertEqual(session.phase, .finished)
  }

  func testInvalidTransitionsAreRejected() async {
    let session = PlaybackSession(playItem: PlaybackTestItem(id: 1), episodeQueue: [])
    // Cannot pause or play from idle.
    session.pause()
    XCTAssertEqual(session.phase, .idle)
    session.play()
    XCTAssertEqual(session.phase, .idle)
    // Cannot skip straight to playing from preparing.
    session.prepare()
    session.play()
    XCTAssertEqual(session.phase, .preparing)
    // A finished session is terminal.
    session.markReady()
    session.finish()
    session.play()
    XCTAssertEqual(session.phase, .finished)
    session.beginRecovery()
    XCTAssertEqual(session.phase, .finished)
  }

  func testRecoveryAttemptCounterAndBackoff() async {
    let session = PlaybackSession(playItem: PlaybackTestItem(id: 1), episodeQueue: [])
    session.prepare()
    session.fail("denied")
    XCTAssertEqual(session.beginRecovery(), 0)
    XCTAssertEqual(session.playbackRecoveryAttempt, 1)
    XCTAssertEqual(session.beginRecovery(), 1)
    XCTAssertEqual(session.playbackRecoveryAttempt, 2)
    XCTAssertEqual(session.beginRecovery(), 2)
    XCTAssertEqual(session.playbackRecoveryAttempt, 3)

    XCTAssertEqual(session.recoveryDelay(forAttempt: 0), 5)
    XCTAssertEqual(session.recoveryDelay(forAttempt: 1), 15)
    XCTAssertEqual(session.recoveryDelay(forAttempt: 2), 30)
    XCTAssertEqual(session.recoveryDelay(forAttempt: 9), 30)
  }

  func testEpisodeQueueNavigationFromInitialItem() async {
    let first = PlaybackTestFixtures.episode(id: 1, number: 1)
    let session = PlaybackSession(playItem: first, episodeQueue: queue)
    XCTAssertFalse(session.hasPreviousEpisode)
    XCTAssertTrue(session.hasNextEpisode)

    XCTAssertEqual(session.adjacentEpisode(to: first, offset: 1)?.id, 2)
    XCTAssertNil(session.adjacentEpisode(to: first, offset: -1))
    XCTAssertNil(session.adjacentEpisode(to: first, offset: 5))
  }

  func testEpisodeQueueNavigationAfterMove() async {
    let session = PlaybackSession(playItem: queue[0], episodeQueue: queue)
    session.move(to: queue[1])
    XCTAssertTrue(session.hasPreviousEpisode)
    XCTAssertTrue(session.hasNextEpisode)
    XCTAssertEqual(session.adjacentEpisode(to: queue[1], offset: -1)?.id, 1)
    XCTAssertEqual(session.adjacentEpisode(to: queue[1], offset: 1)?.id, 3)

    session.move(to: queue[2])
    XCTAssertTrue(session.hasPreviousEpisode)
    XCTAssertFalse(session.hasNextEpisode)
    XCTAssertNil(session.adjacentEpisode(to: queue[2], offset: 1))
  }

  func testNonEpisodeItemHasNoNavigation() async {
    let movie = PlaybackTestItem(id: 9)
    let session = PlaybackSession(playItem: movie, episodeQueue: queue)
    XCTAssertFalse(session.hasPreviousEpisode)
    XCTAssertFalse(session.hasNextEpisode)
    XCTAssertNil(session.adjacentEpisode(to: movie, offset: 1))
  }

  func testMoveResetsRecoveryAttempt() async {
    let session = PlaybackSession(playItem: queue[0], episodeQueue: queue)
    session.prepare()
    session.fail("denied")
    session.beginRecovery()
    XCTAssertEqual(session.playbackRecoveryAttempt, 1)
    session.move(to: queue[1])
    XCTAssertEqual(session.playbackRecoveryAttempt, 0)
  }
}
