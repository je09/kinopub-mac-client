//
//  LibraryRepository+Lifecycle.swift
//  KinoPubAppleClient
//
//  Lifecycle and persistence plumbing of `LibraryRepository`: account deactivation (atomic clear
//  of state + persisted files) and the write/load delegation to `LibraryPersistence`.
//

import Foundation

extension LibraryRepository {

  // MARK: Account lifecycle

  /// Clear all user-specific state atomically and drop the persisted files so a different account
  /// never inherits bookmarks/watchlist/watched overrides. Also cancels in-flight commands (their
  /// optimistic effects are discarded with the state; the server's truth re-seeds on the next
  /// session).
  func deactivate() async {
    guard isActive else { return }
    isActive = false
    for task in workers.values {
      task.cancel()
    }
    workers = [:]
    resumeAllWaiters(.cancelled)
    resetOwnedState()
    await persistence.removeAll()
    publish()
  }

  /// Discard every piece of user-specific state (data + journal) atomically.
  private func resetOwnedState() {
    targets = [:]
    serverValue = [:]
    unknownBaseValue = [:]
    records = [:]
    movieWatchedOverride = [:]
    episodeWatchedOverride = [:]
    audioPreferences = [:]
    subtitlePreferences = [:]
    userVotes = [:]
    bookmarkFolders = []
    bookmarkFoldersLoaded = false
  }

  // MARK: Persistence (delegated to LibraryPersistence)

  /// Queue a write of the current state; `LibraryPersistence` coalesces and writes off the main
  /// thread (see LibraryPersistence.swift).
  func schedulePersist() {
    guard isActive else { return }
    let state = LibraryPersistence.State(
      version: LibraryPersistence.currentVersion,
      records: records,
      movieWatched: movieWatchedOverride,
      episodeWatched: episodeWatchedOverride,
      audioPreferences: audioPreferences,
      subtitlePreferences: subtitlePreferences,
      userVotes: userVotes)
    Task { await persistence.scheduleSave(state) }
  }

  func loadAndPublish() async {
    if let persisted = await persistence.load() {
      records = persisted.records
      movieWatchedOverride = persisted.movieWatched
      episodeWatchedOverride = persisted.episodeWatched
      audioPreferences = persisted.audioPreferences
      subtitlePreferences = persisted.subtitlePreferences ?? [:]
      userVotes = persisted.userVotes ?? [:]
    }
    hasLoaded = true
    publish()
  }

  /// Test/debug helper: wait for any pending persistence write to complete.
  func flushPersistence() async {
    await persistence.flush()
  }
}
