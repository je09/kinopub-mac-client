//
//  HomeView.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 24.06.2026.
//

import SwiftUI
import KinoPubUI
import KinoPubBackend

struct HomeView: View {
  @EnvironmentObject var navigationState: NavigationState
  @EnvironmentObject var errorHandler: ErrorHandler
  @EnvironmentObject var authState: AuthState
  @Environment(\.appContext) var appContext
  @StateObject private var model: HomeModel
  @ObservedObject private var visibility = SectionVisibilityStore.shared
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var featuredIndex = 0
  @State private var heroHovered = false
  @State private var trailerReadyItemID: Int?

  init(model: @autoclosure @escaping () -> HomeModel) {
    _model = StateObject(wrappedValue: model())
  }

  var body: some View {
    NavigationStack(path: $navigationState.homeRoutes) {
      ScrollView(.vertical) {
        LazyVStack(alignment: .leading, spacing: 0) {
          // Media itself is rendered once at the split-view/window level, from the left window edge
          // to the right. This layer supplies only hero gradients, controls and text.
          heroSection

          LazyVStack(alignment: .leading, spacing: 28) {
            if model.continueWatchingLoading {
              continueWatchingPlaceholderShelf
            } else if !model.continueWatching.isEmpty {
              continueWatchingShelf
            }
            ForEach(model.shelves) { shelf in
              if isShelfVisible(shelf) {
                shelfView(shelf)
              }
            }
          }
          .padding(.top, 28)
          .padding(.bottom, 24)
          .background(Color.KinoPub.background)
        }
      }
      .background(Color.clear)
      .refreshable { await model.refresh() }
      .task { await model.refreshContinueWatchingIfStale() }
      // Include the trailer URL in the task identity: list items initially have no playable trailer
      // and are enriched asynchronously without changing their media id.
      .task(id: featuredPreviewTaskID) {
        trailerReadyItemID = nil
        guard let item = currentFeaturedItem,
              !reduceMotion,
              !(item.trailer?.url?.isEmpty ?? true) else { return }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        guard !Task.isCancelled, currentFeaturedItem?.id == item.id else { return }
        trailerReadyItemID = item.id
      }
      // A zero-width verbatim title suppresses AppKit's fallback window title ("KinoPub") without
      // looking up the localization catalog's empty-string key.
      .navigationTitle(Text(verbatim: "\u{200B}"))
      // The native macOS toolbar owns the titlebar material.
      .heroNavBar()
      .routeDestinations()
      .handleError(state: $errorHandler.state)
      .preference(key: WindowHeroMediaPreferenceKey.self, value: windowBackdropMedia)
    }
  }

  // Apple TV devotes roughly three quarters of its standard window to the feature stage.
  private var heroHeight: CGFloat { 620 }

  @ViewBuilder
  private var heroSection: some View {
    if model.featured.isEmpty {
      HeroBackdrop(imageURL: nil,
                   height: heroHeight,
                   blurReduction: heroHeight,
                   transparentBase: true) { EmptyView() }
    } else {
      GeometryReader { proxy in
        ZStack {
          if let hero = currentFeaturedItem {
            heroPage(hero)
              .id(hero.id)
              .frame(width: max(600, proxy.size.width))
              .transition(.opacity.combined(with: .scale(scale: 1.01)))
          }

          HStack {
            carouselArrow(offset: -1)
            Spacer()
            carouselArrow(offset: 1)
          }
          .padding(.horizontal, 14)

          VStack {
            Spacer()
            homeCarouselControls
              .padding(.bottom, 18)
          }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { heroHovered = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: featuredIndex)
      }
      .frame(height: heroHeight)
      .onChange(of: model.featured.count) { count in
        if featuredIndex >= count { featuredIndex = 0 }
      }
    }
  }

  private var currentFeaturedItem: MediaItem? {
    guard model.featured.indices.contains(featuredIndex) else { return model.featured.first }
    return model.featured[featuredIndex]
  }

  private var featuredPreviewTaskID: String {
    guard let item = currentFeaturedItem else { return "none" }
    return "\(item.id)|\(item.trailer?.url ?? "")"
  }

  /// Publish poster and trailer together so the window can preload video behind the poster. The
  /// poster remains fully visible for three seconds and until the trailer reports a renderable frame.
  private var windowBackdropMedia: WindowHeroMedia? {
    guard let item = currentFeaturedItem else { return nil }
    let trailerURL = item.trailer?.url
    let trailer = (!reduceMotion && !(trailerURL?.isEmpty ?? true)) ? trailerURL : nil
    return WindowHeroMedia(posterURL: item.posters.wide ?? item.posters.big,
                           videoURL: trailer,
                           revealVideo: trailerReadyItemID == item.id,
                           height: heroHeight,
                           strongTextScrim: false)
  }

  private var homeCarouselControls: some View {
    HStack(spacing: 7) {
      ForEach(model.featured.indices, id: \.self) { index in
        Button { selectFeatured(index: index) } label: {
          Circle()
            .fill(index == featuredIndex ? Color.white : Color.white.opacity(0.42))
            .frame(width: 6, height: 6)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(8)
  }

  private func carouselArrow(offset: Int) -> some View {
    Button { selectFeatured(offset: offset) } label: {
      Image(systemName: offset < 0 ? "chevron.left" : "chevron.right")
        .font(.system(size: 27, weight: .semibold))
        .frame(width: 34, height: 54)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(.white.opacity(0.75))
    .opacity(heroHovered && model.featured.count > 1 ? 1 : 0)
    .animation(.easeOut(duration: 0.15), value: heroHovered)
  }

  private func selectFeatured(offset: Int) {
    guard !model.featured.isEmpty else { return }
    selectFeatured(index: (featuredIndex + offset + model.featured.count) % model.featured.count)
  }

  private func selectFeatured(index: Int) {
    guard model.featured.indices.contains(index) else { return }
    withAnimation(.easeInOut(duration: 0.8)) { featuredIndex = index }
  }

  @ViewBuilder
  private func heroPage(_ hero: MediaItem) -> some View {
    NavigationLink(value: Route.details(hero)) {
      HeroBackdrop(imageURL: hero.posters.wide ?? hero.posters.big,
                   videoURL: hero.trailer?.url,
                   height: heroHeight,
                   blurReduction: heroHeight,
                   transparentBase: true) {
        VStack(alignment: .leading, spacing: 10) {
          Text(hero.localizedTitle)
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(2)

          HStack(spacing: 5) {
            Image(systemName: "play.tv.fill")
            Text(hero.isSeries ? "TV Show".localized : "Movie".localized)
            if let genre = hero.genres.compactMap({ $0.title }).first {
              Text("·")
              Text(genre)
            }
          }
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.9))
          .lineLimit(1)

          if !hero.plot.isEmpty {
            Text(hero.plot)
              .font(.system(size: 15, weight: .medium))
              .foregroundStyle(.white.opacity(0.72))
              .lineLimit(2)
              .frame(maxWidth: 390, alignment: .leading)
          }

          Label("More Info".localized, systemImage: "info.circle")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(Color.white, in: Capsule())
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 42)
      }
    }
    .buttonStyle(PlainButtonStyle())
  }

  @ViewBuilder
  private var continueWatchingPlaceholderShelf: some View {
    MediaShelf(title: "Continue Watching".localized) {
      ForEach(0..<6, id: \.self) { _ in
        ContinueWatchingCard.placeholder()
      }
    }
  }

  private var continueWatchingShelf: some View {
    MediaShelf(title: "Continue Watching".localized,
               headerValue: Route.mediaList(model.continueWatching.map { $0.item }, "Continue Watching".localized)) {
      ForEach(model.continueWatching) { entry in
        NavigationLink(value: Route.details(entry.item)) {
          ContinueWatchingCard(imageURL: entry.item.posters.wide ?? entry.item.posters.big,
                               title: entry.item.localizedTitle,
                               subtitle: entry.subtitle,
                               progress: entry.progress)
          .overlay(alignment: .topTrailing) {
            MediaCardStatusBadge(item: entry.item, showsWatched: false)
          }
        }
        .buttonStyle(.plain)
      }
    }
  }

  /// A shelf maps to a library category (via its filter's content type). Hide it from Home when the
  /// user has hidden that section in Profile → Sections. Skeleton/filterless shelves always show.
  private func isShelfVisible(_ shelf: HomeModel.Shelf) -> Bool {
    guard let type = shelf.filter?.contentType else { return true }
    return visibility.isVisible(.category(type))
  }

  @ViewBuilder
  private func shelfView(_ shelf: HomeModel.Shelf) -> some View {
    MediaShelf(title: shelf.title,
               onHeaderTap: shelf.filter.map { filter in
                 { navigationState.homeRoutes.append(.filteredCatalog(filter, shelf.title)) }
               }) {
      ForEach(Array(shelf.items.enumerated()), id: \.element.id) { index, item in
        NavigationLink(value: Route.details(item)) {
          // Apple TV's Home shelves let artwork carry the row; titles and ratings belong on detail
          // screens. Popular rows add the oversized chart number directly over the poster.
          PosterCard(imageURL: item.posters.medium,
                     rank: shelf.ranked ? index + 1 : nil,
                     width: 160)
          .overlay(alignment: .topTrailing) { MediaCardStatusBadge(item: item) }
        }
        .buttonStyle(.plain)
      }
    }
  }
}

struct HomeView_Previews: PreviewProvider {
  static var previews: some View {
    HomeView(model: HomeModel(itemsService: VideoContentServiceMock(),
                              authState: AuthState(authService: AuthorizationServiceMock(), accessTokenService: AccessTokenServiceMock(), deviceService: DeviceServiceMock()),
                              errorHandler: ErrorHandler()))
  }
}
