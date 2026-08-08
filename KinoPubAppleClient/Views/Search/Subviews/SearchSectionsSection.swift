//
//  SearchSectionsSection.swift
//  KinoPubAppleClient
//
//  Committed-search layout: Top Results / Movies / TV Shows / Cast & Crew shelves.
//

import SwiftUI
import KinoPubDomain
import KinoPubUI

/// Sectioned results after the user commits a query. Pure presentation over `SearchModel` state;
/// navigation goes through the environment `NavigationState`.
struct SearchSectionsSection: View {
  @ObservedObject var model: SearchModel
  @EnvironmentObject private var navigationState: NavigationState

  /// Movie/TV shelves ordered by how many results each has (so the dominant type leads, like Apple TV
  /// puts TV Shows first for "Shrinking" and Movies first for "Interstellar").
  private var orderedShelves: [(title: String, items: [MediaSummary])] {
    var shelves: [(String, [MediaSummary])] = []
    if !model.movieResults.isEmpty { shelves.append(("Movies".localized, model.movieResults)) }
    if !model.tvResults.isEmpty { shelves.append(("TV Shows".localized, model.tvResults)) }
    return shelves.sorted { $0.1.count > $1.1.count }
  }

  var body: some View {
    if model.searching && model.allResults.isEmpty {
      ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
    } else if model.allResults.isEmpty && model.people.isEmpty {
      EmptyStateView(
        systemImage: "magnifyingglass",
        title: "Nothing found".localized,
        message: "Try a different title, actor or director.".localized
      )
      .padding(.top, 80)
    } else {
      VStack(alignment: .leading, spacing: 28) {
        if !model.topResults.isEmpty { topResultsSection }
        ForEach(orderedShelves, id: \.title) { shelf in
          // ">" opens the full set on its own page (like Apple TV). Only when there's more than fits.
          MediaShelf(
            title: shelf.title,
            showsChevron: shelf.items.count > 1,
            onHeaderTap: { navigationState.searchRoutes.append(.mediaSummaries(shelf.items, shelf.title)) }
          ) {
            ForEach(shelf.items.prefix(18), id: \.id) { item in
              NavigationLink(value: Route.detailsByID(item.id)) {
                PosterCard(imageURL: item.posters.medium, title: item.localizedTitle, width: 130)
              }
              .buttonStyle(.plain)
            }
          }
        }
        if !model.people.isEmpty { castCrewSection }
        if !model.failedScopes.isEmpty {
          Text("Some results couldn't be loaded".localized)
            .font(.system(size: 12))
            .foregroundStyle(Color.KinoPub.subtitle)
            .frame(maxWidth: .infinity, alignment: .center)
        }
      }
      .padding(.vertical, 8)
    }
  }

  private var topResultsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Top Results".localized)
        .font(.system(size: 22, weight: .bold)).foregroundStyle(Color.KinoPub.text)
        .padding(.horizontal, 20)
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(spacing: 12) {
          ForEach(model.topResults, id: \.id) { item in
            NavigationLink(value: Route.detailsByID(item.id)) { topResultCard(item) }
              .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 20)
      }
    }
  }

  private func topResultCard(_ item: MediaSummary) -> some View {
    HStack(spacing: 12) {
      CachedAsyncImage(url: URL(string: item.posters.small)) { image in
        image.resizable().aspectRatio(contentMode: .fill)
      } placeholder: {
        Color.KinoPub.skeleton
      }
      .frame(width: 60, height: 88).clipped()
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      VStack(alignment: .leading, spacing: 4) {
        Text(item.localizedTitle).font(.system(size: 16, weight: .semibold))
          .foregroundStyle(Color.KinoPub.text).lineLimit(2)
        Text(item.searchMetaLine).font(.system(size: 13))
          .foregroundStyle(Color.KinoPub.subtitle).lineLimit(1)
      }
      .frame(width: 200, alignment: .leading)
    }
    .padding(10)
    .background(Color.white.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private var castCrewSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Button {
        // Open the full people list (like a film page's Cast & Crew / Apple TV), not a film search.
        navigationState.searchRoutes.append(.castCrew(model.people, "Cast & Crew".localized))
      } label: {
        HStack(spacing: 4) {
          Text("Cast & Crew".localized)
            .font(.system(size: 22, weight: .bold)).foregroundStyle(Color.KinoPub.text)
          Image(systemName: "chevron.right")
            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.KinoPub.subtitle)
        }
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 20)
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(spacing: 16) {
          ForEach(model.people) { person in
            NavigationLink(value: Route.personSearch(person.name, person.field.rawValue, person.displayName)) {
              CastAvatarView(
                imageURL: ActorImageProvider.photoURLString(for: person.name),
                name: person.displayName,
                role: person.roleLabel)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 20)
      }
    }
  }
}
