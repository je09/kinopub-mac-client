//
//  ListDevicesRequest.swift
//

import Foundation

/// All devices on the account — `GET /v1/device` → `{devices:[…]}`.
public struct ListDevicesRequest: Endpoint {
  public init() {}
  public var path: String { "/v1/device" }
  public var method: HTTPMethod { .get }
  public var parameters: HTTPParameters? { nil }
  public var headers: [String: String]? { nil }
  public var forceSendAsGetParams: Bool { false }
}
