//
//  AuthModel.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 27.07.2023.
//

import Foundation
import SwiftUI
import KinoPubBackend
import KinoPubLogging
import OSLog

@MainActor
class AuthModel: ObservableObject {

  private var authState: AuthState
  private var errorHandler: ErrorHandler
  private let coordinator: DeviceAuthorizationCoordinator
  private let platformActions: AuthPlatformActions

  @Published var deviceCode: String = ""
  @Published var close: Bool = false
  /// The page the user opens to enter the code (shown as a hint, e.g. "kino.pub/device").
  @Published var verificationURL: String = ""
  /// Explicit workflow phase, driven by the coordinator (idle → requestingCode → awaitingApproval
  /// → slowingDown/expired → authorized/failed).
  @Published private(set) var phase: DeviceAuthorizationCoordinator.State = .idle

  private var tempVerificationResponse: VerificationResponse?

  init(
    authService: AuthorizationService,
    authState: AuthState,
    errorHandler: ErrorHandler,
    pollingClock: AuthorizationPollingClock = .continuous,
    platformActions: AuthPlatformActions = .live
  ) {
    self.authState = authState
    self.errorHandler = errorHandler
    self.platformActions = platformActions
    let coordinator = DeviceAuthorizationCoordinator(
      authService: authService,
      pollingClock: pollingClock
    )
    self.coordinator = coordinator
    coordinator.setEventHandler { [weak self] event in
      self?.handle(event)
    }
  }

  deinit {
    // Stop the poll generation so a dismissed activation sheet never keeps polling or replacing
    // expired codes. The coordinator is captured strongly by the cancellation task.
    let coordinator = self.coordinator
    Task { await coordinator.cancel() }
  }

  func fetchDeviceCode() {
    Logger.app.debug("Fetch device code...")
    errorHandler.reset()
    Task {
      await coordinator.requestCode()
    }
  }

  /// Cancels polling explicitly (e.g. session teardown while the sheet stays in the hierarchy).
  func cancelPolling() {
    Task {
      await coordinator.cancel()
    }
  }

  func copyCode() {
    guard !deviceCode.isEmpty else { return }
    platformActions.copyToClipboard(deviceCode)
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

    platformActions.openURL(url)
  }

  // MARK: - Coordinator events → UI state

  private func handle(_ event: DeviceAuthorizationCoordinator.Event) {
    switch event {
    case .stateChanged(let state):
      phase = state
    case .codeReceived(let response):
      deviceCode = response.userCode
      verificationURL = response.verificationUri
      tempVerificationResponse = response
      Logger.app.debug("receive device code: \(response.userCode)")
    case .authorized:
      authState.userState = .authorized
      authState.shouldShowAuthentication = false
      errorHandler.reset()
    case .failed(let error):
      handleError(error)
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
