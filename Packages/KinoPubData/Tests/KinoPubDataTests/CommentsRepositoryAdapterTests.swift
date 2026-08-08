import XCTest
import KinoPubBackend
import KinoPubDomain
@testable import KinoPubData

final class CommentsRepositoryAdapterTests: XCTestCase {
  func testMapsValidCommentsAndDropsDeletedOrInvalidRecords() async throws {
    let client = HTTPClientStub(
      response: CommentsData(comments: [
        .init(
          id: 1, message: " Hello ", created: 1_700_000_000, rating: "2", depth: 1,
          user: .init(id: 10, name: " Alice ", avatar: "https://example.com/avatar.png")
        ),
        .init(id: 2, message: "Deleted", created: 1, deleted: true, user: .init(id: 11, name: "Bob")),
        .init(id: 0, message: "Invalid", created: 1, user: .init(id: 12, name: "Eve")),
        .init(id: 3, message: "Missing author", created: 1, user: .init(id: 0, name: ""))
      ])
    )

    let comments = try await CommentsRepositoryAdapter(client: client).comments(for: 42)

    XCTAssertEqual(comments.count, 1)
    XCTAssertEqual(comments[0].id, 1)
    XCTAssertEqual(comments[0].message, "Hello")
    XCTAssertEqual(comments[0].rating, 2)
    XCTAssertEqual(comments[0].depth, 1)
    XCTAssertEqual(comments[0].author.name, "Alice")
    XCTAssertEqual(comments[0].author.avatarURL?.absoluteString, "https://example.com/avatar.png")
  }

  func testInvalidMediaIdentifierDoesNotReachTransport() async throws {
    let client = HTTPClientStub(response: CommentsData(comments: []))
    let comments = try await CommentsRepositoryAdapter(client: client).comments(for: 0)
    XCTAssertTrue(comments.isEmpty)
    XCTAssertEqual(client.requestCount, 0)
  }
}

private final class HTTPClientStub: HTTPClient {
  private let response: CommentsData
  private(set) var requestCount = 0

  init(response: CommentsData) {
    self.response = response
  }

  func performRequest<T: Decodable>(
    with requestData: Endpoint,
    decodingType: T.Type,
    forceRefresh: Bool
  ) async throws -> T {
    requestCount += 1
    return response as! T
  }

  func clearCache() {}
}
