//
//  PlaybackSession.swift
//  KinoPubAppleClient
//
//  The playback state machine: phase transitions, episode-queue navigation, and the signed-URL
//  recovery-ladder counter (see plans/refactor.md Phase 6). Pure logic with no AVPlayer and no
//  network, so every rule is deterministic and testable. It is deliberately a plain class, not an
//  actor: `PlayerManager` (MainActor) is its only writer and tests run serially, so the
//  state-machine transitions are synchronous by construction and cannot race. The genuinely
//  concurrent playback pieces (watch-mark worker, AVFoundation object graph) live in
//  `WatchProgressSync` (actor) and `AVPlayerController` (@MainActor).
//

import Foundation
import KinoPubBackend
import OSLog
import KinoPubLogging

final class PlaybackSession {
  /// Explicit transition table. Invalid transitions are rejected (and logged in debug) instead
  /// of silently mutating the phase, so a late event from a replaced item cannot corrupt state.
  private static func canTransition(from: PlaybackPhase, to: PlaybackPhase) -> Bool {
    switch (from, to) {
    case (.idle, .preparing): return true
    case (.preparing, .ready), (.preparing, .failed), (.preparing, .finished): return true
    case (.ready, .playing), (.ready, .paused), (.ready, .buffering),
      (.ready, .failed), (.ready, .finished):
      return true
    case (.playing, .paused), (.playing, .buffering), (.playing, .failed), (.playing, .finished): return true
    case (.paused, .playing), (.paused, .buffering), (.paused, .failed), (.paused, .finished): return true
    case (.buffering, .playing), (.buffering, .paused), (.buffering, .failed), (.buffering, .finished): return true
    case (.recovering, .ready), (.recovering, .playing), (.recovering, .failed), (.recovering, .finished): return true
    case (.failed, .recovering), (.failed, .finished): return true
    default: return false
    }
  }

  private(set) var phase: PlaybackPhase
  /// How many signed-URL refresh steps succeeded so far for the current item. Drives the
  /// recovery delay and the ladder rung (hls4 → hls2 → progressive).
  private(set) var playbackRecoveryAttempt = 0
  /// The queue position of the item currently being played, when it is an episode.
  private(set) var currentEpisodeID: Int?

  let episodeQueue: [Episode]

  init(playItem: any PlayableItem, episodeQueue: [Episode]) {
    self.episodeQueue = episodeQueue
    self.currentEpisodeID = (playItem as? Episode)?.id
    self.phase = .idle
  }

  // MARK: - Phase machine

  func prepare() { transition(to: .preparing) }
  func markReady() { transition(to: .ready) }
  func play() { transition(to: .playing) }
  func pause() { transition(to: .paused) }
  func buffer() { transition(to: .buffering) }
  func finish() { transition(to: .finished) }

  func fail(_ message: String) { transition(to: .failed(message)) }

  /// Enter recovery and advance the ladder counter. Returns the attempt number to use for the
  /// next source refresh (the pre-increment value, matching the original recovery semantics).
  @discardableResult
  func beginRecovery() -> Int {
    let attempt = playbackRecoveryAttempt
    transition(to: .recovering)
    playbackRecoveryAttempt += 1
    return attempt
  }

  /// Backoff before opening another server-side session while a CDN 403 slot may not have
  /// expired yet: 5s, then 15s, then a fixed 30s for any further attempts.
  func recoveryDelay(forAttempt attempt: Int) -> TimeInterval {
    let delays: [TimeInterval] = [5, 15, 30]
    return delays[min(attempt, delays.count - 1)]
  }

  private func transition(to newPhase: PlaybackPhase) {
    guard Self.canTransition(from: phase, to: newPhase) else {
      Logger.app.debug("Playback phase transition ignored: \(self.phase) -> \(newPhase)")
      return
    }
    phase = newPhase
  }

  // MARK: - Episode navigation

  var hasPreviousEpisode: Bool {
    guard let index = currentEpisodeIndex else { return false }
    return index > 0
  }

  var hasNextEpisode: Bool {
    guard let index = currentEpisodeIndex else { return false }
    return index + 1 < episodeQueue.count
  }

  /// The episode `offset` steps away from `current` in the queue, or nil when `current` is not
  /// an episode or the offset leaves the queue.
  func adjacentEpisode(to current: any PlayableItem, offset: Int) -> Episode? {
    guard let episode = current as? Episode,
      let index = episodeQueue.firstIndex(where: { $0.id == episode.id })
    else { return nil }
    let targetIndex = index + offset
    guard episodeQueue.indices.contains(targetIndex) else { return nil }
    return episodeQueue[targetIndex]
  }

  /// Switch the current queue position to `episode` and reset the recovery ladder.
  func move(to episode: Episode) {
    currentEpisodeID = episode.id
    playbackRecoveryAttempt = 0
  }

  private var currentEpisodeIndex: Int? {
    guard let currentEpisodeID else { return nil }
    return episodeQueue.firstIndex(where: { $0.id == currentEpisodeID })
  }
}
