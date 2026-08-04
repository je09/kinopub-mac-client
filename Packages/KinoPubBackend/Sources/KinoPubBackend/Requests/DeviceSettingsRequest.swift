//
//  DeviceSettingsRequest.swift
//
//
//  Created by Kirill Kunst on 25.06.2026.
//

import Foundation

public struct DeviceSettingsRequest: Endpoint {

  public var id: Int

  public init(id: Int) {
    self.id = id
  }

  public var path: String {
    "/v1/device/\(id)/settings"
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
