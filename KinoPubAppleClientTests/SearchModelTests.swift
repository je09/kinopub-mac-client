import XCTest
import KinoPubDomain
@testable import KinoPub

@MainActor
final class SearchModelTests: XCTestCase {
  func testOlderMainSearchResponseCannotReplaceNewerQuery() async throws {
    let repository = ControlledSearchRepository()
    let model = makeModel(repository: repository)

    let old = Task { await model.performSearch(query: "old") }
    await repository.waitForPendingRequestCount(3)
    let new = Task { await model.performSearch(query: "new") }
    await repository.waitForPendingRequestCount(6)

    await repository.resolve(query: "new", field: .title, page: nil, items: [.testItem(id: 20)])
    await repository.resolve(query: "new", field: .cast, page: nil, items: [.testItem(id: 21)])
    await repository.resolve(query: "new", field: .director, page: nil, items: [.testItem(id: 22)])
    await new.value

    await repository.resolve(query: "old", field: .title, page: nil, items: [.testItem(id: 10)])
    await repository.resolve(query: "old", field: .cast, page: nil, items: [.testItem(id: 11)])
    await repository.resolve(query: "old", field: .director, page: nil, items: [.testItem(id: 12)])
    await old.value

    XCTAssertEqual(model.titleResults.map(\.id), [20])
    XCTAssertEqual(model.castResults.map(\.id), [21])
    XCTAssertEqual(model.directorResults.map(\.id), [22])
    XCTAssertFalse(model.searching)
  }

  func testOlderFieldSearchCannotReplaceNewerQuery() async {
    let repository = ControlledSearchRepository()
    let model = makeModel(repository: repository)

    let old = Task { await model.performFieldSearch(query: "old", field: nil) }
    await repository.waitForPendingRequestCount(1)
    let new = Task { await model.performFieldSearch(query: "new", field: nil) }
    await repository.waitForPendingRequestCount(2)

    await repository.resolve(query: "new", field: .title, page: nil, items: [.testItem(id: 2)])
    await new.value
    await repository.resolve(query: "old", field: .title, page: nil, items: [.testItem(id: 1)])
    await old.value

    XCTAssertEqual(model.results.map(\.id), [2])
    XCTAssertFalse(model.searching)
  }

  func testFieldSearchFailurePublishesEmptyErrorState() async {
    let repository = ControlledSearchRepository()
    let errorHandler = ErrorHandler()
    let model = SearchModel(repository: repository, recentsRepository: InMemoryRecentSearchRepository(), errorHandler: errorHandler)

    let search = Task { await model.performFieldSearch(query: "failure", field: nil) }
    await repository.waitForPendingRequestCount(1)
    await repository.reject(query: "failure", field: .title, page: nil, error: TestError.failed)
    await search.value

    XCTAssertTrue(model.results.isEmpty)
    XCTAssertFalse(model.searching)
    XCTAssertTrue(errorHandler.state.showError)
  }

  func testCancelledSearchDiscardsLateResponseWithoutPublishing() async {
    let repository = ControlledSearchRepository()
    let model = makeModel(repository: repository)

    let search = Task { await model.performFieldSearch(query: "slow", field: nil) }
    await repository.waitForPendingRequestCount(1)
    search.cancel()

    await repository.resolve(query: "slow", field: .title, page: nil, items: [.testItem(id: 99)])
    await search.value

    // The cancelled task must not publish stale results or flip the loading flag.
    XCTAssertTrue(model.results.allSatisfy { $0.isSkeleton })
    XCTAssertTrue(model.searching)
  }

  func testShortMainSearchPublishesEmptyStateWithoutRequest() async {
    let repository = ControlledSearchRepository()
    let model = makeModel(repository: repository)
    model.titleResults = [.testItem(id: 1)]
    model.castResults = [.testItem(id: 2)]
    model.directorResults = [.testItem(id: 3)]

    await model.performSearch(query: "ab")

    let requestCount = await repository.pendingRequestCount()
    XCTAssertTrue(model.allResults.isEmpty)
    XCTAssertFalse(model.searching)
    XCTAssertEqual(requestCount, 0)
  }

  func testPaginationAppendsOnlyForCurrentQuery() async {
    let repository = ControlledSearchRepository()
    let model = makeModel(repository: repository)

    let initial = Task { await model.performFieldSearch(query: "actor", field: .cast) }
    await repository.waitForPendingRequestCount(1)
    await repository.resolve(
      query: "actor", field: .cast, page: nil, items: [.testItem(id: 1)],
      total: 2, current: 1, perPage: 1
    )
    await initial.value

    model.loadMoreContent(after: model.results[0])
    await repository.waitForPendingRequestCount(1)
    await repository.resolve(
      query: "actor", field: .cast, page: 2, items: [.testItem(id: 2)],
      total: 2, current: 2, perPage: 1
    )
    await eventually { model.results.count == 2 }

    XCTAssertEqual(model.results.map(\.id), [1, 2])
  }


  func testPartialScopeFailureIsRecordedNotFatal() async {
    let repository = ControlledSearchRepository()
    let model = makeModel(repository: repository)

    let search = Task { await model.performSearch(query: "mixed") }
    await repository.waitForPendingRequestCount(3)

    await repository.reject(query: "mixed", field: .title, page: nil, error: TestError.failed)
    await repository.resolve(query: "mixed", field: .cast, page: nil, items: [.testItem(id: 21)])
    await repository.resolve(query: "mixed", field: .director, page: nil, items: [.testItem(id: 22)])
    await search.value

    // The failing scope is recorded and stays empty; the others still render.
    XCTAssertEqual(model.failedScopes, [.title])
    XCTAssertTrue(model.titleResults.isEmpty)
    XCTAssertEqual(model.castResults.map(\.id), [21])
    XCTAssertEqual(model.directorResults.map(\.id), [22])
    XCTAssertFalse(model.searching)
  }

  func testAllScopesFailedPublishesFailureWithoutSkeleton() async {
    let repository = ControlledSearchRepository()
    let model = makeModel(repository: repository)

    let search = Task { await model.performSearch(query: "down") }
    await repository.waitForPendingRequestCount(3)

    await repository.reject(query: "down", field: .title, page: nil, error: TestError.failed)
    await repository.reject(query: "down", field: .cast, page: nil, error: TestError.failed)
    await repository.reject(query: "down", field: .director, page: nil, error: TestError.failed)
    await search.value

    XCTAssertEqual(model.failedScopes, [.title, .cast, .director])
    XCTAssertTrue(model.allResults.isEmpty)
    XCTAssertFalse(model.searching)
  }

  func testRecentsPersistThroughRepositoryAndClear() {
    let repository = InMemoryRecentSearchRepository()
    let model = SearchModel(
      repository: SearchRepositoryStub(),
      recentsRepository: repository,
      errorHandler: ErrorHandler())

    model.recordRecent(.testItem(id: 7))
    model.recordRecent(.testItem(id: 9))

    XCTAssertEqual(model.recentItems.map(\.id), [9, 7])
    XCTAssertEqual(repository.load().map(\.id), [9, 7])

    // A fresh model loads the persisted recents from the same repository.
    let reloaded = SearchModel(
      repository: SearchRepositoryStub(),
      recentsRepository: repository,
      errorHandler: ErrorHandler())
    XCTAssertEqual(reloaded.recentItems.map(\.id), [9, 7])

    model.clearRecents()
    XCTAssertTrue(model.recentItems.isEmpty)
    XCTAssertTrue(repository.load().isEmpty)
  }

  func testPeopleMiningRecoversCanonicalNamesFromCredits() async {
    let model = SearchModel(
      repository: SearchRepositoryStub(),
      recentsRepository: InMemoryRecentSearchRepository(),
      errorHandler: ErrorHandler())
    model.query = "джеки"
    model.castResults = [
      .testItem(id: 1, cast: "Джеки Чан, Джеки Уивер", director: "Джеймс Ганн"),
      .testItem(id: 2, cast: "Джеки Чан", director: "Джеки Чан")
    ]
    model.directorResults = [
      .testItem(id: 3, cast: "", director: "Джеки Чан")
    ]

    let people = model.people

    XCTAssertEqual(people.map(\.name), ["Джеки Чан", "Джеки Уивер"])
    XCTAssertEqual(people[0].isActor, true)
    XCTAssertEqual(people[0].isDirector, true)
    XCTAssertEqual(people[0].field, .cast)
    XCTAssertEqual(people[1].isDirector, false)
  }

  private func makeModel(repository: ControlledSearchRepository) -> SearchModel {
    SearchModel(repository: repository, recentsRepository: InMemoryRecentSearchRepository(), errorHandler: ErrorHandler())
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

private enum TestError: Error {
  case failed
}

private actor ControlledSearchRepository: SearchRepository {
  private struct Key: Hashable {
    let query: String
    let field: SearchField
    let page: Int?
  }

  private var pending: [Key: [CheckedContinuation<Page<MediaSummary>, Error>]] = [:]

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
    field: SearchField,
    page: Int?,
    items: [MediaSummary],
    total: Int = 1,
    current: Int = 1,
    perPage: Int = 50
  ) {
    let key = Key(query: query, field: field, page: page)
    guard var values = pending[key], !values.isEmpty else {
      XCTFail("No pending search request for \(key)")
      return
    }
    let continuation = values.removeFirst()
    pending[key] = values
    continuation.resume(returning: Page(items: items, total: total, current: current, perPage: perPage))
  }

  func reject(query: String, field: SearchField, page: Int?, error: Error) {
    let key = Key(query: query, field: field, page: page)
    guard var values = pending[key], !values.isEmpty else {
      XCTFail("No pending search request for \(key)")
      return
    }
    let continuation = values.removeFirst()
    pending[key] = values
    continuation.resume(throwing: error)
  }

  func search(query: String, field: SearchField, page: Int?) async throws -> Page<MediaSummary> {
    let key = Key(query: query, field: field, page: page)
    return try await withCheckedThrowingContinuation { continuation in
      pending[key, default: []].append(continuation)
    }
  }

  func filter(_ query: CatalogQuery, page: Int?) async throws -> Page<MediaSummary> {
    Page(items: [MediaSummary](), total: 0, current: 0, perPage: 0)
  }

  func genres() async throws -> [Genre] { [] }
}

private extension MediaSummary {
  static func testItem(id: Int, cast: String = "", director: String = "") -> MediaSummary {
    MediaSummary(
      id: id,
      title: "Title \(id)",
      year: 2020,
      type: "movie",
      cast: cast,
      director: director,
      genres: [],
      posters: PosterSet(small: "", medium: ""),
      isSkeleton: false
    )!
  }
}
