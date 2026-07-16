import XCTest
@testable import TrailBox

final class APIClientTests: XCTestCase {
    private struct DatedResponse: Decodable { let createdAt: Date; enum CodingKeys: String, CodingKey { case createdAt = "created_at" } }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testCompatibleDateFormatsDecode() async throws {
        for value in [
            "2026-07-16T08:00:00Z",
            "2026-07-16T08:00:00.123456Z",
            "2026-07-16T08:00:00.123456",
            "2026-07-16 08:00:00",
        ] {
            MockURLProtocol.handler = { request in
                MockURLProtocol.response(status: 200, data: Data("{\"created_at\":\"\(value)\"}".utf8), url: request.url!)
            }
            let client = APIClient(session: MockURLProtocol.session(), baseURL: { URL(string: "https://test.invalid")! }, telemetry: nil)
            let response: DatedResponse = try await client.request("/date")
            XCTAssertGreaterThan(response.createdAt.timeIntervalSince1970, 0)
        }
    }

    func testHTTPAndDecodeFailuresAreClassifiedWithoutPathData() async throws {
        let receiver = CapturingAPIEventReceiver()
        let client = APIClient(
            session: MockURLProtocol.session(),
            baseURL: { URL(string: "https://test.invalid")! },
            telemetry: receiver
        )

        MockURLProtocol.handler = { request in
            MockURLProtocol.response(status: 401, data: Data("{\"detail\":\"expired\"}".utf8), url: request.url!)
        }
        do {
            let _: DatedResponse = try await client.request("/tracks/secret-track-id")
            XCTFail("Expected unauthorized")
        } catch APIError.unauthorized {}

        MockURLProtocol.handler = { request in
            MockURLProtocol.response(status: 404, data: Data("{\"detail\":\"missing\"}".utf8), url: request.url!)
        }
        do {
            let _: DatedResponse = try await client.request("/tracks/private-missing-id")
            XCTFail("Expected client failure")
        } catch APIError.server {}

        MockURLProtocol.handler = { request in
            MockURLProtocol.response(status: 500, data: Data("{\"detail\":\"boom\"}".utf8), url: request.url!)
        }
        do {
            let _: DatedResponse = try await client.request("/tracks/another-secret-id")
            XCTFail("Expected server failure")
        } catch APIError.server {}

        MockURLProtocol.handler = { request in
            MockURLProtocol.response(status: 200, data: Data("<html>spa fallback</html>".utf8), url: request.url!)
        }
        do {
            let _: DatedResponse = try await client.request("/tracks/private-id/public")
            XCTFail("Expected decoding failure")
        } catch APIError.server {}

        try await Task.sleep(nanoseconds: 80_000_000)
        let items = await receiver.items
        XCTAssertTrue(items.contains(.init(source: .routeDetail, category: .unauthorized, statusGroup: .clientError)))
        XCTAssertTrue(items.contains(.init(source: .routeDetail, category: .http4xx, statusGroup: .clientError)))
        XCTAssertTrue(items.contains(.init(source: .routeDetail, category: .http5xx, statusGroup: .serverError)))
        XCTAssertTrue(items.contains(.init(source: .routeDetail, category: .decoding, statusGroup: nil)))
        XCTAssertFalse(String(describing: items).contains("secret-track-id"))
    }

    func testOfflineAndTimeoutAreClassified() async throws {
        let receiver = CapturingAPIEventReceiver()
        let client = APIClient(session: MockURLProtocol.session(), baseURL: { URL(string: "https://test.invalid")! }, telemetry: receiver)

        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            let _: DatedResponse = try await client.request("/tracks/public")
            XCTFail("Expected offline failure")
        } catch {}

        MockURLProtocol.handler = { _ in throw URLError(.timedOut) }
        do {
            let _: DatedResponse = try await client.request("/tracks/public")
            XCTFail("Expected timeout")
        } catch {}

        try await Task.sleep(nanoseconds: 80_000_000)
        let categories = await receiver.items.map(\.category)
        XCTAssertTrue(categories.contains(.networkOffline))
        XCTAssertTrue(categories.contains(.timeout))
    }

    func testEndpointClassifierNeverReturnsRawIdentifiers() {
        let paths = [
            "/tracks/8d70ae6c-raw-user-data/public?query=private",
            "/boxes/want-to-run/tracks/secret-track-id",
            "/integrations/itra/profile/123456",
        ]
        let sources = paths.map { TelemetryEndpointClassifier.source(for: $0).rawValue }
        XCTAssertEqual(sources, ["route_detail", "saved_routes", "itra"])
        XCTAssertFalse(sources.joined().contains("secret"))
        XCTAssertFalse(sources.joined().contains("123456"))
    }
}
