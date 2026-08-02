//
//  HomeModel.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 24.06.2026.
//

import Foundation
import KinoPubBackend
import OSLog
import KinoPubLogging
import Combine

@MainActor
class HomeModel: ObservableObject {

  struct Shelf: Identifiable {
    let id = UUID()
    let title: String
    let items: [MediaItem]
    let ranked: Bool
    /// The catalog filter this shelf represents, so its header can open the full list.
    var filter: MediaItemsFilter? = nil
  }

  /// Definition of a Home shelf (matches the kino.pub web sections).
  private struct ShelfSpec {
    let title: String
    let type: MediaType
    let sort: String
    let period: String?

    var filter: MediaItemsFilter {
      var f = MediaItemsFilter(contentType: type, genres: [], countries: [], year: nil, age: nil, sort: sort)
      f.period = period
      return f
    }
  }

  // Mirrors the kino.pub web home sections (type + order + period). Web order → API sort:
  // views → views-, added → created-, watchers → watchers-. `period` is sent server-side
  // (see FilterItemsRequest); "Популярные фильмы" = most viewed this month.
  private static let shelfSpecs: [ShelfSpec] = [
    ShelfSpec(title: "Popular Movies", type: .movie, sort: "views-", period: "month"),
    ShelfSpec(title: "New Movies", type: .movie, sort: "created-", period: nil),
    ShelfSpec(title: "Popular Series", type: .serial, sort: "watchers-", period: nil),
    ShelfSpec(title: "New Series", type: .serial, sort: "created-", period: nil),
    ShelfSpec(title: "New Concerts", type: .concert, sort: "created-", period: nil),
    ShelfSpec(title: "New in 3D", type: .threeD, sort: "created-", period: nil),
    ShelfSpec(title: "New Documentary Movies", type: .documovie, sort: "created-", period: nil),
    ShelfSpec(title: "New Documentary Series", type: .docuserial, sort: "created-", period: nil),
    ShelfSpec(title: "New TV Shows", type: .tvshow, sort: "created-", period: nil)
  ]

  /// A "Continue Watching" entry enriched with resume progress and, for series,
  /// the last episode the user was watching.
  struct ContinueItem: Identifiable {
    let id: Int
    let item: MediaItem
    /// Resume progress for the movie / last-watched episode (nil for live or unstarted).
    let watch: WatchProgress?
    let subtitle: String?

    /// Fraction for the progress bar — nil (no bar) until the title is actually started.
    var progress: Double? {
      guard let watch, watch.state != .unwatched else { return nil }
      return watch.fraction
    }
    /// Watched to (or past) the credits — surfaced on the card so a finished title reads as "watched"
    /// instead of still inviting you to continue.
    var finished: Bool { watch?.isFinished ?? false }
  }

  private var authState: AuthState
  private var errorHandler: ErrorHandler
  private var itemsService: VideoContentService
  private var bag = Set<AnyCancellable>()

  @Published public var shelves: [Shelf] = HomeModel.skeletonShelves()
  @Published public var featured: [MediaItem] = []
  @Published public var continueWatching: [ContinueItem] = []
  /// True until the Continue Watching row has resolved, so the UI can reserve its space.
  @Published public var continueWatchingLoading: Bool = true
  /// Whether the real shelves have been fetched. `shelves` starts as skeleton placeholders (so
  /// it's never empty), so we can't gate the one-time load on `shelves.isEmpty`.
  private var didLoadShelves = false
  private var lastContinueWatchingRefresh: Date?
  private var isFetchingData = false

  init(itemsService: VideoContentService, authState: AuthState, errorHandler: ErrorHandler) {
    self.itemsService = itemsService
    self.authState = authState
    self.errorHandler = errorHandler
    // Load when the model is created, not on the view's `.task` (which doesn't reliably fire in a
    // compact split view / nested navigation stack). `fetchData` is idempotent + auth-gated.
    Task { await fetchData() }
  }

  func fetchData(forceRefresh: Bool = false) async {
    guard !isFetchingData else { return }
    guard authState.userState == .authorized else {
      subscribeForAuth()
      return
    }

    isFetchingData = true
    defer { isFetchingData = false }

    // The watch history powers the "Continue Watching" shelf. Fetch it alongside the other
    // shelves, but isolate failures so a history error can't take down the whole Home screen.
    async let history = itemsService.fetchHistory(page: nil)

    // Build the shelves from the kino.pub web sections (each with its own order/period),
    // fetched in parallel. A failed shelf is simply dropped rather than failing the screen.
    // Only build them once: returning from a pushed detail must not rebuild the list (which
    // would reset the scroll position). Pull-to-refresh goes through `refresh()` instead.
    if !didLoadShelves {
      let specs = HomeModel.shelfSpecs
      let shelfService = itemsService
      let loaded: [Shelf] = await withTaskGroup(of: (Int, Shelf?).self) { group in
        var iterator = Array(specs.enumerated()).makeIterator()
        func add(_ entry: (offset: Int, element: ShelfSpec)) {
          group.addTask {
            let items = (try? await shelfService.filter(filter: entry.element.filter,
                                                        page: nil,
                                                        forceRefresh: forceRefresh))?.items ?? []
            let shelf = items.isEmpty ? nil
              : Shelf(title: entry.element.title.localized, items: items, ranked: false, filter: entry.element.filter)
            return (entry.offset, shelf)
          }
        }
        for _ in 0..<3 { if let entry = iterator.next() { add(entry) } }
        var slots = [Shelf?](repeating: nil, count: specs.count)
        while let (index, shelf) = await group.next() {
          slots[index] = shelf
          if let entry = iterator.next() { add(entry) }
        }
        return slots.compactMap { $0 }
      }

      // Only commit (and stop reloading) once something actually came back, so a transient
      // failure keeps the skeletons and retries on the next appearance instead of sticking empty.
      if !loaded.isEmpty {
        didLoadShelves = true
        shelves = loaded

        // The banner should surface fresh catalog additions, not whatever older title happens to
        // lead the monthly-popular shelf. Both shelves above come directly from `/v1/items` with
        // `sort=created-`; popular entries remain a fallback if the new-content calls are empty.
        let newShelves = loaded.filter {
          $0.filter?.sort == "created-" && ($0.filter?.contentType == .movie || $0.filter?.contentType == .serial)
        }
        let heroSource = newShelves.isEmpty ? loaded : newShelves
        var heroSeen = Set<Int>()
        let featuredItems = heroSource
          .flatMap(\.items)
          .filter { heroSeen.insert($0.id).inserted }
          .prefix(6)
          .map { $0 }
        featured = featuredItems
        // Catalog rows frequently omit the playable trailer URL. Enrich this small hero set from
        // item details so Home can show real muted Apple TV-style previews without a large fan-out.
        Task { await loadFeaturedPreviews(for: featuredItems) }
      }
    }

    // Best-effort: a history failure should never surface an error on Home.
    let historyEntries = (try? await history)?.history ?? []
    // Deduplicate by id (a series shows up once), keeping the most-recent occurrence and its
    // real "last watched" timestamp so we can order against locally-tracked items below.
    var seen = Set<Int>()
    let uniqueHistory: [(item: MediaItem, watchedAt: TimeInterval)] = historyEntries.compactMap { entry in
      guard seen.insert(entry.item.id).inserted else { return nil }
      return (entry.item, entry.lastSeen ?? entry.time ?? entry.firstSeen ?? 0)
    }
    let candidates = Array(uniqueHistory.prefix(10))

    // Enrich each entry with its watch progress + last-watched episode (details carry the
    // per-episode watching positions that the history list does not), keeping the timestamp.
    let service = itemsService
    let enriched: [(item: ContinueItem, watchedAt: TimeInterval)] = await withTaskGroup(of: (Int, ContinueItem).self) { group in
      var iterator = Array(candidates.enumerated()).makeIterator()
      func add(_ entry: (offset: Int, element: (item: MediaItem, watchedAt: TimeInterval))) {
        group.addTask {
          let candidate = entry.element
          let full = (try? await service.fetchDetails(for: "\(candidate.item.id)").item) ?? candidate.item
          return (entry.offset, HomeModel.continueItem(from: full))
        }
      }
      for _ in 0..<3 { if let entry = iterator.next() { add(entry) } }
      var slots = [ContinueItem?](repeating: nil, count: candidates.count)
      while let (index, value) = await group.next() {
        slots[index] = value
        if let entry = iterator.next() { add(entry) }
      }
      return slots.enumerated().compactMap { index, item in
        item.map { ($0, candidates[index].watchedAt) }
      }
    }

    // Locally-started titles (> 10s) the backend doesn't list yet, with their own update time.
    let backendIds = Set(enriched.map { $0.item.id })
    let localOnly: [(item: ContinueItem, watchedAt: TimeInterval)] = AppContext.shared.localProgressStore.allEntries()
      .filter { !backendIds.contains($0.id) }
      .map { entry in
        let subtitle: String?
        if let season = entry.season, let episode = entry.episode {
          subtitle = "S\(season) · E\(episode)"
        } else {
          subtitle = entry.item.duration.totalFormatted
        }
        let watch = WatchProgress(position: entry.position, duration: entry.duration)
        let item = ContinueItem(id: entry.id, item: entry.item, watch: watch, subtitle: subtitle)
        return (item, entry.updatedAt)
      }

    // Single list ordered by real recency (newest first) across both sources, so Continue Watching
    // matches what History shows instead of always floating local items to the front.
    // Drop finished titles (watched to the credits) — a movie at its end / a fully-watched series
    // shouldn't sit in Continue Watching inviting you to resume (Netflix-style).
    continueWatching = (enriched + localOnly)
      .filter { !$0.item.finished }
      .sorted { $0.watchedAt > $1.watchedAt }
      .map { $0.item }
    continueWatchingLoading = false
    lastContinueWatchingRefresh = Date()
  }

  /// Refresh mutable Home data after returning to this cached sidebar screen, without repeatedly
  /// rebuilding the catalog shelves during quick navigation.
  private func loadFeaturedPreviews(for items: [MediaItem]) async {
    let service = itemsService
    let enriched: [(Int, MediaItem)] = await withTaskGroup(of: (Int, MediaItem).self) { group in
      var iterator = Array(items.enumerated()).makeIterator()
      func add(_ entry: (offset: Int, element: MediaItem)) {
        group.addTask {
          let detail = try? await service.fetchDetails(for: "\(entry.element.id)").item
          return (entry.offset, detail ?? entry.element)
        }
      }

      // Two detail requests at a time keep preview loading below the API's rate-limit threshold.
      for _ in 0..<2 { if let entry = iterator.next() { add(entry) } }
      var result: [(Int, MediaItem)] = []
      while let entry = await group.next() {
        result.append(entry)
        if let next = iterator.next() { add(next) }
      }
      return result
    }

    // Ignore completion if a refresh replaced the featured set while details were loading.
    guard featured.map(\.id) == items.map(\.id) else { return }
    featured = enriched.sorted { $0.0 < $1.0 }.map(\.1)
  }

  func refreshContinueWatchingIfStale() async {
    guard didLoadShelves,
          lastContinueWatchingRefresh.map({ Date().timeIntervalSince($0) >= 30 }) ?? true else { return }
    continueWatchingLoading = true
    await fetchData()
  }

  @Sendable @MainActor
  func refresh() async {
    guard !isFetchingData else { return }
    didLoadShelves = false
    shelves = Self.skeletonShelves()
    featured = []
    continueWatchingLoading = true
    await fetchData(forceRefresh: true)
  }

  /// Builds a Continue Watching entry from a fully-loaded media item. Series use the same
  /// `MediaItem.continueEpisode()` logic as the detail page so the two stay in sync (DRY).
  nonisolated private static func continueItem(from item: MediaItem) -> ContinueItem {
    if item.isSeries, let target = item.continueEpisode() ?? item.orderedEpisodes.last {
      let episode = target.episode
      let watch = WatchProgress(position: Double(episode.watching.time), duration: Double(episode.duration))
      return ContinueItem(id: item.id, item: item, watch: watch,
                          subtitle: "S\(target.season.number) · E\(episode.number)")
    }
    if let video = item.videos?.first {
      let watch = WatchProgress(position: Double(video.watching.time), duration: Double(video.duration))
      return ContinueItem(id: item.id, item: item, watch: watch, subtitle: item.duration.totalFormatted)
    }
    return ContinueItem(id: item.id, item: item, watch: nil, subtitle: item.duration.totalFormatted)
  }

  private static func skeletonShelves() -> [Shelf] {
    [
      Shelf(title: "Popular Movies".localized, items: MediaItem.skeletonMock(), ranked: true),
      Shelf(title: "Popular Series".localized, items: MediaItem.skeletonMock(), ranked: true),
      Shelf(title: "New Movies".localized, items: MediaItem.skeletonMock(), ranked: false)
    ]
  }

  private func subscribeForAuth() {
    authState.$userState.filter({ $0 == .authorized }).first().sink { [weak self] _ in
      Task {
        await self?.fetchData()
      }
    }.store(in: &bag)
  }

}
