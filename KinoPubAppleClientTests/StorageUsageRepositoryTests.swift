import XCTest
@testable import KinoPub

/// Deterministic filesystem contracts for `StorageUsageRepository` (Phase 5): file/bundle sizes and
/// the downloads bucket of the usage snapshot, computed off the main actor against temp files.
final class StorageUsageRepositoryTests: XCTestCase {

  func testByteSizeComputesRegularFilesExactly() async throws {
    let dir = try makeTempDir()
    let file = dir.appendingPathComponent("movie.mp4")
    try Data(repeating: 0xAB, count: 4096).write(to: file)

    let repository = StorageUsageRepository(epgService: EPGServiceMock())
    let size = await repository.byteSize(of: file)
    XCTAssertEqual(size, 4096)
  }

  func testByteSizeSumsMovpkgBundleContents() async throws {
    let dir = try makeTempDir()
    // An HLS download is a `.movpkg` *bundle* (a directory); attributesOfItem alone would return
    // only the tiny directory entry, so the repository must sum the contents.
    let bundle = dir.appendingPathComponent("show.movpkg")
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    try Data(repeating: 0xCD, count: 2048).write(to: bundle.appendingPathComponent("seg0.ts"))
    try Data(repeating: 0xEF, count: 1024).write(to: bundle.appendingPathComponent("seg1.ts"))

    let repository = StorageUsageRepository(epgService: EPGServiceMock())
    let size = await repository.byteSize(of: bundle)
    XCTAssertGreaterThanOrEqual(size, 2048 + 1024)
  }

  func testUsageSnapshotBucketsDownloadsFromProvidedURLs() async throws {
    let dir = try makeTempDir()
    let movie = dir.appendingPathComponent("movie.mp4")
    let episode = dir.appendingPathComponent("s1e1.movpkg")
    try Data(repeating: 0x11, count: 1024).write(to: movie)
    try FileManager.default.createDirectory(at: episode, withIntermediateDirectories: true)
    try Data(repeating: 0x22, count: 512).write(to: episode.appendingPathComponent("seg.ts"))

    let repository = StorageUsageRepository(epgService: EPGServiceMock())
    let usage = await repository.usage(downloadURLs: [movie, episode])

    // Downloads bucket must equal the per-file bundle-aware sizes (logical size for a plain file,
    // allocated size for a bundle's contents).
    let movieSize = await repository.byteSize(of: movie)
    let episodeSize = await repository.byteSize(of: episode)
    let expected = movieSize + episodeSize
    XCTAssertEqual(usage.downloads, expected)
    XCTAssertGreaterThanOrEqual(usage.downloads, 1024 + 512)
    // The whole app container is always non-empty (Documents/Library/tmp exist).
    XCTAssertGreaterThan(usage.total, usage.downloads)
  }

  func testMissingFileReportsZero() async {
    let repository = StorageUsageRepository(epgService: EPGServiceMock())
    let missing = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).mp4")
    let size = await repository.byteSize(of: missing)
    XCTAssertEqual(size, 0)
  }

  private func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("StorageUsageRepositoryTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }
}
