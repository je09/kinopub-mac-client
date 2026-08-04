//
//  BookmarksRequest.swift
//
//
//  Created by Kirill Kunst on 6.08.2023.
//

import Foundation

public struct BookmarksRequest: Endpoint {


  public init() {}

  public var path: String {
    "/v1/bookmarks"
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
