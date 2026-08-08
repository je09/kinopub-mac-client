//
//  Subtitle.swift
//
//
//  Created by Kirill Kunst on 21.07.2023.
//

import Foundation

public struct Subtitle: Codable, Hashable {
  public let lang: String
  public let shift: Int
  public let embed: Bool
  public let url: String
  /// Whether this is a "forced" subtitle track (only foreign-language lines). Present in the live
  /// response but previously dropped. Optional so older/short responses still decode.
  public let forced: Bool?
  /// Server-side file path (alongside the playable `url`).
  public let file: String?

  private enum CodingKeys: String, CodingKey { case lang, shift, embed, url, forced, file }

  public init(lang: String, shift: Int, embed: Bool, url: String, forced: Bool? = nil, file: String? = nil) {
    self.lang = lang
    self.shift = shift
    self.embed = embed
    self.url = url
    self.forced = forced
    self.file = file
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    lang = try container.decodeIfPresent(String.self, forKey: .lang) ?? ""
    shift = try container.decodeIfPresent(Int.self, forKey: .shift) ?? 0
    embed = try container.decodeIfPresent(Bool.self, forKey: .embed) ?? false
    url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
    forced = try container.decodeIfPresent(Bool.self, forKey: .forced)
    file = try container.decodeIfPresent(String.self, forKey: .file)
  }
}
