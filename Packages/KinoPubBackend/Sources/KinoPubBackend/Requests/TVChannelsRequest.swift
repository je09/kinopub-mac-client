//
//  TVChannelsRequest.swift
//
//
//  GET /v1/tv — currently broadcasting (sport) live channels.
//

import Foundation

public struct TVChannelsRequest: Endpoint {

  public init() {}

  public var path: String {
    "/v1/tv"
  }

  public var method: HTTPMethod {
    .get
  }

  public var parameters: HTTPParameters? {
    nil
  }

  public var headers: [String: String]? {
    nil
  }

  public var forceSendAsGetParams: Bool { false }
}
