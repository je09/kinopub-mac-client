import XCTest
@testable import KinoPubDomain

final class CommentsTests: XCTestCase {
  func testCommentNormalizesDisplayValues() throws {
    let author = try XCTUnwrap(UserSummary(id: 1, name: "  Alice  ", avatarURL: nil))
    let comment = try XCTUnwrap(
      Comment(id: 2, message: "  Hello  ", createdAt: .distantPast, rating: 0, depth: -2, author: author)
    )

    XCTAssertEqual(author.name, "Alice")
    XCTAssertEqual(comment.message, "Hello")
    XCTAssertNil(comment.rating)
    XCTAssertEqual(comment.depth, 0)
  }

  func testInvalidIdentifiersAndEmptyValuesAreRejected() {
    XCTAssertNil(UserSummary(id: 0, name: "Alice", avatarURL: nil))
    XCTAssertNil(UserSummary(id: 1, name: "  ", avatarURL: nil))

    let author = UserSummary(id: 1, name: "Alice", avatarURL: nil)!
    XCTAssertNil(Comment(id: 0, message: "Hello", createdAt: .distantPast, rating: nil, depth: 0, author: author))
    XCTAssertNil(Comment(id: 1, message: "  ", createdAt: .distantPast, rating: nil, depth: 0, author: author))
  }
}
