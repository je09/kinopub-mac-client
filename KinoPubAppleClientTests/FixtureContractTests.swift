import XCTest
import KinoPubBackend
@testable import KinoPub

final class FixtureContractTests: XCTestCase {
  func testCatalogFixtureMatchesTransportContract() throws {
    let response = try decode(PaginatedData<MediaItem>.self, fixture: "catalog-page")

    XCTAssertTrue(response.items.isEmpty)
    XCTAssertEqual(response.pagination.current, 1)
    XCTAssertEqual(response.pagination.total, 1)
    XCTAssertEqual(response.pagination.perpage, 20)
  }

  func testCommentsFixtureMatchesTransportContract() throws {
    let response = try decode(CommentsData.self, fixture: "comments")

    XCTAssertTrue(response.comments.isEmpty)
  }

  func testMediaLinksFixtureMatchesTransportContract() throws {
    let response = try decode(MediaLinksData.self, fixture: "media-links")

    XCTAssertEqual(response.id, 42)
    XCTAssertTrue(response.files.isEmpty)
    XCTAssertEqual(response.subtitles, [])
    XCTAssertNil(response.thumbnail)
  }

  private func decode<T: Decodable>(_ type: T.Type, fixture name: String) throws -> T {
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
    )
    return try JSONDecoder().decode(type, from: Data(contentsOf: url))
  }
}
