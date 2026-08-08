//
//  SidebarNavigationDetail.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 11.08.2023.
//

import Foundation
import SwiftUI
import KinoPubBackend

struct SidebarNavigationDetail: View {
  @Environment(\.dependencies) var dependencies
  @EnvironmentObject var navigationState: NavigationState
  @EnvironmentObject var errorHandler: ErrorHandler
  @EnvironmentObject var authState: AuthState
  @EnvironmentObject var libraryState: LibraryViewState
  @StateObject private var screenCache = SidebarScreenCache()
  
  @Binding var selection: SidebarItem?
  
  var body: some View {
    let selected = selection ?? .new
    // Let each destination's native ScrollView establish its own initial position. Forcing an
    // AppKit offset during split-view reconciliation caused newly selected screens to inherit the
    // previous screen's scroll position and visibly jump after layout.
    destination(for: selected)
  }
  
  @ViewBuilder
  private func destination(for selected: SidebarItem) -> some View {
    switch selected {
    case .search:
      search
    case .new:
      home
    case .category(let type):
      mainCatalog(contentType: type, shortcut: .hot)
        .id("library-\(type.rawValue)")
    case .preset(let preset):
      FilteredCatalogView(
        catalog: screenCache.model(for: .preset(preset)) {
          MediaCatalog(
            itemsService: dependencies.contentService,
            authState: authState,
            errorHandler: errorHandler,
            filter: preset.filter)
        },
        title: preset.title.localized,
        linkProvider: RouteLinkProvider()
      )
      .id("preset-\(preset.rawValue)")
    case .sport:
      sport
    case .collections:
      collections
    case .newEpisodes:
      // "New episodes" and "Watching" are both WatchingView — distinct ids so switching between them
      // doesn't reuse the wrong model (same view type would otherwise share one @StateObject).
      newEpisodes.id("section-new-episodes")
    case .watching:
      watching.id("section-watching")
    case .bookmarks:
      bookmarks
    case .bookmarkFolder(let id):
      bookmarkFolder(id: id)
    case .history:
      history
    case .downloads:
      downloads
    case .profile:
      profile
    }
  }
  
  var search: some View {
    SearchView(
      model: screenCache.model(for: .search) {
        SearchModel(
          repository: dependencies.searchRepository,
          errorHandler: errorHandler)
      })
  }
  
  var home: some View {
    HomeView(
      model: screenCache.model(for: .new) {
        HomeModel(
          itemsService: dependencies.contentService,
          localProgressStore: dependencies.localProgressStore,
          authState: authState,
          errorHandler: errorHandler)
      })
  }
  
  /// The pending deep-link filter if it targets this content type.
  private func categoryFilter(for type: MediaType) -> MediaItemsFilter? {
    navigationState.pendingCategoryFilter?.contentType == type ? navigationState.pendingCategoryFilter : nil
  }
  
  func mainCatalog(contentType: MediaType, shortcut: MediaShortcut) -> some View {
    let key = SidebarItem.category(contentType)
    return MainView(
      catalog: screenCache.model(for: key) {
        MediaCatalog(
          itemsService: dependencies.contentService,
          authState: authState,
          errorHandler: errorHandler,
          contentType: contentType,
          shortcut: shortcut,
          filter: categoryFilter(for: contentType))
      })
  }
  
  var sport: some View {
    SportView(
      model: screenCache.model(for: .sport) {
        SportModel(
          itemsService: dependencies.contentService,
          epgService: dependencies.epgService,
          authState: authState,
          errorHandler: errorHandler)
      })
  }
  
  var collections: some View {
    CollectionsView(
      model: screenCache.model(for: .collections) {
        CollectionsModel(
          collectionsService: dependencies.collectionsService,
          authState: authState,
          errorHandler: errorHandler)
      })
  }
  
  var newEpisodes: some View {
    WatchingView(
      model: screenCache.model(for: .newEpisodes) {
        WatchingModel(
          itemsService: dependencies.contentService,
          authState: authState,
          errorHandler: errorHandler,
          tab: .newEpisodes)
      })
  }
  
  var watching: some View {
    WatchingView(
      model: screenCache.model(for: .watching) {
        WatchingModel(
          itemsService: dependencies.contentService,
          authState: authState,
          errorHandler: errorHandler,
          tab: .watchlist)
      })
  }
  
  var bookmarks: some View {
    BookmarksView(
      catalog: screenCache.model(for: .bookmarks) {
        BookmarksCatalog(
          itemsService: dependencies.contentService,
          libraryState: dependencies.libraryState,
          authState: authState,
          errorHandler: errorHandler)
      })
  }
  
  @ViewBuilder
  func bookmarkFolder(id: Int) -> some View {
    if let bookmark = libraryState.bookmarkFolders.first(where: { $0.id == id }) {
      NavigationStack(path: $navigationState.bookmarksRoutes) {
        BookmarkView(
          model: screenCache.model(for: .bookmarkFolder(id)) {
            BookmarkModel(
              bookmark: bookmark,
              itemsService: dependencies.contentService,
              libraryState: dependencies.libraryState,
              errorHandler: errorHandler)
          }
        )
        .routeDestinations()
      }
      .id("sidebar-bookmark-\(id)")
    } else {
      ProgressView()
    }
  }
  
  var history: some View {
    HistoryView(
      catalog: screenCache.model(for: .history) {
        HistoryModel(
          itemsService: dependencies.contentService,
          actionsService: dependencies.actionsService,
          localProgressStore: dependencies.localProgressStore,
          authState: authState,
          errorHandler: errorHandler)
      })
  }
  
  var downloads: some View {
    DownloadsView(
      catalog: screenCache.model(for: .downloads) {
        DownloadsCatalog(
          downloadsDatabase: dependencies.downloadedFilesDatabase,
          downloadManager: dependencies.downloadManager,
          storageRepository: dependencies.storageUsageRepository)
      })
  }
  
  var profile: some View {
    ProfileView(
      model: screenCache.model(for: .profile) {
        ProfileModel(
          userService: dependencies.userService,
          errorHandler: errorHandler,
          authState: authState)
      })
  }
}

/// Retains each visited sidebar screen's observable model. SwiftUI may discard the detail view when
/// another destination is selected; keeping the model alive preserves loaded data, filters and sort
/// choices instead of rebuilding and refetching the screen on every sidebar click.
@MainActor
private final class SidebarScreenCache: ObservableObject {
  private var models: [SidebarItem: AnyObject] = [:]
  
  func model<Model: AnyObject>(
    for item: SidebarItem,
    create: () -> Model
  ) -> Model {
    if let cached = models[item] as? Model { return cached }
    let model = create()
    models[item] = model
    return model
  }
}

struct SidebarNavigationDetail_Previews: PreviewProvider {
  struct Preview: View {
    @State private var selection: SidebarItem? = .new
    var body: some View {
      SidebarNavigationDetail(selection: $selection)
    }
  }
  static var previews: some View {
    Preview()
      .appPreviewEnvironment()
  }
}
