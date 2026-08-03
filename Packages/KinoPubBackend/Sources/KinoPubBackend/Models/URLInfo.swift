//
//  URLInfo.swift
//
//
//  Created by Kirill Kunst on 21.07.2023.
//

import Foundation

public struct URLInfo: Codable, Hashable {
  public let http: String
  public let hls: String
  public let hls4: String
  public let hls2: String

  public init(http: String, hls: String, hls4: String, hls2: String) {
    self.http = http
    self.hls = hls
    self.hls4 = hls4
    self.hls2 = hls2
  }

  private enum CodingKeys: String, CodingKey { case http, hls, hls4, hls2 }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    http = try container.decodeIfPresent(String.self, forKey: .http) ?? ""
    hls = try container.decodeIfPresent(String.self, forKey: .hls) ?? ""
    hls4 = try container.decodeIfPresent(String.self, forKey: .hls4) ?? ""
    hls2 = try container.decodeIfPresent(String.self, forKey: .hls2) ?? ""
  }
}
