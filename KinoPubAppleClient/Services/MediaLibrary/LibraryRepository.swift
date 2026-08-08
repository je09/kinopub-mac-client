//
//  LibraryRepository.swift
//  KinoPubAppleClient
//
//  Actor-owned authoritative library state for an item: bookmark-folder membership, watchlist,
//  watched overrides, the user's votes and playback preferences. It is the single route for every
//  bookmark/watch/watchlist mutation in the app (see plans/refactor.md Phase 4).
//
//  Responsibilities split from the old MediaLibraryStore:
//   • authoritative local state + optimistic command journal + remote synchronization (this actor)
//   • UI projection / subscription            → LibraryViewState (@MainActor, observable)
//   • download status adapter                  → LibraryDownloadStatusAdapter (separate source)
//   • watch progress                          → LocalWatchProgressStore (separate source)
//   • atomic versioned persistence            → LibraryPersistence (separate actor)
//
//  Command model:
//   - Every user mutation is a typed `LibraryCommand` with a sync key. Mutations on the same key
//     are serialized per item and coalesced: rapid repeated toggles pair off into one remote call
//     (or none), so two conflicting toggles for the same item can never run concurrently.
//   - Optimistic state is applied immediately; the journal replays the exact remote effect needed
//     to converge the server and rolls back to the last known server truth when a call fails.
//   - A cancelled call (e.g. logout mid-flight) rolls back too; the divergence self-heals on the
//     next authoritative fetch (seed/reconcile).
//
//  Account lifecycle:
//   - User-specific state is cleared atomically on logout (`deactivate()`): there is no stable
//     account id available at bootstrap, so the safe cross-account boundary is clear-on-logout
//     (the server re-seeds the next session). A per-account file partition can be layered on once
//     an account identity exists.
//

import Foundation
import KinoPubBackend

actor LibraryRepository {

  // MARK: Owned state

  // Module-internal (not `private`) so the API extensions in LibraryRepository+Sync.swift and
  // LibraryRepository+Lifecycle.swift can touch it (this includes the journal internals
  // RemoteCall/SyncTarget/targets). The repository is only ever held by `AppDependencies` and
  // `LibraryViewState`; nothing else in the app reaches it.

  var records: [Int: LibraryRecord] = [:]
  /// Optimistic "watched" overrides — win over the server's value until a fetch reconciles them
  /// away. Movie keyed by item id, episode keyed by episode id.
  var movieWatchedOverride: [Int: Bool] = [:]
  var episodeWatchedOverride: [Int: Bool] = [:]
  /// Remembered audio track (озвучка) per item/series id.
  var audioPreferences: [Int: LibraryAudioPreference] = [:]
  /// Remembered native subtitle selection per item/series, including an explicit Off choice.
  var subtitlePreferences: [Int: LibrarySubtitlePreference] = [:]
  /// The user's like (true) / dislike (false) per item id.
  var userVotes: [Int: Bool] = [:]
  /// Session cache of the user's bookmark folders.
  var bookmarkFolders: [Bookmark] = []
  var bookmarkFoldersLoaded = false
  var bookmarkFoldersLoading = false

  /// Last value the server confirmed per sync key (from seeds, reconciles and acked toggles).
  var serverValue: [LibrarySyncKey: Bool] = [:]
  /// Local value captured before the first unacked mutation of a key whose server truth is
  /// unknown — the rollback target for a failed call in that case.
  var unknownBaseValue: [LibrarySyncKey: Bool] = [:]

  // MARK: Command journal

  /// What the worker sends for a key. Distinct toggles on the same key share the same remote call,
  /// so the parameters can be stored once per target.
  enum RemoteCall {
    case toggleBookmark(itemId: Int, folderId: Int)
    case toggleWatchlist(itemId: Int)
    case toggleWatching(itemId: Int, video: Int?, season: Int?)
  }

  struct SyncTarget {
    var remote: RemoteCall
    /// Latest explicit set target (nil = only toggles queued). Toggles queued before/after a set
    /// are absorbed into it (each toggle flips the desired value).
    var setTarget: Bool?
    /// Parity of queued toggles: consecutive toggles pair off, so odd parity means one toggle
    /// needs to be sent, even parity means none.
    var toggleParity = false
    var waiters: [CheckedContinuation<LibraryCommandOutcome, Never>] = []
    var hasWork: Bool { setTarget != nil || toggleParity }
  }

  var targets: [LibrarySyncKey: SyncTarget] = [:]
  var workers: [LibrarySyncKey: Task<Void, Never>] = [:]
  var isActive = true
  var hasLoaded = false

  // MARK: Dependencies + persistence

  let actionsService: UserActionsService
  let persistence: LibraryPersistence

  // MARK: Snapshot publishing

  let stream: AsyncStream<LibrarySnapshot>
  let continuation: AsyncStream<LibrarySnapshot>.Continuation

  init(actionsService: UserActionsService, fileURL: URL? = nil) {
    self.actionsService = actionsService
    let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    self.persistence = LibraryPersistence(
      fileURL: fileURL ?? directory.appendingPathComponent("media_library.json"))
    let (stream, continuation) = AsyncStream.makeStream(of: LibrarySnapshot.self)
    self.stream = stream
    self.continuation = continuation
    // Load off the main actor; the loaded snapshot arrives on the stream.
    Task { await self.loadAndPublish() }
  }

  // MARK: Subscription

  func snapshots() -> AsyncStream<LibrarySnapshot> { stream }

  func currentSnapshot() -> LibrarySnapshot { makeSnapshot() }

  /// Test helper: whether the initial load from disk has finished.
  func loadCompleted() -> Bool { hasLoaded }

  private func makeSnapshot() -> LibrarySnapshot {
    LibrarySnapshot(
      records: records,
      movieWatchedOverride: movieWatchedOverride,
      episodeWatchedOverride: episodeWatchedOverride,
      audioPreferences: audioPreferences,
      subtitlePreferences: subtitlePreferences,
      userVotes: userVotes,
      bookmarkFolders: bookmarkFolders)
  }

  func publish() {
    continuation.yield(makeSnapshot())
  }

  // MARK: Commands

  /// Submit a command: applies the optimistic state immediately, serializes the remote effect on
  /// the command's sync key and returns once that effect has settled (applied / coalesced /
  /// failed / cancelled).
  func submit(_ command: LibraryCommand) async -> LibraryCommandOutcome {
    guard isActive else { return .cancelled }
    let key = command.syncKey
    // Remember the pre-intent value for keys whose server truth is unknown so a failed call can
    // roll the optimistic state back to it.
    if serverValue[key] == nil && unknownBaseValue[key] == nil {
      unknownBaseValue[key] = currentLocalValue(key)
    }
    applyOptimistic(command)
    schedulePersist()

    var target = targets[key] ?? SyncTarget(remote: remoteCall(for: command))
    merge(command, into: &target)
    let outcome: LibraryCommandOutcome = await withCheckedContinuation { continuation in
      target.waiters.append(continuation)
      targets[key] = target
      if workers[key] == nil {
        let task = Task { await self.runLoop(key) }
        workers[key] = task
      }
    }
    return outcome
  }

  /// Fold a command into the pending target: toggles flip the parity bit, a set absorbs any queued
  /// toggles into its explicit target.
  private func merge(_ command: LibraryCommand, into target: inout SyncTarget) {
    switch command {
    case .toggleBookmark, .toggleWatchlist, .toggleMovieWatched, .toggleEpisodeWatched:
      target.toggleParity.toggle()
    case .setBookmark(_, _, let isOn):
      mergeSet(isOn, into: &target)
    case .setWatchlist(_, let value):
      mergeSet(value, into: &target)
    }
  }

  /// A set absorbs any queued toggles into its explicit target.
  private func mergeSet(_ value: Bool, into target: inout SyncTarget) {
    target.setTarget = value != target.toggleParity
    target.toggleParity = false
  }

  // MARK: Command journal (per-key workers)

  /// One worker per key. All steps between `await`s are atomic on the actor, so a submit can only
  /// interleave at an `await` — where it merges work into `targets` and relies on this loop (which
  /// it saw as running) to pick it up.
  private func runLoop(_ key: LibrarySyncKey) async {
    while true {
      guard let result = drain(key) else {
        // Idle: hand the key back only once there is genuinely no work.
        if keepRunningIfWorkArrived(key) { continue }
        // Ops that drained to nothing (e.g. a set already matching server state) resolve their
        // waiters here: optimistic state is applied, nothing was sent.
        resume(extractWaiters(key), with: .coalesced)
        return
      }
      // Waiters queued before this op starts belong to it; waiters added while the remote call is
      // in flight belong to the next batch.
      let batchWaiters = extractWaiters(key)
      let outcome: LibraryCommandOutcome
      do {
        try await performRemote(result.remote)
        ackSuccess(key, setEffective: result.setEffective)
        outcome = .applied
      } catch is CancellationError {
        outcome = .cancelled
      } catch {
        outcome = .failed(error)
      }
      if case .applied = outcome {
        resume(batchWaiters, with: .applied)
      } else {
        // Roll the optimistic state back and drop queued work; every waiter (this batch plus the
        // dropped queue) resolves with the same outcome so no submit hangs or misses the rollback.
        let droppedWaiters = rollback(key)
        resume(batchWaiters + droppedWaiters, with: outcome)
      }
    }
  }

  /// Take the waiters currently queued for `key`; they resolve against the op about to execute.
  private func extractWaiters(
    _ key: LibrarySyncKey
  ) -> [CheckedContinuation<LibraryCommandOutcome, Never>] {
    guard var target = targets[key] else { return [] }
    let waiters = target.waiters
    target.waiters = []
    targets[key] = target.hasWork ? target : nil
    return waiters
  }

  private func resume(
    _ waiters: [CheckedContinuation<LibraryCommandOutcome, Never>],
    with outcome: LibraryCommandOutcome
  ) {
    for waiter in waiters {
      waiter.resume(returning: outcome)
    }
  }

  /// Resume every waiter still queued across all keys (used by `deactivate()`).
  func resumeAllWaiters(_ outcome: LibraryCommandOutcome) {
    for target in targets.values {
      for waiter in target.waiters {
        waiter.resume(returning: outcome)
      }
    }
  }

  /// Returns true when work arrived between the last drain and releasing the key, in which case
  /// this loop keeps running as the key's worker. All steps are synchronous, so a submit can only
  /// interleave at an `await` — the second check closes the handoff race.
  private func keepRunningIfWorkArrived(_ key: LibrarySyncKey) -> Bool {
    if targets[key]?.hasWork == true { return true }
    workers[key] = nil
    return targets[key]?.hasWork == true
  }

  private struct DrainResult {
    var remote: RemoteCall
    /// Non-nil when the drained op was a set: after a successful toggle the server equals this.
    var setEffective: Bool?
  }

  /// Take the next remote effect to send for `key`, or nil when nothing needs sending.
  private func drain(_ key: LibrarySyncKey) -> DrainResult? {
    guard var target = targets[key] else { return nil }
    defer { targets[key] = target }

    if let set = target.setTarget {
      let effective = set != target.toggleParity
      let send: Bool
      if let server = serverValue[key] {
        send = server != effective
      } else {
        // Unknown server truth: the caller asserted a membership change, so enforce it with one
        // toggle (matches the legacy blind-toggle behaviour for remove-from-folder / add-to-folder).
        send = true
      }
      target.setTarget = nil
      target.toggleParity = false
      return send ? DrainResult(remote: target.remote, setEffective: effective) : nil
    }

    if target.toggleParity {
      target.toggleParity = false
      return DrainResult(remote: target.remote, setEffective: nil)
    }
    return nil
  }

  // MARK: Remote effects

  private func performRemote(_ remote: RemoteCall) async throws {
    switch remote {
    case .toggleBookmark(let itemId, let folderId):
      try await actionsService.toggleBookmark(itemId: itemId, folderId: folderId)
    case .toggleWatchlist(let itemId):
      try await actionsService.toggleWatchlist(id: itemId)
    case .toggleWatching(let itemId, let video, let season):
      try await actionsService.toggleWatching(id: itemId, video: video, season: season)
    }
  }

  private func remoteCall(for command: LibraryCommand) -> RemoteCall {
    switch command {
    case .toggleBookmark(let itemId, let folderId), .setBookmark(let itemId, let folderId, _):
      return .toggleBookmark(itemId: itemId, folderId: folderId)
    case .toggleWatchlist(let itemId), .setWatchlist(let itemId, _):
      return .toggleWatchlist(itemId: itemId)
    case .toggleMovieWatched(let itemId):
      return .toggleWatching(itemId: itemId, video: nil, season: nil)
    case .toggleEpisodeWatched(let itemId, _, let video, let season):
      return .toggleWatching(itemId: itemId, video: video, season: season)
    }
  }

  /// A successful remote effect: for a set we now know the server equals the effective target; for
  /// a pure toggle the server flipped (when its value was tracked).
  private func ackSuccess(_ key: LibrarySyncKey, setEffective: Bool?) {
    guard isActive else { return }
    if let effective = setEffective {
      serverValue[key] = effective
    } else if serverValue[key] != nil {
      serverValue[key]?.toggle()
    }
    unknownBaseValue.removeValue(forKey: key)
  }

  /// Failed/cancelled remote effect: restore the last known server truth (or the pre-intent local
  /// value when the server truth was never tracked), drop queued work for the key, and hand back
  /// that queue's waiters so the caller can resolve them (they must never be left suspended).
  private func rollback(
    _ key: LibrarySyncKey
  ) -> [CheckedContinuation<LibraryCommandOutcome, Never>] {
    guard isActive else { return [] }
    if let server = serverValue[key] {
      setLocalValue(key, server)
    } else if let base = unknownBaseValue[key] {
      setLocalValue(key, base)
    }
    serverValue.removeValue(forKey: key)
    unknownBaseValue.removeValue(forKey: key)
    let dropped = targets.removeValue(forKey: key)?.waiters ?? []
    schedulePersist()
    return dropped
  }

  // MARK: Optimistic application

  private func applyOptimistic(_ command: LibraryCommand) {
    switch command {
    case .toggleBookmark(let itemId, let folderId):
      applyToggle(.bookmark(itemId: itemId, folderId: folderId))
    case .setBookmark(let itemId, let folderId, let isOn):
      setLocalValue(.bookmark(itemId: itemId, folderId: folderId), isOn)
    case .toggleWatchlist(let itemId):
      applyToggle(.watchlist(itemId: itemId))
    case .setWatchlist(let itemId, let value):
      setLocalValue(.watchlist(itemId: itemId), value)
    case .toggleMovieWatched(let itemId):
      applyToggle(.watchedMovie(itemId: itemId))
    case .toggleEpisodeWatched(let itemId, let episodeId, _, _):
      applyToggle(.watchedEpisode(itemId: itemId, episodeId: episodeId))
    }
  }

  /// Flip the local value for a key — the optimistic half of a toggle command.
  private func applyToggle(_ key: LibrarySyncKey) {
    setLocalValue(key, !currentLocalValue(key))
  }

  private func currentLocalValue(_ key: LibrarySyncKey) -> Bool {
    switch key {
    case .bookmark(let itemId, let folderId):
      return records[itemId]?.bookmarkFolderIds.contains(folderId) ?? false
    case .watchlist(let itemId):
      return records[itemId]?.inWatchlist ?? false
    case .watchedMovie(let itemId):
      return movieWatchedOverride[itemId] ?? serverValue[key] ?? false
    case .watchedEpisode(_, let episodeId):
      return episodeWatchedOverride[episodeId] ?? serverValue[key] ?? false
    }
  }

  private func setLocalValue(_ key: LibrarySyncKey, _ value: Bool) {
    switch key {
    case .bookmark(let itemId, let folderId):
      var record = records[itemId] ?? LibraryRecord()
      var set = Set(record.bookmarkFolderIds)
      if value {
        set.insert(folderId)
      } else {
        set.remove(folderId)
      }
      record.bookmarkFolderIds = set.sorted()
      records[itemId] = record
    case .watchlist(let itemId):
      var record = records[itemId] ?? LibraryRecord()
      record.inWatchlist = value
      records[itemId] = record
    case .watchedMovie(let itemId):
      movieWatchedOverride[itemId] = value
    case .watchedEpisode(_, let episodeId):
      episodeWatchedOverride[episodeId] = value
    }
  }
}
