import XCTest
import KinoPubBackend
@testable import KinoPub

final class LocalWatchProgressStoreTests: XCTestCase {
  private var directory: URL!
  private var fileURL: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("LocalWatchProgressStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    fileURL = directory.appendingPathComponent("progress.json")
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    directory = nil
    fileURL = nil
  }

  func testBelowMinimumAndUnknownItemsAreNotRecorded() {
    let store = LocalWatchProgressStore(fileURL: fileURL)

    store.recordProgress(mediaId: 1, position: 20, duration: 100, season: nil, episode: nil)
    store.cacheItem(.mock(id: 2))
    store.recordProgress(
      mediaId: 2,
      position: LocalWatchProgressStore.minimumSeconds - 1,
      duration: 100,
      season: nil,
      episode: nil
    )

    XCTAssertTrue(store.allEntries().isEmpty)
  }

  func testLatestProgressReplacesSameMediaAndPreservesEpisodeIdentity() {
    var timestamp: TimeInterval = 100
    let store = LocalWatchProgressStore(
      fileURL: fileURL,
      now: { Date(timeIntervalSince1970: timestamp) }
    )
    store.cacheItem(.mock(id: 42))

    store.recordProgress(mediaId: 42, position: 30, duration: 100, season: 1, episode: 2)
    timestamp = 200
    store.recordProgress(mediaId: 42, position: 50, duration: 100, season: 1, episode: 3)

    XCTAssertNil(store.entry(forId: 42, season: 1, episode: 2))
    let latest = store.entry(forId: 42, season: 1, episode: 3)
    XCTAssertEqual(latest?.position, 50)
    XCTAssertEqual(latest?.updatedAt, 200)
    XCTAssertEqual(store.allEntries().map(\.id), [42])
  }

  func testEntriesPersistAcrossStoreInstancesAndClearPersists() {
    let first = LocalWatchProgressStore(fileURL: fileURL)
    first.cacheItem(.mock(id: 7))
    first.recordProgress(mediaId: 7, position: 25, duration: 100, season: nil, episode: nil)

    let reloaded = LocalWatchProgressStore(fileURL: fileURL)
    XCTAssertEqual(reloaded.entry(forId: 7, season: nil, episode: nil)?.position, 25)

    reloaded.clear(id: 7)
    XCTAssertTrue(LocalWatchProgressStore(fileURL: fileURL).allEntries().isEmpty)
  }

  func testCorruptPersistenceStartsEmpty() throws {
    try Data("not-json".utf8).write(to: fileURL)

    let store = LocalWatchProgressStore(fileURL: fileURL)

    XCTAssertTrue(store.allEntries().isEmpty)
  }
}
