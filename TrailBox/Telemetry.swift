import Foundation
import MetricKit
import OSLog
import SwiftUI
import UIKit

enum TelemetryConsentState: String, Codable {
    case unknown
    case enabled
    case disabled
}

enum TelemetryEventName: String, Codable, CaseIterable {
    case appSession = "app_session"
    case routeOpen = "route_open"
    case favorite
    case departure
    case navigation
    case gpxExport = "gpx_export"
    case share
    case activityUpload = "activity_upload"
    case routeContribution = "route_contribution"
    case apiFailure = "api_failure"
}

enum TelemetryEventPhase: String, Codable {
    case started
    case succeeded
    case failed
    case cancelled
}

enum TelemetrySource: String, Codable {
    case app
    case explore
    case deepLink = "deep_link"
    case savedRoutes = "saved_routes"
    case activityMatch = "activity_match"
    case activity
    case routeDetail = "route_detail"
    case departureSheet = "departure_sheet"
    case appleMaps = "apple_maps"
    case amap
    case baidu
    case tencent
    case googleMaps = "google_maps"
    case shareSheet = "share_sheet"
    case photoLibrary = "photo_library"
    case contribution
    case authentication
    case profile
    case itra
    case admin
    case moderation
    case api
}

enum TelemetryFailureCategory: String, Codable {
    case networkOffline = "network_offline"
    case timeout
    case connection
    case unauthorized
    case http4xx = "http_4xx"
    case http5xx = "http_5xx"
    case decoding
    case file
    case permission
    case cancelled
    case unknown

    static func classify(_ error: Error) -> TelemetryFailureCategory {
        if error is CancellationError { return .cancelled }
        if case APIError.unauthorized = error { return .unauthorized }
        if case APIError.invalidResponse = error { return .decoding }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorDataNotAllowed,
                 NSURLErrorInternationalRoamingOff:
                return .networkOffline
            case NSURLErrorTimedOut:
                return .timeout
            case NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorDNSLookupFailed:
                return .connection
            case NSURLErrorCancelled:
                return .cancelled
            default:
                return .unknown
            }
        }
        if nsError.domain == NSCocoaErrorDomain, (0..<1024).contains(nsError.code) {
            return .file
        }
        return .unknown
    }
}

enum TelemetryHTTPStatusGroup: String, Codable {
    case clientError = "4xx"
    case serverError = "5xx"
}

private enum TelemetryEventLogger {
    static let telemetry = Logger(subsystem: "com.trailbox.ios", category: "telemetry")
    static let upload = Logger(subsystem: "com.trailbox.ios", category: "upload")
    static let share = Logger(subsystem: "com.trailbox.ios", category: "share")
    static let navigation = Logger(subsystem: "com.trailbox.ios", category: "navigation")

    static func logger(for name: TelemetryEventName) -> Logger {
        switch name {
        case .activityUpload, .routeContribution:
            return upload
        case .share:
            return share
        case .departure, .navigation, .gpxExport:
            return navigation
        default:
            return telemetry
        }
    }
}

struct TelemetryRuntimeMetadata: Codable, Equatable {
    let appVersion: String
    let build: String
    let osVersion: String

    static var current: TelemetryRuntimeMetadata {
        TelemetryRuntimeMetadata(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            osVersion: "iOS \(UIDevice.current.systemVersion)"
        )
    }
}

struct TelemetryEventRecord: Codable, Equatable, Identifiable {
    let id: String
    let name: TelemetryEventName
    let phase: TelemetryEventPhase
    let source: TelemetrySource?
    let occurredAt: Date
    let durationMS: Int?
    let failureCategory: TelemetryFailureCategory?
    let httpStatusGroup: TelemetryHTTPStatusGroup?

    init(
        id: String = UUID().uuidString.lowercased(),
        name: TelemetryEventName,
        phase: TelemetryEventPhase,
        source: TelemetrySource? = nil,
        occurredAt: Date = Date(),
        durationMS: Int? = nil,
        failureCategory: TelemetryFailureCategory? = nil,
        httpStatusGroup: TelemetryHTTPStatusGroup? = nil
    ) {
        self.id = id
        self.name = name
        self.phase = phase
        self.source = source
        self.occurredAt = occurredAt
        self.durationMS = durationMS
        self.failureCategory = failureCategory
        self.httpStatusGroup = httpStatusGroup
    }

    enum CodingKeys: String, CodingKey {
        case id, name, phase, source
        case occurredAt = "occurred_at"
        case durationMS = "duration_ms"
        case failureCategory = "failure_category"
        case httpStatusGroup = "http_status_group"
    }
}

indirect enum TelemetryJSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: TelemetryJSONValue])
    case array([TelemetryJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: TelemetryJSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([TelemetryJSONValue].self) { self = .array(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct TelemetryReportRecord: Codable, Equatable, Identifiable {
    enum ReportType: String, Codable { case metric, diagnostic }

    let id: String
    let reportType: ReportType
    let occurredAt: Date
    let crashCount: Int
    let hangCount: Int
    let cpuExceptionCount: Int
    let diskWriteExceptionCount: Int
    let payload: TelemetryJSONValue

    init(
        id: String = UUID().uuidString.lowercased(),
        reportType: ReportType,
        occurredAt: Date = Date(),
        crashCount: Int = 0,
        hangCount: Int = 0,
        cpuExceptionCount: Int = 0,
        diskWriteExceptionCount: Int = 0,
        payload: TelemetryJSONValue
    ) {
        self.id = id
        self.reportType = reportType
        self.occurredAt = occurredAt
        self.crashCount = crashCount
        self.hangCount = hangCount
        self.cpuExceptionCount = cpuExceptionCount
        self.diskWriteExceptionCount = diskWriteExceptionCount
        self.payload = payload
    }

    enum CodingKeys: String, CodingKey {
        case payload
        case id = "report_id"
        case reportType = "report_type"
        case occurredAt = "occurred_at"
        case crashCount = "crash_count"
        case hangCount = "hang_count"
        case cpuExceptionCount = "cpu_exception_count"
        case diskWriteExceptionCount = "disk_write_exception_count"
    }
}

struct MetricKitCapturedReport {
    let type: TelemetryReportRecord.ReportType
    let data: Data
    let crashCount: Int
    let hangCount: Int
    let cpuExceptionCount: Int
    let diskWriteExceptionCount: Int
}

protocol MetricKitReporting: AnyObject {
    func start()
    func stop()
}

struct TelemetryEventBatch: Encodable {
    let installationID: String
    let sessionID: String
    let metadata: TelemetryRuntimeMetadata
    let events: [TelemetryEventRecord]

    enum CodingKeys: String, CodingKey {
        case events
        case installationID = "installation_id"
        case sessionID = "session_id"
        case appVersion = "app_version"
        case build
        case osVersion = "os_version"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(installationID, forKey: .installationID)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(metadata.appVersion, forKey: .appVersion)
        try container.encode(metadata.build, forKey: .build)
        try container.encode(metadata.osVersion, forKey: .osVersion)
        try container.encode(events, forKey: .events)
    }
}

struct TelemetryReportUpload: Encodable {
    let installationID: String
    let sessionID: String
    let metadata: TelemetryRuntimeMetadata
    let report: TelemetryReportRecord

    func encode(to encoder: Encoder) throws {
        try report.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(installationID, forKey: .installationID)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(metadata.appVersion, forKey: .appVersion)
        try container.encode(metadata.build, forKey: .build)
        try container.encode(metadata.osVersion, forKey: .osVersion)
    }

    enum CodingKeys: String, CodingKey {
        case installationID = "installation_id"
        case sessionID = "session_id"
        case appVersion = "app_version"
        case build
        case osVersion = "os_version"
    }
}

protocol TelemetryTransporting {
    func send(events: TelemetryEventBatch) async throws
    func send(report: TelemetryReportUpload) async throws
}

final class TelemetryTransport: TelemetryTransporting {
    private let session: URLSession
    private let baseURL: () -> URL
    private let encoder: JSONEncoder

    init(session: URLSession = .shared, baseURL: @escaping () -> URL = { AppConfiguration.apiBaseURL }) {
        self.session = session
        self.baseURL = baseURL
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    func send(events: TelemetryEventBatch) async throws {
        try await send(events, path: "/telemetry/events")
    }

    func send(report: TelemetryReportUpload) async throws {
        try await send(report, path: "/telemetry/reports")
    }

    private func send<Body: Encodable>(_ body: Body, path: String) async throws {
        guard let url = URL(string: path, relativeTo: baseURL())?.absoluteURL else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
    }
}

protocol APIEventReceiving {
    func recordAPIFailure(
        source: TelemetrySource,
        category: TelemetryFailureCategory,
        statusGroup: TelemetryHTTPStatusGroup?
    ) async
}

struct TelemetryQueueSnapshot: Equatable {
    let isEnabled: Bool
    let hasInstallationID: Bool
    let eventCount: Int
    let reportCount: Int
}

actor TelemetryManager: APIEventReceiving {
    static let shared: TelemetryManager = {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-trailboxUITestMode") {
            return TelemetryManager(transport: TrailBoxUITestTelemetryTransport())
        }
#endif
        return TelemetryManager()
    }()

    private static let installationKey = "trailbox.telemetry.installation-id"
    private static let queueKey = "trailbox.telemetry.queue"
    private static let maxEvents = 500
    private static let maxReports = 20
    private static let queueLifetime: TimeInterval = 7 * 24 * 60 * 60

    private struct Queue: Codable {
        var events: [TelemetryEventRecord] = []
        var reports: [TelemetryReportRecord] = []
    }

    private let defaults: UserDefaults
    private let transport: any TelemetryTransporting
    private let metadata: TelemetryRuntimeMetadata
    private let logger = Logger(subsystem: "com.trailbox.ios", category: "telemetry")
    private var queue: Queue
    private var isEnabled = false
    private var installationID: String?
    private var sessionID: String?

    init(
        defaults: UserDefaults = .standard,
        transport: any TelemetryTransporting = TelemetryTransport(),
        metadata: TelemetryRuntimeMetadata = .current
    ) {
        self.defaults = defaults
        self.transport = transport
        self.metadata = metadata
        if let data = defaults.data(forKey: Self.queueKey), let stored = try? JSONDecoder().decode(Queue.self, from: data) {
            queue = stored
        } else {
            queue = Queue()
        }
    }

    func activate() async {
        isEnabled = true
        if let stored = defaults.string(forKey: Self.installationKey), UUID(uuidString: stored) != nil {
            installationID = stored.lowercased()
        } else {
            let value = UUID().uuidString.lowercased()
            installationID = value
            defaults.set(value, forKey: Self.installationKey)
        }
        if sessionID == nil { sessionID = UUID().uuidString.lowercased() }
        pruneAndPersist()
        await flush()
    }

    func deactivate() {
        isEnabled = false
        installationID = nil
        sessionID = nil
        queue = Queue()
        defaults.removeObject(forKey: Self.installationKey)
        defaults.removeObject(forKey: Self.queueKey)
    }

    func record(
        _ name: TelemetryEventName,
        phase: TelemetryEventPhase,
        source: TelemetrySource? = nil,
        occurredAt: Date = Date(),
        durationMS: Int? = nil,
        failureCategory: TelemetryFailureCategory? = nil,
        statusGroup: TelemetryHTTPStatusGroup? = nil
    ) async {
        guard isEnabled, installationID != nil, sessionID != nil else { return }
        queue.events.append(TelemetryEventRecord(
            name: name,
            phase: phase,
            source: source,
            occurredAt: occurredAt,
            durationMS: durationMS,
            failureCategory: failureCategory,
            httpStatusGroup: statusGroup
        ))
        if queue.events.count > Self.maxEvents {
            queue.events.removeFirst(queue.events.count - Self.maxEvents)
        }
        pruneAndPersist()
        logger.info("queued event \(name.rawValue, privacy: .public) \(phase.rawValue, privacy: .public)")
        await flush()
    }

    func recordAPIFailure(
        source: TelemetrySource,
        category: TelemetryFailureCategory,
        statusGroup: TelemetryHTTPStatusGroup?
    ) async {
        await record(
            .apiFailure,
            phase: .failed,
            source: source,
            failureCategory: category,
            statusGroup: statusGroup
        )
    }

    func enqueue(report: TelemetryReportRecord) async {
        guard isEnabled, installationID != nil, sessionID != nil else { return }
        queue.reports.append(report)
        if queue.reports.count > Self.maxReports {
            queue.reports.removeFirst(queue.reports.count - Self.maxReports)
        }
        pruneAndPersist()
        await flush()
    }

    func flush() async {
        guard isEnabled, let installationID, let sessionID else { return }
        pruneAndPersist()
        while !queue.events.isEmpty {
            let events = Array(queue.events.prefix(50))
            do {
                try await transport.send(events: TelemetryEventBatch(
                    installationID: installationID,
                    sessionID: sessionID,
                    metadata: metadata,
                    events: events
                ))
                queue.events.removeFirst(events.count)
                persist()
            } catch {
                logger.error("event upload deferred: \(error.localizedDescription, privacy: .private)")
                break
            }
        }
        while let report = queue.reports.first {
            do {
                try await transport.send(report: TelemetryReportUpload(
                    installationID: installationID,
                    sessionID: sessionID,
                    metadata: metadata,
                    report: report
                ))
                queue.reports.removeFirst()
                persist()
            } catch {
                logger.error("diagnostic upload deferred: \(error.localizedDescription, privacy: .private)")
                break
            }
        }
    }

    func snapshot() -> TelemetryQueueSnapshot {
        TelemetryQueueSnapshot(
            isEnabled: isEnabled,
            hasInstallationID: installationID != nil || defaults.string(forKey: Self.installationKey) != nil,
            eventCount: queue.events.count,
            reportCount: queue.reports.count
        )
    }

    private func pruneAndPersist() {
        let cutoff = Date().addingTimeInterval(-Self.queueLifetime)
        queue.events.removeAll { $0.occurredAt < cutoff }
        queue.reports.removeAll { $0.occurredAt < cutoff }
        persist()
    }

    private func persist() {
        if queue.events.isEmpty && queue.reports.isEmpty {
            defaults.removeObject(forKey: Self.queueKey)
        } else if let data = try? JSONEncoder().encode(queue) {
            defaults.set(data, forKey: Self.queueKey)
        }
    }
}

private final class MetricKitReporter: NSObject, MXMetricManagerSubscriber, MetricKitReporting {
    private let capture: (MetricKitCapturedReport) -> Void
    private var isStarted = false

    init(capture: @escaping (MetricKitCapturedReport) -> Void) {
        self.capture = capture
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        MXMetricManager.shared.add(self)
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        MXMetricManager.shared.remove(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            capture(MetricKitCapturedReport(
                type: .metric,
                data: payload.jsonRepresentation(),
                crashCount: 0,
                hangCount: 0,
                cpuExceptionCount: 0,
                diskWriteExceptionCount: 0
            ))
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            capture(MetricKitCapturedReport(
                type: .diagnostic,
                data: payload.jsonRepresentation(),
                crashCount: payload.crashDiagnostics?.count ?? 0,
                hangCount: payload.hangDiagnostics?.count ?? 0,
                cpuExceptionCount: payload.cpuExceptionDiagnostics?.count ?? 0,
                diskWriteExceptionCount: payload.diskWriteExceptionDiagnostics?.count ?? 0
            ))
        }
    }
}

@MainActor
final class TelemetryConsentController: ObservableObject {
    private static let consentKey = "trailbox.telemetry.consent"

    @Published private(set) var state: TelemetryConsentState
    private let defaults: UserDefaults
    private let manager: TelemetryManager
    private let reporterFactory: (@escaping (MetricKitCapturedReport) -> Void) -> any MetricKitReporting
    private var didRecordSession = false
    private lazy var reporter: any MetricKitReporting = reporterFactory { [weak self] report in
        Task { @MainActor [weak self] in self?.capture(report) }
    }

    init(
        defaults: UserDefaults = .standard,
        manager: TelemetryManager = .shared,
        reporterFactory: @escaping (@escaping (MetricKitCapturedReport) -> Void) -> any MetricKitReporting = { MetricKitReporter(capture: $0) }
    ) {
        self.defaults = defaults
        self.manager = manager
        self.reporterFactory = reporterFactory
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-trailboxUITestReset") {
            defaults.removeObject(forKey: Self.consentKey)
            defaults.removeObject(forKey: "trailbox.telemetry.installation-id")
            defaults.removeObject(forKey: "trailbox.telemetry.queue")
        }
        if let index = arguments.firstIndex(of: "-trailboxUITestConsent"), arguments.indices.contains(index + 1) {
            let value = arguments[index + 1]
            if value == TelemetryConsentState.unknown.rawValue {
                defaults.removeObject(forKey: Self.consentKey)
            } else if TelemetryConsentState(rawValue: value) != nil {
                defaults.set(value, forKey: Self.consentKey)
            }
        }
#endif
        state = defaults.string(forKey: Self.consentKey).flatMap(TelemetryConsentState.init(rawValue:)) ?? .unknown
        if state == .enabled {
            Task { @MainActor [weak self] in await self?.enableServices() }
        } else {
            Task { await manager.deactivate() }
        }
    }

    var isEnabled: Bool { state == .enabled }

    func setEnabled(_ enabled: Bool) {
        setConsent(enabled ? .enabled : .disabled)
    }

    func setConsent(_ value: TelemetryConsentState) {
        guard value != .unknown else { return }
        state = value
        defaults.set(value.rawValue, forKey: Self.consentKey)
        if value == .enabled {
            Task { @MainActor [weak self] in await self?.enableServices() }
        } else {
            reporter.stop()
            didRecordSession = false
            Task { await manager.deactivate() }
        }
    }

    func record(
        _ name: TelemetryEventName,
        phase: TelemetryEventPhase,
        source: TelemetrySource? = nil,
        durationMS: Int? = nil,
        failureCategory: TelemetryFailureCategory? = nil,
        statusGroup: TelemetryHTTPStatusGroup? = nil
    ) {
        guard state == .enabled else { return }
        let logger = TelemetryEventLogger.logger(for: name)
        if let failureCategory {
            logger.error("event \(name.rawValue, privacy: .public) \(phase.rawValue, privacy: .public) category \(failureCategory.rawValue, privacy: .public)")
        } else {
            logger.info("event \(name.rawValue, privacy: .public) \(phase.rawValue, privacy: .public)")
        }
        Task {
            await manager.record(
                name,
                phase: phase,
                source: source,
                durationMS: durationMS,
                failureCategory: failureCategory,
                statusGroup: statusGroup
            )
        }
    }

    private func enableServices() async {
        await manager.activate()
        reporter.start()
        guard !didRecordSession else { return }
        didRecordSession = true
        await manager.record(.appSession, phase: .succeeded, source: .app)
    }

    private func capture(_ captured: MetricKitCapturedReport) {
        guard state == .enabled,
              let payload = try? JSONDecoder().decode(TelemetryJSONValue.self, from: captured.data) else { return }
        Task {
            await manager.enqueue(report: TelemetryReportRecord(
                reportType: captured.type,
                crashCount: captured.crashCount,
                hangCount: captured.hangCount,
                cpuExceptionCount: captured.cpuExceptionCount,
                diskWriteExceptionCount: captured.diskWriteExceptionCount,
                payload: payload
            ))
        }
    }
}

struct TelemetryConsentView: View {
    @EnvironmentObject private var telemetry: TelemetryConsentController
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.system(size: 44))
                    .foregroundStyle(TrailBoxColor.primaryDark)
                    .frame(width: 76, height: 76)
                    .background(TrailBoxColor.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text("帮助改进小野box")
                        .font(.title2.bold())
                        .foregroundStyle(TrailBoxColor.text)
                    Text("你可以选择发送匿名的功能使用结果、崩溃与性能诊断，帮助我们发现路线、收藏、出发和分享流程中的问题。")
                        .foregroundStyle(TrailBoxColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SectionCard {
                    VStack(alignment: .leading, spacing: 12) {
                        consentRow("不包含账号、轨迹坐标、路线名称和搜索内容", icon: "hand.raised.fill")
                        consentRow("不用于广告，也不会与登录用户关联", icon: "person.crop.circle.badge.xmark")
                        consentRow("可在设置中随时关闭并清除本地队列", icon: "gearshape.fill")
                    }
                }

                Button("查看隐私政策") { openURL(AppConfiguration.privacyPolicyURL) }
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button {
                    telemetry.setConsent(.enabled)
                } label: {
                    Text("同意并继续")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.plain)
                .background(TrailBoxColor.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityIdentifier("telemetry-consent-accept")

                Button("暂不") { telemetry.setConsent(.disabled) }
                    .font(.headline)
                    .foregroundStyle(TrailBoxColor.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .accessibilityIdentifier("telemetry-consent-decline")
            }
            .padding(22)
            .background(TrailPageBackground())
            .interactiveDismissDisabled()
        }
    }

    private func consentRow(_ text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(TrailBoxColor.primaryDark)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(TrailBoxColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum TelemetryEndpointClassifier {
    static func source(for path: String) -> TelemetrySource {
        let normalized = URLComponents(string: path)?.path ?? path
        if normalized.hasPrefix("/auth") { return .authentication }
        if normalized.hasPrefix("/boxes") { return .savedRoutes }
        if normalized.hasPrefix("/integrations/itra") { return .itra }
        if normalized.hasPrefix("/admin") { return .admin }
        if normalized.hasPrefix("/moderation") { return .moderation }
        if normalized.hasPrefix("/users") { return .profile }
        if normalized == "/tracks/public" || normalized == "/tags" { return .explore }
        if normalized.hasPrefix("/tracks") { return .routeDetail }
        return .api
    }
}
