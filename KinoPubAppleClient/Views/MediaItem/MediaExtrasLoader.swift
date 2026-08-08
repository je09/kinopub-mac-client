//
//  MediaExtrasLoader.swift
//  KinoPubAppleClient
//
//  Loads Kinopoisk-sourced supplementary content (facts / reviews / full crew / stills) for a
//  media detail page via the kpapp.link kpapi proxy. Best-effort by design: a failure hides its
//  section and never triggers a global error; the whole block settles in one layout change.
//

import Foundation
import KinoPubBackend

/// Kinopoisk extras (facts / reviews / crew / stills) for a single title. Independently loadable:
/// owns its own `extrasLoaded` flag so the page can reserve skeleton space and settle once.
@MainActor
final class MediaExtrasLoader: ObservableObject {

  @Published private(set) var facts: [KpFact] = []
  @Published private(set) var reviews: KpReviewsPage = .empty
  @Published private(set) var staff: [KpStaffMember] = []
  @Published private(set) var images: [KpImage] = []
  /// True when the extras block has settled (loaded, or known-unavailable). The view uses it to
  /// decide whether to keep reserving skeleton space.
  @Published private(set) var extrasLoaded: Bool = false

  private let extrasService: KinopoiskExtrasService

  init(extrasService: KinopoiskExtrasService) {
    self.extrasService = extrasService
  }

  /// Loads facts / reviews / crew / stills for this title. Requires a Kinopoisk id; each request
  /// is independent and best-effort (a failure hides its section).
  func load(for item: MediaItem) {
    // No Kinopoisk id → there will never be extras; mark loaded so the view doesn't reserve skeleton
    // space for sections that can't appear.
    guard let filmId = item.kinopoisk, filmId > 0 else {
      extrasLoaded = true
      return
    }
    // Resolve all four together and publish once, so the extras block settles in a single layout
    // change (with the skeleton reserving its space) instead of four staggered pops.
    Task {
      async let f = extrasService.facts(filmId: filmId)
      async let r = extrasService.reviews(filmId: filmId)
      async let s = extrasService.staff(filmId: filmId)
      async let i = extrasService.images(filmId: filmId)
      facts = (try? await f) ?? []
      reviews = (try? await r) ?? .empty
      staff = (try? await s) ?? []
      images = (try? await i) ?? []
      extrasLoaded = true
    }
  }
}
