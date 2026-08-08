//
//  PlaybackSourceRepositoryTests.swift
//  KinoPubAppleClientTests
//
//  Phase 6: local-vs-remote source resolution and the signed-URL refresh ladder, without
//  AVPlayer or network. Covers local-file preference, local-file disappearance, 3D progressive
//  routing, ladder stepping, and refresh error handling.
//

import XCTest
import CoreGraphics
import KinoPubBackend
@testable import KinoPubKit
@testable import KinoPub

final class PlaybackSourceRepositoryTests: XCTestCase {
  private var directory: URL!
  private var existence: TestFileExistenceChecker!
  private var contentService: StubContentService!
  private var database: DownloadedFilesDatabase<DownloadMeta>!

  override func setUp() {
    super.setUp()
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("PlaybackSourceRepositoryTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    existence = TestFileExistenceChecker()
    contentService = StubContentService()
    let saver = PlaybackTestFileSaver(directory: directory)
    database = DownloadedFilesDatabase<DownloadMeta>(fileSaver: saver)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: directory)
    super.tearDown()
  }

  private func makeRepository() -> PlaybackSourceRepository {
    PlaybackSourceRepository(
      downloadedFilesDatabase: database,
      contentService: contentService,
      fileExistence: existence)
  }

  private func addDownloadedRow(
    originalURL: String,
    localFilename: String,
    itemID: Int,
    files: [FileInfo]
  ) -> URL {
    let meta = DownloadMeta(
      id: itemID,
      files: files,
      originalTitle: "T",
      localizedTitle: "T",
      imageUrl: "",
      metadata: WatchingMetadata(id: itemID))
    // `DownloadedFileInfo.localFileURL` resolves against the (sandboxed) Documents directory, so
    // the row must be registered there — the existence checker, not real files, simulates disk.
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let localURL = documents.appendingPathComponent(localFilename)
    database.save(
      fileInfo: DownloadedFileInfo(
        originalURL: URL(string: originalURL)!,
        localFilename: localFilename,
        downloadDate: Date(),
        metadata: meta))
    existence.registerExisting(localURL.path)
    return localURL
  }

  /// Simulate the file disappearing from disk after the row was written.
  private func removeDownloadedFile(_ localFilename: String, localURL: URL) {
    existence.forgetExisting(localURL.path)
  }

  // MARK: - Local vs remote

  func testLocalDownloadIsPreferredWhenFileExists() async {
    let files = [PlaybackTestFixtures.file(resolution: 1080, http: "https://cdn/x.mp4", hls4: "https://cdn/x.m3u8")]
    let item = PlaybackTestItem(id: 10, files: files, metadata: WatchingMetadata(id: 10))
    let localURL = addDownloadedRow(
      originalURL: "https://cdn/x.mp4",
      localFilename: "x.mp4",
      itemID: 10,
      files: files)

    let source = makeRepository().initialSource(for: item, mode: .media, is3D: false, maxResolution: nil)
    XCTAssertEqual(source?.kind, .localFile)
    XCTAssertEqual(source?.url, localURL)
  }

  func testLocalRowWhoseFileDisappearedFallsThroughToRemote() async {
    let files = [PlaybackTestFixtures.file(resolution: 1080, http: "https://cdn/x.mp4", hls4: "https://cdn/x.m3u8")]
    let item = PlaybackTestItem(id: 10, files: files, metadata: WatchingMetadata(id: 10))
    let localURL = addDownloadedRow(originalURL: "https://cdn/x.mp4", localFilename: "x.mp4", itemID: 10, files: files)
    // The file was deleted from disk; the database row is stale.
    removeDownloadedFile("x.mp4", localURL: localURL)

    let source = makeRepository().initialSource(for: item, mode: .media, is3D: false, maxResolution: nil)
    XCTAssertEqual(source?.kind, .remoteHLS)
    XCTAssertEqual(source?.url.absoluteString, "https://cdn/x.m3u8")
  }

  func testEpisodeRowMatchPrefersMatchingSourceURL() async {
    // Two downloads under the same series id: the first row belongs to a different episode.
    let episodeFiles = [PlaybackTestFixtures.file(resolution: 720, http: "https://cdn/ep2.mp4")]
    addDownloadedRow(originalURL: "https://cdn/ep1.mp4", localFilename: "ep1.mp4", itemID: 7, files: [])
    let localURL = addDownloadedRow(
      originalURL: "https://cdn/ep2.mp4",
      localFilename: "ep2.mp4",
      itemID: 7,
      files: episodeFiles)

    let item = PlaybackTestItem(id: 77, files: episodeFiles, metadata: WatchingMetadata(id: 7, video: 2, season: 1))
    let source = makeRepository().initialSource(for: item, mode: .media, is3D: false, maxResolution: nil)
    XCTAssertEqual(source?.url, localURL)
  }

  // MARK: - 3D and remote ladder

  func test3DTitleUsesProgressiveURL() async {
    let files = [
      PlaybackTestFixtures.file(resolution: 1080, http: "https://cdn/3d.mp4", hls4: "https://cdn/3d.m3u8")
    ]
    let item = PlaybackTestItem(id: 1, files: files, metadata: WatchingMetadata(id: 1))
    let source = makeRepository().initialSource(for: item, mode: .media, is3D: true, maxResolution: nil)
    XCTAssertEqual(source?.kind, .remoteProgressive)
    XCTAssertEqual(source?.url.absoluteString, "https://cdn/3d.mp4")
  }

  func testRemoteLadderStartsAtHLS4() async {
    let files = [PlaybackTestFixtures.file(resolution: 1080, hls4: "https://cdn/x.m3u8", hls2: "https://cdn/y.m3u8")]
    let item = PlaybackTestItem(id: 1, files: files, metadata: WatchingMetadata(id: 1))
    let source = makeRepository().initialSource(for: item, mode: .media, is3D: false, maxResolution: nil)
    XCTAssertEqual(source?.kind, .remoteHLS)
    XCTAssertEqual(source?.url.absoluteString, "https://cdn/x.m3u8")
    XCTAssertEqual(source?.streamType, "hls4")
  }

  func testTrailerSource() async {
    let trailer = Trailer(url: "https://cdn/trailer.m3u8")
    let item = PlaybackTestItem(id: 1, trailer: trailer)
    let source = makeRepository().initialSource(for: item, mode: .trailer, is3D: false, maxResolution: nil)
    XCTAssertEqual(source?.kind, .trailer)
    XCTAssertEqual(source?.url.absoluteString, "https://cdn/trailer.m3u8")
  }

  func testMissingItemFilesReturnNil() async {
    let item = PlaybackTestItem(id: 1)
    let source = makeRepository().initialSource(for: item, mode: .media, is3D: false, maxResolution: nil)
    XCTAssertNil(source)
  }

  // MARK: - Signed-URL refresh ladder

  func testRefreshWalksLadderHLS4ToHLS2ToProgressive() async throws {
    let files = [
      PlaybackTestFixtures.file(
        resolution: 1080, http: "https://cdn/p.mp4", hls4: "https://cdn/x.m3u8", hls2: "https://cdn/y.m3u8")
    ]
    let item = PlaybackTestItem(id: 1, files: files, metadata: WatchingMetadata(id: 1))
    let repository = makeRepository()

    await contentService.setLinksFiles(files)
    await contentService.setVideoLinkURL("https://fresh/1.m3u8")
    let first = try await repository.refreshSource(for: item, recoveryAttempt: 0, maxResolution: nil)
    XCTAssertEqual(first.kind, .remoteHLS)
    XCTAssertEqual(first.streamType, "hls4")
    XCTAssertEqual(first.url.absoluteString, "https://fresh/1.m3u8")

    await contentService.setVideoLinkURL("https://fresh/2.m3u8")
    let second = try await repository.refreshSource(for: item, recoveryAttempt: 1, maxResolution: nil)
    XCTAssertEqual(second.streamType, "hls2")
    XCTAssertEqual(second.url.absoluteString, "https://fresh/2.m3u8")

    await contentService.setVideoLinkURL("https://fresh/p.mp4")
    let third = try await repository.refreshSource(for: item, recoveryAttempt: 2, maxResolution: nil)
    XCTAssertEqual(third.kind, .remoteProgressive)
    XCTAssertEqual(third.streamType, "http")
    XCTAssertEqual(third.url.absoluteString, "https://fresh/p.mp4")
  }

  func testRefreshFetchesLinksOnceAndUsesGeneratedURLNext() async throws {
    let files = [PlaybackTestFixtures.file(resolution: 1080, hls4: "https://cdn/x.m3u8")]
    let item = PlaybackTestItem(id: 1, files: files, metadata: WatchingMetadata(id: 1))
    let repository = makeRepository()

    await contentService.setLinksFiles([PlaybackTestFixtures.file(resolution: 720, hls4: "https://cdn/new.m3u8")])
    await contentService.setVideoLinkURL("https://fresh/1.m3u8")
    _ = try await repository.refreshSource(for: item, recoveryAttempt: 0, maxResolution: nil)

    // The generated URL now wins over the item's own hls4 (expired links are never reused).
    let source = repository.initialSource(for: item, mode: .media, is3D: false, maxResolution: nil)
    XCTAssertEqual(source?.url.absoluteString, "https://fresh/1.m3u8")

    // A second refresh must reuse the refreshed file list (no second media-links call).
    await contentService.setVideoLinkURL("https://fresh/2.m3u8")
    _ = try await repository.refreshSource(for: item, recoveryAttempt: 1, maxResolution: nil)
    let videoLinkCalls = await contentService.videoLinkCalls
    let linksCalls = await contentService.linksCalls
    XCTAssertEqual(videoLinkCalls.map(\.type), ["hls4", "hls2"])
    XCTAssertEqual(linksCalls, 1)
  }

  func testRefreshErrors() async {
    let files = [PlaybackTestFixtures.file(resolution: 1080, hls4: "https://cdn/x.m3u8")]
    let item = PlaybackTestItem(id: 1, files: files, metadata: WatchingMetadata(id: 1))

    // Each case uses a fresh repository: refreshSource caches the refreshed file list, so later
    // cases must not inherit state from earlier ones.
    await contentService.setShouldFailLinks(true)
    await assertRefreshError(nil, repository: makeRepository(), item: item)

    await contentService.setShouldFailLinks(false)
    await contentService.setLinksFiles([])
    await assertRefreshError(.missingFiles, repository: makeRepository(), item: item)

    // A file without a server path cannot mint a URL.
    let pathless = FileInfo(
      codec: "h264", w: 1920, h: 1080, quality: "1080p", qualityID: 1080,
      url: URLInfo(http: "", hls: "", hls4: "", hls2: ""))
    await contentService.setLinksFiles([pathless])
    await assertRefreshError(.missingFilePath, repository: makeRepository(), item: item)

    await contentService.setLinksFiles(files)
    await contentService.setVideoLinkURL("")
    await assertRefreshError(.missingURL, repository: makeRepository(), item: item)
  }

  /// Asserts the refresh throws exactly `expected` (nil = any non-PlaybackRefreshError error).
  private func assertRefreshError(
    _ expected: PlaybackSourceRepository.PlaybackRefreshError?,
    repository: PlaybackSourceRepository,
    item: PlaybackTestItem,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    do {
      _ = try await repository.refreshSource(for: item, recoveryAttempt: 0, maxResolution: nil)
      XCTFail("expected \(String(describing: expected))", file: file, line: line)
    } catch let error as PlaybackSourceRepository.PlaybackRefreshError {
      XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
      if expected != nil {
        XCTFail("unexpected error: \(error)", file: file, line: line)
      }
    }
  }

  // MARK: - Preferred file / quality cap

  func testPreferredFileAppliesResolutionCap() async {
    let repository = makeRepository()
    let files = [
      PlaybackTestFixtures.file(resolution: 480),
      PlaybackTestFixtures.file(resolution: 720),
      PlaybackTestFixtures.file(resolution: 1080),
    ]
    let capped = repository.preferredFile(in: files, maxResolution: CGSize(width: 1280, height: 720))
    XCTAssertEqual(capped?.resolution, 720)
    let uncapped = repository.preferredFile(in: files, maxResolution: nil)
    XCTAssertEqual(uncapped?.resolution, 1080)
    // A cap below every rung falls back to the best file rather than failing.
    let belowAll = repository.preferredFile(in: files, maxResolution: CGSize(width: 640, height: 360))
    XCTAssertEqual(belowAll?.resolution, 1080)
  }

  func testResetForgetsRecoveryState() async throws {
    let files = [PlaybackTestFixtures.file(resolution: 1080, hls4: "https://cdn/x.m3u8")]
    let item = PlaybackTestItem(id: 1, files: files, metadata: WatchingMetadata(id: 1))
    let repository = makeRepository()

    await contentService.setLinksFiles(files)
    await contentService.setVideoLinkURL("https://fresh/1.m3u8")
    _ = try await repository.refreshSource(for: item, recoveryAttempt: 0, maxResolution: nil)
    XCTAssertEqual(
      (repository.initialSource(for: item, mode: .media, is3D: false, maxResolution: nil))?.url.absoluteString,
      "https://fresh/1.m3u8")

    repository.reset()
    let afterReset = repository.initialSource(for: item, mode: .media, is3D: false, maxResolution: nil)
    XCTAssertEqual(afterReset?.url.absoluteString, "https://cdn/x.m3u8")
  }
}
