//
//  PlaybackPhase.swift
//  KinoPubAppleClient
//
//  Explicit playback state machine (see plans/refactor.md Phase 6). Pure logic — no AVPlayer,
//  no network — so every transition rule is testable in isolation.
//

import Foundation

/// The explicit playback state machine phases. `PlaybackSession` owns the transition table;
/// `AVPlayerController` and `PlayerManager` map AVFoundation events onto it.
enum PlaybackPhase: Hashable, Equatable, CustomStringConvertible {
  /// No item loaded yet (before the session is prepared).
  case idle
  /// An item was handed to the player but is not ready to play.
  case preparing
  /// The current item is ready to play.
  case ready
  /// Playback is advancing.
  case playing
  /// Playback was paused (user or system).
  case paused
  /// The item is stalling / buffering.
  case buffering
  /// A denied signed URL is being replaced (recovery ladder in progress).
  case recovering
  /// The current item failed and could not be recovered. The message is user-facing.
  case failed(String)
  /// Playback reached the end of the final item.
  case finished

  var description: String {
    switch self {
    case .idle: return "idle"
    case .preparing: return "preparing"
    case .ready: return "ready"
    case .playing: return "playing"
    case .paused: return "paused"
    case .buffering: return "buffering"
    case .recovering: return "recovering"
    case .failed: return "failed"
    case .finished: return "finished"
    }
  }
}
