//
//  DeviceAuthorizationCoordinator.swift
//  KinoPubAppleClient
//
//  Device-activation state machine. Owns the poll generation (exactly one polling task at a time),
//  the expiry/retry/slow-down ladder, and the injected clock/sleeper. UI state lives in `AuthModel`,
//  which maps coordinator events to published values — the coordinator never touches AppKit/SwiftUI.
//

import Foundation
import KinoPubBackend
import KinoPubLogging
import OSLog

/// Deterministic clock/sleeper for authorization polling (injected in tests).
struct AuthorizationPollingClock {
  var now: () -> Date
  var sleep: (_ seconds: TimeInterval) async throws -> Void

  static let continuous = AuthorizationPollingClock(
    now: Date.init,
    sleep: { try await Task.sleep(for: .seconds($0)) }
  )
}

/// Event sink installed by the owning UI store after the actor is constructed (avoids capturing an
/// uninitialized owner in the initializer). `@unchecked Sendable` because it is only ever accessed
/// from the main actor (writer) and the coordinator's poll task (reader via `await`).
final class DeviceAuthorizationEventSink: @unchecked Sendable {
  var handler: (@MainActor (DeviceAuthorizationCoordinator.Event) -> Void)?
}

/// Owns the device-authorization workflow: requesting a code, polling until the user approves on
/// the website, reacting to slow-down/expiry, and authorizing the session. An actor so the poll
/// generation and its mutable interval/expiry are race-free; events are delivered on the main
/// actor to whoever owns the UI projection.
actor DeviceAuthorizationCoordinator {

  /// Explicit phases of the activation workflow (mirrors the plan's Phase 5 states).
  enum State: Equatable {
    case idle
    case requestingCode
    case awaitingApproval
    case slowingDown
    case authorized
    case expired(restarting: Bool)
    case failed
  }

  enum Event {
    case stateChanged(State)
    case codeReceived(VerificationResponse)
    case authorized
    case failed(Error)
  }

  private(set) var state: State = .idle

  private let authService: AuthorizationService
  private let pollingClock: AuthorizationPollingClock
  private let eventSink = DeviceAuthorizationEventSink()
  private var pollingTask: Task<Void, Never>?

  init(
    authService: AuthorizationService,
    pollingClock: AuthorizationPollingClock
  ) {
    self.authService = authService
    self.pollingClock = pollingClock
  }

  /// Installs the UI-side event handler (must be called right after construction).
  nonisolated func setEventHandler(_ handler: @escaping @MainActor (Event) -> Void) {
    eventSink.handler = handler
  }

  /// Requests a fresh device code and starts (or restarts) the poll generation. Cancels any
  /// previous poll so only one generation ever exists.
  func requestCode() async {
    pollingTask?.cancel()
    await setState(.requestingCode)
    do {
      let response = try await authService.fetchDeviceCode()
      await setState(.awaitingApproval)
      await emit(.codeReceived(response))
      startPolling(for: response)
    } catch {
      Logger.app.debug("failed to fetch device code: \(error)")
      await setState(.failed)
      await emit(.failed(error))
    }
  }

  /// Cancels the current poll generation. Called on feature/session teardown so a dismissed
  /// activation sheet never keeps polling or replacing expired codes.
  func cancel() {
    pollingTask?.cancel()
    pollingTask = nil
  }

  private func emit(_ event: Event) async {
    await eventSink.handler?(event)
  }

  private func setState(_ newState: State) async {
    state = newState
    await emit(.stateChanged(newState))
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
          await setState(.expired(restarting: true))
          await requestCode()
          return
        }

        do {
          try await pollingClock.sleep(TimeInterval(interval))
          try Task.checkCancellation()
          Logger.app.debug("request token...")
          try await authService.fetchToken(by: response)
          await setState(.authorized)
          await emit(.authorized)
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
            await setState(.slowingDown)
            Logger.app.debug("authorization poll slowed to \(interval) seconds")
            continue
          }
          if error.isActivationCodeExpired {
            Logger.app.debug("server expired device code; requesting a replacement")
            await setState(.expired(restarting: true))
            await requestCode()
            return
          }
          if error.isRetryableTransportError {
            Logger.app.debug("transient authorization polling error: \(error)")
            continue
          }

          await setState(.failed)
          await emit(.failed(error))
          return
        } catch {
          await setState(.failed)
          await emit(.failed(error))
          return
        }
      }
    }
  }
}
