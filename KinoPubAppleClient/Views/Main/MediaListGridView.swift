//
//  MediaListGridView.swift
//  KinoPubAppleClient
//
//  A "see all" grid of already-loaded media items (a search section / Home shelf / Related opened
//  in full). Uses the full transport item because those producers still hold `MediaItem` values;
//  the search feature uses `SearchMediaGridView` with domain summaries instead.
//

import SwiftUI
import KinoPubBackend
import KinoPubUI

struct MediaListGridView: View {
  let items: [MediaItem]
  let title: String
  
  var body: some View {
    WidthReader { width in
      ScrollView {
        LazyVGrid(columns: PosterGridLayout.columns(width: width), spacing: 16) {
          ForEach(items, id: \.id) { item in
            NavigationLink(value: Route.details(item)) {
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
