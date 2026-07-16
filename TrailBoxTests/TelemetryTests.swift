import XCTest
@testable import TrailBox

final class TelemetryTests: XCTestCase {
    @MainActor
    private func eventually(
        timeout: TimeInterval = 5,
        condition: () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        } while Date() < deadline
        return await condition()
    }

    func testNoConsentMeansNoIdentifierOrQueue() async {
        let defaults = makeDefaults()
        let transport = CapturingTelemetryTransport(fails: true)
        let manager = TelemetryManager(defaults: defaults, transport: transport, metadata: .init(appVersion: "test", build: "1", osVersion: "iOS test"))

        await manager.record(.routeOpen, phase: .succeeded, source: .explore)
        let snapshot = await manager.snapshot()
        XCTAssertFalse(snapshot.isEnabled)
        XCTAssertFalse(snapshot.hasInstallationID)
        XCTAssertEqual(snapshot.eventCount, 0)
    }

    func testQueueCapsRetriesAndDisableClearsEverything() async {
        let defaults = makeDefaults()
        let transport = CapturingTelemetryTransport(fails: true)
        let manager = TelemetryManager(defaults: defaults, transport: transport, metadata: .init(appVersion: "test", build: "1", osVersion: "iOS test"))
        await manager.activate()

        for _ in 0..<505 {
            await manager.record(.routeOpen, phase: .succeeded, source: .explore)
        }
        var snapshot = await manager.snapshot()
        XCTAssertTrue(snapshot.hasInstallationID)
        XCTAssertEqual(snapshot.eventCount, 500)

        await transport.setFails(false)
        await manager.flush()
        snapshot = await manager.snapshot()
        XCTAssertEqual(snapshot.eventCount, 0)
        let sent = await transport.eventBatches.reduce(0) { $0 + $1.events.count }
        XCTAssertEqual(sent, 500)

        await manager.deactivate()
        snapshot = await manager.snapshot()
        XCTAssertFalse(snapshot.isEnabled)
        XCTAssertFalse(snapshot.hasInstallationID)
        XCTAssertEqual(snapshot.reportCount, 0)
    }

    func testQueueExpiresOldItemsAndCapsReports() async {
        let defaults = makeDefaults()
        let transport = CapturingTelemetryTransport(fails: true)
        let manager = TelemetryManager(defaults: defaults, transport: transport, metadata: .init(appVersion: "test", build: "1", osVersion: "iOS test"))
        await manager.activate()

        await manager.record(
            .routeOpen,
            phase: .succeeded,
            source: .explore,
            occurredAt: Date().addingTimeInterval(-8 * 24 * 60 * 60)
        )
        await manager.enqueue(report: TelemetryReportRecord(
            reportType: .metric,
            occurredAt: Date().addingTimeInterval(-8 * 24 * 60 * 60),
            payload: .object([:])
        ))
        var snapshot = await manager.snapshot()
        XCTAssertEqual(snapshot.eventCount, 0)
        XCTAssertEqual(snapshot.reportCount, 0)

        for _ in 0..<25 {
            await manager.enqueue(report: TelemetryReportRecord(reportType: .diagnostic, payload: .object([:])))
        }
        snapshot = await manager.snapshot()
        XCTAssertEqual(snapshot.reportCount, 20)
    }

    func testEncodedPayloadHasOnlyWhitelistedFields() throws {
        let metadata = TelemetryRuntimeMetadata(appVersion: "0.1.7", build: "9", osVersion: "iOS 26.5")
        let event = TelemetryEventRecord(
            name: .apiFailure,
            phase: .failed,
            source: .routeDetail,
            failureCategory: .http5xx,
            httpStatusGroup: .serverError
        )
        let batch = TelemetryEventBatch(
            installationID: UUID().uuidString,
            sessionID: UUID().uuidString,
            metadata: metadata,
            events: [event]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(batch)) as? [String: Any])
        let eventObject = try XCTUnwrap((object["events"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(eventObject.keys), ["id", "name", "phase", "source", "occurred_at", "failure_category", "http_status_group"])
        let text = String(data: try encoder.encode(batch), encoding: .utf8)!
        for forbidden in ["username", "token", "authorization", "track_id", "latitude", "longitude", "route_name", "query"] {
            XCTAssertFalse(text.lowercased().contains(forbidden))
        }

        let report = TelemetryReportUpload(
            installationID: UUID().uuidString,
            sessionID: UUID().uuidString,
            metadata: metadata,
            report: TelemetryReportRecord(reportType: .diagnostic, crashCount: 1, payload: .object(["kind": .string("crash")]))
        )
        let reportObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(report)) as? [String: Any])
        XCTAssertEqual(reportObject["report_type"] as? String, "diagnostic")
        XCTAssertNotNil(reportObject["payload"])
        XCTAssertEqual(reportObject["crash_count"] as? Int, 1)
    }

    @MainActor
    func testConsentControllerCreatesAndClearsIdentity() async throws {
        let defaults = makeDefaults()
        let transport = CapturingTelemetryTransport(fails: true)
        let manager = TelemetryManager(defaults: defaults, transport: transport, metadata: .init(appVersion: "test", build: "1", osVersion: "iOS test"))
        let controller = TelemetryConsentController(defaults: defaults, manager: manager)
        XCTAssertEqual(controller.state, .unknown)
        var snapshot = await manager.snapshot()
        XCTAssertFalse(snapshot.hasInstallationID)

        controller.setConsent(.enabled)
        let activated = await eventually {
            (await manager.snapshot()).hasInstallationID
        }
        XCTAssertTrue(activated)
        snapshot = await manager.snapshot()
        XCTAssertTrue(snapshot.hasInstallationID)

        controller.setEnabled(false)
        let deactivated = await eventually {
            !(await manager.snapshot()).hasInstallationID
        }
        XCTAssertTrue(deactivated)
        snapshot = await manager.snapshot()
        XCTAssertFalse(snapshot.hasInstallationID)
        XCTAssertEqual(controller.state, .disabled)
    }

    @MainActor
    func testInjectedMetricKitReporterTransportsDiagnostic() async throws {
        let defaults = makeDefaults()
        let transport = CapturingTelemetryTransport(fails: false)
        let manager = TelemetryManager(defaults: defaults, transport: transport, metadata: .init(appVersion: "test", build: "1", osVersion: "iOS test"))
        let reporter = FakeMetricKitReporter()
        let controller = TelemetryConsentController(
            defaults: defaults,
            manager: manager,
            reporterFactory: { capture in
                reporter.capture = capture
                return reporter
            }
        )

        controller.setConsent(.enabled)
        let reporterStarted = await eventually { reporter.isStarted }
        XCTAssertTrue(reporterStarted)
        reporter.emit(MetricKitCapturedReport(
            type: .diagnostic,
            data: Data("{\"diagnostics\":[]}".utf8),
            crashCount: 1,
            hangCount: 2,
            cpuExceptionCount: 3,
            diskWriteExceptionCount: 4
        ))
        let reportTransported = await eventually {
            await transport.reports.count == 1
        }
        XCTAssertTrue(reportTransported)

        let reports = await transport.reports
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.report.crashCount, 1)
        XCTAssertEqual(reports.first?.report.hangCount, 2)

        controller.setEnabled(false)
        XCTAssertFalse(reporter.isStarted)
    }
}
