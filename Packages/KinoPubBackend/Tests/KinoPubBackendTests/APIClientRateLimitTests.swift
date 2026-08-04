import Foundation
import XCTest
@testable import KinoPubBackend

final class APIClientRateLimitTests: XCTestCase {
  func test429HonorsRetryAfterWithoutRealSleep() async throws {
    let session = ScriptedURLSession(steps: [
      .response(status: 429, headers: ["Retry-After": "7"]),
      .response(status: 200, headers: [:])
    ])
    let clock = AdvancingAPIClock()
    let client = APIClient(
      baseUrl: "https://api.example.com",
      session: session,
      clock: clock
    )

    let response: VerificationResponse = try await client.performRequest(
      with: RequestData(path: "/token", method: .get),
      decodingType: VerificationResponse.self
    )

    XCTAssertEqual(response.userCode, "ABCD-1234")
    XCTAssertEqual(session.requestCount, 2)
    XCTAssertEqual(clock.sleeps, [7])
  }

  func testCancellationDuringRateLimitCooldownStopsRetry() async {
    let session = ScriptedURLSession(steps: [
      .response(status: 429, headers: ["Retry-After": "30"]),
      .response(status: 200, headers: [:])
    ])
    let clock = CancellingAPIClock()
    let client = APIClient(
      baseUrl: "https://api.example.com",
      session: session,
      clock: clock
    )

    do {
      let _: VerificationResponse = try await client.performRequest(
        with: RequestData(path: "/token", method: .get),
        decodingType: VerificationResponse.self
      )
      XCTFail("Expected cancellation")
    } catch is CancellationError {
      XCTAssertEqual(session.requestCount, 1)
      XCTAssertEqual(clock.sleepCount, 1)
    } catch {
      XCTFail("Expected CancellationError, got \(error)")
    }
  }
}

private final class AdvancingAPIClock: APIClientClock, @unchecked Sendable {
  private let lock = NSLock()
  private var date = Date(timeIntervalSince1970: 1_700_000_000)
  private var intervals: [TimeInterval] = []

  var sleeps: [Int] { lock.withLock { intervals.map(Int.init) } }
  func now() -> Date { lock.withLock { date } }

  func sleep(for interval: TimeInterval) async throws {
    try Task.checkCancellation()
    lock.withLock {
      intervals.append(interval)
      date = date.addingTimeInterval(interval)
    }
  }
}

private final class CancellingAPIClock: APIClientClock, @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var sleepCount: Int { lock.withLock { count } }
  func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) }

  func sleep(for interval: TimeInterval) async throws {
    lock.withLock { count += 1 }
    throw CancellationError()
  }
}

private final class ScriptedURLSession: URLSessionProtocol, @unchecked Sendable {
  enum Step {
    case response(status: Int, headers: [String: String])
  }

  private let lock = NSLock()
  private var steps: [Step]
  private var count = 0

  var requestCount: Int { lock.withLock { count } }

  init(steps: [Step]) {
    self.steps = steps
  }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    let step: Step = try lock.withLock {
      count += 1
      guard !steps.isEmpty else { throw ScriptError.unexpectedRequest }
      return steps.removeFirst()
    }
    switch step {
    case .response(let status, let headers):
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: nil,
        headerFields: headers
      )!
      return (Self.successPayload, response)
    }
  }

  private static let successPayload = Data("""
    {
      "code": "test-code",
      "user_code": "ABCD-1234",
      "verification_uri": "https://example.invalid/device",
      "expires_in": 600,
      "interval": 5
    }
    """.utf8)

  private enum ScriptError: Error {
    case unexpectedRequest
  }
}
