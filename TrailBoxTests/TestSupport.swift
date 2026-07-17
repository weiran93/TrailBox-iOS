import Foundation
@testable import TrailBox

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func response(status: Int, data: Data, url: URL = URL(string: "https://test.invalid/value")!) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
    }
}

actor CapturingAPIEventReceiver: APIEventReceiving {
    struct Item: Equatable {
        let source: TelemetrySource
        let category: TelemetryFailureCategory
        let statusGroup: TelemetryHTTPStatusGroup?
    }

    private(set) var items: [Item] = []

    func recordAPIFailure(
        source: TelemetrySource,
        category: TelemetryFailureCategory,
        statusGroup: TelemetryHTTPStatusGroup?
    ) async {
        items.append(Item(source: source, category: category, statusGroup: statusGroup))
    }
}

actor CapturingTelemetryTransport: TelemetryTransporting {
    enum Failure: Error { case offline }

    private(set) var eventBatches: [TelemetryEventBatch] = []
    private(set) var reports: [TelemetryReportUpload] = []
    private var fails: Bool

    init(fails: Bool) { self.fails = fails }

    func setFails(_ value: Bool) { fails = value }

    func send(events: TelemetryEventBatch) async throws {
        if fails { throw Failure.offline }
        eventBatches.append(events)
    }

    func send(report: TelemetryReportUpload) async throws {
        if fails { throw Failure.offline }
        reports.append(report)
    }
}

final class FakeMetricKitReporter: MetricKitReporting {
    private(set) var isStarted = false
    var capture: ((MetricKitCapturedReport) -> Void)?

    func start() { isStarted = true }
    func stop() { isStarted = false }
    func emit(_ report: MetricKitCapturedReport) { capture?(report) }
}

func makeDefaults() -> UserDefaults {
    let name = "TrailBoxTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

let testTrackJSON = """
{
  "id":"test-route","user_id":1,"name":"测试路线","description":null,"city":"北京","tags":"越野跑",
  "distance_m":10000,"elevation_gain_m":500,"elevation_loss_m":500,"duration_sec":3600,
  "start_time":"2026-07-16T08:00:00Z","sport":"越野跑","track_kind":"route_contribution",
  "is_public":true,"show_contributor":true,"recommendation_reason":null,"contributor_name":"测试者",
  "contributor_public_id":"100001","created_at":"2026-07-16T08:00:00Z",
  "points":[{"lat":40,"lon":116,"altitude":100,"distance":0},{"lat":40.01,"lon":116.01,"altitude":200,"distance":10000}]
}
"""

func testBoxJSON(includesTrack: Bool) -> Data {
    let tracks = includesTrack ? "[\(testTrackJSON)]" : "[]"
    return Data("""
    {"id":"box","name":"收藏路线","description":null,"is_public":false,"created_at":"2026-07-16T08:00:00Z","tracks":\(tracks)}
    """.utf8)
}
