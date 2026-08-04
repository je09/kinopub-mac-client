import XCTest
import KinoPubBackend
@testable import KinoPub

@MainActor
final class AuthModelPollingTests: XCTestCase {
  func testPollingAuthorizesAfterConfiguredInterval() async throws {
    let service = AuthorizationServiceSpy(
      codes: [try fixture("device-code")],
      tokenResults: [.success(())]
    )
    let clock = AdvancingPollingClock()
    let harness = makeHarness(service: service, clock: clock.clock)
    
    harness.model.fetchDeviceCode()
    
    await eventually { harness.authState.userState == .authorized }
    XCTAssertEqual(clock.sleeps, [5])
    XCTAssertFalse(harness.authState.shouldShowAuthentication)
    XCTAssertFalse(harness.errorHandler.state.showError)
  }
  
  func testAuthorizationPendingKeepsPollingAtSameInterval() async throws {
    let service = AuthorizationServiceSpy(
      codes: [try fixture("device-code-short-interval")],
      tokenResults: [
        .failure(try apiError("authorization-pending")),
        .success(())
      ]
    )
    let clock = AdvancingPollingClock()
    let harness = makeHarness(service: service, clock: clock.clock)
    
    harness.model.fetchDeviceCode()
    
    await eventually { harness.authState.userState == .authorized }
    XCTAssertEqual(clock.sleeps, [2, 2])
    XCTAssertEqual(service.tokenCallCount, 2)
  }
  
  func testSlowDownAddsFiveSecondsToSubsequentPolls() async throws {
    let service = AuthorizationServiceSpy(
      codes: [try fixture("device-code-three-second-interval")],
      tokenResults: [
        .failure(try apiError("slow-down")),
        .success(())
      ]
    )
    let clock = AdvancingPollingClock()
    let harness = makeHarness(service: service, clock: clock.clock)
    
    harness.model.fetchDeviceCode()
    
    await eventually { harness.authState.userState == .authorized }
    XCTAssertEqual(clock.sleeps, [3, 8])
  }
  
  func testTransientTransportFailureRetriesWithoutPresentingError() async throws {
    let service = AuthorizationServiceSpy(
      codes: [try fixture("device-code-one-second-interval")],
      tokenResults: [
        .failure(APIClientError.networkError(URLError(.timedOut))),
        .success(())
      ]
    )
    let clock = AdvancingPollingClock()
    let harness = makeHarness(service: service, clock: clock.clock)
    
    harness.model.fetchDeviceCode()
    
    await eventually { harness.authState.userState == .authorized }
    XCTAssertEqual(clock.sleeps, [1, 1])
    XCTAssertFalse(harness.errorHandler.state.showError)
  }
  
  func testTerminalAuthorizationFailureStopsAndPresentsError() async throws {
    let service = AuthorizationServiceSpy(
      codes: [try fixture("device-code")],
      tokenResults: [.failure(try apiError("access-denied"))]
    )
    let clock = AdvancingPollingClock()
    let harness = makeHarness(service: service, clock: clock.clock)
    
    harness.model.fetchDeviceCode()
    
    await eventually { harness.errorHandler.state.showError }
    XCTAssertEqual(service.tokenCallCount, 1)
    XCTAssertEqual(clock.sleeps, [5])
    XCTAssertEqual(harness.authState.userState, .unauthorized)
  }
  
  func testServerExpiryRequestsReplacementCode() async throws {
    let service = AuthorizationServiceSpy(
      codes: [try fixture("device-code"), try fixture("replacement-device-code")],
      tokenResults: [
        .failure(try apiError("expired-token")),
        .success(())
      ]
    )
    let clock = AdvancingPollingClock()
    let harness = makeHarness(service: service, clock: clock.clock)
    
    harness.model.fetchDeviceCode()
    
    await eventually { harness.authState.userState == .authorized }
    XCTAssertEqual(service.deviceCodeCallCount, 2)
    XCTAssertEqual(harness.model.deviceCode, "WXYZ-9876")
  }
  
  func testRequestingAnotherCodeCancelsPreviousSleep() async throws {
    let service = AuthorizationServiceSpy(
      codes: [try fixture("device-code"), try fixture("replacement-device-code")],
      tokenResults: []
    )
    let clock = CancellablePollingClock()
    let harness = makeHarness(service: service, clock: clock.clock)
    
    harness.model.fetchDeviceCode()
    await eventually { harness.model.deviceCode == "ABCD-1234" && clock.startedSleepCount == 1 }
    
    harness.model.fetchDeviceCode()
    
    await eventually { harness.model.deviceCode == "WXYZ-9876" && clock.cancelledSleepCount >= 1 }
    XCTAssertEqual(service.tokenCallCount, 0)
  }
  
  private func makeHarness(service: AuthorizationServiceSpy,
                           clock: AuthorizationPollingClock) -> Harness {
    let authState = AuthState(
      authService: service,
      accessTokenService: AccessTokenServiceStub(),
      deviceService: DeviceServiceMock()
    )
    let errorHandler = ErrorHandler()
    let model = AuthModel(
      authService: service,
      authState: authState,
      errorHandler: errorHandler,
      pollingClock: clock
    )
    return Harness(model: model, authState: authState, errorHandler: errorHandler)
  }
  
  private func eventually(
    iterations: Int = 1_000,
    _ condition: @escaping @MainActor () -> Bool
  ) async {
    for _ in 0..<iterations {
      if condition() { return }
      await Task.yield()
    }
    XCTFail("Condition was not satisfied")
  }
  
  private func fixture(_ name: String) throws -> VerificationResponse {
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
    )
    return try JSONDecoder().decode(VerificationResponse.self, from: Data(contentsOf: url))
  }
  
  private func apiError(_ name: String) throws -> APIClientError {
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
    )
    let backend = try JSONDecoder().decode(BackendError.self, from: Data(contentsOf: url))
    return .networkError(backend)
  }
}

@MainActor
private struct Harness {
  let model: AuthModel
  let authState: AuthState
  let errorHandler: ErrorHandler
}

private final class AuthorizationServiceSpy: AuthorizationService, @unchecked Sendable {
  private let lock = NSLock()
  private var codes: [VerificationResponse]
  private var tokenResults: [Result<Void, Error>]
  private(set) var deviceCodeCallCount = 0
  private(set) var tokenCallCount = 0
  
  init(codes: [VerificationResponse], tokenResults: [Result<Void, Error>]) {
    self.codes = codes
    self.tokenResults = tokenResults
  }
  
  func fetchDeviceCode() async throws -> VerificationResponse {
    try lock.withLock {
      deviceCodeCallCount += 1
      guard !codes.isEmpty else { throw TestFailure.unexpectedCall }
      return codes.removeFirst()
    }
  }
  
  func fetchToken(by verification: VerificationResponse) async throws {
    let result: Result<Void, Error> = lock.withLock {
      tokenCallCount += 1
      return tokenResults.isEmpty ? .failure(TestFailure.unexpectedCall) : tokenResults.removeFirst()
    }
    try result.get()
  }
  
  func refreshToken() async throws {}
  func logout() {}
}

private final class AdvancingPollingClock: @unchecked Sendable {
  private let lock = NSLock()
  private var date = Date(timeIntervalSince1970: 1_700_000_000)
  private var recordedSleeps: [TimeInterval] = []
  
  var sleeps: [Int] { lock.withLock { recordedSleeps.map(Int.init) } }
  
  var clock: AuthorizationPollingClock {
    AuthorizationPollingClock(
      now: { [self] in lock.withLock { date } },
      sleep: { [self] seconds in
        try Task.checkCancellation()
        lock.withLock {
          recordedSleeps.append(seconds)
          date = date.addingTimeInterval(seconds)
        }
        await Task.yield()
      }
    )
  }
}

private final class CancellablePollingClock: @unchecked Sendable {
  private let lock = NSLock()
  private var started = 0
  private var cancelled = 0
  
  var startedSleepCount: Int { lock.withLock { started } }
  var cancelledSleepCount: Int { lock.withLock { cancelled } }
  
  var clock: AuthorizationPollingClock {
    AuthorizationPollingClock(
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      sleep: { [self] _ in
        lock.withLock { started += 1 }
        do {
          try await Task.sleep(for: .seconds(3_600))
        } catch {
          lock.withLock { cancelled += 1 }
          throw error
        }
      }
    )
  }
}

private struct AccessTokenServiceStub: AccessTokenService {
  func set<T: Token>(token: T) {}
  func token<T: Token>() -> T? { nil }
  func clear() {}
}

private enum TestFailure: Error {
  case unexpectedCall
}
