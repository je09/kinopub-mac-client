//
//  PlaybackTestSupport.swift
//  KinoPubAppleClientTests
//
//  Shared fixtures for Phase 6 playback tests: a minimal `PlayableItem`, a temp-dir file saver,
//  a configurable file-existence checker, a controllable content-service stub, and a blocking
//  user-actions service. Everything is in-memory / temp-dir — no network, no real files.
//

import Foundation
import KinoPubBackend
@testable import KinoPubKit
@testable import KinoPub

/// A minimal `PlayableItem` for playback tests (movies, episodes, and trailers alike).
struct PlaybackTestItem: PlayableItem {
  let id: Int
  let files: [FileInfo]
  let trailer: Trailer?
  let metadata: WatchingMetadata
  let playerTitle: String
  let playerSubtitle: String?

  init(
    id: Int,
    files: [FileInfo] = [],
    trailer: Trailer? = nil,
    metadata: WatchingMetadata = WatchingMetadata(id: 1),
    playerTitle: String = "Test",
    playerSubtitle: String? = nil
  ) {
    self.id = id
    self.files = files
    self.trailer = trailer
    self.metadata = metadata
    self.playerTitle = playerTitle
    self.playerSubtitle = playerSubtitle
  }
}

/// Writes DB files into the temporary directory instead of the app container.
final class PlaybackTestFileSaver: FileSaving {
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

/// Configurable file-existence check: only paths registered as present "exist".
final class TestFileExistenceChecker: FileExistenceChecking {
  private(set) var existingPaths: Set<String> = []

  func registerExisting(_ path: String) {
    existingPaths.insert(path)
  }

  func forgetExisting(_ path: String) {
    existingPaths.remove(path)
  }

  func fileExists(atPath path: String) -> Bool {
    existingPaths.contains(path)
  }
}

/// Content-service stub with controllable media-links / video-link responses and call recording.
actor StubContentService: VideoContentService {
  var linksFiles: [FileInfo] = []
  var videoLinkURL: String = ""
  var shouldFailLinks = false
  var shouldFailVideoLink = false
  private(set) var linksCalls = 0
  private(set) var videoLinkCalls: [(file: String, type: String)] = []

  func setLinksFiles(_ files: [FileInfo]) { linksFiles = files }
  func setVideoLinkURL(_ url: String) { videoLinkURL = url }
  func setShouldFailLinks(_ fail: Bool) { shouldFailLinks = fail }
  func setShouldFailVideoLink(_ fail: Bool) { shouldFailVideoLink = fail }

  func fetchMediaLinks(mediaID: Int) async throws -> MediaLinksData {
    linksCalls += 1
    if shouldFailLinks { throw PlaybackStubError.linksFailed }
    return MediaLinksData(id: mediaID, files: linksFiles, subtitles: nil, thumbnail: nil)
  }

  func fetchMediaVideoLink(file: String, type: String) async throws -> MediaVideoLinkData {
    videoLinkCalls.append((file, type))
    if shouldFailVideoLink { throw PlaybackStubError.videoLinkFailed }
    return MediaVideoLinkData(url: videoLinkURL)
  }

  func fetch(
    shortcut: MediaShortcut, contentType: MediaType, page: Int?, forceRefresh: Bool
  ) async throws -> PaginatedData<MediaItem> {
    PaginatedData.mock(data: [])
  }
  func search(
    query: String?, contentType: MediaType?, field: String?, page: Int?
  ) async throws -> PaginatedData<MediaItem> {
    PaginatedData.mock(data: [])
  }
  func filter(filter: MediaItemsFilter, page: Int?, forceRefresh: Bool) async throws -> PaginatedData<MediaItem> {
    PaginatedData.mock(data: [])
  }
  func itemsByPerson(name: String, field: String, page: Int?) async throws -> PaginatedData<MediaItem> {
    PaginatedData.mock(data: [])
  }
  func fetchGenres(type: MediaType?) async throws -> [MediaGenre] { [] }
  func fetchCountries() async throws -> [Country] { [] }
  func fetchDetails(for id: String) async throws -> SingleItemData<MediaItem> {
    SingleItemData.mock(data: MediaItem.mock())
  }
  func fetchBookmarks() async throws -> ArrayData<Bookmark> { ArrayData.mock(data: []) }
  func fetchBookmarkItems(id: String) async throws -> ArrayData<MediaItem> { ArrayData.mock(data: []) }
  func fetchHistory(page: Int?) async throws -> HistoryData { HistoryData.mock() }
  func fetchWatchingSerials(subscribed: Int?, type: String?) async throws -> ArrayData<WatchingSerial> {
    ArrayData.mock(data: [])
  }
  func fetchWatchingMovies() async throws -> ArrayData<WatchingSerial> { ArrayData.mock(data: []) }
  func fetchTVChannels() async throws -> [TVChannel] { [] }
  func fetchComments(for id: Int) async throws -> CommentsData { CommentsData.mock() }
}

enum PlaybackStubError: Error {
  case linksFailed
  case videoLinkFailed
}

/// A blocking `UserActionsService`: the first `markWatch` call waits until released, so tests can
/// interleave enqueues and observe the serialized, coalesced drain order.
actor ControlledUserActionsService: UserActionsService {
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
    throw PlaybackStubError.linksFailed
  }
  func vote(id: Int, like: Int) async throws -> VoteData { throw PlaybackStubError.linksFailed }
  func clearHistory(forMedia id: Int) async throws {}
  func clearHistory(forSeason id: Int) async throws {}
  func clearHistory(forItem id: Int) async throws {}
}

// MARK: - Episode + file builders

enum PlaybackTestFixtures {
  /// A real `Episode` value (constructible now that the backend models expose public inits).
  static func episode(id: Int, number: Int, season: Int? = 1) -> Episode {
    let episode = Episode(
      id: id,
      title: "Episode \(number)",
      thumbnail: "",
      duration: 1800,
      tracks: 2,
      number: number,
      ac3: 0,
      audios: [],
      watched: 0,
      watching: EpisodeWatching(status: 0, time: 0),
      subtitles: [],
      files: [])
    episode.seasonNumber = season
    episode.mediaId = 100
    return episode
  }

  static func file(resolution: Int, http: String = "", hls4: String = "", hls2: String = "") -> FileInfo {
    FileInfo(
      codec: "h264",
      w: resolution * 16 / 9,
      h: resolution,
      quality: "\(resolution)p",
      qualityID: resolution,
      file: "/media/\(resolution).mp4",
      url: URLInfo(http: http, hls: "", hls4: hls4, hls2: hls2))
  }

  /// Builds a database seeded with one downloaded row.
  static func makeDatabase(
    in directory: URL,
    originalURL: String,
    localFilename: String,
    metadata: DownloadMeta
  ) -> DownloadedFilesDatabase<DownloadMeta> {
    let saver = PlaybackTestFileSaver(directory: directory)
    let database = DownloadedFilesDatabase<DownloadMeta>(fileSaver: saver)
    database.save(
      fileInfo: DownloadedFileInfo(
        originalURL: URL(string: originalURL)!,
        localFilename: localFilename,
        downloadDate: Date(),
        metadata: metadata))
    return database
  }
}
