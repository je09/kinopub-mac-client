//
//  AuthModel.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 27.07.2023.
//

import AppKit
import Foundation
import SwiftUI
import KinoPubBackend
import KinoPubLogging
import OSLog

struct AuthorizationPollingClock {
  var now: () -> Date
  var sleep: (_ seconds: TimeInterval) async throws -> Void
  
  static let continuous = AuthorizationPollingClock(
    now: Date.init,
    sleep: { try await Task.sleep(for: .seconds($0)) }
  )
}

@MainActor
class AuthModel: ObservableObject {
  
  private var authService: AuthorizationService
  private var authState: AuthState
  private var errorHandler: ErrorHandler
  
  @Published var deviceCode: String = ""
  @Published var close: Bool = false
  /// The page the user opens to enter the code (shown as a hint, e.g. "kino.pub/device").
  @Published var verificationURL: String = ""
  
  private var tempVerificationResponse: VerificationResponse?
  private var pollingTask: Task<Void, Never>?
  private let pollingClock: AuthorizationPollingClock
  
  init(
    authService: AuthorizationService,
    authState: AuthState,
    errorHandler: ErrorHandler,
    pollingClock: AuthorizationPollingClock = .continuous
  ) {
    self.authService = authService
    self.authState = authState
    self.errorHandler = errorHandler
    self.pollingClock = pollingClock
  }
  
  deinit {
    pollingTask?.cancel()
  }
  
  func fetchDeviceCode() {
    Logger.app.debug("Fetch device code...")
    pollingTask?.cancel()
    errorHandler.reset()
    Task {
      do {
        let response = try await authService.fetchDeviceCode()
        self.deviceCode = response.userCode
        self.verificationURL = response.verificationUri
        self.tempVerificationResponse = response
        Logger.app.debug("receive device code: \(response.userCode)")
        startPolling(for: response)
      } catch {
        handleError(error)
      }
    }
  }
  
  func copyCode() {
    guard !deviceCode.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(deviceCode, forType: .string)
  }
  
  /// Human-friendly activation page (host + path, without the scheme), e.g. "kino.pub/device".
  var activationDisplayURL: String {
    guard let url = URL(string: verificationURL), let host = url.host else { return verificationURL }
    let path = url.path
    return path.isEmpty || path == "/" ? host : host + path
  }
  
  func openActivationURL() {
    guard let urlString = tempVerificationResponse?.verificationUri, let url = URL(string: urlString) else {
      return
    }
    
    Logger.app.debug("open activation url: \(url)")
    
    NSWorkspace.shared.open(url)
  }
  
  private func startPolling(for response: VerificationResponse) {
    pollingTask?.cancel()
    pollingTask = Task { [weak self] in
      guard let self else { return }
      
      var interval = max(response.interval, 1)
      let expiresAt = pollingClock.now().addingTimeInterval(TimeInterval(response.expiresIn))
      
      while !Task.isCancelled {
        if pollingClock.now() >= expiresAt {
          Logger.app.debug("device code expired; requesting a replacement")
          fetchDeviceCode()
          return
        }
        
        do {
          try await pollingClock.sleep(TimeInterval(interval))
          try Task.checkCancellation()
          Logger.app.debug("request token...")
          try await authService.fetchToken(by: response)
          authState.userState = .authorized
          authState.shouldShowAuthentication = false
          errorHandler.reset()
          Logger.app.debug("token requested")
          return
        } catch is CancellationError {
          return
        } catch let error as APIClientError {
          if error.isAuthorizationPending {
            continue
          }
          if error.shouldSlowAuthorizationPolling {
            interval += 5
            Logger.app.debug("authorization poll slowed to \(interval) seconds")
            continue
          }
          if error.isActivationCodeExpired {
            Logger.app.debug("server expired device code; requesting a replacement")
            fetchDeviceCode()
            return
          }
          if error.isRetryableTransportError {
            Logger.app.debug("transient authorization polling error: \(error)")
            continue
          }
          
          handleError(error)
          return
        } catch {
          handleError(error)
          return
        }
      }
    }
  }
  
  private func handleError(_ error: Error) {
    Logger.app.debug("got error: \(error)")
    
    guard let error = error as? APIClientError else {
      return
    }
    
    errorHandler.setError(error)
  }
  
}
