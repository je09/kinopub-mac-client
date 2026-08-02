//
//  CollectionsModel.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 24.06.2026.
//

import Foundation
import KinoPubBackend
import OSLog
import KinoPubLogging
import Combine

/// Sort tabs shown on the Collections screen, mirroring the web /selection sections.
enum CollectionsSort: CaseIterable, Identifiable {
  case new
  case popular
  case views

  var id: Self { self }

  /// Localized pill title.
  var title: String {
    switch self {
    case .new: return "New".localized
    case .popular: return "Popular".localized
    case .views: return "Views".localized
    }
  }

  /// API `sort` parameter value.
  var apiValue: String {
    switch self {
    case .new: return "created-"
    case .popular: return "watchers-"
    case .views: return "views-"
    }
  }
}

@MainActor
class CollectionsModel: ObservableObject {

  private var authState: AuthState
  private var errorHandler: ErrorHandler
  private var collectionsService: CollectionsService
  private var bag = Set<AnyCancellable>()

  @Published public var collections: [Collection] = []
  /// Preview items per collection (keyed by collection id), so each collection renders as a shelf —
  /// the same layout as Bookmarks. Nil until that collection's items have loaded (shows placeholders).
  @Published public var collectionItems: [Int: [MediaItem]] = [:]
  @Published public var isLoading: Bool = true
  @Published public var selectedSort: CollectionsSort = .new

  private var pagination: Pagination?
  private var isLoadingMore: Bool = false
  private var loadGeneration = 0

  init(collectionsService: CollectionsService, authState: AuthState, errorHandler: ErrorHandler) {
    self.collectionsService = collectionsService
    self.authState = authState
    self.errorHandler = errorHandler
    subscribe()
    // Load on creation, not via the view's `.task` (unreliable in a compact split view / nested stack).
    Task { await fetchCollections() }
  }

  func fetchCollections() async {
    guard authState.userState == .authorized else {
      subscribeForAuth()
      return
    }

    loadGeneration &+= 1
    let generation = loadGeneration
    isLoading = true
    pagination = nil
    collectionItems = [:]
    do {
      let data = try await collectionsService.fetchCollections(page: nil, sort: selectedSort.apiValue)
      guard generation == loadGeneration else { return }
      collections = data.collections
      pagination = data.pagination
      loadItems(for: data.collections, generation: generation)
    } catch {
      guard generation == loadGeneration, !error.isCancellationError else { return }
      Logger.app.debug("fetch collections error: \(error)")
      errorHandler.setError(error)
    }
    if generation == loadGeneration { isLoading = false }
  }

  /// Loads each collection's preview items in parallel (best-effort) so they fill in as they arrive,
  /// each shelf showing placeholders until then — exactly like the Bookmarks folders.
  private func loadItems(for collections: [Collection], generation: Int) {
    let service = collectionsService
    Task {
      await withTaskGroup(of: (Int, [MediaItem]).self) { group in
        var iterator = collections.makeIterator()
        func add(_ collection: Collection) {
          group.addTask {
            let items = (try? await service.fetchCollection(id: collection.id).1) ?? []
            return (collection.id, items)
          }
        }
        for _ in 0..<3 { if let collection = iterator.next() { add(collection) } }
        while let (id, items) = await group.next() {
          guard generation == loadGeneration else {
            group.cancelAll()
            return
          }
          collectionItems[id] = items
          if let collection = iterator.next() { add(collection) }
        }
      }
    }
  }

  /// Loads the next page when the user scrolls near the end of the grid.
  func loadMoreContent(after collection: Collection) {
    guard let pagination = pagination, !isLoadingMore else {
      return
    }
    guard pagination.current < pagination.total else {
      return
    }

    let thresholdIndex = collections.index(collections.endIndex, offsetBy: -1)
    guard thresholdIndex == collections.firstIndex(of: collection) else {
      return
    }

    Logger.app.debug("load more collections after: \(collection.id)")
    Task { await fetchNextPage() }
  }

  private func fetchNextPage() async {
    guard let pagination = pagination, !isLoadingMore else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }

    let nextPage = pagination.current + 1
    do {
      let data = try await collectionsService.fetchCollections(page: nextPage, sort: selectedSort.apiValue)
      collections.append(contentsOf: data.collections)
      self.pagination = data.pagination
      loadItems(for: data.collections, generation: loadGeneration)
    } catch {
      Logger.app.debug("fetch more collections error: \(error)")
      errorHandler.setError(error)
    }
  }

  @Sendable @MainActor
  func refresh() async {
    errorHandler.reset()
    await fetchCollections()
  }

  private func subscribe() {
    $selectedSort
      .dropFirst()
      .removeDuplicates()
      .sink { [weak self] _ in
        Task { await self?.refresh() }
      }.store(in: &bag)
  }

  private func subscribeForAuth() {
    authState.$userState.filter({ $0 == .authorized }).first().sink { [weak self] _ in
      Task {
        await self?.refresh()
      }
    }.store(in: &bag)
  }

}
