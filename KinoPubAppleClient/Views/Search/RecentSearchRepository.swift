//
//  RecentSearchRepository.swift
//  KinoPubAppleClient
//
//  Persistence boundary for recently opened search results. `SearchModel` talks to this protocol
//  instead of `UserDefaults` directly, so the storage key/layout can change without touching the
//  feature store and tests can use an in-memory fixture.
//

import Foundation

/// A recently opened search result, shown as a card in the "Recent" section.
struct RecentSearchItem: Codable, Identifiable, Hashable {
  let id: Int
  let title: String
  let subtitle: String
  let poster: String
}

protocol RecentSearchRepository {
  func load() -> [RecentSearchItem]
  func save(_ items: [RecentSearchItem])
  func clear()
}

/// Default production storage: a JSON blob in `UserDefaults`.
struct UserDefaultsRecentSearchRepository: RecentSearchRepository {
  private static let key = "recentSearchItems"
  private static let limit = 12

  let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() -> [RecentSearchItem] {
    guard let data = defaults.data(forKey: Self.key),
          let items = try? JSONDecoder().decode([RecentSearchItem].self, from: data)
    else {
      return []
    }
    return items
  }

  func save(_ items: [RecentSearchItem]) {
    let bounded = Array(items.prefix(Self.limit))
    if let data = try? JSONEncoder().encode(bounded) {
      defaults.set(data, forKey: Self.key)
    }
  }

  func clear() {
    defaults.removeObject(forKey: Self.key)
  }
}

/// In-memory fixture for previews and tests.
final class InMemoryRecentSearchRepository: RecentSearchRepository {
  private var storage: [RecentSearchItem] = []

  func load() -> [RecentSearchItem] { storage }

  func save(_ items: [RecentSearchItem]) {
    storage = items
  }

  func clear() {
    storage = []
  }
}
