import Foundation

public protocol APIClientPlugin {
  func prepare(_ request: URLRequest) -> URLRequest
  /// Receives a redacted request. Plugins must not be an escape hatch for credentials.
  func willSend(_ request: URLRequest)
  /// Receives a redacted body.
  func didReceive(_ response: URLResponse, data: Data?)
}

extension URLRequest {
  func redactedForLogging() -> URLRequest {
    var result = self
    let sensitiveHeaders = ["authorization", "cookie", "x-api-key"]
    result.allHTTPHeaderFields?.forEach { key, _ in
      if sensitiveHeaders.contains(key.lowercased()) { result.setValue("<redacted>", forHTTPHeaderField: key) }
    }
    if let url = result.url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
      components.queryItems = components.queryItems?.map {
        URLQueryItem(name: $0.name, value: Self.isSensitive($0.name) ? "<redacted>" : $0.value)
      }
      result.url = components.url
    }
    result.httpBody = result.httpBody?.redactedForLogging()
    return result
  }

  private static func isSensitive(_ name: String) -> Bool {
    ["access_token", "token", "client_secret", "code", "password", "refresh_token"].contains(name.lowercased())
  }
}

extension Data {
  func redactedForLogging() -> Data {
    guard var text = String(data: self, encoding: .utf8) else { return Data("<binary response redacted>".utf8) }
    let names = "access_token|refresh_token|client_secret|token|password|code"
    // Cover form bodies and simple JSON fields without trying to log arbitrary response payloads.
    text = text.replacingOccurrences(of: "(?i)(\(names)=)[^&\\s]*", with: "$1<redacted>", options: .regularExpression)
    text = text.replacingOccurrences(of: "(?i)(\"\(names)\"\\s*:\\s*\")[^\"]*(\")", with: "$1<redacted>$2", options: .regularExpression)
    return Data(text.utf8)
  }
}
