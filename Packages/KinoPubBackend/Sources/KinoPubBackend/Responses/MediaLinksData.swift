import Foundation

/// Fresh media-file metadata returned for one movie video or series episode.
/// Unlike most v1 responses, `/items/media-links` has no `status` wrapper.
public struct MediaLinksData: Codable, Hashable {
  public let id: Int?
  public let files: [FileInfo]
  public let subtitles: [Subtitle]?
  public let thumbnail: String?

  public init(id: Int?, files: [FileInfo], subtitles: [Subtitle]?, thumbnail: String?) {
    self.id = id
    self.files = files
    self.subtitles = subtitles
    self.thumbnail = thumbnail
  }
}

/// A newly minted signed URL for one raw media path and streaming type.
public struct MediaVideoLinkData: Codable, Hashable {
  public let url: String

  public init(url: String) { self.url = url }
}
