import XCTest
import KinoPubBackend
import KinoPubKit
@testable import KinoPub

@MainActor
final class MediaLibraryStoreTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("MediaLibraryStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    directory = nil
  }

  func testBookmarkOptimisticToggleCanBeReverted() {
    let store = makeStore()
    store.seedIfAbsent(itemId: 42, folderIds: [], inWatchlist: false)

    let optimisticValue = store.toggleBookmark(itemId: 42, folderId: 7)
    XCTAssertTrue(optimisticValue)
    XCTAssertTrue(store.isBookmarked(itemId: 42, folderId: 7))

    store.setBookmark(itemId: 42, folderId: 7, isOn: !optimisticValue)
    XCTAssertFalse(store.isBookmarked(itemId: 42, folderId: 7))
  }

  func testWatchlistOptimisticValueCanBeReverted() {
    let store = makeStore()
    store.seedIfAbsent(itemId: 42, folderIds: [], inWatchlist: false)

    store.setWatchlist(itemId: 42, value: true)
    XCTAssertEqual(store.inWatchlist(itemId: 42), true)

    store.setWatchlist(itemId: 42, value: false)
    XCTAssertEqual(store.inWatchlist(itemId: 42), false)
  }

  func testWatchedOverrideWinsUntilServerReconcilesIt() {
    let store = makeStore()

    store.setMovieWatched(itemId: 42, value: true)
    XCTAssertTrue(store.movieWatched(itemId: 42, serverWatched: false))

    store.reconcileWatched(movieItemId: 42, serverMovieWatched: true, episodes: [])
    XCTAssertFalse(store.movieWatched(itemId: 42, serverWatched: false))
  }

  func testOptimisticStatePersistsAcrossStoreInstances() {
    let first = makeStore()
    first.seedIfAbsent(itemId: 42, folderIds: [7], inWatchlist: true)
    first.setMovieWatched(itemId: 42, value: true)

    let reloaded = makeStore()

    XCTAssertTrue(reloaded.isBookmarked(itemId: 42, folderId: 7))
    XCTAssertEqual(reloaded.inWatchlist(itemId: 42), true)
    XCTAssertTrue(reloaded.movieWatched(itemId: 42, serverWatched: false))
  }

  private func makeStore() -> MediaLibraryStore {
    let saver = TestFileSaver(directory: directory)
    let database = DownloadedFilesDatabase<DownloadMeta>(fileSaver: saver)
    let manager = DownloadManager<DownloadMeta>(fileSaver: saver, database: database)
    return MediaLibraryStore(
      downloadManager: manager,
      downloadedFilesDatabase: database,
      progressStore: LocalWatchProgressStore(fileURL: directory.appendingPathComponent("progress.json")),
      actionsService: UserActionsServiceStub(),
      fileURL: directory.appendingPathComponent("library.json")
    )
  }
}

private final class TestFileSaver: FileSaving {
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

private struct UserActionsServiceStub: UserActionsService {
  func markWatch(id: Int, time: Int, video: Int?, season: Int?) async throws {}
  func toggleWatching(id: Int, video: Int?, season: Int?) async throws {}
  func toggleWatchlist(id: Int) async throws {}
  func toggleBookmark(itemId: Int, folderId: Int) async throws {}
  func fetchBookmarks() async throws -> [Bookmark] { [] }
  func createBookmarkFolder(title: String) async throws -> Int { 1 }
  func removeBookmarkFolder(id: Int) async throws {}
  func foldersContaining(itemId: Int) async throws -> [Int] { [] }
  func fetchWatchMark(id: Int, video: Int?, season: Int?) async throws -> WatchData {
    throw StubError.notImplemented
  }
  func vote(id: Int, like: Int) async throws -> VoteData { throw StubError.notImplemented }
  func clearHistory(forMedia id: Int) async throws {}
  func clearHistory(forSeason id: Int) async throws {}
  func clearHistory(forItem id: Int) async throws {}
}

private enum StubError: Error {
  case notImplemented
}
