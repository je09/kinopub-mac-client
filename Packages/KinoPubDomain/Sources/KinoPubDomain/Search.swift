import Foundation

// MARK: - Genre

public struct Genre: Equatable, Hashable, Identifiable, Sendable {
  public let id: Int
  public let title: String

  public init?(id: Int, title: String) {
    let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard id > 0, !normalizedTitle.isEmpty else { return nil }
    self.id = id
    self.title = normalizedTitle
  }
}

// MARK: - MediaKind

/// The content type of a media item, normalized from the transport's raw `type` string.
/// Unknown types map to `.unknown` so a single unrecognized value never breaks a list.
public enum MediaKind: Equatable, Hashable, Sendable {
  case movie
  case serial
  case threeD
  case concert
  case documovie
  case docuserial
  case tvshow
  case unknown

  public init(rawType: String) {
    switch rawType {
    case "movie": self = .movie
    case "serial": self = .serial
    case "3D": self = .threeD
    case "concert": self = .concert
    case "documovie": self = .documovie
    case "docuserial": self = .docuserial
    case "tvshow": self = .tvshow
    default: self = .unknown
    }
  }

  public var isSeries: Bool {
    switch self {
    case .serial, .docuserial, .tvshow: return true
    default: return false
    }
  }

  /// Display title mirroring the transport's `MediaType` labels; empty for unknown kinds so
  /// callers can omit the type from metadata lines.
  public var title: String {
    switch self {
    case .movie: return "Movie"
    case .serial: return "Serial"
    case .threeD: return "3D"
    case .concert: return "Concert"
    case .documovie: return "Documental"
    case .docuserial: return "Documental Series"
    case .tvshow: return "TV Show"
    case .unknown: return ""
    }
  }
}

// MARK: - PosterSet

public struct PosterSet: Equatable, Hashable, Sendable {
  public let small: String
  public let medium: String
  public let wide: String?

  public init(small: String, medium: String, wide: String? = nil) {
    self.small = small
    self.medium = medium
    self.wide = wide
  }
}

// MARK: - MediaSummary

/// A validated summary of a media title for list/catalog surfaces. Carries the fields the search
/// presentation needs (title, kind, posters, credits) without the full transport payload.
public struct MediaSummary: Equatable, Hashable, Identifiable, Sendable {
  public let id: Int
  public let title: String
  public let year: Int
  public let type: String
  public let cast: String
  public let director: String
  public let genres: [Genre]
  public let posters: PosterSet
  public let kinopoiskRating: Double?
  public let imdbRating: Double?
  public let isSkeleton: Bool

  public init?(
    id: Int,
    title: String,
    year: Int,
    type: String,
    cast: String,
    director: String,
    genres: [Genre],
    posters: PosterSet,
    kinopoiskRating: Double? = nil,
    imdbRating: Double? = nil,
    isSkeleton: Bool = false
  ) {
    let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard id > 0, !normalizedTitle.isEmpty else { return nil }
    self.id = id
    self.title = normalizedTitle
    self.year = year
    self.type = type
    self.cast = cast
    self.director = director
    self.genres = genres
    self.posters = posters
    self.kinopoiskRating = kinopoiskRating
    self.imdbRating = imdbRating
    self.isSkeleton = isSkeleton
  }

  public var kind: MediaKind { MediaKind(rawType: type) }
  public var isSeries: Bool { kind.isSeries }

  /// First title segment ("Russian / Original" style titles) for display.
  public var localizedTitle: String {
    title.split(separator: "/").first?.trimmingCharacters(in: .whitespaces) ?? title
  }

  /// Last title segment; used where the original title matters.
  public var originalTitle: String {
    title.split(separator: "/").last?.trimmingCharacters(in: .whitespaces) ?? title
  }

  /// The transport's own label for the kind; empty when unrecognized (mirrors `kind.title`).
  public var typeTitle: String { kind.title }

  public var primaryGenreTitle: String? {
    genres.first?.title
  }
}

// MARK: - PersonSearchResult

/// A person surfaced from a search (actor/director). kino.pub returns films rather than person
/// entities, so a person is recovered from the matched films' credits and can hold both roles
/// (e.g. Jackie Chan is both an actor and a director).
public struct PersonSearchResult: Equatable, Hashable, Identifiable, Sendable {
  public let name: String
  public let isActor: Bool
  public let isDirector: Bool

  public init?(name: String, isActor: Bool, isDirector: Bool) {
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedName.isEmpty else { return nil }
    self.name = normalizedName
    self.isActor = isActor
    self.isDirector = isDirector
  }

  public var id: String { name }
  public var displayName: String { name }

  /// Field used to open their filmography (acting is usually the larger set).
  public var field: SearchField { isActor ? .cast : .director }
}

// MARK: - SearchField

/// The search field a query targets. `.title` matches by title; person fields use the reliable
/// cast=/director= filter (the transport's full-text `search?field=` misses most people).
public enum SearchField: String, Equatable, Hashable, Sendable {
  case title
  case cast
  case director

  public var isPerson: Bool { self != .title }
}

// MARK: - CatalogQuery

/// A catalog browse query (genre grid, representative posters). Hides the transport's filter
/// envelope and the facets the server silently ignores.
public struct CatalogQuery: Equatable, Hashable, Sendable {
  public enum ContentKind: Equatable, Hashable, Sendable {
    case all
    case movie
    case serial
  }

  public enum Sort: String, Equatable, Hashable, Sendable {
    case ratingDescending = "rating-"
  }

  public var kind: ContentKind
  public var genreID: Int?
  public var sort: Sort?

  public init(kind: ContentKind = .all, genreID: Int? = nil, sort: Sort? = nil) {
    self.kind = kind
    self.genreID = genreID
    self.sort = sort
  }
}

// MARK: - Page

/// A validated page of domain items with its pagination metadata; the transport's paginated
/// response envelope never reaches the UI layer.
public struct Page<Element: Hashable & Sendable>: Equatable, Hashable, Sendable {
  public let items: [Element]
  public let total: Int
  public let current: Int
  public let perPage: Int

  public init(items: [Element], total: Int, current: Int, perPage: Int) {
    self.items = items
    self.total = total
    self.current = current
    self.perPage = perPage
  }

  public var hasMore: Bool { current < total }
  public var nextPage: Int { current + 1 }
}

// MARK: - SearchRepository

/// The search/catalog read surface used by the search feature. Hides request names, response
/// envelopes, the person-field endpoint fallback, and pagination DTOs.
public protocol SearchRepository {
  func search(query: String, field: SearchField, page: Int?) async throws -> Page<MediaSummary>
  func filter(_ query: CatalogQuery, page: Int?) async throws -> Page<MediaSummary>
  func genres() async throws -> [Genre]
}
