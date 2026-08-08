//
//  SearchView.swift
//  KinoPubAppleClient
//
//  Native macOS toolbar search with live results and sectioned results after submission.
//  Composition only: state lives in `SearchModel`, section rendering in `Subviews/`.
//

import SwiftUI
import KinoPubUI
import KinoPubDomain

struct SearchView: View {
  @EnvironmentObject var navigationState: NavigationState
  @EnvironmentObject var errorHandler: ErrorHandler
  @Environment(\.dependencies) var dependencies
  @StateObject private var model: SearchModel

  @State private var bookmarkTarget: BookmarkTarget?
  /// True after the user commits a search (Return or tapping a suggestion) → show the sectioned
  /// layout. It is NOT tied to raw focus: incidental focus loss (opening a row's "…" menu, scrolling)
  /// must keep the live list, otherwise a row appears to vanish the moment you interact with it.
  @State private var committed = false
  @FocusState private var searchFocused: Bool

  init(model: @autoclosure @escaping () -> SearchModel) {
    _model = StateObject(wrappedValue: model())
  }

  private var trimmedQuery: String { model.query.trimmingCharacters(in: .whitespaces) }

  var body: some View {
    NavigationStack(path: $navigationState.searchRoutes) {
      VStack(spacing: 0) {
        searchField
        WidthReader { width in
          ScrollView {
            if trimmedQuery.isEmpty {
              SearchDiscoverySection(model: model)
            } else if committed {
              SearchSectionsSection(model: model)            } else {
              SearchLiveResultsSection(
                model: model,
                onBookmark: { bookmarkTarget = BookmarkTarget(item: $0) },
                onCommit: { committed = true }
              )
            }
          }
        }
      }
      .background(Color.KinoPub.background)
      .navigationTitle(Text(verbatim: "\u{200B}"))
      .routeDestinations()
      .handleError(state: $errorHandler.state)
      .onChange(of: model.query) { _ in committed = false }
      .task { await model.loadGenres() }
      .onAppear {
        DispatchQueue.main.async { searchFocused = true }
      }
      .sheet(item: $bookmarkTarget) { target in
        BookmarkActionSheet(item: target.item)
      }
    }
  }

  private var searchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(Color.KinoPub.subtitle)
      TextField("Search".localized, text: $model.query)
        .textFieldStyle(.plain)
        .focused($searchFocused)
        .onSubmit { committed = true }
    }
    .font(.system(size: 17, weight: .medium))
    .padding(.horizontal, 16)
    .frame(width: 500, height: 44)
    .background(Color.black.opacity(0.16), in: Capsule())
    .overlay {
      Capsule().stroke(
        searchFocused ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.14),
        lineWidth: searchFocused ? 3 : 1)
    }
    .padding(.top, 14)
    .padding(.bottom, 22)
  }
}

struct SearchView_Previews: PreviewProvider {
  @StateObject static var navState = NavigationState()

  static var previews: some View {
    SearchView(
      model: SearchModel(
        repository: SearchRepositoryStub(),
        recentsRepository: InMemoryRecentSearchRepository(),
        errorHandler: ErrorHandler())
    )
    .appPreviewEnvironment()
  }
}
