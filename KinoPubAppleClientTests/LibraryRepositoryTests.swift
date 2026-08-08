import XCTest
import Dispatch
import KinoPubBackend
import KinoPubKit
@testable import KinoPub

/// Phase 4 tests for the `LibraryRepository` actor: optimistic command journal, per-item
/// serialization/coalescing, rollback on failure, atomic versioned persistence with corruption
/// recovery, account clearing, and reconciliation.
@MainActor
final class LibraryRepositoryTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("LibraryRepositoryTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    directory = nil
  }

  // MARK: - Optimistic commands

  func testBookmarkOptimisticToggleAppliesAndRollsBackOnFailure() async {
    let service = RecordingUserActionsService()
    let repo = makeRepository(actionsService: service)

    let outcome = await repo.submit(.toggleBookmark(itemId: 42, folderId: 7))
    XCTAssertTrue(isApplied(outcome))
    let snapshot = await repo.currentSnapshot()
    XCTAssertTrue(snapshot.isBookmarked(itemId: 42, folderId: 7))

    await service.setBehavior(.fail(TestError.remoteDown))
    let failed = await repo.submit(.toggleBookmark(itemId: 42, folderId: 7))
    XCTAssertTrue(isFailed(failed))
    // The failed call rolled the optimistic state back to the last server truth (in folder).
    let rolledBack = await repo.currentSnapshot()
    XCTAssertTrue(rolledBack.isBookmarked(itemId: 42, folderId: 7))
  }

  func testRollbackUsesPreIntentValueWhenServerTruthUnknown() async {
    let service = RecordingUserActionsService()
    await service.setBehavior(.fail(TestError.remoteDown))
    let repo = makeRepository(actionsService: service)

    let outcome = await repo.submit(.toggleBookmark(itemId: 42, folderId: 7))
    XCTAssertTrue(isFailed(outcome))
    let snapshot = await repo.currentSnapshot()
    XCTAssertFalse(snapshot.isBookmarked(itemId: 42, folderId: 7))
  }

  func testWatchlistCommandOutcome() async {
    let service = RecordingUserActionsService()
    let repo = makeRepository(actionsService: service)

    let outcome = await repo.submit(.toggleWatchlist(itemId: 42))
    XCTAssertTrue(isApplied(outcome))
    let snapshot = await repo.currentSnapshot()
    XCTAssertEqual(snapshot.records[42]?.inWatchlist, true)
  }

  func testWatchedOverrideWinsUntilServerReconcilesIt() async {
    let service = RecordingUserActionsService()
    let repo = makeRepository(actionsService: service)

    _ = await repo.submit(.toggleMovieWatched(itemId: 42))
    let snapshot = await repo.currentSnapshot()
    XCTAssertTrue(snapshot.movieWatched(itemId: 42, serverWatched: false))

    await repo.reconcileWatched(movieItemId: 42, serverMovieWatched: true, episodes: [])
    let reconciled = await repo.currentSnapshot()
    XCTAssertFalse(reconciled.movieWatched(itemId: 42, serverWatched: false))
  }

  func testReconcileKeepsOverrideThatStillDiffersFromServer() async {
    let service = RecordingUserActionsService()
    let repo = makeRepository(actionsService: service)

    _ = await repo.submit(.toggleMovieWatched(itemId: 42))  // override = true
    await repo.reconcileWatched(movieItemId: 42, serverMovieWatched: false, episodes: [])
    // Server says unwatched but the optimistic override is still in flight → keep it.
    let snapshot = await repo.currentSnapshot()
    XCTAssertTrue(snapshot.movieWatched(itemId: 42, serverWatched: false))
  }

  // MARK: - Serialization / coalescing

  func testTogglesOnSameKeyAreSerializedWhileFirstIsInFlight() async {
    let service = RecordingUserActionsService()
    await service.setBehavior(.blockFirst)
    let repo = makeRepository(actionsService: service)

    let first = Task { await repo.submit(.toggleBookmark(itemId: 42, folderId: 7)) }
    await waitUntil { await service.toggleCallCount() == 1 }

    let second = Task { await repo.submit(.toggleBookmark(itemId: 42, folderId: 7)) }
    await settle()

    await service.releaseBlockedCall()
    let firstOutcome = await first.value
    let secondOutcome = await second.value
    XCTAssertTrue(isApplied(firstOutcome))
    XCTAssertTrue(isApplied(secondOutcome))

    // Both toggles went out, serialized — and the local state returned to its base (out).
    let calls = await service.toggleCallCount()
    XCTAssertEqual(calls, 2)
    let snapshot = await repo.currentSnapshot()
    XCTAssertFalse(snapshot.isBookmarked(itemId: 42, folderId: 7))
  }

  func testRapidRepeatedTogglesNeverProduceStrayRemoteCall() async {
    let service = RecordingUserActionsService()
    let repo = makeRepository(actionsService: service)

    let first = Task { await repo.submit(.toggleBookmark(itemId: 42, folderId: 7)) }
    let second = Task { await repo.submit(.toggleBookmark(itemId: 42, folderId: 7)) }
    _ = await first.value
    _ = await second.value

    // Paired toggles cancel into zero calls (if both merged before the worker drained) or two
    // serialized calls (if the first was already in flight) — never a single stray toggle.
    let calls = await service.toggleCallCount()
    XCTAssertTrue(calls == 0 || calls == 2, "expected 0 or 2 remote toggles, got \(calls)")
    let snapshot = await repo.currentSnapshot()
    XCTAssertFalse(snapshot.isBookmarked(itemId: 42, folderId: 7))
  }

  func testCoalescesQueuedTogglesWhileFirstIsInFlight() async {
    let service = RecordingUserActionsService()
    await service.setBehavior(.blockFirst)
    let repo = makeRepository(actionsService: service)

    let first = Task { await repo.submit(.toggleBookmark(itemId: 42, folderId: 7)) }
    await waitUntil { await service.toggleCallCount() == 1 }

    let second = Task { await repo.submit(.toggleBookmark(itemId: 42, folderId: 7)) }
    let third = Task { await repo.submit(.toggleBookmark(itemId: 42, folderId: 7)) }
    await settle()

    await service.releaseBlockedCall()
    _ = await first.value
    _ = await second.value
    _ = await third.value

    // Three toggles = one in flight + a queued pair that cancels → exactly one remote call.
    let calls = await service.toggleCallCount()
    XCTAssertEqual(calls, 1)
    // Net effect is a single flip: the item ends up in the folder.
    let snapshot = await repo.currentSnapshot()
    XCTAssertTrue(snapshot.isBookmarked(itemId: 42, folderId: 7))
  }

  // MARK: - Set commands

  func testSetBookmarkWithKnownServerStateSkipsRedundantRemote() async {
    let service = RecordingUserActionsService()
    let repo = makeRepository(actionsService: service)

    await repo.seedIfAbsent(itemId: 42, folderIds: [7], inWatchlist: false)
    let noop = await repo.submit(.setBookmark(itemId: 42, folderId: 7, isOn: true))
    XCTAssertTrue(isCoalesced(noop))
    let calls = await service.toggleCallCount()
    XCTAssertEqual(calls, 0)

    let remove = await repo.submit(.setBookmark(itemId: 42, folderId: 7, isOn: false))
    XCTAssertTrue(isApplied(remove))
    let removeCalls = await service.toggleCallCount()
    XCTAssertEqual(removeCalls, 1)
    let snapshot = await repo.currentSnapshot()
    XCTAssertFalse(snapshot.isBookmarked(itemId: 42, folderId: 7))
  }

  func testSetBookmarkWithUnknownServerStateEnforcesMembershipChange() async {
    let service = RecordingUserActionsService()
    let repo = makeRepository(actionsService: service)

    // remove-from-folder flow: the item was never seeded, so the server truth is unknown — the
    // repository must still send the toggle (legacy behaviour) so the folder actually loses it.
    let outcome = await repo.submit(.setBookmark(itemId: 42, folderId: 7, isOn: false))
    XCTAssertTrue(isApplied(outcome))
    let calls = await service.toggleCallCount()
    XCTAssertEqual(calls, 1)
    let snapshot = await repo.currentSnapshot()
    XCTAssertFalse(snapshot.isBookmarked(itemId: 42, folderId: 7))
  }

  // MARK: - Persistence

  func testOptimisticStatePersistsAcrossRepositoryInstances() async {
    let url = directory.appendingPathComponent("library.json")
    let service = RecordingUserActionsService()
    let first = LibraryRepository(actionsService: service, fileURL: url)
    _ = await first.submit(.toggleBookmark(itemId: 42, folderId: 7))
    _ = await first.submit(.toggleWatchlist(itemId: 42))
    _ = await first.submit(.toggleMovieWatched(itemId: 42))
    await first.flushPersistence()

    let reloaded = LibraryRepository(actionsService: service, fileURL: url)
    await waitUntil { await reloaded.currentSnapshot().isBookmarked(itemId: 42, folderId: 7) }

    let snapshot = await reloaded.currentSnapshot()
    XCTAssertTrue(snapshot.isBookmarked(itemId: 42, folderId: 7))
    let watchlist = await reloaded.currentSnapshot()
    XCTAssertEqual(watchlist.records[42]?.inWatchlist, true)
    let watched = await reloaded.currentSnapshot()
    XCTAssertTrue(watched.movieWatched(itemId: 42, serverWatched: false))
  }

  func testCorruptionRecoveryFallsBackToBackup() async {
    let url = directory.appendingPathComponent("library.json")
    let service = RecordingUserActionsService()

    // Two writes so the backup holds an earlier good version.
    let first = LibraryRepository(actionsService: service, fileURL: url)
    _ = await first.submit(.toggleBookmark(itemId: 42, folderId: 7))
    await first.flushPersistence()
    _ = await first.submit(.toggleWatchlist(itemId: 42))
    await first.flushPersistence()

    // Corrupt the main file; the backup still decodes.
    try? Data("garbage-not-json".utf8).write(to: url)

    let recovered = LibraryRepository(actionsService: service, fileURL: url)
    await waitUntil { await recovered.loadCompleted() }

    // Recovered from the backup: the first write's bookmark survived, the second's did not.
    let snapshot = await recovered.currentSnapshot()
    XCTAssertTrue(snapshot.isBookmarked(itemId: 42, folderId: 7))
    let watchlist = await recovered.currentSnapshot()
    XCTAssertNil(watchlist.records[42]?.inWatchlist)
  }

  func testFutureVersionFileStartsEmptyWithoutCrashing() async {
    let url = directory.appendingPathComponent("library.json")
    // A file from a newer schema version must not crash the loader.
    let newer = """
      {"version": 99, "records": {}}
      """
    try? Data(newer.utf8).write(to: url)

    let repo = LibraryRepository(actionsService: RecordingUserActionsService(), fileURL: url)
    await waitUntil { await repo.loadCompleted() }
    let snapshot = await repo.currentSnapshot()
    XCTAssertTrue(snapshot.records.isEmpty)
  }

  // MARK: - Account lifecycle

  func testDeactivateClearsStateAndPersistedFile() async {
    let url = directory.appendingPathComponent("library.json")
    let service = RecordingUserActionsService()
    let repo = LibraryRepository(actionsService: service, fileURL: url)
    _ = await repo.submit(.toggleBookmark(itemId: 42, folderId: 7))
    await repo.flushPersistence()
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

    await repo.deactivate()
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    let snapshot = await repo.currentSnapshot()
    XCTAssertFalse(snapshot.isBookmarked(itemId: 42, folderId: 7))

    // A fresh repository on the same file starts empty (no cross-account leakage).
    let next = LibraryRepository(actionsService: service, fileURL: url)
    await waitUntil { await next.loadCompleted() }
    let nextSnapshot = await next.currentSnapshot()
    XCTAssertTrue(nextSnapshot.records.isEmpty)
  }

  func testCommandsSubmittedAfterDeactivateAreCancelled() async {
    let repo = makeRepository(actionsService: RecordingUserActionsService())
    await repo.deactivate()
    let outcome = await repo.submit(.toggleBookmark(itemId: 42, folderId: 7))
    XCTAssertTrue(isCancelled(outcome))
  }

  // MARK: - Helpers

  private func makeRepository(actionsService: RecordingUserActionsService) -> LibraryRepository {
    LibraryRepository(
      actionsService: actionsService,
      fileURL: directory.appendingPathComponent("library.json"))
  }

  private func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    _ condition: @escaping @Sendable () async -> Bool
  ) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while await !condition() {
      if DispatchTime.now().uptimeNanoseconds > deadline {
        XCTFail("waitUntil timed out")
        return
      }
      await Task.yield()
    }
  }

  /// Drain the cooperative scheduler so tasks created just above get a chance to run.
  private func settle() async {
    for _ in 0..<100 { await Task.yield() }
  }

  private func isApplied(_ outcome: LibraryCommandOutcome) -> Bool {
    if case .applied = outcome { return true }
    return false
  }
  private func isCoalesced(_ outcome: LibraryCommandOutcome) -> Bool {
    if case .coalesced = outcome { return true }
    return false
  }
  private func isFailed(_ outcome: LibraryCommandOutcome) -> Bool {
    if case .failed = outcome { return true }
    return false
  }
  private func isCancelled(_ outcome: LibraryCommandOutcome) -> Bool {
    if case .cancelled = outcome { return true }
    return false
  }
}

private enum TestError: Error {
  case remoteDown
}

// MARK: - Recording stub

/// Records every library mutation and can fail or block calls for concurrency tests.
private actor RecordingUserActionsService: UserActionsService {
  enum Behavior {
    case succeed
    case fail(Error)
    /// Record the first call but keep it in flight until released.
    case blockFirst
  }

  private var behavior: Behavior = .succeed
  private var toggleBookmarkCalls = 0
  private var toggleWatchlistCalls = 0
  private var toggleWatchingCalls = 0
  private var blocked: CheckedContinuation<Void, Never>?
  private var hasBlockedFirstCall = false

  func setBehavior(_ behavior: Behavior) {
    self.behavior = behavior
  }

  func toggleCallCount() -> Int {
    toggleBookmarkCalls + toggleWatchlistCalls + toggleWatchingCalls
  }

  func releaseBlockedCall() {
    blocked?.resume()
    blocked = nil
  }

  private func recordToggle() async throws {
    switch behavior {
    case .succeed:
      break
    case .fail(let error):
      throw error
    case .blockFirst:
      if !hasBlockedFirstCall {
        hasBlockedFirstCall = true
        await withCheckedContinuation { blocked = $0 }
      }
    }
  }

  func toggleBookmark(itemId: Int, folderId: Int) async throws {
    toggleBookmarkCalls += 1
    try await recordToggle()
  }

  func toggleWatchlist(id: Int) async throws {
    toggleWatchlistCalls += 1
    try await recordToggle()
  }

  func toggleWatching(id: Int, video: Int?, season: Int?) async throws {
    toggleWatchingCalls += 1
    try await recordToggle()
  }

  func markWatch(id: Int, time: Int, video: Int?, season: Int?) async throws {}
  func fetchBookmarks() async throws -> [Bookmark] { [] }
  func createBookmarkFolder(title: String) async throws -> Int { 1 }
  func removeBookmarkFolder(id: Int) async throws {}
  func foldersContaining(itemId: Int) async throws -> [Int] { [] }
  func fetchWatchMark(id: Int, video: Int?, season: Int?) async throws -> WatchData {
    throw TestError.remoteDown
  }
  func vote(id: Int, like: Int) async throws -> VoteData { throw TestError.remoteDown }
  func clearHistory(forMedia id: Int) async throws {}
  func clearHistory(forSeason id: Int) async throws {}
  func clearHistory(forItem id: Int) async throws {}
}

// MARK: - Snapshot test helpers

private extension LibrarySnapshot {
  func isBookmarked(itemId: Int, folderId: Int) -> Bool {
    records[itemId]?.bookmarkFolderIds.contains(folderId) ?? false
  }

  func movieWatched(itemId: Int, serverWatched: Bool) -> Bool {
    movieWatchedOverride[itemId] ?? serverWatched
  }
}
