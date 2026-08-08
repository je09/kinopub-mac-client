//
//  MediaItemView.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 28.07.2023.
//
//  Composition only: owns screen state, sheets and the section stack. Section rendering lives in
//  `Sections/`; behavior lives in `MediaItemModel` and its loaders.
//

import Foundation
import SwiftUI
import KinoPubUI
import KinoPubBackend
import KinoPubKit

struct MediaItemView: View {
  
  @EnvironmentObject var errorHandler: ErrorHandler
  @EnvironmentObject private var navigationState: NavigationState
  @EnvironmentObject private var libraryState: LibraryViewState
  @Environment(\.dependencies) private var dependencies
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @StateObject private var itemModel: MediaItemModel
  
  @State private var plotExpanded: Bool = false
  @State private var showComments: Bool = false
  @State private var showCastCrew: Bool = false
  @State private var showFacts: Bool = false
  @State private var showReviews: Bool = false
  /// Non-nil when the full-screen stills viewer is open, holding the index being shown.
  @State private var stillSelection: StillSelection?
  @State private var showCreateFolder: Bool = false
  @State private var newFolderName: String = ""
  /// Person picked in the Cast & Crew modal — pushed onto this page's stack after the modal closes.
  @State private var pendingPersonRoute: Route?
  @State private var showPerson: Bool = false
  
  init(model: @autoclosure @escaping () -> MediaItemModel) {
    _itemModel = StateObject(wrappedValue: model())
  }
  
  private var mediaItem: MediaItem { itemModel.mediaItem }
  private var isSkeleton: Bool { !itemModel.itemLoaded }
  
  /// The macOS sidebar lets facets deep-link into a catalog section.
  private var usesSidebarSections: Bool {
    return true
  }
  
  /// A tappable facet (genre/country/year). On wide layouts it selects the matching Library
  /// section in the sidebar and pre-filters it; on compact it pushes a filtered catalog.
  @ViewBuilder
  private func sectionFacet<Label: View>(
    filter: MediaItemsFilter,
    route: (any Hashable)?,
    @ViewBuilder label: () -> Label
  ) -> some View {
    if usesSidebarSections {
      Button {
        navigationState.pendingCategoryFilter = filter
        navigationState.sidebarSelection = .category(filter.contentType)
      } label: {
        label()
      }
      .buttonStyle(.plain)
    } else {
      facetLink(route, label: label)
    }
  }
  
  /// Wraps `label` in a NavigationLink to `route` when one exists; otherwise
  /// renders the label as-is. Lets tappable metadata degrade gracefully on
  /// link providers that don't support facet routes.
  @ViewBuilder
  private func facetLink<Label: View>(_ route: (any Hashable)?, @ViewBuilder label: () -> Label) -> some View {
    if let route {
      NavigationLink(value: route) {
        label()
      }
      .buttonStyle(.plain)
    } else {
      label()
    }
  }
  
  private let heroHeight: CGFloat = 552
  
  private var windowBackdropMedia: WindowHeroMedia? {
    let poster = mediaItem.posters.wide ?? mediaItem.posters.big
    let trailerURL = mediaItem.trailer?.url
    let trailer = (!reduceMotion && !(trailerURL?.isEmpty ?? true)) ? trailerURL : nil
    guard !poster.isEmpty || trailer != nil else { return nil }
    return WindowHeroMedia(
      posterURL: poster,
      videoURL: trailer,
      revealVideo: trailer != nil,
      height: heroHeight,
      strongTextScrim: true)
  }
  
  var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 28) {
        MediaHeroSection(
          model: itemModel,
          plotExpanded: $plotExpanded,
          showCreateFolder: $showCreateFolder,
          newFolderName: $newFolderName,
          usesSidebar: usesSidebarSections)
        MediaEpisodesSection(model: itemModel)
        MediaTrailersSection(model: itemModel)
        MediaStillsSection(extras: itemModel.extras, itemLoaded: itemModel.itemLoaded, stillSelection: $stillSelection)
        MediaCastCrewSection(model: itemModel, showCastCrew: $showCastCrew)
        MediaDescriptionSection(model: itemModel, usesSidebar: usesSidebarSections)
        MediaFactsSection(extras: itemModel.extras, itemLoaded: itemModel.itemLoaded, showFacts: $showFacts)
        MediaReviewsSection(extras: itemModel.extras, itemLoaded: itemModel.itemLoaded, showReviews: $showReviews)
        MediaRelatedSection(model: itemModel)
        MediaPeopleShelvesSection(model: itemModel)
        MediaMetadataSection(
          mediaItem: mediaItem,
          model: itemModel,
          usesSidebar: usesSidebarSections,
          openSection: { filter in
            navigationState.pendingCategoryFilter = filter
            navigationState.sidebarSelection = .category(filter.contentType)
          })
        MediaCommentsSection(showComments: $showComments, isSkeleton: isSkeleton)
      }
      .padding(.bottom, 32)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(alignment: .top) {
        VStack(spacing: 0) {
          Color.clear.frame(height: heroHeight)
          Color.KinoPub.background
        }
      }
    }
    .background(Color.clear)
    .accessibilityIdentifier(AccessibilityID.detailScreen)
    .preference(key: WindowHeroMediaPreferenceKey.self, value: windowBackdropMedia)
    .sheet(isPresented: $showComments) {
      CommentsView(
        store: CommentsStore(
          mediaID: mediaItem.id,
          repository: dependencies.commentsRepository
        )
      )
    }
    .sheet(
      isPresented: $showCastCrew,
      onDismiss: {
        // The modal closed; if a person was picked, open their section on this page.
        if pendingPersonRoute != nil { showPerson = true }
      }
    ) {
      CastCrewView(
        directors: itemModel.directorNames,
        actors: itemModel.castNames,
        staff: itemModel.extras.staff,
        onSelect: { name, field in
          pendingPersonRoute = .personSearch(name, field, name)
        })
    }
    // Programmatic push onto whichever navigation stack hosts this page.
    .navigationDestination(isPresented: $showPerson) {
      if let route = pendingPersonRoute {
        RouteDestinationView(route: route)
      }
    }
    .onChange(of: showPerson) { presented in
      if !presented { pendingPersonRoute = nil }
    }
    .sheet(isPresented: $showFacts) {
      FactsView(facts: itemModel.extras.facts)
    }
    .sheet(isPresented: $showReviews) {
      ReviewsView(reviews: itemModel.extras.reviews)
    }
    .sheet(item: $stillSelection) { selection in
      StillsViewer(images: itemModel.extras.images, startIndex: selection.index)
    }
    .alert("New folder".localized, isPresented: $showCreateFolder) {
      TextField("Folder name".localized, text: $newFolderName)
      Button("Cancel".localized, role: .cancel) {}
      Button("Create".localized) { itemModel.createFolderAndAdd(named: newFolderName) }
    }
    .toast(message: $itemModel.toastMessage)
    // The native macOS toolbar owns the titlebar material.
    .heroNavBar()
    .task {
      itemModel.fetchData()
      itemModel.loadBookmarkFolders()
    }
    // Returning from the player: re-read local progress for instant feedback and refetch the
    // server so the resume button and episode progress bars reflect what was just watched.
    .onAppear {
      itemModel.refreshOnReappear()
    }
    // Cache artwork/title locally so a started title can resume in Continue Watching.
    .onChange(of: itemModel.itemLoaded) { loaded in
      if loaded {
        dependencies.localProgressStore.cacheItem(itemModel.mediaItem)
      }
    }
    .handleError(state: $errorHandler.state)
  }
}

struct MediaItemView_Previews: PreviewProvider {
  struct Preview: View {
    var body: some View {
      let deps = AppDependencies.preview()
      return MediaItemView(
        model: MediaItemModel(
          mediaItemId: MediaItem.mock().id,
          itemsService: VideoContentServiceMock(),
          downloadManager: deps.downloadManager,
          linkProvider: RouteLinkProvider(),
          errorHandler: ErrorHandler(),
          actionsService: deps.actionsService,
          libraryState: deps.libraryState,
          localProgressStore: deps.localProgressStore,
          seasonDownloadManager: deps.seasonDownloadManager))
    }
  }
  static var previews: some View {
    NavigationStack {
      Preview()
    }
    .appPreviewEnvironment()
  }
}
