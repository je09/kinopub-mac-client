import XCTest
import KinoPubDomain
@testable import KinoPub

@MainActor
final class CommentsStoreTests: XCTestCase {
  func testLoadPublishesLoadedState() async throws {
    let comment = try makeComment()
    let store = CommentsStore(mediaID: 42, repository: CommentsRepositoryStub(result: .success([comment])))

    await store.load()

    XCTAssertEqual(store.state, .loaded([comment]))
  }

  func testLoadPublishesEmptyState() async {
    let store = CommentsStore(mediaID: 42, repository: CommentsRepositoryStub(result: .success([])))
    await store.load()
    XCTAssertEqual(store.state, .empty)
  }

  func testLoadPublishesFailureState() async {
    let store = CommentsStore(
      mediaID: 42,
      repository: CommentsRepositoryStub(result: .failure(TestError.failed))
    )
    await store.load()
    XCTAssertEqual(store.state, .failed)
  }

  func testCancellationReturnsToIdleWithoutFailure() async {
    let repository = SuspendedCommentsRepository()
    let store = CommentsStore(mediaID: 42, repository: repository)
    let task = Task { await store.load() }
    await repository.waitUntilRequested()

    task.cancel()
    await repository.cancel()
    await task.value

    XCTAssertEqual(store.state, .idle)
  }

  private func makeComment() throws -> Comment {
    let author = try XCTUnwrap(UserSummary(id: 1, name: "Alice", avatarURL: nil))
    return try XCTUnwrap(
      Comment(id: 2, message: "Hello", createdAt: .distantPast, rating: nil, depth: 0, author: author)
    )
  }
}

private enum TestError: Error {
  case failed
}

private struct CommentsRepositoryStub: CommentsRepository {
  let result: Result<[Comment], Error>
  func comments(for mediaID: Int) async throws -> [Comment] { try result.get() }
}

private actor SuspendedCommentsRepository: CommentsRepository {
  private var requested = false
  private var continuation: CheckedContinuation<[Comment], Error>?

  func comments(for mediaID: Int) async throws -> [Comment] {
    requested = true
    return try await withCheckedThrowingContinuation { continuation = $0 }
  }

  func waitUntilRequested() async {
    while !requested { await Task.yield() }
  }

  func cancel() {
    continuation?.resume(throwing: CancellationError())
    continuation = nil
  }
}
