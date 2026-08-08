//
//  BookmarkActionSheet.swift
//  KinoPubAppleClient
//
//  "Add to bookmarks" sheet opened from a search result row. Mutations go through the shared
//  library command API (`LibraryViewState`), the same single source of truth as the detail screen.
//

import SwiftUI
import KinoPubDomain
import KinoPubUI

/// Wrapper so a `MediaSummary` can drive a `.sheet(item:)` (MediaSummary isn't Identifiable on its own).
struct BookmarkTarget: Identifiable {
  let item: MediaSummary
  var id: Int { item.id }
}

struct BookmarkActionSheet: View {
  let item: MediaSummary
  @EnvironmentObject private var libraryState: LibraryViewState
  @Environment(\.dismiss) private var dismiss
  @State private var loading = true

  var body: some View {
    NavigationStack {
      List {
        if item.isSeries {
          Section {
            Button {
              Task {
                _ = await libraryState.toggleWatchlist(itemId: item.id)
                dismiss()
              }
            } label: {
              Label("Add to watchlist".localized, systemImage: "plus.rectangle.on.rectangle")
            }
          }
        }
        Section(header: Text("Bookmark folders".localized)) {
          if loading {
            ProgressView()
          } else if libraryState.bookmarkFolders.isEmpty {
            Text("No bookmark folders yet.".localized).foregroundStyle(Color.KinoPub.subtitle)
          } else {
            ForEach(libraryState.bookmarkFolders) { folder in
              Button {
                Task { _ = await libraryState.toggleBookmark(itemId: item.id, folderId: folder.id) }
              } label: {
                HStack {
                  Text(folder.title).foregroundStyle(Color.KinoPub.text)
                  Spacer()
                  // Checkmarks come from the shared library snapshot, so this sheet always renders
                  // the same membership as the detail screen for the same item.
                  if libraryState.isBookmarked(itemId: item.id, folderId: folder.id) {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                  }
                }
              }
            }
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(Color.KinoPub.background)
      .navigationTitle(item.localizedTitle)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done".localized) { dismiss() } }
      }
      .task {
        // Folder list + membership come from the shared library repository (single source of
        // truth), seeded from the server without clobbering in-flight optimistic toggles.
        await libraryState.loadBookmarkFoldersIfNeeded()
        await libraryState.seedBookmarkMembership(itemId: item.id)
        loading = false
      }
    }
  }
}

/// A "see all" grid for a search section (Movies / TV Shows), showing the already-loaded results.
struct SearchMediaGridView: View {
  let items: [MediaSummary]
  let title: String

  var body: some View {
    WidthReader { width in
      ScrollView {
        LazyVGrid(columns: PosterGridLayout.columns(width: width), spacing: 16) {
          ForEach(items, id: \.id) { item in
            NavigationLink(value: Route.detailsByID(item.id)) {
              PosterCard(imageURL: item.posters.medium, title: item.localizedTitle, width: nil)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(16)
      }
    }
    .kinoScreen(title)
  }
}

/// Full "Cast & Crew" people list opened from a committed search — mirrors the people grid on a film
/// page / Apple TV. Each person opens their filmography (a person search), not a film-title search.
struct SearchCastCrewView: View {
  let people: [PersonSearchResult]
  let title: String

  private let columns = [GridItem(.adaptive(minimum: 100), spacing: 14, alignment: .top)]

  var body: some View {
    ScrollView {
      LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
        ForEach(people) { person in
          NavigationLink(value: Route.personSearch(person.name, person.field.rawValue, person.displayName)) {
            CastAvatarView(
              imageURL: ActorImageProvider.photoURLString(for: person.name),
              name: person.displayName,
              role: person.roleLabel,
              diameter: 80)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(16)
    }
    .kinoScreen(title)
  }
}
