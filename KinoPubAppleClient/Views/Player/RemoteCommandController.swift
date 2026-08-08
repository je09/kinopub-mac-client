//
//  RemoteCommandController.swift
//  KinoPubAppleClient
//
//  Wraps `MPRemoteCommandCenter` (Touch Bar / media keys / Control Center) for episode
//  navigation (see plans/refactor.md Phase 6). Targets are installed at most once and removed
//  exactly once on teardown.
//

import Foundation
import MediaPlayer

@MainActor
final class RemoteCommandController {
  private let center = MPRemoteCommandCenter.shared()
  private var nextTrackTarget: Any?
  private var previousTrackTarget: Any?
  private var isConfigured = false

  /// Install previous/next track handlers once. Safe to call multiple times.
  func configure(onPrevious: @escaping () -> Void, onNext: @escaping () -> Void) {
    guard !isConfigured else { return }
    isConfigured = true
    previousTrackTarget = center.previousTrackCommand.addTarget { _ in
      Task { @MainActor in onPrevious() }
      return .success
    }
    nextTrackTarget = center.nextTrackCommand.addTarget { _ in
      Task { @MainActor in onNext() }
      return .success
    }
  }

  /// Keep the remote controls' enabled state in sync with the queue position.
  func updateNavigation(hasPrevious: Bool, hasNext: Bool) {
    center.previousTrackCommand.isEnabled = hasPrevious
    center.nextTrackCommand.isEnabled = hasNext
  }

  /// Remove both targets; safe to call repeatedly.
  func teardown() {
    guard isConfigured else { return }
    isConfigured = false
    if let nextTrackTarget {
      center.nextTrackCommand.removeTarget(nextTrackTarget)
      self.nextTrackTarget = nil
    }
    if let previousTrackTarget {
      center.previousTrackCommand.removeTarget(previousTrackTarget)
      self.previousTrackTarget = nil
    }
  }
}
