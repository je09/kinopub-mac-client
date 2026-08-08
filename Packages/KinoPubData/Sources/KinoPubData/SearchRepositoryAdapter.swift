import Foundation
import KinoPubBackend
import KinoPubDomain

public struct SearchRepositoryAdapter: SearchRepository {
  private let client: any HTTPClient

  public init(client: any HTTPClient) {
    self.client = client
  }

  public func search(query: String, field: SearchField, page: Int?) async throws -> Page<MediaSummary> {
    let request: any Endpoint
    switch field {
    case .title:
      // Plain title match. `field` stays nil: the transport's full-text `search?field=` misses
      // most actors/directors, so person queries never route here (see below).
      request = SearchItemsRequest(contentType: nil, page: page, query: query, field: nil)
    case .cast, .director:
      // Person filmographies use the documented, reliable cast=/director= FILTER rather than the
      // flaky full-text field match. Encapsulated here so callers just ask for a "cast search".
      request = FilterItemsRequest(
        director: field == .director ? query : nil,
        cast: field == .cast ? query : nil,
        page: page
      )
    }
    let response = try await client.performRequest(
      with: request,
      decodingType: PaginatedData<MediaItem>.self,
      forceRefresh: false
    )
    return SearchPageMapper.map(response)
  }

  public func filter(_ query: CatalogQuery, page: Int?) async throws -> Page<MediaSummary> {
    let request = FilterItemsRequest(
      contentType: query.kind.mediaType,
      genres: query.genreID.map { [$0] },
      sort: query.sort?.rawValue,
      page: page
    )
    let response = try await client.performRequest(
      with: request,
      decodingType: PaginatedData<MediaItem>.self,
      forceRefresh: false
    )
    return SearchPageMapper.map(response)
  }

  public func genres() async throws -> [Genre] {
    let response = try await client.performRequest(
      with: GenresRequest(),
      decodingType: ArrayData<MediaGenre>.self,
      forceRefresh: false
    )
    return response.items.compactMap { Genre(id: $0.id, title: $0.title) }
  }
}

enum SearchPageMapper {
  static func map(_ dto: PaginatedData<MediaItem>) -> Page<MediaSummary> {
    Page(
      items: dto.items.compactMap(MediaSummaryMapper.map),
      total: dto.pagination.total,
      current: dto.pagination.current,
      perPage: dto.pagination.perpage
    )
  }
}

enum MediaSummaryMapper {
  static func map(_ dto: MediaItem) -> MediaSummary? {
    MediaSummary(
      id: dto.id,
      title: dto.title,
      year: dto.year,
      type: dto.type,
      cast: dto.cast,
      director: dto.director,
      genres: dto.genres.compactMap { Genre(id: $0.id, title: $0.title ?? "") },
      posters: PosterSet(small: dto.posters.small, medium: dto.posters.medium, wide: dto.posters.wide),
      kinopoiskRating: dto.kinopoiskRating,
      imdbRating: dto.imdbRating,
      isSkeleton: dto.skeleton ?? false
    )
  }
}

private extension CatalogQuery.ContentKind {
  var mediaType: MediaType? {
    switch self {
    case .all: return nil
    case .movie: return .movie
    case .serial: return .serial
    }
  }
}
