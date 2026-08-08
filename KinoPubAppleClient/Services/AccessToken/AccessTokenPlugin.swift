//
//  AccessTokenPlugin.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 27.07.2023.
//

import Foundation
import KinoPubBackend

extension AccessToken: Token {}

struct AccessTokenPlugin: APIClientPlugin {
  
  private let accessTokenService: AccessTokenService
  
  init(accessTokenService: AccessTokenService) {
    self.accessTokenService = accessTokenService
  }
  
  func prepare(_ request: URLRequest) -> URLRequest {
    var request = request
    
    if let token: AccessToken = accessTokenService.token() {
      let authValue = "Bearer " + token.accessToken
      request.addValue(authValue, forHTTPHeaderField: "Authorization")
    }
    
    return request
  }
  
  func willSend(_ request: URLRequest) {
    
  }
  
  func didReceive(_ response: URLResponse, data: Data?) {
    
  }
}

/// Uses a dedicated unauthenticated client so refreshing cannot recursively trigger another refresh.
actor AccessTokenCredentialRefresher: CredentialRefreshing {
  enum RefreshError: Error {
    case missingRefreshToken
  }

  private let apiClient: APIClient
  private let clientID: String
  private let clientSecret: String
  private let accessTokenService: AccessTokenService
  private var inFlight: Task<Void, Error>?

  init(baseURL: String, configuration: Configuration, accessTokenService: AccessTokenService) {
    self.apiClient = APIClient(baseUrl: baseURL)
    self.clientID = configuration.clientID
    self.clientSecret = configuration.clientSecret
    self.accessTokenService = accessTokenService
  }

  func refreshCredentials() async throws {
    if let inFlight {
      return try await inFlight.value
    }

    let apiClient = apiClient
    let clientID = clientID
    let clientSecret = clientSecret
    let accessTokenService = accessTokenService
    let task = Task {
      guard let token: AccessToken = accessTokenService.token() else {
        throw RefreshError.missingRefreshToken
      }
      let request = RefreshTokenRequest(
        clientID: clientID,
        clientSecret: clientSecret,
        refreshToken: token.refreshToken)
      let replacement = try await apiClient.performRequest(with: request, decodingType: AccessToken.self)
      accessTokenService.set(token: replacement)
    }
    inFlight = task
    defer { inFlight = nil }
    try await task.value
  }
}

/// The token hash avoids putting credentials in cache keys while partitioning cached responses.
struct AccessTokenCachePartitionProvider: CachePartitionProviding, @unchecked Sendable {
  let accessTokenService: AccessTokenService

  var cachePartition: String {
    guard let token: AccessToken = accessTokenService.token() else { return "anonymous" }
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in token.refreshToken.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x100000001b3
    }
    return String(format: "%016llx", hash)
  }
}
