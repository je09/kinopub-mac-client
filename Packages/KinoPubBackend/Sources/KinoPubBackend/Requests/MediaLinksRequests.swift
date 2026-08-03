import Foundation

/// Fetches files (including their stable raw `file` paths) for a movie video or series episode.
public struct MediaLinksRequest: Endpoint {
  private let mediaID: Int

  public init(mediaID: Int) { self.mediaID = mediaID }

  public var path: String { "/v1/items/media-links" }
  public var method: String { "GET" }
  public var parameters: [String: Any]? { ["mid": mediaID] }
  public var headers: [String: String]? { nil }
  public var forceSendAsGetParams: Bool { true }
}

/// Mints a fresh signed playback URL instead of reusing a URL embedded in stale item metadata.
public struct MediaVideoLinkRequest: Endpoint {
  private let file: String
  private let type: String

  public init(file: String, type: String) {
    self.file = file
    self.type = type
  }

  public var path: String { "/v1/items/media-video-link" }
  public var method: String { "GET" }
  public var parameters: [String: Any]? { ["file": file, "type": type] }
  public var headers: [String: String]? { nil }
  public var forceSendAsGetParams: Bool { true }
}
