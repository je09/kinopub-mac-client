//
//  LibraryPersistence.swift
//  KinoPubAppleClient
//
//  Atomic versioned file persistence for `LibraryRepository`'s owned state, with corruption
//  recovery and coalesced writes. All disk I/O happens on this actor — never the main thread.
//

import Foundation
import KinoPubLogging
import OSLog

/// Owns the on-disk shape and file I/O of the library repository's user-specific state.
actor LibraryPersistence {
  /// Bumped when the persisted schema changes; older files (version <= current) are accepted,
  /// newer ones are treated as unreadable (fall back to the backup / empty).
  static let currentVersion = 2

  /// On-disk shape (single file so all owned state persists together). `version` is nil for legacy
  /// pre-refactor files, which share the same schema.
  struct State: Codable {
    var version: Int?
    var records: [Int: LibraryRecord] = [:]
    var movieWatched: [Int: Bool] = [:]
    var episodeWatched: [Int: Bool] = [:]
    var audioPreferences: [Int: LibraryAudioPreference] = [:]
    // Optional so older persisted files decode without losing their other library state.
    var subtitlePreferences: [Int: LibrarySubtitlePreference]?
    var userVotes: [Int: Bool]?
  }

  private let fileURL: URL
  private let backupURL: URL
  /// Latest state waiting to be written; a newer `scheduleSave` replaces an unsaved one
  /// (write coalescing — the file always ends up with the newest state).
  private var pending: State?
  private var saveTask: Task<Void, Never>?

  init(fileURL: URL) {
    self.fileURL = fileURL
    self.backupURL = fileURL.appendingPathExtension("bak")
  }

  /// Load the last readable state: the main file, else the backup, else empty.
  func load() -> State? {
    if let state = Self.readValidated(fileURL, currentVersion: Self.currentVersion) {
      return state
    }
    if FileManager.default.fileExists(atPath: fileURL.path),
      let backup = Self.readValidated(backupURL, currentVersion: Self.currentVersion)
    {
      Logger.app.error(
        "Library persistence: main file corrupt (\(self.fileURL.lastPathComponent)); recovered from backup")
      return backup
    }
    if FileManager.default.fileExists(atPath: fileURL.path) || FileManager.default.fileExists(atPath: backupURL.path) {
      Logger.app.error("Library persistence: no readable state; starting empty")
    }
    return nil
  }

  /// Queue a write. Cheap and safe to call on every mutation: writes coalesce and the file I/O
  /// happens on this actor's executor (off the main thread).
  func scheduleSave(_ state: State) {
    pending = state
    if saveTask == nil {
      saveTask = Task { await self.drain() }
    }
  }

  /// Delete the persisted files (account switch). Cancels any pending write first so the files
  /// cannot be recreated afterwards.
  func removeAll() {
    saveTask?.cancel()
    saveTask = nil
    pending = nil
    try? FileManager.default.removeItem(at: fileURL)
    try? FileManager.default.removeItem(at: backupURL)
  }

  /// Test helper: wait for any pending write to complete.
  func flush() async {
    while let task = saveTask {
      await task.value
    }
  }

  private func drain() async {
    while true {
      guard let state = pending else {
        saveTask = nil
        // A save could have been scheduled in between the read and the nil assignment; it saw us
        // and relied on this loop, so restart and pick it up.
        if pending != nil { continue }
        return
      }
      pending = nil
      await write(state)
    }
  }

  private func write(_ state: State) async {
    // Keep the previous good file as a recovery backup (best effort).
    if FileManager.default.fileExists(atPath: fileURL.path) {
      try? FileManager.default.removeItem(at: backupURL)
      try? FileManager.default.copyItem(at: fileURL, to: backupURL)
    }
    do {
      let data = try JSONEncoder().encode(state)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      Logger.app.error("Library persistence: failed to save \(self.fileURL.lastPathComponent): \(error)")
    }
  }

  private static func readValidated(_ url: URL, currentVersion: Int) -> State? {
    guard let data = try? Data(contentsOf: url),
      let decoded = try? JSONDecoder().decode(State.self, from: data),
      (decoded.version ?? 1) <= currentVersion
    else { return nil }
    return decoded
  }
}
