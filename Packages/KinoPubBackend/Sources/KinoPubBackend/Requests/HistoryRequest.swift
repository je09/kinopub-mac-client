//
//  HistoryRequest.swift
//
//
//  Created by Kirill Kunst on 24.06.2026.
//

import Foundation

public struct HistoryRequest: Endpoint {

  private var page: Int?
  private var perpage: Int?

  public init(page: Int? = nil, perpage: Int? = nil) {
    self.page = page
    self.perpage = perpage
  }

  public var path: String {
    "/v1/history"
  }

  public var method: HTTPMethod {
    .get
  }

  public var parameters: HTTPParameters? {
    var params = HTTPParameters()

    if let page = page {
      params["page"] = "\(page)"
    }

    if let perpage = perpage {
      params["perpage"] = "\(perpage)"
    }

    return params
  }

  public var headers: [String: String]? {
    nil
  }

  public var forceSendAsGetParams: Bool { false }
}
