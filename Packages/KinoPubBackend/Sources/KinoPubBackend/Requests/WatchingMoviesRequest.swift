//
//  WatchingMoviesRequest.swift
//

import Foundation

/// Unwatched / in-progress movies (and concerts/documentaries) — `GET /v1/watching/movies`.
/// Response: `{status, items:[{id,type,subtype,title,posters}]}` (slim, decodes into `WatchingSerial`).
public struct WatchingMoviesRequest: Endpoint {

  public init() {}

  public var path: String { "/v1/watching/movies" }
  public var method: HTTPMethod { .get }
  public var parameters: HTTPParameters? { nil }
  public var headers: [String: String]? { nil }
  public var forceSendAsGetParams: Bool { false }
}
