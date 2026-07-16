#if DEBUG
import Foundation

enum TrailBoxUITestSupport {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TrailBoxUITestURLProtocol.self]
        return URLSession(configuration: configuration)
    }()
}

struct TrailBoxUITestTelemetryTransport: TelemetryTransporting {
    func send(events: TelemetryEventBatch) async throws {}
    func send(report: TelemetryReportUpload) async throws {}
}

final class TrailBoxUITestURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return finish(status: 400, object: ["detail": "invalid url"]) }
        let path = url.path

        if path == "/tracks/public" {
            return finish(object: [Self.route])
        }
        if path == "/tags" {
            return finish(object: [])
        }
        if path == "/tracks/test-route" || path == "/tracks/test-route/public" {
            return finish(object: Self.route)
        }
        if path == "/boxes/want-to-run" {
            if ProcessInfo.processInfo.arguments.contains("-trailboxUITestExpiredSession") {
                return finish(status: 401, object: ["detail": "expired"])
            }
            if request.httpMethod == "PUT" {
                return finish(object: Self.box(tracks: [Self.route]))
            }
            return finish(object: Self.box(tracks: []))
        }
        if path.hasPrefix("/boxes/want-to-run/tracks/") {
            return finish(object: request.httpMethod == "DELETE" ? Self.box(tracks: []) : Self.box(tracks: [Self.route]))
        }
        if path == "/telemetry/events" || path == "/telemetry/reports" {
            return finish(status: 202, object: ["accepted": 1, "duplicates": 0])
        }
        return finish(status: 404, object: ["detail": "fixture not available"])
    }

    override func stopLoading() {}

    private func finish(status: Int = 200, object: Any) {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
              ) else { return }
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func box(tracks: [[String: Any]]) -> [String: Any] {
        [
            "id": "ui-test-box",
            "name": "收藏路线",
            "description": NSNull(),
            "is_public": false,
            "created_at": "2026-07-16T08:00:00Z",
            "tracks": tracks,
        ]
    }

    private static let route: [String: Any] = [
        "id": "test-route",
        "user_id": 999,
        "name": "北京西山测试环线",
        "description": "用于验证探索、收藏与一键出发的固定路线。",
        "city": "北京",
        "tags": "越野跑,环线",
        "distance_m": 12300.0,
        "elevation_gain_m": 680.0,
        "elevation_loss_m": 680.0,
        "duration_sec": 7200.0,
        "start_time": "2026-07-16T08:00:00Z",
        "sport": "越野跑",
        "track_kind": "route_contribution",
        "is_public": true,
        "show_contributor": true,
        "recommendation_reason": "视野开阔",
        "contributor_name": "测试跑者",
        "contributor_public_id": "999999",
        "created_at": "2026-07-16T08:00:00Z",
        "points": [
            ["lat": 39.99, "lon": 116.10, "altitude": 120.0, "distance": 0.0],
            ["lat": 40.00, "lon": 116.11, "altitude": 260.0, "distance": 6000.0],
            ["lat": 39.99, "lon": 116.10, "altitude": 120.0, "distance": 12300.0],
        ],
    ]
}
#endif
