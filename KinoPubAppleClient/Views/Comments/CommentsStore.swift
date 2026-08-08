import Foundation
import Combine
import OSLog
import KinoPubDomain
import KinoPubLogging

@MainActor
final class CommentsStore: ObservableObject {
  enum State: Equatable {
    case idle
    case loading
    case empty
    case loaded([Comment])
    case failed
  }

  @Published private(set) var state: State = .idle

  private let mediaID: Int
  private let repository: any CommentsRepository
  private var loadGeneration = 0

  init(mediaID: Int, repository: any CommentsRepository) {
    self.mediaID = mediaID
    self.repository = repository
  }

  func load() async {
    loadGeneration += 1
    let generation = loadGeneration
    state = .loading

    do {
      let comments = try await repository.comments(for: mediaID)
      guard generation == loadGeneration else { return }
      guard !Task.isCancelled else {
        state = .idle
        return
      }
      state = comments.isEmpty ? .empty : .loaded(comments)
    } catch is CancellationError {
      guard generation == loadGeneration else { return }
      state = .idle
    } catch {
      guard generation == loadGeneration else { return }
      guard !Task.isCancelled else {
        state = .idle
        return
      }
      Logger.app.error("[COMMENTS] Failed to load comments for \(self.mediaID): \(error)")
      state = .failed
    }
  }
}
