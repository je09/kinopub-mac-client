import XCTest
@testable import KinoPubBackend

final class TransportHardeningTests: XCTestCase {
  func testInvalidBaseURLFailsRequestRatherThanCrashing() async {
    let client = APIClient(baseUrl: "not a URL", session: URLSessionMock())
    do {
      let _: EmptyResponse = try await client.performRequest(with: Probe(), decodingType: EmptyResponse.self)
      XCTFail("Expected invalid request")
    } catch APIClientError.invalidRequest {
      // expected
    } catch {
      XCTFail("Expected invalidRequest, got \(error)")
    }
  }

  func testEligible401RefreshesOnceAndReplaysRequest() async throws {
    let session = StatusSession(statuses: [401, 200])
    let refresher = CountingRefresher()
    let client = APIClient(baseUrl: "https://example.com", session: session, credentialRefresher: refresher)

    let response: Value = try await client.performRequest(with: Probe(), decodingType: Value.self)

    let requestCount = await session.requestCount
    let refreshCount = await refresher.count
    XCTAssertEqual(response.value, 1)
    XCTAssertEqual(requestCount, 2)
    XCTAssertEqual(refreshCount, 1)
  }

  func testConcurrent401sCollapseRefreshAndResumeEveryWaiter() async throws {
    let callerCount = 8
    let session = StatusSession(statuses: Array(repeating: 401, count: callerCount)
      + Array(repeating: 200, count: callerCount))
    let refresher = SuspendedRefresher()
    let client = APIClient(baseUrl: "https://example.com", session: session, credentialRefresher: refresher)

    let requests = Task {
      try await withThrowingTaskGroup(of: Int.self) { group in
        for _ in 0..<callerCount {
          group.addTask {
            let response: Value = try await client.performRequest(with: Probe(), decodingType: Value.self)
            return response.value
          }
        }
        return try await group.reduce(into: []) { $0.append($1) }
      }
    }

    while await session.requestCount < callerCount { await Task.yield() }
    while await refresher.count == 0 { await Task.yield() }
    await refresher.resume()

    let values = try await requests.value
    let refreshCount = await refresher.count
    let requestCount = await session.requestCount
    XCTAssertEqual(values, Array(repeating: 1, count: callerCount))
    XCTAssertEqual(refreshCount, 1)
    XCTAssertEqual(requestCount, callerCount * 2)
  }

  func testCacheIsPartitionedByAuthenticatedAccount() async throws {
    let session = StatusSession(statuses: [200, 200])
    let cache = MemoryResponseCache()
    let partition = MutableCachePartition("account-a")
    let client = APIClient(
      baseUrl: "https://example.com",
      session: session,
      cache: cache,
      cachePartitionProvider: partition)

    let first: Value = try await client.performRequest(with: CacheProbe(), decodingType: Value.self)
    partition.value = "account-b"
    let second: Value = try await client.performRequest(with: CacheProbe(), decodingType: Value.self)

    let requestCount = await session.requestCount
    XCTAssertEqual(first.value, second.value)
    XCTAssertEqual(requestCount, 2)
    XCTAssertEqual(cache.keys.count, 2)
  }

  func testCurlOutputRedactsHeadersQueryAndFormSecrets() {
    var request = URLRequest(url: URL(string: "https://example.com/token?access_token=query-secret")!)
    request.httpMethod = "POST"
    request.setValue("Bearer header-secret", forHTTPHeaderField: "Authorization")
    request.httpBody = Data("client_secret=body-secret&name=Mac".utf8)

    let curl = request.cURL()
    XCTAssertFalse(curl.contains("query-secret"))
    XCTAssertFalse(curl.contains("header-secret"))
    XCTAssertFalse(curl.contains("body-secret"))
    XCTAssertTrue(curl.contains("<redacted>"))
  }
}

private struct EmptyResponse: Decodable {}
private struct Value: Decodable { let value: Int }

private actor StatusSession: URLSessionProtocol {
  private var statuses: [Int]
  private(set) var requestCount = 0

  init(statuses: [Int]) { self.statuses = statuses }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    requestCount += 1
    let status = statuses.removeFirst()
    return (Data("{\"value\":1}".utf8), HTTPURLResponse(url: request.url!, statusCode: status,
                                                              httpVersion: nil, headerFields: nil)!)
  }
}

private actor CountingRefresher: CredentialRefreshing {
  private(set) var count = 0
  func refreshCredentials() async throws { count += 1 }
}

private actor SuspendedRefresher: CredentialRefreshing {
  private(set) var count = 0
  private var continuation: CheckedContinuation<Void, Never>?

  func refreshCredentials() async throws {
    count += 1
    await withCheckedContinuation { continuation = $0 }
  }

  func resume() {
    continuation?.resume()
    continuation = nil
  }
}

private final class MutableCachePartition: CachePartitionProviding, @unchecked Sendable {
  private let lock = NSLock()
  private var storedValue: String

  init(_ value: String) { self.storedValue = value }

  var value: String {
    get { lock.withLock { storedValue } }
    set { lock.withLock { storedValue = newValue } }
  }

  var cachePartition: String { value }
}

private final class MemoryResponseCache: ResponseCaching {
  private var values: [String: Data] = [:]
  var keys: [String] { Array(values.keys) }
  func data(for key: String) -> Data? { values[key] }
  func store(_ data: Data, for key: String, ttl: TimeInterval, persist: Bool) { values[key] = data }
  func remove(for key: String) { values[key] = nil }
  func clear() { values.removeAll() }
}

private struct CacheProbe: Endpoint, CacheableRequest {
  let path = "/cache"
  let method: HTTPMethod = .get
  let headers: [String: String]? = nil
  let parameters: HTTPParameters? = nil
  let cachePolicy: CachePolicy = .memory(ttl: 60)
}

private struct Probe: Endpoint {
  let path = "/probe"
  let method: HTTPMethod = .get
  let headers: [String: String]? = nil
  let parameters: HTTPParameters? = nil
}
