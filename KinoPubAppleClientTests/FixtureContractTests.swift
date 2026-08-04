import XCTest
import KinoPubBackend
@testable import KinoPub

final class FixtureContractTests: XCTestCase {
  func testCatalogFixtureMatchesTransportContract() throws {
    let response = try decode(PaginatedData<MediaItem>.self, fixture: "catalog-page")
    
    XCTAssertEqual(response.items.map(\.id), [42])
    XCTAssertEqual(response.pagination.current, 1)
    XCTAssertEqual(response.pagination.total, 1)
    XCTAssertEqual(response.pagination.perpage, 20)
  }
  
  func testDetailFixtureMatchesTransportContract() throws {
    let response = try decode(SingleItemData<MediaItem>.self, fixture: "detail")
    
    XCTAssertEqual(response.item.id, 42)
    XCTAssertEqual(response.item.createdAt, nil)
    XCTAssertEqual(response.item.updatedAt, nil)
  }
  
  func testMalformedCatalogFixtureDropsOnlyInvalidItem() throws {
    let response = try decode(PaginatedData<MediaItem>.self, fixture: "catalog-malformed")
    
    XCTAssertEqual(response.items.map(\.id), [42])
  }
  
  func testBookmarksAndHistoryFixturesMatchTransportContracts() throws {
    let bookmarks = try decode(ArrayData<Bookmark>.self, fixture: "bookmarks")
    let history = try decode(HistoryData.self, fixture: "history")
    
    XCTAssertEqual(bookmarks.items.map(\.id), [7])
    XCTAssertEqual(bookmarks.items.first?.count, "2")
    XCTAssertTrue(history.history.isEmpty)
    XCTAssertEqual(history.pagination.current, 1)
  }
  
  func testPlaybackSourceFixtureMatchesTransportContract() throws {
    let response = try decode(MediaVideoLinkData.self, fixture: "playback-source")
    
    XCTAssertEqual(response.url, "https://example.invalid/signed-playback-url")
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
