//
//  FileInfo.swift
//
//
//  Created by Kirill Kunst on 21.07.2023.
//

import Foundation

public struct FileInfo: Codable, Hashable {
  public let codec: String
  public let w: Int
  public let h: Int
  public let quality: String
  public let qualityID: Int
  /// Stable server-side media path used to mint a fresh signed URL via `media-video-link`.
  public let file: String?
  public let url: URLInfo

  private enum CodingKeys: String, CodingKey {
    case codec = "codec"
    case w = "w"
    case h = "h"
    case quality = "quality"
    case qualityID = "quality_id"
    case file
    case url
    case urls
  }

  public init(codec: String,
              w: Int,
              h: Int,
              quality: String,
              qualityID: Int,
              file: String? = nil,
              url: URLInfo) {
    self.codec = codec
    self.w = w
    self.h = h
    self.quality = quality
    self.qualityID = qualityID
    self.file = file
    self.url = url
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    codec = try container.decodeIfPresent(String.self, forKey: .codec) ?? ""
    w = try container.decodeIfPresent(Int.self, forKey: .w) ?? 0
    h = try container.decodeIfPresent(Int.self, forKey: .h) ?? 0
    quality = try container.decodeIfPresent(String.self, forKey: .quality) ?? ""
    qualityID = try container.decodeIfPresent(Int.self, forKey: .qualityID) ?? 0
    file = try container.decodeIfPresent(String.self, forKey: .file)
    url = try container.decodeIfPresent(URLInfo.self, forKey: .url)
      ?? container.decodeIfPresent(URLInfo.self, forKey: .urls)
      ?? URLInfo(http: "", hls: "", hls4: "", hls2: "")
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(codec, forKey: .codec)
    try container.encode(w, forKey: .w)
    try container.encode(h, forKey: .h)
    try container.encode(quality, forKey: .quality)
    try container.encode(qualityID, forKey: .qualityID)
    try container.encodeIfPresent(file, forKey: .file)
    try container.encode(url, forKey: .url)
  }
}

public extension FileInfo {
  var resolution: Int {
    Int(quality.dropLast()) ?? 0
  }
}

public extension Array where Element == FileInfo {
  /// One file per quality label. With the device profile's `mixedPlaylist` on, kino.pub returns both
  /// an HEVC and an h264 file for each resolution (same `quality`), which would otherwise show as
  /// duplicate rows ("2160p", "2160p", …) in quality/download menus. Keeps the first per quality
  /// (HEVC, which kino.pub lists first) and preserves the original order.
  var dedupedByQuality: [FileInfo] {
    var seen = Set<String>()
    return filter { seen.insert($0.quality).inserted }
  }
}

extension FileInfo: Identifiable {
  public var id: Int {
    url.hashValue
  }
}
