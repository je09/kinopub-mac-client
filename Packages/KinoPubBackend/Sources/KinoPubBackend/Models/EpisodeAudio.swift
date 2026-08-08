//
//  EpisodeAudio.swift
//
//
//  Created by Kirill Kunst on 21.07.2023.
//

import Foundation

public struct EpisodeAudio: Codable, Hashable {
  public let id: Int
  public let index: Int
  public let codec: String
  public let channels: Int
  public let lang: String
  public let type: TypeClass?
  public let author: Author?

  public init(
    id: Int,
    index: Int,
    codec: String,
    channels: Int,
    lang: String,
    type: TypeClass? = nil,
    author: Author? = nil
  ) {
    self.id = id
    self.index = index
    self.codec = codec
    self.channels = channels
    self.lang = lang
    self.type = type
    self.author = author
  }
}
