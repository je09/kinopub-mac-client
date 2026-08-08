//
//  AuthorizationServiceImpl.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 26.07.2023.
//

import Foundation
import KinoPubBackend

final class AuthorizationServiceImpl: AuthorizationService {
  
  private let apiClient: APIClient
  private let configuration: Configuration
  private let accessTokenService: AccessTokenService
  private let credentialRefresher: any CredentialRefreshing
  
  init(apiClient: APIClient,
       configuration: Configuration,
       accessTokenService: AccessTokenService,
       credentialRefresher: any CredentialRefreshing) {
    self.apiClient = apiClient
    self.configuration = configuration
    self.accessTokenService = accessTokenService
    self.credentialRefresher = credentialRefresher
  }
  
  func fetchDeviceCode() async throws -> VerificationResponse {
    let request = DeviceCodeRequest(
      grantType: .deviceCode, clientID: configuration.clientID, clientSecret: configuration.clientSecret)
    return try await apiClient.performRequest(with: request, decodingType: VerificationResponse.self)
  }
  
  func fetchToken(by verification: VerificationResponse) async throws {
    let request = DeviceCodeRequest(
      grantType: .deviceToken, clientID: configuration.clientID, clientSecret: configuration.clientSecret,
      code: verification.code)
    let token = try await apiClient.performRequest(with: request, decodingType: AccessToken.self)
    accessTokenService.set(token: token)
  }
  
  func refreshToken() async throws {
    guard let _: AccessToken = accessTokenService.token() else { return }
    try await credentialRefresher.refreshCredentials()
  }
  
  func logout() {
    accessTokenService.clear()
    // Drop cached API responses so the next account never sees the previous user's data.
    apiClient.clearCache()
  }
  
}
