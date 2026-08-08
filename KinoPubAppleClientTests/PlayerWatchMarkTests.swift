import XCTest
import KinoPubBackend
import KinoPubKit
@testable import KinoPub

@MainActor
final class PlayerWatchMarkTests: XCTestCase {
  func testWatchMarksAreSerializedAndCoalescedWithoutMovingBackward() async {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("PlayerWatchMarkTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let saver = PlayerTestFileSaver(directory: directory)
    let database = DownloadedFilesDatabase<DownloadMeta>(fileSaver: saver)
    let service = ControlledUserActionsService()
    let manager = PlayerManager(
      playItem: PlayerTestItem(id: 100, metadata: WatchingMetadata(id: 42, video: 3, season: 2)),
      watchMode: .trailer,
      downloadedFilesDatabase: database,
      actionsService: service,
      contentService: VideoContentServiceMock(),
      localProgressStore: LocalWatchProgressStore(fileURL: directory.appendingPathComponent("progress.json")),
      libraryState: makePreviewLibrary(saver: saver, database: database, actionsService: service)
    )

    manager.saveWatchMark(time: 10)
    await service.waitForCallCount(1)

    // These arrive while the first request is blocked. The queue must retain only the newest
    // position for the same media identity and reject the delayed lower value.
    manager.saveWatchMark(time: 20)
    manager.saveWatchMark(time: 15)
    manager.saveWatchMark(time: 30)

    await service.releaseFirstCall()
    await service.waitForCallCount(2)

    let calls = await service.recordedCalls()
    XCTAssertEqual(calls.map(\.time), [10, 30])
    XCTAssertEqual(calls.map(\.id), [42, 42])
    XCTAssertEqual(calls.map(\.video), [3, 3])
    XCTAssertEqual(calls.map(\.season), [2, 2])
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

private struct PlayerTestItem: PlayableItem {
  let id: Int
  let files: [FileInfo] = []
  let trailer: Trailer? = nil
  let metadata: WatchingMetadata
}

private final class PlayerTestFileSaver: FileSaving {
  let directory: URL

  init(directory: URL) {
    self.directory = directory
  }

  func saveFile(from sourceURL: URL, to destinationURL: URL) throws {
    try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
  }

  func removeFile(at sourceURL: URL) throws {
    try FileManager.default.removeItem(at: sourceURL)
  }

  func getDocumentsDirectoryURL(forFilename filename: String) -> URL {
    directory.appendingPathComponent(filename)
  }
}

private actor ControlledUserActionsService: UserActionsService {
  struct Call: Equatable {
    let id: Int
    let time: Int
    let video: Int?
    let season: Int?
  }

  private var calls: [Call] = []
  private var firstCallContinuation: CheckedContinuation<Void, Never>?

  func markWatch(id: Int, time: Int, video: Int?, season: Int?) async throws {
    calls.append(Call(id: id, time: time, video: video, season: season))
    if calls.count == 1 {
      await withCheckedContinuation { continuation in
        firstCallContinuation = continuation
      }
    }
  }

  func waitForCallCount(_ count: Int) async {
    while calls.count < count {
      await Task.yield()
    }
  }

  func releaseFirstCall() {
    firstCallContinuation?.resume()
    firstCallContinuation = nil
  }

  func recordedCalls() -> [Call] { calls }

  func toggleWatching(id: Int, video: Int?, season: Int?) async throws {}
  func toggleWatchlist(id: Int) async throws {}
  func toggleBookmark(itemId: Int, folderId: Int) async throws {}
  func fetchBookmarks() async throws -> [Bookmark] { [] }
  func createBookmarkFolder(title: String) async throws -> Int { 1 }
  func removeBookmarkFolder(id: Int) async throws {}
  func foldersContaining(itemId: Int) async throws -> [Int] { [] }
  func fetchWatchMark(id: Int, video: Int?, season: Int?) async throws -> WatchData {
    throw PlayerTestError.notImplemented
  }
  func vote(id: Int, like: Int) async throws -> VoteData { throw PlayerTestError.notImplemented }
  func clearHistory(forMedia id: Int) async throws {}
  func clearHistory(forSeason id: Int) async throws {}
  func clearHistory(forItem id: Int) async throws {}
}

private enum PlayerTestError: Error {
  case notImplemented
}
