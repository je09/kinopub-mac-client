import Foundation

/// Supported HTTP verbs. Keeping this closed prevents request construction from relying on string
/// comparisons and makes replay policy explicit.
public enum HTTPMethod: String, Sendable {
  case get = "GET"
  case post = "POST"
  case put = "PUT"
  case patch = "PATCH"
  case delete = "DELETE"

  public var isSafe: Bool { self == .get }
}

/// A value that can be encoded deterministically in a URL query or form body.
///
/// Deliberately do not conform arbitrary values: callers must choose a wire representation before
/// reaching the transport layer.
public protocol HTTPParameterValue: Sendable {
  var encodedValue: String { get }
}

extension String: HTTPParameterValue { public var encodedValue: String { self } }
extension Int: HTTPParameterValue { public var encodedValue: String { String(self) } }
extension Int64: HTTPParameterValue { public var encodedValue: String { String(self) } }
extension Double: HTTPParameterValue { public var encodedValue: String { String(self) } }
extension Bool: HTTPParameterValue { public var encodedValue: String { self ? "true" : "false" } }

public typealias HTTPParameters = [String: any HTTPParameterValue]

/// Immutable, fully typed transport request produced from an endpoint.
public struct HTTPRequest: Sendable {
  public let path: String
  public let method: HTTPMethod
  public let headers: [String: String]
  public let parameters: HTTPParameters
  public let sendsParametersInQuery: Bool
  public let allowsAuthenticationReplay: Bool

  public init(path: String,
              method: HTTPMethod,
              headers: [String: String] = [:],
              parameters: HTTPParameters = [:],
              sendsParametersInQuery: Bool = false,
              allowsAuthenticationReplay: Bool? = nil) {
    self.path = path
    self.method = method
    self.headers = headers
    self.parameters = parameters
    self.sendsParametersInQuery = sendsParametersInQuery
    self.allowsAuthenticationReplay = allowsAuthenticationReplay ?? method.isSafe
  }
}

/// Compatibility endpoint surface retained so existing application services do not change.
public protocol Endpoint {
  var path: String { get }
  var method: HTTPMethod { get }
  var headers: [String: String]? { get }
  var parameters: HTTPParameters? { get }
  var forceSendAsGetParams: Bool { get }
  /// Unsafe mutations opt in only after the backend confirms replay is idempotent.
  var allowsAuthenticationReplay: Bool { get }
}

public extension Endpoint {
  var forceSendAsGetParams: Bool { false }
  var allowsAuthenticationReplay: Bool { method.isSafe }

  var httpRequest: HTTPRequest {
    HTTPRequest(path: path,
                method: method,
                headers: headers ?? [:],
                parameters: parameters ?? [:],
                sendsParametersInQuery: forceSendAsGetParams,
                allowsAuthenticationReplay: allowsAuthenticationReplay)
  }
}
