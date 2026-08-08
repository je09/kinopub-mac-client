import Foundation
import KinoPubBackend
import KinoPubDomain

public struct CommentsRepositoryAdapter: CommentsRepository {
  private let client: any HTTPClient

  public init(client: any HTTPClient) {
    self.client = client
  }

  public func comments(for mediaID: Int) async throws -> [KinoPubDomain.Comment] {
    guard mediaID > 0 else { return [] }
    let response = try await client.performRequest(
      with: CommentsRequest(id: mediaID),
      decodingType: CommentsData.self,
      forceRefresh: false
    )
    return response.comments.compactMap(CommentMapper.map)
  }
}

enum CommentMapper {
  static func map(_ dto: KinoPubBackend.Comment) -> KinoPubDomain.Comment? {
    guard dto.deleted != true,
          let author = UserSummary(
            id: dto.user.id,
            name: dto.user.name,
            avatarURL: validatedURL(dto.user.avatar)
          )
    else { return nil }

    return KinoPubDomain.Comment(
      id: dto.id,
      message: dto.message,
      createdAt: Date(timeIntervalSince1970: TimeInterval(dto.created)),
      rating: dto.rating.flatMap(Int.init),
      depth: dto.depth ?? 0,
      author: author
    )
  }

  private static func validatedURL(_ value: String?) -> URL? {
    guard let value, !value.isEmpty,
          let url = URL(string: value),
          let scheme = url.scheme?.lowercased(),
          scheme == "https" || scheme == "http"
    else { return nil }
    return url
  }
}
