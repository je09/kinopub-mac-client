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

private struct Probe: Endpoint {
  let path = "/probe"
  let method: HTTPMethod = .get
  let headers: [String: String]? = nil
  let parameters: HTTPParameters? = nil
}
