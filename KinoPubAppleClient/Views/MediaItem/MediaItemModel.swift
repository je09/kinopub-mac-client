//
//  MediaItemModel.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 2.08.2023.
//

import Foundation
import KinoPubBackend
import OSLog
import KinoPubLogging
import KinoPubKit
import KinoPubUI

/// The current user's like/dislike choice for a title (this session only).
public enum UserVote: Equatable {
  case none, up, down
}

@MainActor
class MediaItemModel: ObservableObject {

  private var itemsService: VideoContentService
  private var actionsService: UserActionsService
  private var downloadManager: DownloadManager<DownloadMeta>
  private var errorHandler: ErrorHandler
  private var libraryState: LibraryViewState
  private var seasonDownloadManager: SeasonDownloadManager
  public var linkProvider: NavigationLinkProvider
  public var mediaItemId: Int

  /// Supplementary recommendation shelves (related / more from director / more with actor).
  /// Independently loadable so one failure never blanks the page.
  public let recommendations: MediaRecommendationsLoader
  /// Kinopoisk extras (facts / reviews / crew / stills), best-effort and independently loadable.
  public let extras: MediaExtrasLoader

  @Published public var mediaItem: MediaItem = MediaItem.mock()
  @Published public var itemLoaded: Bool = false
  /// The user's like/dislike for this title this session. kino.pub voting is ONE-TIME (you can't
  /// change a cast vote), and there's no API to read a prior vote, so this starts `.none` each session.
  @Published public var myVote: UserVote = .none
  /// Like / dislike counts shown next to the ratings — seeded from the item, refreshed after a vote.
  @Published public var likeCount: Int = 0
  @Published public var dislikeCount: Int = 0
  /// Transient typed message shown as a toast (e.g. after toggling a bookmark).
  @Published public var toastMessage: ToastMessage?
  /// 3D view-mode preference (shared with the player via `PlayerManager.preferredThreeDMode`).
  @Published public var threeDMode: ThreeDMode = PlayerManager.preferredThreeDMode
  /// Effective watched state for an episode (client optimistic override first, then server data).
  public func isEpisodeWatched(_ episode: Episode) -> Bool {
    libraryState.episodeWatched(episodeId: episode.id, serverWatched: episode.isWatched)
  }

  /// Effective watched state for a movie (client optimistic override first, then server data).
  public var isMovieWatched: Bool {
    libraryState.movieWatched(
      itemId: mediaItemId,
      serverWatched: mediaItem.videos?.first?.isWatched ?? false)
  }

  private let localProgressStore: LocalWatchProgressStore
  /// Bumped when the screen reappears (e.g. back from the player) so the local-progress overlay
  /// re-reads the store immediately, before the authoritative server refetch returns.
  @Published private var localProgressTick: Int = 0

  // MARK: - Local watch progress overlay (instant resume feedback, "Netflix-style")

  /// The locally recorded resume point for THIS item, if any. The store keeps one entry per item
  /// (the most-recently-watched video/episode), keyed by `(season, episode)`.
  private var localEntry: LocalWatchEntry? {
    localProgressStore.allEntries().first { $0.id == mediaItemId }
  }

  /// Locally recorded resume position (seconds) for a specific video/episode of this item, or 0.
  /// Movie matches by id (season nil); an episode requires an exact `(season, episode)` match.
  public func localResumeSeconds(season: Int?, episode: Int?) -> Int {
    guard let entry = localProgressStore.entry(forId: mediaItemId, season: season, episode: episode) else { return 0 }
    return Int(entry.position)
  }

  /// Local progress fraction [0,1] for a specific video/episode, or nil if nothing recorded.
  public func localProgressFraction(season: Int?, episode: Int?) -> Double? {
    localProgressStore.entry(forId: mediaItemId, season: season, episode: episode)?.progress
  }

  /// For a series with no server-side continue point yet, the (season, episode) to resume based on
  /// the local store — so the play button reads "Continue" instantly after watching, pre-refetch.
  public func localSeriesContinue() -> (season: Season, episode: Episode)? {
    guard mediaItem.isSeries, let entry = localEntry,
      let season = mediaItem.seasons?.first(where: { $0.number == entry.season }),
      let episode = season.episodes.first(where: { $0.number == entry.episode })
    else { return nil }
    return (season, episode)
  }

  /// Call when the detail screen reappears (returning from the player). Re-reads local progress for
  /// instant feedback and refetches authoritative server progress. No-op before the first load,
  /// which is handled by `fetchData()` in the view's `.task`.
  func refreshOnReappear() {
    guard itemLoaded else { return }
    localProgressTick &+= 1
    fetchData(includeSupplementary: false)
  }

  /// The lead actor/director names (first credited), used by the people shelves and cast section.
  public var primaryDirector: String? { directorNames.first }
  public var primaryActor: String? { castNames.first }

  /// Actor names parsed from the comma-separated `cast` field (trimmed, non-empty).
  public var castNames: [String] {
    mediaItem.cast
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  /// Director names parsed from the comma-separated `director` field.
  public var directorNames: [String] {
    mediaItem.director
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  /// The content type to use for facet filters opened from this item, so a
  /// serial's genre opens serials and a movie's opens movies.
  private var facetContentType: MediaType {
    MediaType(rawValue: mediaItem.type) ?? .movie
  }

  private func facetFilter(genres: [Int] = [], countries: [Int] = [], year: String? = nil) -> MediaItemsFilter {
    MediaItemsFilter(
      contentType: facetContentType,
      genres: genres,
      countries: countries,
      year: year,
      age: nil,
      sort: nil)
  }

  // MARK: - Facet filters (for deep-linking into the section)

  func genreFilter(id: Int) -> MediaItemsFilter { facetFilter(genres: [id]) }
  func countryFilter(id: Int) -> MediaItemsFilter { facetFilter(countries: [id]) }
  func yearFilter(_ year: Int) -> MediaItemsFilter { facetFilter(year: "\(year)") }

  // MARK: - Tappable metadata routes

  /// Route to a catalog filtered by a single genre.
  func genreRoute(id: Int, title: String) -> (any Hashable)? {
    linkProvider.filteredCatalog(filter: facetFilter(genres: [id]), title: title)
  }

  /// Route to a catalog filtered by a single country.
  func countryRoute(id: Int, title: String) -> (any Hashable)? {
    linkProvider.filteredCatalog(filter: facetFilter(countries: [id]), title: title)
  }

  /// Route to a catalog filtered by a single year.
  func yearRoute(_ year: Int) -> (any Hashable)? {
    linkProvider.filteredCatalog(filter: facetFilter(year: "\(year)"), title: "\(year)")
  }

  /// Route to a person search for an actor (kino.pub `field=cast`).
  func actorRoute(_ name: String) -> (any Hashable)? {
    linkProvider.personSearch(query: name, field: "cast", title: name)
  }

  /// Route to a person search for a director (kino.pub `field=director`).
  func directorRoute(_ name: String) -> (any Hashable)? {
    linkProvider.personSearch(query: name, field: "director", title: name)
  }

  init(
    mediaItemId: Int,
    itemsService: VideoContentService,
    downloadManager: DownloadManager<DownloadMeta>,
    linkProvider: NavigationLinkProvider,
    errorHandler: ErrorHandler,
    actionsService: UserActionsService,
    libraryState: LibraryViewState,
    localProgressStore: LocalWatchProgressStore,
    seasonDownloadManager: SeasonDownloadManager,
    extrasService: KinopoiskExtrasService = KinopoiskExtrasService()
  ) {
    self.itemsService = itemsService
    self.mediaItemId = mediaItemId
    self.linkProvider = linkProvider
    self.errorHandler = errorHandler
    self.downloadManager = downloadManager
    self.actionsService = actionsService
    self.libraryState = libraryState
    self.localProgressStore = localProgressStore
    self.seasonDownloadManager = seasonDownloadManager
    self.recommendations = MediaRecommendationsLoader(
      itemsService: itemsService,
      errorHandler: errorHandler)
    self.extras = MediaExtrasLoader(extrasService: extrasService)
  }

  func fetchData(includeSupplementary: Bool = true) {
    Task {
      do {
        mediaItem = try await itemsService.fetchDetails(for: "\(mediaItemId)").item
        let mediaId = mediaItem.id
        mediaItem.seasons = mediaItem.seasons?.map({
          $0.mediaId = mediaId; return $0
        })
        itemLoaded = true
        seedVoteCounts()
        // Reconcile optimistic watched overrides against fresh server data: drop the ones the
        // server now confirms (keeps any still-in-flight toggle), so the server can drive again.
        await libraryState.reconcileWatched(
          movieItemId: mediaId,
          serverMovieWatched: mediaItem.isSeries ? nil : mediaItem.videos?.first?.isWatched ?? false,
          episodes: mediaItem.orderedEpisodes.map { (id: $0.episode.id, watched: $0.episode.isWatched) })
        // Seed the client library state once (bookmark folders + watchlist) so the UI reflects
        // membership instantly; optimistic toggles thereafter aren't clobbered by refetches.
        await libraryState.seedIfAbsent(
          itemId: mediaId,
          folderIds: mediaItem.bookmarks?.map { $0.id } ?? [],
          inWatchlist: mediaItem.inWatchlist == true)
        if includeSupplementary {
          recommendations.loadRelated(for: mediaItem)
          recommendations.loadPeopleShelves(
            for: mediaItem,
            director: directorNames.first,
            actor: castNames.first)
          extras.load(for: mediaItem)
        }
      } catch {
        errorHandler.setError(error)
      }
    }
  }

  func startDownload(item: DownloadableMediaItem, file: FileInfo) {
    let meta = DownloadMeta.make(from: item, quality: file.quality)
    guard let url = URL(string: file.url.http) else {
      toastMessage = .error("Couldn't start download".localized)
      return
    }
    _ = downloadManager.startDownload(url: url, withMetadata: meta)
    toastMessage = .success("Download started".localized)
  }

  /// Persists the 3D view-mode preference (shared with the player) and updates local state.
  func setThreeDMode(_ mode: ThreeDMode) {
    threeDMode = mode
    PlayerManager.preferredThreeDMode = mode
  }

  /// Enqueues every episode of `season`. `quality` of nil downloads the best available per episode.
  func downloadSeason(_ season: Season, quality: String?) {
    let count = seasonDownloadManager.downloadSeason(
      mediaId: mediaItem.id,
      seriesTitle: mediaItem.localizedTitle,
      season: season,
      quality: quality)
    toastMessage =
      count > 0
      ? .success(String(format: "%d episodes queued".localized, count))
      : .warning("Nothing to download".localized)
  }

  /// Common handling of a library command outcome: run `onApplied` only when the remote effect
  /// actually landed (`.applied`); surface failures; ignore net-no-op and cancelled outcomes.
  private func handleCommandOutcome(_ outcome: LibraryCommandOutcome, onApplied: () -> Void) {
    switch outcome {
    case .applied:
      onApplied()
    case .failed(let error):
      errorHandler.setError(error)
    case .coalesced, .cancelled:
      break
    }
  }

  func toggleWatched() {
    let newState = !isMovieWatched
    Task {
      let outcome = await libraryState.toggleMovieWatched(itemId: mediaItemId)
      handleCommandOutcome(outcome) {
        toastMessage =
          newState
          ? .success("Marked as watched".localized)
          : .info("Marked as unwatched".localized)
      }
    }
  }

  func toggleEpisodeWatched(episode: Episode, season: Int) {
    let newState = !isEpisodeWatched(episode)
    Task {
      let outcome = await libraryState.toggleEpisodeWatched(
        itemId: mediaItemId,
        episodeId: episode.id,
        video: episode.number,
        season: season)
      handleCommandOutcome(outcome) {
        toastMessage =
          newState
          ? .success("Marked as watched".localized)
          : .info("Marked as unwatched".localized)
      }
    }
  }

  func toggleWatchlist() {
    let current = libraryState.inWatchlist(itemId: mediaItemId) ?? (mediaItem.inWatchlist == true)
    let newState = !current
    Task {
      let outcome = await libraryState.toggleWatchlist(itemId: mediaItemId)
      handleCommandOutcome(outcome) {
        toastMessage =
          newState
          ? .success("Added to watchlist".localized)
          : .info("Removed from watchlist".localized)
      }
    }
  }

  func loadBookmarkFolders() {
    // Cached once per session in the library repository; no refetch on every detail-screen appearance.
    Task { await libraryState.loadBookmarkFoldersIfNeeded() }
  }

  func toggleBookmark(folderId: Int, folderTitle: String) {
    let wasOn = libraryState.isBookmarked(itemId: mediaItemId, folderId: folderId)
    Task {
      let outcome = await libraryState.toggleBookmark(itemId: mediaItemId, folderId: folderId)
      handleCommandOutcome(outcome) {
        toastMessage =
          wasOn
          ? .info(String(format: "Removed from %@".localized, folderTitle))
          : .success(String(format: "Saved to %@".localized, folderTitle))
      }
    }
  }

  /// Cast a like (`up: true` → `like=1`) or dislike (`up: false` → `like=0`). kino.pub votes are
  /// one-time: the API answers `voted: true` when counted, or `voted: false` when the user already
  /// voted (it can't be changed). We optimistically highlight + update the count, reverting if the
  /// server says it didn't count.
  /// Load Kinopoisk extras (facts / reviews / crew / stills) for this title via the kpapp.link proxy.
  /// Requires a Kinopoisk id; each request is independent and best-effort (a failure hides its section).
  /// kino.pub gives the aggregate as `rating_votes` (total) + `rating_percentage` (% positive), not
  /// separate like/dislike counts, so derive them for the initial display. A real vote refreshes them.
  /// Also restores the user's own remembered vote so their like/dislike stays visible on revisits.
  private func seedVoteCounts() {
    myVote = libraryState.userVote(itemId: mediaItemId).map { $0 ? .up : .down } ?? .none
    let total = mediaItem.ratingVotes
    guard total > 0 else { likeCount = 0; dislikeCount = 0; return }
    let positive = Int((Double(total) * mediaItem.ratingPercentage / 100.0).rounded())
    likeCount = min(max(positive, 0), total)
    dislikeCount = total - likeCount
  }

  func vote(up: Bool) {
    let target: UserVote = up ? .up : .down
    // kino.pub votes are permanent: you can't switch a like to a dislike (or re-cast).
    if myVote == target { return }
    if myVote != .none {
      toastMessage = .info("You've already rated this".localized)
      return
    }
    // First vote for this title: optimistic highlight + count bump, remembered locally so it persists.
    myVote = target
    if up { likeCount += 1 } else { dislikeCount += 1 }
    Task {
      do {
        await libraryState.setUserVote(itemId: mediaItemId, up: up)
        let result = try await actionsService.vote(id: mediaItemId, like: up ? 1 : 0)
        if result.voted {
          // Server counted it — trust its fresh totals.
          if let p = result.positive.flatMap({ Int($0) }) { likeCount = p }
          if let n = result.negative.flatMap({ Int($0) }) { dislikeCount = n }
        } else {
          // The account already voted earlier (e.g. on another device). Keep the user's choice
          // visible, but undo the optimistic bump since the server didn't count it again.
          if up { likeCount = max(0, likeCount - 1) } else { dislikeCount = max(0, dislikeCount - 1) }
        }
        toastMessage = .success(up ? "Liked".localized : "Disliked".localized)
      } catch {
        // Network failure — fully revert (including the remembered vote).
        myVote = .none
        await libraryState.clearUserVote(itemId: mediaItemId)
        if up { likeCount = max(0, likeCount - 1) } else { dislikeCount = max(0, dislikeCount - 1) }
        errorHandler.setError(error)
      }
    }
  }

  /// Create a new bookmark folder and put this item in it, then refresh the shared folder list.
  func createFolderAndAdd(named name: String) {
    let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return }
    Task {
      do {
        let folderId = try await libraryState.createBookmarkFolder(title: title)
        _ = await libraryState.setBookmark(itemId: mediaItemId, folderId: folderId, isOn: true)
        toastMessage = .success(String(format: "Saved to %@".localized, title))
      } catch {
        errorHandler.setError(error)
      }
    }
  }

}
