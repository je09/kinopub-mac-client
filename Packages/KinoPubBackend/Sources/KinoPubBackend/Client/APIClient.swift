//
//  APIClient.swift
//
//
//  Created by Kirill Kunst on 21.07.2023.
//

import Foundation

/// Time is injectable so rate-limit and cancellation behavior can be tested without real sleeps.
public protocol APIClientClock: Sendable {
  func now() -> Date
  func sleep(for interval: TimeInterval) async throws
}

public struct SystemAPIClientClock: APIClientClock {
  public init() {}

  public func now() -> Date { Date() }

  public func sleep(for interval: TimeInterval) async throws {
    try await Task.sleep(for: .seconds(interval))
  }
}

/// Spaces request starts across the whole API client and turns a server 429 into a shared cooldown.
/// A serial gate is intentional: limiting only task concurrency still permits short request bursts.
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
      let now = clock.now()
      let delay = nextStart.timeIntervalSince(now)
      if delay <= 0 {
        nextStart = now.addingTimeInterval(minimumInterval)
        return
      }
      // Re-check after sleeping: another caller may have taken the slot, or a 429 may have moved
      // `nextStart` farther out while this task was suspended.
      try await clock.sleep(for: delay)
    }
  }

  func pause(for delay: TimeInterval) {
    nextStart = max(nextStart, clock.now().addingTimeInterval(max(0, delay)))
  }
}

public class APIClient {
  private let session: URLSessionProtocol
  private let requestBuilder: RequestBuilder
  private let baseUrl: URL
  private var plugins: [APIClientPlugin]
  private let cache: ResponseCaching?
  private let requestGate: APIRequestGate

  public init(baseUrl: String,
              plugins: [APIClientPlugin] = [],
              session: URLSessionProtocol = URLSessionImpl(session: .shared),
              cache: ResponseCaching? = nil,
              minimumRequestInterval: TimeInterval = 0,
              clock: any APIClientClock = SystemAPIClientClock()) {
    self.baseUrl = URL(string: baseUrl)!
    self.plugins = plugins
    self.session = session
    self.cache = cache
    self.requestGate = APIRequestGate(minimumInterval: minimumRequestInterval, clock: clock)
    self.requestBuilder = RequestBuilder(baseURL: self.baseUrl)
  }

  /// - Parameter forceRefresh: when true, skips any cached value and always hits the network
  ///   (the fresh result still updates the cache). Pull-to-refresh paths pass `true`.
  public func performRequest<T: Decodable>(with requestData: Endpoint,
                                           decodingType: T.Type,
                                           forceRefresh: Bool = false) async throws -> T {
    // Serve from cache when the request opts in and we're not force-refreshing.
    let cacheable = requestData as? CacheableRequest
    let policy = cacheable?.cachePolicy ?? .noCache
    if !forceRefresh, let cacheable, policy.ttl != nil,
       let cachedData = cache?.data(for: cacheable.cacheKey),
       let cached = try? JSONDecoder().decode(T.self, from: cachedData) {
      return cached
    }

    guard let request = requestBuilder.build(with: requestData) else {
      throw APIClientError.invalidUrlParams
    }

    let preparedRequest = plugins.reduce(request) { $1.prepare(request) }
    // Notify plugins
    plugins.forEach { $0.willSend(preparedRequest) }

    var attempt = 0
    while true {
      // The gate normally passes immediately. After any caller receives 429, however, it holds all
      // subsequent requests until the shared Retry-After window ends, avoiding a retry storm without
      // artificially serializing normal Home-screen loading.
      try await requestGate.wait()
      let (data, response) = try await session.data(for: preparedRequest)

      // Notify plugins
      plugins.forEach { $0.didReceive(response, data: data) }

      if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        let retryAfter = Self.retryAfter(from: http)
        // A 429 response means the server rejected the request before processing it. Retry only a
        // small bounded number of times and honor Retry-After; never blindly retry other mutations.
        if http.statusCode == 429, attempt < 2 {
          attempt += 1
          let delay = min(max(retryAfter ?? pow(2, Double(attempt - 1)), 1), 60)
          // Cool down every caller sharing this client, not just the request that saw the 429. This
          // prevents the remaining queue from extending a server-side rate-limit window.
          await requestGate.pause(for: delay)
          continue
        }
        if let backendError = try? JSONDecoder().decode(BackendError.self, from: data) {
          throw APIClientError.networkError(backendError)
        }
        throw APIClientError.httpError(statusCode: http.statusCode, retryAfter: retryAfter)
      }

      let result = try decode(T.self, from: data, throwDecodingErrorImmediately: false)
      // Cache only successfully decoded 2xx responses (never error bodies), per the request's policy.
      if let cacheable, let ttl = policy.ttl {
        cache?.store(data, for: cacheable.cacheKey, ttl: ttl, persist: policy.persistsToDisk)
      }
      return result
    }
  }

  /// Drops all cached responses. Call on logout so the next user never sees cached data.
  public func clearCache() {
    cache?.clear()
  }

  private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
    guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
    if let seconds = TimeInterval(value) { return max(0, seconds) }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
    return formatter.date(from: value).map { max(0, $0.timeIntervalSinceNow) }
  }

  private func decode<T: Decodable>(_ type: T.Type,
                                    from data: Data,
                                    throwDecodingErrorImmediately: Bool) throws -> T where T: Decodable {
    do {
      let result = try JSONDecoder().decode(T.self, from: data)
      return result
    } catch {
      if throwDecodingErrorImmediately {
        throw APIClientError.decodingError(error)
      }

      if let backendError = try? JSONDecoder().decode(BackendError.self, from: data) {
        throw APIClientError.networkError(backendError)
      }

      throw APIClientError.decodingError(error)
    }
  }
}
