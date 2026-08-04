import Foundation

/// Transport-only failures. Metadata intentionally excludes request bodies and credentials.
public enum APIClientError: Error {
  case urlError
  case invalidUrlParams
  case invalidRequest(String)
  case networkError(Error)
  case transport(Error)
  case httpError(statusCode: Int, retryAfter: TimeInterval?)
  case backendError(BackendError)
  case decodingError(Error)
  case cancelled
}

extension APIClientError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .urlError: return "The server URL is invalid."
    case .invalidUrlParams, .invalidRequest: return "The request contains invalid URL parameters."
    case .cancelled: return "The request was cancelled."
    case .networkError(let error), .transport(let error):
      guard let backendError = error as? BackendError else {
        return "A network error occurred: \(error.localizedDescription)"
      }
      return APIClientError.backendError(backendError).errorDescription
    case .backendError(let backendError):
      if let description = backendError.errorDescription, !description.isEmpty { return description }
      switch backendError.errorCode {
      case .authorizationPending: return "Device authorization is still pending."
      case .slowDown: return "The server asked the app to check less frequently."
      case .expiredToken: return "The device activation code expired."
      case .accessDenied: return "Device activation was denied."
      case .invalidClient: return "The app is not recognized by the KinoPub server."
      case .unauthorized: return "The KinoPub session is not authorized."
      default: return "KinoPub server error: \(backendError.errorCode.rawValue)"
      }
    case .httpError(let statusCode, let retryAfter):
      if statusCode == 429 {
        if let retryAfter { return "Too many requests. Try again in \(Int(retryAfter.rounded(.up))) seconds." }
        return "Too many requests. Please try again shortly."
      }
      return "The KinoPub server returned HTTP \(statusCode)."
    case .decodingError(let error):
      return "The KinoPub server returned an unexpected response: \(error.localizedDescription)"
    }
  }
}
