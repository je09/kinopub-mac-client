//
//  DeviceInfoRequest.swift
//
//
//  Created by Kirill Kunst on 25.06.2026.
//

import Foundation

public struct DeviceInfoRequest: Endpoint {

  public init() {}

  public var path: String {
    "/v1/device/info"
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
