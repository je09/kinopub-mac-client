//
//  SearchLiveResultsSection.swift
//  KinoPubAppleClient
//
//  Live (pre-commit) results: matching recents as suggestions + result rows.
//

import SwiftUI
import KinoPubDomain
import KinoPubUI

/// Live list while typing: recent-title suggestions on top, then scoped result rows. The bookmark
/// intent is forwarded to the parent via `onBookmark` (it owns the sheet).
struct SearchLiveResultsSection: View {
  @ObservedObject var model: SearchModel
  @EnvironmentObject private var navigationState: NavigationState
  let onBookmark: (MediaSummary) -> Void
  /// Called when a suggestion is tapped: the parent commits the query and switches to sections.
  let onCommit: () -> Void

  private var trimmedQuery: String { model.query.trimmingCharacters(in: .whitespaces) }

  /// Recent searches whose title matches the current prefix — our stand-in for query suggestions
  /// (kino.pub has no autocomplete API).
  private var matchingRecents: [RecentSearchItem] {
    let q = trimmedQuery.lowercased()
    guard q.count >= 1 else { return [] }
    // Exclude anything already shown as a result row below, so an item never appears as both a
    // suggestion and a result (and never seems to "move" out of the list when opened).
    let resultIds = Set(model.allResults.map { $0.id })
    return model.recentItems
      .filter { $0.title.lowercased().contains(q) && !resultIds.contains($0.id) }
      .prefix(3).map { $0 }
  }

  var body: some View {
    LazyVStack(alignment: .leading, spacing: 0) {
      ForEach(matchingRecents) { recent in
        Button {
          model.query = recent.title
          onCommit()
        } label: {
          HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.accentColor)
            Text(recent.title).foregroundStyle(Color.KinoPub.text)
            Spacer()
          }
          .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        Divider().background(Color.white.opacity(0.06))
      }

      if model.searching && model.allResults.isEmpty {
        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
      } else if trimmedQuery.count >= 3 && model.allResults.isEmpty && !model.searching {
        EmptyStateView(
          systemImage: "magnifyingglass",
          title: "Nothing found".localized,
          message: "Try a different title, actor or director.".localized
        )
        .padding(.top, 60)
      } else {
        ForEach(model.allResults.prefix(25), id: \.id) { item in
          resultRow(item)
          Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
        }
      }

      if !model.failedScopes.isEmpty {
        Text("Some results couldn't be loaded".localized)
          .font(.system(size: 12))
          .foregroundStyle(Color.KinoPub.subtitle)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.top, 14)
      }
    }
  }

  private func resultRow(_ item: MediaSummary) -> some View {
    HStack(spacing: 0) {
      NavigationLink(value: Route.detailsByID(item.id)) {
        HStack(spacing: 12) {
          CachedAsyncImage(url: URL(string: item.posters.small)) { image in
            image.resizable().aspectRatio(contentMode: .fill)
          } placeholder: {
            Color.KinoPub.skeleton
          }
          .frame(width: 46, height: 66).clipped()
          .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
          VStack(alignment: .leading, spacing: 3) {
            Text(item.localizedTitle).font(.system(size: 16))
              .foregroundStyle(Color.KinoPub.text).lineLimit(1)
            Text(item.searchMetaLine).font(.system(size: 13))
              .foregroundStyle(Color.KinoPub.subtitle).lineLimit(1)
          }
          Spacer(minLength: 8)
        }
      }
      .buttonStyle(.plain)
      .simultaneousGesture(TapGesture().onEnded { model.recordRecent(item) })

      Menu {
        Button {
          model.recordRecent(item)
          navigationState.searchRoutes.append(.detailsByID(item.id))
        } label: {
          Label("Open".localized, systemImage: "info.circle")
        }
        Button {
          onBookmark(item)
        } label: {
          Label("Add to bookmarks".localized, systemImage: "bookmark")
        }
      } label: {
        Image(systemName: "ellipsis")
          .foregroundStyle(Color.KinoPub.subtitle)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
    }
    .padding(.horizontal, 16).padding(.vertical, 8)
  }
}
