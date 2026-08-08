//
//  LibraryViewState.swift
//  KinoPubAppleClient
//
//  The `@MainActor` UI projection of the library repository. Holds the latest published snapshot
//  for synchronous reads in view bodies, forwards commands to the actor, and joins the separate
//  download-status adapter into its read model (see plans/refactor.md Phase 4). Watch progress
//  stays in `LocalWatchProgressStore`, which feature models query directly.
//

import Foundation
import Combine
import KinoPubBackend
import KinoPubKit

/// The UI projection of the library repository: a `@MainActor` observable snapshot plus the
/// download-status adapter (a separate source joined into one read model).
@MainActor
final class LibraryViewState: ObservableObject {

  enum DownloadStatus: Equatable {
    case none
    case downloading(Double)  // 0...1
    case downloaded
  }

  @Published private(set) var snapshot: LibrarySnapshot = .empty
  /// Convenience projection of `snapshot.bookmarkFolders`, kept as its own `@Published` so the
  /// Bookmarks list can subscribe to folder changes directly.
  @Published private(set) var bookmarkFolders: [Bookmark] = []

  private let repository: LibraryRepository
  private let downloads: LibraryDownloadStatusAdapter
  private var streamTask: Task<Void, Never>?
  private var cancellables = Set<AnyCancellable>()

  /// The composition root (`AppDependencies.make()`/`preview()`) builds this on the main thread
  /// (see the `MainActor.assumeIsolated` wrappers there); every published mutation below also hops
  /// to the main actor.
  init(
    repository: LibraryRepository,
    downloadStatus: LibraryDownloadStatusAdapter
  ) {
    self.repository = repository
    self.downloads = downloadStatus
    streamTask = Task { @MainActor [weak self] in
      guard let self else { return }
      // Seed the snapshot once so the first frame is not empty even before the stream delivers.
      self.snapshot = await self.repository.currentSnapshot()
      self.bookmarkFolders = self.snapshot.bookmarkFolders
      for await next in await self.repository.snapshots() {
        guard !Task.isCancelled else { return }
        self.snapshot = next
        self.bookmarkFolders = next.bookmarkFolders
      }
    }
    // Republish download changes so any view observing the library updates live as downloads
    // progress/complete — mirrors what DownloadsCatalog does for the Downloads tab.
    downloads.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.objectWillChange.send()
      }
      .store(in: &cancellables)
  }

  deinit {
    streamTask?.cancel()
  }

  // MARK: - Commands (optimistic + remote via the repository)

  func toggleBookmark(itemId: Int, folderId: Int) async -> LibraryCommandOutcome {
    await repository.submit(.toggleBookmark(itemId: itemId, folderId: folderId))
  }

  func setBookmark(itemId: Int, folderId: Int, isOn: Bool) async -> LibraryCommandOutcome {
    await repository.submit(.setBookmark(itemId: itemId, folderId: folderId, isOn: isOn))
  }

  func toggleWatchlist(itemId: Int) async -> LibraryCommandOutcome {
    await repository.submit(.toggleWatchlist(itemId: itemId))
  }

  func setWatchlist(itemId: Int, value: Bool) async -> LibraryCommandOutcome {
    await repository.submit(.setWatchlist(itemId: itemId, value: value))
  }

  func toggleMovieWatched(itemId: Int) async -> LibraryCommandOutcome {
    await repository.submit(.toggleMovieWatched(itemId: itemId))
  }

  func toggleEpisodeWatched(itemId: Int, episodeId: Int, video: Int, season: Int) async -> LibraryCommandOutcome {
    await repository.submit(.toggleEpisodeWatched(itemId: itemId, episodeId: episodeId, video: video, season: season))
  }

  func createBookmarkFolder(title: String) async throws -> Int {
    try await repository.createBookmarkFolder(title: title)
  }

  func removeBookmarkFolder(id: Int) async throws {
    try await repository.removeBookmarkFolder(id: id)
  }

  // MARK: - Seeding / reconciliation (authoritative server data)

  func seedIfAbsent(itemId: Int, folderIds: [Int], inWatchlist: Bool) async {
    await repository.seedIfAbsent(itemId: itemId, folderIds: folderIds, inWatchlist: inWatchlist)
  }

  func reconcileWatched(movieItemId: Int, serverMovieWatched: Bool?, episodes: [(id: Int, watched: Bool)]) async {
    await repository.reconcileWatched(
      movieItemId: movieItemId,
      serverMovieWatched: serverMovieWatched,
      episodes: episodes)
  }

  func seedBookmarkMembership(itemId: Int) async {
    await repository.seedBookmarkMembership(itemId: itemId)
  }

  // MARK: - Bookmark folder cache

  func loadBookmarkFoldersIfNeeded() async {
    await repository.loadBookmarkFoldersIfNeeded()
  }

  func reloadBookmarkFolders() async {
    await repository.reloadBookmarkFolders()
  }

  func removeCachedBookmarkFolder(id: Int) async {
    await repository.removeCachedBookmarkFolder(id: id)
  }

  // MARK: - Preferences / votes (local persistence, no remote)

  func setAudioPreference(itemId: Int, _ preference: LibraryAudioPreference) async {
    await repository.setAudioPreference(itemId: itemId, preference)
  }

  func setSubtitlePreference(itemId: Int, _ preference: LibrarySubtitlePreference) async {
    await repository.setSubtitlePreference(itemId: itemId, preference)
  }

  func setUserVote(itemId: Int, up: Bool) async {
    await repository.setUserVote(itemId: itemId, up: up)
  }

  func clearUserVote(itemId: Int) async {
    await repository.clearUserVote(itemId: itemId)
  }

  // MARK: - Account lifecycle

  func deactivate() async {
    await repository.deactivate()
  }

  // MARK: - Reads (snapshot-backed, safe for view bodies)

  func bookmarkFolderIds(itemId: Int) -> Set<Int> {
    Set(snapshot.records[itemId]?.bookmarkFolderIds ?? [])
  }

  func isBookmarked(itemId: Int, folderId: Int) -> Bool {
    snapshot.records[itemId]?.bookmarkFolderIds.contains(folderId) ?? false
  }

  func isInAnyBookmarkFolder(itemId: Int) -> Bool {
    !(snapshot.records[itemId]?.bookmarkFolderIds.isEmpty ?? true)
  }

  func inWatchlist(itemId: Int) -> Bool? {
    snapshot.records[itemId]?.inWatchlist
  }

  /// Effective watched state for a movie: optimistic override if present, else the server's value.
  func movieWatched(itemId: Int, serverWatched: Bool) -> Bool {
    snapshot.movieWatchedOverride[itemId] ?? serverWatched
  }

  /// Effective watched state for an episode: optimistic override if present, else the server's value.
  func episodeWatched(episodeId: Int, serverWatched: Bool) -> Bool {
    snapshot.episodeWatchedOverride[episodeId] ?? serverWatched
  }

  func userVote(itemId: Int) -> Bool? {
    snapshot.userVotes[itemId]
  }

  func audioPreference(itemId: Int) -> LibraryAudioPreference? {
    snapshot.audioPreferences[itemId]
  }

  func subtitlePreference(itemId: Int) -> LibrarySubtitlePreference? {
    snapshot.subtitlePreferences[itemId]
  }

  // MARK: - Downloads (separate adapter source)

  func downloadStatus(itemId: Int, video: Int?, season: Int?) -> DownloadStatus {
    if downloads.isDownloaded(itemId: itemId, video: video, season: season) { return .downloaded }
    if let progress = downloads.activeDownloadProgress(itemId: itemId, video: video, season: season) {
      return .downloading(progress)
    }
    return .none
  }

  func isDownloadedAny(itemId: Int) -> Bool {
    downloads.isDownloadedAny(itemId: itemId)
  }

  func isDownloadingAny(itemId: Int) -> Bool {
    downloads.isDownloadingAny(itemId: itemId)
  }
}

/// Completed/in-flight download index for per-card status reads, kept as a separate source from
/// the library repository and joined into `LibraryViewState`'s read model. Owns the O(1)
/// "downloaded" index and republishes changes as the download managers mutate.
final class LibraryDownloadStatusAdapter: ObservableObject {

  @Published private(set) var downloadedKeys: Set<String> = []

  private let downloadManager: DownloadManager<DownloadMeta>
  private let downloadedFilesDatabase: DownloadedFilesDatabase<DownloadMeta>
  private var cancellables = Set<AnyCancellable>()

  init(
    downloadManager: DownloadManager<DownloadMeta>,
    downloadedFilesDatabase: DownloadedFilesDatabase<DownloadMeta>
  ) {
    self.downloadManager = downloadManager
    self.downloadedFilesDatabase = downloadedFilesDatabase
    // Rebuild the completed-download index so per-card "downloaded" checks stay current and cheap.
    // Index rebuilds touch the downloads database on disk — never on the main thread.
    downloadManager.$activeDownloads
      .receive(on: DispatchQueue.global(qos: .utility))
      .sink { [weak self] _ in
        self?.rebuildDownloadedIndex()
      }
      .store(in: &cancellables)
    DispatchQueue.global(qos: .utility).async { [weak self] in
      self?.rebuildDownloadedIndex()
    }
  }

  func isDownloaded(itemId: Int, video: Int?, season: Int?) -> Bool {
    downloadedKeys.contains(Self.downloadKey(itemId, video, season))
  }

  func isDownloadedAny(itemId: Int) -> Bool {
    let prefix = "\(itemId)|"
    return downloadedKeys.contains { $0.hasPrefix(prefix) }
  }

  /// Whether the title has ANY in-flight download right now (any episode/video).
  func isDownloadingAny(itemId: Int) -> Bool {
    downloadManager.activeDownloads.values.contains(where: { $0.metadata.id == itemId })
  }

  /// Live progress [0,1] of an in-flight download for this item/episode, or nil if none.
  func activeDownloadProgress(itemId: Int, video: Int?, season: Int?) -> Double? {
    if let mp4 = downloadManager.activeDownloads.values.first(where: {
      $0.metadata.id == itemId && $0.metadata.metadata.video == video && $0.metadata.metadata.season == season
    }) {
      return Double(mp4.progress)
    }
    return nil
  }

  /// Rebuild the completed-download index from the downloaded files database. Runs on whatever
  /// thread called it (utility queue by construction); the published index is assigned on main so
  /// `objectWillChange` always fires on the main thread for SwiftUI.
  private func rebuildDownloadedIndex() {
    var keys = Set<String>()
    for file in (downloadedFilesDatabase.readData() ?? [])
    where FileManager.default.fileExists(atPath: file.localFileURL.path) {
      keys.insert(Self.downloadKey(file.metadata.id, file.metadata.metadata.video, file.metadata.metadata.season))
    }
    DispatchQueue.main.async { [weak self] in
      self?.downloadedKeys = keys
    }
  }

  private static func downloadKey(_ id: Int, _ video: Int?, _ season: Int?) -> String {
    "\(id)|\(video.map(String.init) ?? "-")|\(season.map(String.init) ?? "-")"
  }
}
