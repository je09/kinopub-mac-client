import XCTest
import KinoPubBackend
import KinoPubKit
@testable import KinoPubBackend
@testable import KinoPub

/// Phase 6: watch marks are serialized, coalesced per media identity, and never sent out of
/// order (see plans/refactor.md — "No watch-mark can be sent out of order"). Tests the
/// `WatchProgressSync` actor directly, plus one PlayerManager façade integration test proving the
/// periodic tick still routes through the same queue.
@MainActor
final class PlayerWatchMarkTests: XCTestCase {
  private var directory: URL!

  override func setUp() {
    super.setUp()
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("PlayerWatchMarkTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: directory)
    super.tearDown()
  }

  private func makeSync(service: ControlledUserActionsService) -> WatchProgressSync {
    let store = LocalWatchProgressStore(
      fileURL: directory.appendingPathComponent("progress.json"))
    // `recordProgress` only records when the item has a cached snapshot (used to render Continue
    // cards), so seed the same identity the marks report.
    store.cacheItem(MediaItem.mock(id: 42))
    return WatchProgressSync(actionsService: service, localProgressStore: store)
  }

  func testWatchMarksAreSerializedAndCoalescedWithoutMovingBackward() async {
    let service = ControlledUserActionsService()
    let sync = makeSync(service: service)

    await sync.recordProgress(mediaId: 42, position: 10, duration: 600, season: 2, episode: 3)
    await service.waitForCallCount(1)

    // These arrive while the first request is blocked. The queue must retain only the newest
    // position for the same media identity and reject the delayed lower value.
    await sync.enqueueMark(id: 42, video: 3, season: 2, time: 20)
    await sync.enqueueMark(id: 42, video: 3, season: 2, time: 15)
    await sync.enqueueMark(id: 42, video: 3, season: 2, time: 30)

    await service.releaseFirstCall()
    await service.waitForCallCount(2)

    let calls = await service.recordedCalls()
    XCTAssertEqual(calls.map(\.time), [10, 30])
    XCTAssertEqual(calls.map(\.id), [42, 42])
    XCTAssertEqual(calls.map(\.video), [3, 3])
    XCTAssertEqual(calls.map(\.season), [2, 2])
  }

  func testDifferentMediaIdentitiesQueueIndependently() async {
    let service = ControlledUserActionsService()
    let sync = makeSync(service: service)

    await sync.enqueueMark(id: 1, video: nil, season: nil, time: 5)
    await service.waitForCallCount(1)
    await sync.enqueueMark(id: 2, video: nil, season: nil, time: 9)
    await service.releaseFirstCall()
    await service.waitForCallCount(2)

    let calls = await service.recordedCalls()
    XCTAssertEqual(calls.map(\.id), [1, 2])
    XCTAssertEqual(calls.map(\.time), [5, 9])
  }

  func testCancellationStopsTheWorker() async {
    let service = ControlledUserActionsService()
    let sync = makeSync(service: service)

    await sync.enqueueMark(id: 42, video: nil, season: nil, time: 10)
    await service.waitForCallCount(1)
    await sync.enqueueMark(id: 42, video: nil, season: nil, time: 20)
    await sync.cancel()
    await service.releaseFirstCall()
    // Give the worker a chance to (incorrectly) drain; it must not send the queued mark.
    try? await Task.sleep(for: .milliseconds(100))
    let calls = await service.recordedCalls()
    XCTAssertEqual(calls.map(\.time), [10])
  }

  func testRecordProgressPersistsLocalResumePoint() async {
    let service = ControlledUserActionsService()
    let store = LocalWatchProgressStore(fileURL: directory.appendingPathComponent("progress.json"))
    store.cacheItem(MediaItem.mock(id: 42))
    let sync = WatchProgressSync(actionsService: service, localProgressStore: store)

    await sync.recordProgress(mediaId: 42, position: 120, duration: 600, season: 2, episode: 3)
    let entry = store.entry(forId: 42, season: 2, episode: 3)
    XCTAssertEqual(entry?.position, 120)
    await service.releaseFirstCall()
  }

  func testMarkFinishedClearsLocalProgressAndSendsFinalMark() async {
    let service = ControlledUserActionsService()
    let store = LocalWatchProgressStore(fileURL: directory.appendingPathComponent("progress.json"))
    store.cacheItem(MediaItem.mock(id: 42))
    let sync = WatchProgressSync(actionsService: service, localProgressStore: store)

    await sync.recordProgress(mediaId: 42, position: 100, duration: 600, season: 2, episode: 3)
    await service.waitForCallCount(1)
    await sync.markFinished(mediaId: 42, season: 2, episode: 3, duration: 600)
    await service.releaseFirstCall()
    await service.waitForCallCount(2)

    XCTAssertNil(store.entry(forId: 42, season: 2, episode: 3))
    let calls = await service.recordedCalls()
    XCTAssertEqual(calls.map(\.time), [100, 600])
  }

  func testMarkFinishedIgnoresNonFiniteOrEmptyDuration() async {
    let service = ControlledUserActionsService()
    let store = LocalWatchProgressStore(fileURL: directory.appendingPathComponent("progress.json"))
    store.cacheItem(MediaItem.mock(id: 42))
    let sync = WatchProgressSync(actionsService: service, localProgressStore: store)

    await sync.recordProgress(mediaId: 42, position: 100, duration: 600, season: 2, episode: 3)
    await sync.markFinished(mediaId: 42, season: 2, episode: 3, duration: .infinity)
    await sync.markFinished(mediaId: 42, season: 2, episode: 3, duration: 0)
    try? await Task.sleep(for: .milliseconds(100))
    await service.releaseFirstCall()
    // Only the periodic mark was sent; the local resume point survives.
    XCTAssertNotNil(store.entry(forId: 42, season: 2, episode: 3))
    let sent = await service.recordedCalls();
    XCTAssertEqual(sent.count, 1)
  }

  // MARK: - PlayerManager façade integration

  func testPlayerManagerSaveWatchMarkRoutesThroughTheQueue() async {
    let service = ControlledUserActionsService()
    let saver = PlaybackTestFileSaver(directory: directory)
    let database = DownloadedFilesDatabase<DownloadMeta>(fileSaver: saver)
    let manager = PlayerManager(
      playItem: PlaybackTestItem(id: 100, metadata: WatchingMetadata(id: 42, video: 3, season: 2)),
      watchMode: .trailer,
      downloadedFilesDatabase: database,
      actionsService: service,
      contentService: VideoContentServiceMock(),
      localProgressStore: LocalWatchProgressStore(fileURL: directory.appendingPathComponent("progress.json")),
      libraryState: makePreviewLibrary(saver: saver, database: database, actionsService: service)
    )

    manager.saveWatchMark(time: 10)
    await service.waitForCallCount(1)
    manager.saveWatchMark(time: 30)
    await service.releaseFirstCall()
    await service.waitForCallCount(2)

    let calls = await service.recordedCalls()
    XCTAssertEqual(calls.map(\.time), [10, 30])
    XCTAssertEqual(calls.map(\.id), [42, 42])
  }

  /// Builds an isolated `LibraryViewState` for the player test (temp file, no production state).
  private func makePreviewLibrary(
    saver: FileSaving,
    database: DownloadedFilesDatabase<DownloadMeta>,
    actionsService: UserActionsService
  ) -> LibraryViewState {
    let manager = DownloadManager<DownloadMeta>(fileSaver: saver, database: database)
    let repository = LibraryRepository(
      actionsService: actionsService,
      fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("PlayerWatchMarkTests-library-\(UUID().uuidString).json"))
    return LibraryViewState(
      repository: repository,
      downloadStatus: LibraryDownloadStatusAdapter(
        downloadManager: manager,
        downloadedFilesDatabase: database))
  }
}
