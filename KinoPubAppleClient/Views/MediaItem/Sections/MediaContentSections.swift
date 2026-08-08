//
//  MediaContentSections.swift
//  KinoPubAppleClient
//
//  Secondary shelves of the media detail page: trailers, related, people shelves, cast & crew,
//  description and comments. Render-only; state comes from `MediaItemModel` and its loaders.
//

import SwiftUI
import KinoPubBackend
import KinoPubUI

// MARK: - Trailers

/// Trailer shelf; holds its place with a skeleton until the item loads.
struct MediaTrailersSection: View {
  @ObservedObject var model: MediaItemModel

  private var mediaItem: MediaItem { model.mediaItem }

  @ViewBuilder
  var body: some View {
    if mediaItem.trailer?.url != nil {
      MediaShelf(title: "Trailers".localized, showsChevron: false) {
        NavigationLink(value: model.linkProvider.trailerPlayer(for: mediaItem)) {
          EpisodeCard(imageURL: mediaItem.posters.big, title: "Trailer")
        }
        .buttonStyle(.plain)
      }
    } else if !model.itemLoaded {
      // Whether a trailer exists is known only once the item loads; hold its place until then.
      MediaShelf(title: "Trailers".localized, showsChevron: false) {
        EpisodeCard(imageURL: nil, title: "Trailer")
          .redacted(reason: .placeholder)
      }
    }
  }
}

// MARK: - Related

/// "Related" shelf (same genre & content type). Skeleton until the recommendations loader settles.
struct MediaRelatedSection: View {
  @ObservedObject var model: MediaItemModel

  @ViewBuilder
  var body: some View {
    if !model.recommendations.relatedItems.isEmpty {
      MediaShelf(
        title: "Related".localized,
        headerValue: Route.mediaList(model.recommendations.relatedItems, "Related".localized)
      ) {
        ForEach(model.recommendations.relatedItems) { item in
          NavigationLink(value: model.linkProvider.link(for: item)) {
            PosterCard(imageURL: item.posters.medium, title: item.localizedTitle)
          }
          .buttonStyle(.plain)
        }
      }
    } else if model.itemLoaded && !model.recommendations.relatedLoaded {
      skeletonPosterShelf("Related".localized)
    }
  }

  private func skeletonPosterShelf(_ title: String) -> some View {
    MediaShelf(title: title, showsChevron: false) {
      ForEach(0..<6, id: \.self) { _ in PosterCard.placeholder() }
    }
  }
}

// MARK: - More from director / with actor

/// "More from this director" / "More with this actor" shelves.
struct MediaPeopleShelvesSection: View {
  @ObservedObject var model: MediaItemModel

  @ViewBuilder
  var body: some View {
    if let director = model.primaryDirector {
      if !model.recommendations.moreFromDirector.isEmpty {
        peopleShelf(
          String(format: "More from %@".localized, director),
          items: model.recommendations.moreFromDirector,
          headerValue: Route.personSearch(director, "director", director))
      } else if !model.recommendations.moreFromLoaded {
        skeletonPosterShelf(String(format: "More from %@".localized, director))
      }
    }

    if let actor = model.primaryActor {
      if !model.recommendations.moreWithActor.isEmpty {
        peopleShelf(
          String(format: "More with %@".localized, actor),
          items: model.recommendations.moreWithActor,
          headerValue: Route.personSearch(actor, "cast", actor))
      } else if !model.recommendations.moreWithLoaded {
        skeletonPosterShelf(String(format: "More with %@".localized, actor))
      }
    }
  }

  @ViewBuilder
  private func peopleShelf(_ title: String, items: [MediaItem], headerValue: (any Hashable)? = nil) -> some View {
    if !items.isEmpty {
      MediaShelf(title: title, headerValue: headerValue) {
        ForEach(items) { item in
          NavigationLink(value: model.linkProvider.link(for: item)) {
            PosterCard(imageURL: item.posters.medium, title: item.localizedTitle)
              .overlay(alignment: .topTrailing) { MediaCardStatusBadge(item: item) }
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private func skeletonPosterShelf(_ title: String) -> some View {
    MediaShelf(title: title, showsChevron: false) {
      ForEach(0..<6, id: \.self) { _ in PosterCard.placeholder() }
    }
  }
}

// MARK: - Cast & Crew

/// Cast & crew shelf: richer Kinopoisk crew when available, else kino.pub plain names.
struct MediaCastCrewSection: View {
  @ObservedObject var model: MediaItemModel
  @Binding var showCastCrew: Bool

  @ViewBuilder
  var body: some View {
    // Prefer the richer Kinopoisk crew (photos + characters + English names) when available,
    // falling back to kino.pub's plain cast/director names.
    if !model.extras.staff.isEmpty {
      staffShelf
    } else {
      castNamesShelf
    }
  }

  private var staffShelf: some View {
    // Lead with a single main director, then the cast — seeing actors matters more than a long list
    // of every director/crew member (the full ordered list stays available in the modal).
    let staff = model.extras.staff
    let directors = staff.filter { $0.professionKey == "DIRECTOR" }
    let actors = staff.filter { $0.professionKey == "ACTOR" }
    let others = staff.filter { $0.professionKey != "DIRECTOR" && $0.professionKey != "ACTOR" }
    let ordered = Array(directors.prefix(1)) + actors + others
    let top = Array(ordered.prefix(14))
    return MediaShelf(
      title: "Cast & Crew".localized,
      showsChevron: staff.count > top.count,
      onHeaderTap: { showCastCrew = true }
    ) {
      ForEach(top) { member in
        facetLink(staffRoute(member)) {
          CastAvatarView(
            imageURL: member.posterUrl,
            name: member.displayName,
            role: staffRole(member))
        }
      }
    }
  }

  @ViewBuilder
  private var castNamesShelf: some View {
    // Just the main director up front, then the cast (the full director list is in the modal).
    let directors = Array(model.directorNames.prefix(1))
    let allActors = model.castNames
    let actors = Array(allActors.prefix(12))
    let hasMore = allActors.count > actors.count || model.directorNames.count > directors.count
    if !actors.isEmpty || !directors.isEmpty {
      MediaShelf(
        title: "Cast & Crew".localized,
        showsChevron: hasMore,
        onHeaderTap: hasMore ? { showCastCrew = true } : nil
      ) {
        ForEach(directors, id: \.self) { name in
          facetLink(model.directorRoute(name)) {
            CastAvatarView(
              imageURL: ActorImageProvider.photoURLString(for: name),
              name: name, role: "Director".localized)
          }
        }
        ForEach(actors, id: \.self) { name in
          facetLink(model.actorRoute(name)) {
            CastAvatarView(
              imageURL: ActorImageProvider.photoURLString(for: name),
              name: name, role: "Actor".localized)
          }
        }
      }
    }
  }

  /// For an actor show the character (`description`); for crew show the profession.
  private func staffRole(_ member: KpStaffMember) -> String? {
    let character = member.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !character.isEmpty { return character }
    return member.professionText
  }

  private func staffRoute(_ member: KpStaffMember) -> (any Hashable)? {
    member.professionKey == "DIRECTOR"
    ? model.directorRoute(member.displayName)
    : model.actorRoute(member.displayName)
  }

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
}

// MARK: - Description

/// Plot + tappable genre chips.
struct MediaDescriptionSection: View {
  @ObservedObject var model: MediaItemModel
  @EnvironmentObject private var navigationState: NavigationState
  let usesSidebar: Bool

  private var mediaItem: MediaItem { model.mediaItem }

  @ViewBuilder
  var body: some View {
    if !mediaItem.plot.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        Text("Description")
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(Color.KinoPub.text)
        genreChips
        Text(mediaItem.plot)
          .font(.system(size: 14))
          .foregroundStyle(Color.KinoPub.text)
          .multilineTextAlignment(.leading)
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(Color.white.opacity(0.06))
      )
      .padding(.horizontal, 20)
    }
  }

  /// Tappable genre chips. Each opens a catalog filtered by that genre, scoped
  /// to this item's own content type (a serial's genre opens serials, etc.).
  @ViewBuilder
  private var genreChips: some View {
    let genres = mediaItem.genres.filter { ($0.title?.isEmpty == false) }
    if !genres.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(genres, id: \.id) { genre in
            sectionFacet(
              filter: model.genreFilter(id: genre.id),
              route: model.genreRoute(id: genre.id, title: genre.title ?? "")
            ) {
              chip(genre.title?.uppercased() ?? "")
            }
          }
        }
      }
    }
  }

  private func chip(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(Color.accentColor)
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(
        Capsule().fill(Color.accentColor.opacity(0.15))
      )
  }

  /// A tappable facet (genre/country/year). On wide layouts it selects the matching Library
  /// section in the sidebar and pre-filters it; on compact it pushes a filtered catalog.
  @ViewBuilder
  private func sectionFacet<Label: View>(
    filter: MediaItemsFilter,
    route: (any Hashable)?,
    @ViewBuilder label: () -> Label
  ) -> some View {
    if usesSidebar {
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
}

// MARK: - Comments

/// Row that opens the comments sheet.
struct MediaCommentsSection: View {
  @Binding var showComments: Bool
  let isSkeleton: Bool

  @ViewBuilder
  var body: some View {
    if FeatureFlags.comments, !isSkeleton {
      Button {
        showComments = true
      } label: {
        HStack(spacing: 12) {
          Image(systemName: "bubble.left.and.bubble.right.fill")
            .font(.system(size: 18))
            .foregroundStyle(Color.accentColor)
          Text("Comments".localized)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.KinoPub.text)
          Spacer()
          Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.KinoPub.subtitle)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.06))
        )
        .padding(.horizontal, 20)
      }
      .buttonStyle(.plain)
    }
  }
}
