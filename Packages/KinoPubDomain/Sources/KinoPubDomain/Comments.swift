import Foundation

public struct UserSummary: Equatable, Hashable, Identifiable, Sendable {
  public let id: Int
  public let name: String
  public let avatarURL: URL?

  public init?(id: Int, name: String, avatarURL: URL?) {
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard id > 0, !normalizedName.isEmpty else { return nil }
    self.id = id
    self.name = normalizedName
    self.avatarURL = avatarURL
  }
}

public struct Comment: Equatable, Hashable, Identifiable, Sendable {
  public let id: Int
  public let message: String
  public let createdAt: Date
  public let rating: Int?
  public let depth: Int
  public let author: UserSummary

  public init?(
    id: Int,
    message: String,
    createdAt: Date,
    rating: Int?,
    depth: Int,
    author: UserSummary
  ) {
    let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard id > 0, !normalizedMessage.isEmpty else { return nil }
    self.id = id
    self.message = normalizedMessage
    self.createdAt = createdAt
    self.rating = rating == 0 ? nil : rating
    self.depth = max(0, depth)
    self.author = author
  }
}

public protocol CommentsRepository {
  func comments(for mediaID: Int) async throws -> [Comment]
}
