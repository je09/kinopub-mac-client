import XCTest
import KinoPubBackend
@testable import KinoPub

@MainActor
final class SearchModelTests: XCTestCase {
  func testOlderMainSearchResponseCannotReplaceNewerQuery() async throws {
    let service = ControlledSearchService()
    let model = makeModel(service: service)
    
    let old = Task { await model.performSearch(query: "old") }
    await service.waitForPendingRequestCount(3)
    let new = Task { await model.performSearch(query: "new") }
    await service.waitForPendingRequestCount(6)
    
    await service.resolve(query: "new", field: nil, page: nil, items: [.mock(id: 20)])
    await service.resolve(query: "new", field: "cast", page: nil, items: [.mock(id: 21)])
    await service.resolve(query: "new", field: "director", page: nil, items: [.mock(id: 22)])
    await new.value
    
    await service.resolve(query: "old", field: nil, page: nil, items: [.mock(id: 10)])
    await service.resolve(query: "old", field: "cast", page: nil, items: [.mock(id: 11)])
    await service.resolve(query: "old", field: "director", page: nil, items: [.mock(id: 12)])
    await old.value
    
    XCTAssertEqual(model.titleResults.map(\.id), [20])
    XCTAssertEqual(model.castResults.map(\.id), [21])
    XCTAssertEqual(model.directorResults.map(\.id), [22])
    XCTAssertFalse(model.searching)
  }
  
  func testOlderFieldSearchCannotReplaceNewerQuery() async {
    let service = ControlledSearchService()
    let model = makeModel(service: service)
    
    let old = Task { await model.performFieldSearch(query: "old", field: nil) }
    await service.waitForPendingRequestCount(1)
    let new = Task { await model.performFieldSearch(query: "new", field: nil) }
    await service.waitForPendingRequestCount(2)
    
    await service.resolve(query: "new", field: nil, page: nil, items: [.mock(id: 2)])
    await new.value
    await service.resolve(query: "old", field: nil, page: nil, items: [.mock(id: 1)])
    await old.value
    
    XCTAssertEqual(model.results.map(\.id), [2])
    XCTAssertFalse(model.searching)
  }
  
  func testFieldSearchFailurePublishesEmptyErrorState() async {
    let service = ControlledSearchService()
    let errorHandler = ErrorHandler()
    let model = SearchModel(
      itemsService: service,
      authState: AuthState(
        authService: AuthorizationServiceMock(),
        accessTokenService: AccessTokenServiceMock(),
        deviceService: DeviceServiceMock()
      ),
      errorHandler: errorHandler
    )
    
    let search = Task { await model.performFieldSearch(query: "failure", field: nil) }
    await service.waitForPendingRequestCount(1)
    await service.reject(
      query: "failure",
      field: nil,
      page: nil,
      error: APIClientError.networkError(URLError(.notConnectedToInternet))
    )
    await search.value
    
    XCTAssertTrue(model.results.isEmpty)
    XCTAssertFalse(model.searching)
    XCTAssertTrue(errorHandler.state.showError)
  }
  
  func testShortMainSearchPublishesEmptyStateWithoutRequest() async {
    let service = ControlledSearchService()
    let model = makeModel(service: service)
    model.titleResults = [.mock(id: 1)]
    model.castResults = [.mock(id: 2)]
    model.directorResults = [.mock(id: 3)]
    
    await model.performSearch(query: "ab")
    
    let requestCount = await service.pendingRequestCount()
    XCTAssertTrue(model.allResults.isEmpty)
    XCTAssertFalse(model.searching)
    XCTAssertEqual(requestCount, 0)
  }
  
  func testPaginationAppendsOnlyForCurrentQuery() async {
    let service = ControlledSearchService()
    let model = makeModel(service: service)
    
    let initial = Task { await model.performFieldSearch(query: "actor", field: "cast") }
    await service.waitForPendingRequestCount(1)
    await service.resolve(
      query: "actor", field: "cast", page: nil, items: [.mock(id: 1)],
      pagination: Pagination(total: 2, current: 1, perpage: 1)
    )
    await initial.value
    
    model.loadMoreContent(after: model.results[0])
    await service.waitForPendingRequestCount(1)
    await service.resolve(
      query: "actor", field: "cast", page: 2, items: [.mock(id: 2)],
      pagination: Pagination(total: 2, current: 2, perpage: 1)
    )
    await eventually { model.results.count == 2 }
    
    XCTAssertEqual(model.results.map(\.id), [1, 2])
  }
  
  private func makeModel(service: ControlledSearchService) -> SearchModel {
    SearchModel(
      itemsService: service,
      authState: AuthState(
        authService: AuthorizationServiceMock(),
        accessTokenService: AccessTokenServiceMock(),
        deviceService: DeviceServiceMock()
      ),
      errorHandler: ErrorHandler()
    )
  }
  
  private func eventually(
    timeout: TimeInterval = 1,
    condition: @escaping @MainActor () -> Bool
  ) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
      await Task.yield()
    }
    XCTAssertTrue(condition())
  }
}

private actor ControlledSearchService: VideoContentService {
  private struct Key: Hashable {
    let query: String
    let field: String?
    let page: Int?
  }
  
  private var pending: [Key: [CheckedContinuation<PaginatedData<MediaItem>, Error>]] = [:]
  
  func waitForPendingRequestCount(_ count: Int) async {
    while pending.values.reduce(0, { $0 + $1.count }) < count {
      await Task.yield()
    }
  }
  
  func pendingRequestCount() -> Int {
    pending.values.reduce(0, { $0 + $1.count })
  }
  
  func resolve(
    query: String,
    field: String?,
    page: Int?,
    items: [MediaItem],
    pagination: Pagination = Pagination(total: 1, current: 1, perpage: 50)
  ) {
    let key = Key(query: query, field: field, page: page)
    guard var values = pending[key], !values.isEmpty else {
      XCTFail("No pending search request for \(key)")
      return
    }
    let continuation = values.removeFirst()
    pending[key] = values
    continuation.resume(returning: PaginatedData(items: items, pagination: pagination))
  }
  
  func reject(query: String, field: String?, page: Int?, error: Error) {
    let key = Key(query: query, field: field, page: page)
    guard var values = pending[key], !values.isEmpty else {
      XCTFail("No pending search request for \(key)")
      return
    }
    let continuation = values.removeFirst()
    pending[key] = values
    continuation.resume(throwing: error)
  }
  
  func search(query: String?, contentType: MediaType?, field: String?, page: Int?) async throws -> PaginatedData<MediaItem> {
    try await response(query: query ?? "", field: field, page: page)
  }
  
  func itemsByPerson(name: String, field: String, page: Int?) async throws -> PaginatedData<MediaItem> {
    try await response(query: name, field: field, page: page)
  }
  
  private func response(query: String, field: String?, page: Int?) async throws -> PaginatedData<MediaItem> {
    let key = Key(query: query, field: field, page: page)
    return try await withCheckedThrowingContinuation { continuation in
      pending[key, default: []].append(continuation)
    }
  }
  
  func fetch(shortcut: MediaShortcut, contentType: MediaType, page: Int?, forceRefresh: Bool) async throws -> PaginatedData<MediaItem> { .mock(data: []) }
  func filter(filter: MediaItemsFilter, page: Int?, forceRefresh: Bool) async throws -> PaginatedData<MediaItem> { .mock(data: []) }
  func fetchGenres(type: MediaType?) async throws -> [MediaGenre] { [] }
  func fetchCountries() async throws -> [Country] { [] }
  func fetchDetails(for id: String) async throws -> SingleItemData<MediaItem> { .mock(data: .mock()) }
  func fetchMediaLinks(mediaID: Int) async throws -> MediaLinksData { MediaLinksData(id: mediaID, files: [], subtitles: nil, thumbnail: nil) }
  func fetchMediaVideoLink(file: String, type: String) async throws -> MediaVideoLinkData { MediaVideoLinkData(url: "") }
  func fetchBookmarks() async throws -> ArrayData<Bookmark> { .mock(data: []) }
  func fetchBookmarkItems(id: String) async throws -> ArrayData<MediaItem> { .mock(data: []) }
  func fetchHistory(page: Int?) async throws -> HistoryData { .mock(data: []) }
  func fetchWatchingSerials(subscribed: Int?, type: String?) async throws -> ArrayData<WatchingSerial> { .mock(data: []) }
  func fetchWatchingMovies() async throws -> ArrayData<WatchingSerial> { .mock(data: []) }
  func fetchTVChannels() async throws -> [TVChannel] { [] }
  func fetchComments(for id: Int) async throws -> CommentsData { .mock() }
}
