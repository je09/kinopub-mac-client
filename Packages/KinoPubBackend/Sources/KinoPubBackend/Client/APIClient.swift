import Foundation

public protocol APIClientClock: Sendable {
  func now() -> Date
  func sleep(for interval: TimeInterval) async throws
}

public struct SystemAPIClientClock: APIClientClock {
  public init() {}
  public func now() -> Date { Date() }
  public func sleep(for interval: TimeInterval) async throws { try await Task.sleep(for: .seconds(interval)) }
}

public protocol APIClientRandomSource: Sendable {
  func nextUnitInterval() -> Double
}

public struct SystemAPIClientRandomSource: APIClientRandomSource {
  public init() {}
  public func nextUnitInterval() -> Double { Double.random(in: 0...1) }
}

/// Supplies a stable, non-secret partition for authenticated response-cache entries.
public protocol CachePartitionProviding: Sendable {
  var cachePartition: String { get }
}

/// A narrow seam for services. Existing services can continue accepting `APIClient` until they are
/// migrated to this protocol.
public protocol HTTPClient {
  func performRequest<T: Decodable>(with requestData: Endpoint,
                                    decodingType: T.Type,
                                    forceRefresh: Bool) async throws -> T
  func clearCache()
}

/// Refreshes credentials once after an eligible 401. Implementations must persist the replacement
/// credential before returning.
public protocol CredentialRefreshing: Sendable {
  func refreshCredentials() async throws
}

private actor CredentialRefreshCoordinator {
  private let refresher: any CredentialRefreshing
  private var inFlight: Task<Void, Error>?

  init(refresher: any CredentialRefreshing) { self.refresher = refresher }

  func refresh() async throws {
    if let inFlight { return try await inFlight.value }
    let task = Task { try await refresher.refreshCredentials() }
    inFlight = task
    defer { inFlight = nil }
    try await task.value
  }
}

private actor APIRequestGate {
  private let minimumInterval: TimeInterval
  private let clock: any APIClientClock
  private var nextStart = Date.distantPast

  init(minimumInterval: TimeInterval, clock: any APIClientClock) {
    self.minimumInterval = max(0, minimumInterval)
    self.clock = clock
  }

  func wait() async throws {
    while true {
      try Task.checkCancellation()
      let now = clock.now()
      let delay = nextStart.timeIntervalSince(now)
      if delay <= 0 {
        nextStart = now.addingTimeInterval(minimumInterval)
        return
      }
      try await clock.sleep(for: delay)
    }
  }

  func pause(for delay: TimeInterval) {
    nextStart = max(nextStart, clock.now().addingTimeInterval(max(0, delay)))
  }
}

public final class APIClient: HTTPClient {
  private let session: URLSessionProtocol
  private let requestBuilder: RequestBuilder?
  private let plugins: [APIClientPlugin]
  private let cache: ResponseCaching?
  private let requestGate: APIRequestGate
  private let decoder: JSONDecoder
  private let clock: any APIClientClock
  private let randomSource: any APIClientRandomSource
  private let cachePartitionProvider: (any CachePartitionProviding)?
  private let credentialRefresh: CredentialRefreshCoordinator?

  /// Invalid URLs are retained as an initialization state so legacy synchronous construction stays
  /// source-compatible. The first request throws `invalidRequest` instead of crashing.
  public init(baseUrl: String,
              plugins: [APIClientPlugin] = [],
              session: URLSessionProtocol = URLSessionImpl(session: .shared),
              cache: ResponseCaching? = nil,
              minimumRequestInterval: TimeInterval = 0,
              clock: any APIClientClock = SystemAPIClientClock(),
              randomSource: any APIClientRandomSource = SystemAPIClientRandomSource(),
              decoder: JSONDecoder = JSONDecoder(),
              credentialRefresher: (any CredentialRefreshing)? = nil,
              cachePartitionProvider: (any CachePartitionProviding)? = nil) {
    self.plugins = plugins
    self.session = session
    self.cache = cache
    self.decoder = decoder
    self.clock = clock
    self.randomSource = randomSource
    self.cachePartitionProvider = cachePartitionProvider
    self.requestGate = APIRequestGate(minimumInterval: minimumRequestInterval, clock: clock)
    self.credentialRefresh = credentialRefresher.map(CredentialRefreshCoordinator.init)
    if let url = URL(string: baseUrl) { self.requestBuilder = try? RequestBuilder(validating: url) } else { self.requestBuilder = nil }
  }

  public func performRequest<T: Decodable>(with requestData: Endpoint,
                                           decodingType: T.Type,
                                           forceRefresh: Bool = false) async throws -> T {
    let cacheable = requestData as? CacheableRequest
    let policy = cacheable?.cachePolicy ?? .noCache
    let cacheKey = cacheable.map { partitionedCacheKey($0.cacheKey) }
    if !forceRefresh, let cacheKey, policy.ttl != nil,
       let data = cache?.data(for: cacheKey), let cached = try? decoder.decode(T.self, from: data) {
      return cached
    }
    guard let requestBuilder else { throw APIClientError.invalidRequest("The base URL is invalid.") }
    let request = try requestBuilder.buildThrowing(with: requestData)
    var prepared = plugins.reduce(request) { $1.prepare($0) }
    plugins.forEach { $0.willSend(prepared.redactedForLogging()) }

    var rateLimitAttempt = 0
    var didRefresh = false
    while true {
      do {
        try Task.checkCancellation()
        try await requestGate.wait()
        let (data, response) = try await session.data(for: prepared)
        plugins.forEach { $0.didReceive(response, data: data.redactedForLogging()) }
        // URLSession always supplies HTTPURLResponse in production. Retain compatibility with
        // existing custom test transports that return a plain URLResponse.
        guard let http = response as? HTTPURLResponse else {
          let responseCacheKey = cacheable.map { partitionedCacheKey($0.cacheKey) }
          return try decodeResponse(T.self, from: data, cacheKey: responseCacheKey, policy: policy)
        }

        if !(200..<300).contains(http.statusCode) {
          let retryAfter = Self.retryAfter(from: http, now: clock.now())
          if http.statusCode == 401, !didRefresh, requestData.allowsAuthenticationReplay,
             let credentialRefresh {
            didRefresh = true
            try await credentialRefresh.refresh()
            // Re-run auth plugins so the replay uses the freshly persisted credential.
            prepared = plugins.reduce(request) { $1.prepare($0) }
            plugins.forEach { $0.willSend(prepared.redactedForLogging()) }
            continue
          }
          if http.statusCode == 429, rateLimitAttempt < 2 {
            rateLimitAttempt += 1
            let delay = retryAfter ?? jitteredBackoff(forAttempt: rateLimitAttempt)
            await requestGate.pause(for: min(max(delay, 1), 60))
            continue
          }
          if let backendError = try? decoder.decode(BackendError.self, from: data) { throw APIClientError.networkError(backendError) }
          throw APIClientError.httpError(statusCode: http.statusCode, retryAfter: retryAfter)
        }

        // Credentials may have rotated during a 401 replay; partition the stored response with the
        // current credential rather than the one used for the initial cache lookup.
        let responseCacheKey = cacheable.map { partitionedCacheKey($0.cacheKey) }
        return try decodeResponse(T.self, from: data, cacheKey: responseCacheKey, policy: policy)
      } catch is CancellationError {
        throw CancellationError()
      } catch let error as APIClientError {
        throw error
      } catch {
        throw APIClientError.transport(error)
      }
    }
  }

  public func clearCache() { cache?.clear() }

  private func decodeResponse<T: Decodable>(_ type: T.Type,
                                            from data: Data,
                                            cacheKey: String?,
                                            policy: CachePolicy) throws -> T {
    do {
      let result = try decoder.decode(T.self, from: data)
      if let cacheKey, let ttl = policy.ttl {
        cache?.store(data, for: cacheKey, ttl: ttl, persist: policy.persistsToDisk)
      }
      return result
    } catch {
      if let backendError = try? decoder.decode(BackendError.self, from: data) {
        throw APIClientError.networkError(backendError)
      }
      throw APIClientError.decodingError(error)
    }
  }

  private func partitionedCacheKey(_ key: String) -> String {
    "account=\(cachePartitionProvider?.cachePartition ?? "anonymous") \(key)"
  }

  /// Full jitter prevents clients released from the same outage from retrying in lockstep.
  private func jitteredBackoff(forAttempt attempt: Int) -> TimeInterval {
    let ceiling = pow(2, Double(max(0, attempt - 1)))
    return min(max(randomSource.nextUnitInterval(), 0), 1) * ceiling
  }

  private static func retryAfter(from response: HTTPURLResponse, now: Date) -> TimeInterval? {
    guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
    if let seconds = TimeInterval(value) { return max(0, seconds) }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
    return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
  }
}
