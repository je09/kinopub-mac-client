//
//  SearchDiscoverySection.swift
//  KinoPubAppleClient
//
//  Empty-query state: Browse genre grid + Recent opened titles.
//

import SwiftUI
import KinoPubDomain
import KinoPubUI

/// Browse + Recent shelves shown while the query is empty. Pure presentation over `SearchModel` state.
struct SearchDiscoverySection: View {
  @ObservedObject var model: SearchModel

  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      if !model.genres.isEmpty { browseSection }
      if !model.recentItems.isEmpty { recentSection }
      if model.recentItems.isEmpty && model.genres.isEmpty {
        EmptyStateView(
          systemImage: "magnifyingglass",
          title: "Search".localized,
          message: "Find movies, shows, actors and directors.".localized
        )
        .padding(.top, 80)
      }
    }
    .padding(16)
  }

  private var recentSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Recent").font(Font.KinoPub.subheader).foregroundStyle(Color.KinoPub.text)
        Spacer()
        Button("Clear") { model.clearRecents() }.foregroundStyle(Color.accentColor)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          ForEach(model.recentItems) { recent in
            NavigationLink(value: Route.detailsByID(recent.id)) { recentCard(recent) }
              .buttonStyle(.plain)
          }
        }
      }
    }
  }

  private var browseSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Browse").font(Font.KinoPub.subheader).foregroundStyle(Color.KinoPub.text)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 180), spacing: 20)], spacing: 20) {
        ForEach(model.genres, id: \.id) { genre in
          NavigationLink(
            value: Route.filteredCatalogQuery(
              CatalogQuery(kind: .movie, genreID: genre.id),
              genre.title)
          ) {
            browseCard(genre)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private func browseCard(_ genre: Genre) -> some View {
    ZStack(alignment: .bottomLeading) {
      CachedAsyncImage(url: URL(string: model.genrePosters[genre.id] ?? "")) { image in
        image.resizable().aspectRatio(contentMode: .fill)
      } placeholder: {
        LinearGradient(
          colors: [Color.accentColor.opacity(0.5), Color.black.opacity(0.6)],
          startPoint: .topLeading, endPoint: .bottomTrailing)
      }
      LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
      Text(genre.title)
        .font(.system(size: 15, weight: .bold)).foregroundStyle(.white).padding(10)
    }
    .aspectRatio(2.0 / 3.0, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private func recentCard(_ recent: RecentSearchItem) -> some View {
    HStack(spacing: 12) {
      CachedAsyncImage(url: URL(string: recent.poster)) { image in
        image.resizable().aspectRatio(contentMode: .fill)
      } placeholder: {
        Color.KinoPub.skeleton
      }
      .frame(width: 100, height: 62).clipped()
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      VStack(alignment: .leading, spacing: 2) {
        Text(recent.title).font(.system(size: 15, weight: .medium))
          .foregroundStyle(Color.KinoPub.text).lineLimit(2)
        Text(recent.subtitle).font(.system(size: 13))
          .foregroundStyle(Color.KinoPub.subtitle).lineLimit(1)
      }
      .frame(width: 150, alignment: .leading)
    }
    .padding(8)
    .background(Color.white.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}
