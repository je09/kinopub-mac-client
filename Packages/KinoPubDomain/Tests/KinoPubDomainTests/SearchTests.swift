import XCTest
@testable import KinoPubDomain

final class MediaSummaryTests: XCTestCase {
  func testValidSummaryIsAcceptedAndTrimsTitle() {
    let summary = MediaSummary(
      id: 7,
      title: "  Стражи Галактики / Guardians  ",
      year: 2023,
      type: "movie",
      cast: "Крис Пратт",
      director: "Джеймс Ганн",
      genres: [Genre(id: 1, title: "Action")!],
      posters: PosterSet(small: "s", medium: "m", wide: "w")
    )

    XCTAssertNotNil(summary)
    XCTAssertEqual(summary?.id, 7)
    XCTAssertEqual(summary?.title, "Стражи Галактики / Guardians")
    XCTAssertEqual(summary?.localizedTitle, "Стражи Галактики")
    XCTAssertEqual(summary?.originalTitle, "Guardians")
    XCTAssertFalse(summary?.isSeries ?? true)
    XCTAssertEqual(summary?.typeTitle, "Movie")
    XCTAssertEqual(summary?.primaryGenreTitle, "Action")
    XCTAssertEqual(summary?.kind, .movie)
  }

  func testInvalidIdentifiersAndEmptyTitlesAreRejected() {
    XCTAssertNil(MediaSummary(
      id: 0, title: "Title", year: 2023, type: "movie",
      cast: "", director: "", genres: [], posters: PosterSet(small: "", medium: "")))
    XCTAssertNil(MediaSummary(
      id: 1, title: "   ", year: 2023, type: "movie",
      cast: "", director: "", genres: [], posters: PosterSet(small: "", medium: "")))
  }

  func testKindClassification() {
    XCTAssertTrue(MediaSummary.testItem(id: 1, type: "serial").isSeries)
    XCTAssertTrue(MediaSummary.testItem(id: 2, type: "tvshow").isSeries)
    XCTAssertTrue(MediaSummary.testItem(id: 3, type: "docuserial").isSeries)
    XCTAssertFalse(MediaSummary.testItem(id: 4, type: "movie").isSeries)
    XCTAssertFalse(MediaSummary.testItem(id: 5, type: "unknown-raw").isSeries)
    XCTAssertEqual(MediaSummary.testItem(id: 6, type: "unknown-raw").typeTitle, "")
  }

  func testSkeletonFlagIsPreserved() {
    let summary = MediaSummary.testItem(id: 1, isSkeleton: true)
    XCTAssertTrue(summary.isSkeleton)
  }
}

final class PersonSearchResultTests: XCTestCase {
  func testDualRolePersonExposesBothRolesAndCastField() {
    let person = PersonSearchResult(name: "  Джеки Чан  ", isActor: true, isDirector: true)
    XCTAssertNotNil(person)
    XCTAssertEqual(person?.name, "Джеки Чан")
    XCTAssertEqual(person?.displayName, "Джеки Чан")
    XCTAssertEqual(person?.id, "Джеки Чан")
    XCTAssertEqual(person?.field, .cast)
  }

  func testDirectorOnlyPersonUsesDirectorField() {
    let person = PersonSearchResult(name: "Джеймс Ганн", isActor: false, isDirector: true)
    XCTAssertEqual(person?.field, .director)
  }

  func testEmptyNameIsRejected() {
    XCTAssertNil(PersonSearchResult(name: "  ", isActor: true, isDirector: false))
  }
}

final class PageTests: XCTestCase {
  func testPaginationMetadata() {
    let page = Page(items: [MediaSummary.testItem(id: 1)], total: 3, current: 1, perPage: 10)
    XCTAssertTrue(page.hasMore)
    XCTAssertEqual(page.nextPage, 2)
  }

  func testFinalPageHasNoMore() {
    let page = Page(items: [MediaSummary](), total: 2, current: 2, perPage: 10)
    XCTAssertFalse(page.hasMore)
  }
}

private extension MediaSummary {
  static func testItem(id: Int, type: String = "movie", isSkeleton: Bool = false) -> MediaSummary {
    MediaSummary(
      id: id,
      title: "Title \(id)",
      year: 2020,
      type: type,
      cast: "",
      director: "",
      genres: [],
      posters: PosterSet(small: "", medium: ""),
      isSkeleton: isSkeleton
    )!
  }
}
