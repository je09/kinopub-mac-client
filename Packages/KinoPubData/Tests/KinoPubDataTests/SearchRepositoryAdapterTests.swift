import XCTest
import KinoPubBackend
import KinoPubDomain
@testable import KinoPubData

final class SearchRepositoryAdapterTests: XCTestCase {
  func testTitleSearchUsesSearchEndpointAndMapsPage() async throws {
    let client = HTTPClientStub(
      response: PaginatedData<MediaItem>(
        items: [MediaItem.mock(id: 1), MediaItem.mock(id: 2)],
        pagination: Pagination(total: 7, current: 1, perpage: 2))
    )

    let page = try await SearchRepositoryAdapter(client: client)
      .search(query: "guardians", field: .title, page: 1)

    XCTAssertTrue(client.lastRequest is SearchItemsRequest)
    XCTAssertEqual(page.items.map(\.id), [1, 2])
    XCTAssertEqual(page.total, 7)
    XCTAssertEqual(page.current, 1)
    XCTAssertEqual(page.perPage, 2)
    XCTAssertTrue(page.hasMore)
    XCTAssertEqual(page.nextPage, 2)
    XCTAssertEqual(
      page.items[0].localizedTitle,
      "Стражи Галактики. Часть 3 / Guardians of the Galaxy Vol. 3"
        .split(separator: "/").first?.trimmingCharacters(in: .whitespaces))
    XCTAssertFalse(page.items[0].isSeries)
  }

  func testCastSearchRoutesThroughPersonFilter() async throws {
    let client = HTTPClientStub(response: PaginatedData<MediaItem>.mock(data: [MediaItem.mock(id: 3)]))

    let page = try await SearchRepositoryAdapter(client: client)
      .search(query: "Джеки Чан", field: .cast, page: nil)

    XCTAssertTrue(client.lastRequest is FilterItemsRequest)
    XCTAssertEqual(page.items.map(\.id), [3])
  }

  func testDirectorSearchRoutesThroughPersonFilter() async throws {
    let client = HTTPClientStub(response: PaginatedData<MediaItem>.mock(data: [MediaItem.mock(id: 4)]))

    let page = try await SearchRepositoryAdapter(client: client)
      .search(query: "Джеймс Ганн", field: .director, page: nil)

    XCTAssertTrue(client.lastRequest is FilterItemsRequest)
    XCTAssertEqual(page.items.map(\.id), [4])
  }

  func testFilterMapsKindGenreAndSort() async throws {
    let client = HTTPClientStub(response: PaginatedData<MediaItem>.mock(data: [MediaItem.mock(id: 5)]))

    let page = try await SearchRepositoryAdapter(client: client).filter(
      CatalogQuery(kind: .movie, genreID: 12, sort: .ratingDescending),
      page: nil)

    XCTAssertTrue(client.lastRequest is FilterItemsRequest)
    XCTAssertEqual(page.items.map(\.id), [5])
  }

  func testMalformedItemIsDroppedAtBoundary() async throws {
    let client = HTTPClientStub(
      response: PaginatedData<MediaItem>(
        items: [MediaItem.mock(id: 6), try Self.mediaItemWithEmptyTitle()],
        pagination: Pagination(total: 2, current: 1, perpage: 2))
    )

    let page = try await SearchRepositoryAdapter(client: client)
      .search(query: "x", field: .title, page: nil)

    XCTAssertEqual(page.items.map(\.id), [6])
  }

  func testGenresMapsValidEntriesAndDropsEmptyTitles() async throws {
    let json = """
    {"items":[
      {"id": 1, "title": "Action", "type": "movie"},
      {"id": 2, "title": " ", "type": null}
    ]}
    """
    let response = try JSONDecoder().decode(ArrayData<MediaGenre>.self, from: Data(json.utf8))
    let client = HTTPClientStub(response: response)

    let genres = try await SearchRepositoryAdapter(client: client).genres()

    XCTAssertEqual(genres.map(\.id), [1])
    XCTAssertEqual(genres[0].title, "Action")
  }

  private static func mediaItemWithEmptyTitle() throws -> MediaItem {
    let json = """
    {
      "id": 99, "type": "movie", "subtype": "test", "title": "",
      "year": 2023, "cast": "", "director": "", "genres": [], "countries": [],
      "voice": null, "duration": {"average": 0, "total": 0}, "langs": 0, "quality": 0,
      "plot": "", "imdb": null, "imdb_rating": null, "imdb_votes": null,
      "kinopoisk": null, "kinopoisk_rating": null, "kinopoisk_votes": null,
      "rating": 0, "rating_votes": 0, "rating_percentage": 0, "views": 0, "comments": 0,
      "posters": {"small": "", "medium": "", "big": "", "wide": null},
      "trailer": null, "finished": true, "advert": false, "poor_quality": false
    }
    """
    return try JSONDecoder().decode(MediaItem.self, from: Data(json.utf8))
  }
}

private final class HTTPClientStub<T: Decodable>: HTTPClient {
  private let response: T
  private(set) var lastRequest: (any Endpoint)?

  init(response: T) {
    self.response = response
  }

  func performRequest<U: Decodable>(
    with requestData: Endpoint,
    decodingType: U.Type,
    forceRefresh: Bool
  ) async throws -> U {
    lastRequest = requestData
    guard let response = response as? U else {
      throw APIClientError.invalidRequest("stub response type mismatch")
    }
    return response
  }

  func clearCache() {}
}
