import Foundation

/// Converts typed transport values to URLRequest. The throwing API is used in production; the
/// optional compatibility API preserves existing service and test call sites during this migration.
internal struct RequestBuilder {
  let baseURL: URL

  init(baseURL: URL) { self.baseURL = baseURL }

  init(validating baseURL: URL) throws {
    guard let components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
          let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
          components.host != nil else {
      throw APIClientError.invalidRequest("The base URL must include an HTTP(S) scheme and host.")
    }
    self.baseURL = baseURL
  }

  func build(with endpoint: Endpoint) -> URLRequest? { try? buildThrowing(with: endpoint) }
  func buildThrowing(with endpoint: Endpoint) throws -> URLRequest { try buildThrowing(endpoint.httpRequest) }

  func buildThrowing(_ request: HTTPRequest) throws -> URLRequest {
    guard let url = URL(string: request.path, relativeTo: baseURL) else {
      throw APIClientError.invalidRequest("The endpoint path is invalid.")
    }
    var result = URLRequest(url: url)
    result.httpMethod = request.method.rawValue
    request.headers.forEach { result.setValue($0.value, forHTTPHeaderField: $0.key) }
    guard !request.parameters.isEmpty else { return result }
    if request.method == .get || request.sendsParametersInQuery {
      return try appendingQuery(to: result, parameters: request.parameters)
    }
    result.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    result.httpBody = formURLEncodedBody(from: request.parameters)
    return result
  }

  private func appendingQuery(to request: URLRequest, parameters: HTTPParameters) throws -> URLRequest {
    var result = request
    guard var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: true) else {
      throw APIClientError.invalidRequest("The endpoint URL cannot be represented as components.")
    }
    components.queryItems = (components.queryItems ?? []) + parameters.sorted { $0.key < $1.key }.map {
      URLQueryItem(name: $0.key, value: $0.value.encodedValue)
    }
    guard let url = components.url else { throw APIClientError.invalidRequest("The endpoint query is invalid.") }
    result.url = url
    return result
  }

  private func formURLEncodedBody(from parameters: HTTPParameters) -> Data {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "+&=?")
    let pairs = parameters.sorted { $0.key < $1.key }.map { key, value -> String in
      let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
      let encodedValue = value.encodedValue.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
      return "\(encodedKey)=\(encodedValue)"
    }
    return Data(pairs.joined(separator: "&").utf8)
  }
}
