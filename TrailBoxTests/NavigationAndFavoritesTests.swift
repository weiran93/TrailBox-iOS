import XCTest
@testable import TrailBox

final class NavigationAndFavoritesTests: XCTestCase {
    @MainActor
    func testDeepLinkAcceptsOnlyRoutePaths() {
        let router = DeepLinkRouter()
        router.handle(URL(string: "https://runfast.fun/r/route-123?utm_source=test")!)
        XCTAssertEqual(router.pendingRoute?.id, "route-123")

        let invalid = DeepLinkRouter()
        invalid.handle(URL(string: "https://runfast.fun/tracks/route-123")!)
        XCTAssertNil(invalid.pendingRoute)
    }

    @MainActor
    func testFavoriteFailureRollsBackOptimisticState() async {
        var shouldFail = false
        MockURLProtocol.handler = { request in
            if request.httpMethod == "DELETE" && shouldFail {
                return MockURLProtocol.response(status: 500, data: Data("{\"detail\":\"failed\"}".utf8), url: request.url!)
            }
            return MockURLProtocol.response(status: 200, data: testBoxJSON(includesTrack: request.httpMethod != "DELETE"), url: request.url!)
        }
        let client = APIClient(session: MockURLProtocol.session(), baseURL: { URL(string: "https://test.invalid")! }, telemetry: nil)
        let telemetry = TelemetryManager(defaults: makeDefaults(), transport: CapturingTelemetryTransport(fails: true), metadata: .init(appVersion: "test", build: "1", osVersion: "test"))
        let store = SavedRoutesStore(apiClient: client, telemetryManager: telemetry)

        await store.load(token: "token")
        XCTAssertTrue(store.isSaved("test-route"))
        shouldFail = true
        await store.toggle(trackID: "test-route", token: "token")
        XCTAssertTrue(store.isSaved("test-route"))
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNil(store.feedback)
    }

    @MainActor
    func testFavoriteSuccessUpdatesState() async {
        var saved = false
        MockURLProtocol.handler = { request in
            if request.httpMethod == "PUT" { saved = true }
            return MockURLProtocol.response(status: 200, data: testBoxJSON(includesTrack: saved), url: request.url!)
        }
        let client = APIClient(session: MockURLProtocol.session(), baseURL: { URL(string: "https://test.invalid")! }, telemetry: nil)
        let telemetry = TelemetryManager(defaults: makeDefaults(), transport: CapturingTelemetryTransport(fails: true), metadata: .init(appVersion: "test", build: "1", osVersion: "test"))
        let store = SavedRoutesStore(apiClient: client, telemetryManager: telemetry)

        await store.load(token: "token")
        XCTAssertFalse(store.isSaved("test-route"))
        await store.toggle(trackID: "test-route", token: "token")
        XCTAssertTrue(store.isSaved("test-route"))
        XCTAssertEqual(store.feedback?.kind, .saved)
        XCTAssertNil(store.errorMessage)
    }
}
