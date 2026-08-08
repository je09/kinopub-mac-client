//
//  MediaRecommendationsLoader.swift
//  KinoPubAppleClient
//
//  Loads the supplementary recommendation shelves for a media detail page: "Related",
//  "More from director" and "More with actor". Owns its own state so one shelf's failure
//  never drags the rest of the page into a global error or indefinite skeleton.
//

import Foundation
import KinoPubBackend

/// Recommendations for a single media item (related + people shelves). Independently loadable:
/// each shelf publishes its own loaded flag so the page can reserve skeleton space per shelf.
@MainActor
final class MediaRecommendationsLoader: ObservableObject {

  @Published private(set) var relatedItems: [MediaItem] = []
  /// "More from this director" / "More with this actor" shelves (via /v1/items?director=/cast=).
  @Published private(set) var moreFromDirector: [MediaItem] = []
  @Published private(set) var moreWithActor: [MediaItem] = []
  // Per-shelf "finished loading" flags so the view can reserve space with a skeleton shelf while a
  // dynamically-loaded block is in flight, then swap content in place (or collapse).
  @Published private(set) var relatedLoaded: Bool = false
  @Published private(set) var moreFromLoaded: Bool = false
  @Published private(set) var moreWithLoaded: Bool = false

  private let itemsService: VideoContentService
  private let errorHandler: ErrorHandler

  init(itemsService: VideoContentService, errorHandler: ErrorHandler) {
    self.itemsService = itemsService
    self.errorHandler = errorHandler
  }

  /// Loads items similar to the current one (same primary genre & content type)
  /// using the catalog filter endpoint. Errors are surfaced but never fatal.
  func loadRelated(for item: MediaItem) {
    relatedLoaded = false
    Task {
      do {
        let contentType = MediaType(rawValue: item.type) ?? .movie
        var genres: [Int] = []
        if let genreId = item.genres.first?.id {
          genres.append(genreId)
        }
        let filter = MediaItemsFilter(
          contentType: contentType,
          genres: genres,
          countries: [],
          year: nil,
          age: nil,
          sort: nil)
        let response = try await itemsService.filter(filter: filter, page: nil)
        relatedItems = response.items
          .filter { $0.id != item.id }
          .prefix(15)
          .map { $0 }
      } catch {
        errorHandler.setError(error)
      }
      relatedLoaded = true
    }
  }

  /// "More from director" / "More with actor" shelves, mirroring the web detail page. Best-effort:
  /// a failure just leaves the shelf empty (no error banner).
  func loadPeopleShelves(for item: MediaItem, director: String?, actor: String?) {
    let contentType = MediaType(rawValue: item.type) ?? .movie
    if let director {
      moreFromLoaded = false
      Task {
        let filter = MediaItemsFilter(
          contentType: contentType, genres: [], countries: [],
          year: nil, age: nil, sort: "rating-", director: director)
        if let response = try? await itemsService.filter(filter: filter, page: nil) {
          moreFromDirector = response.items.filter { $0.id != item.id }.prefix(15).map { $0 }
        }
        moreFromLoaded = true
      }
    } else {
      moreFromLoaded = true
    }
    if let actor {
      moreWithLoaded = false
      Task {
        let filter = MediaItemsFilter(
          contentType: contentType, genres: [], countries: [],
          year: nil, age: nil, sort: "rating-", cast: actor)
        if let response = try? await itemsService.filter(filter: filter, page: nil) {
          moreWithActor = response.items.filter { $0.id != item.id }.prefix(15).map { $0 }
        }
        moreWithLoaded = true
      }
    } else {
      moreWithLoaded = true
    }
  }
}
