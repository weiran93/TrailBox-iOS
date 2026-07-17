import Foundation
import OSLog

enum APIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "服务器返回了无法识别的数据"
        case .unauthorized: return "登录已过期，请重新登录"
        case .server(let message): return message
        }
    }
}

enum ErrorMessage {
    static func display(_ error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.localizedDescription
        }

        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return error.localizedDescription
        }

        switch nsError.code {
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorDataNotAllowed,
             NSURLErrorInternationalRoamingOff:
            return "网络连接不可用，请检查网络后重试"
        case NSURLErrorTimedOut:
            return "网络请求超时，请稍后重试"
        case NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorNetworkConnectionLost:
            return "无法连接服务器，请稍后重试"
        default:
            return "网络请求失败，请稍后重试"
        }
    }
}

final class APIClient {
    static let shared: APIClient = {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-trailboxUITestMode") {
            return APIClient(
                session: TrailBoxUITestSupport.session,
                baseURL: { URL(string: "https://trailbox-ui-test.invalid")! },
                telemetry: nil
            )
        }
#endif
        return APIClient()
    }()
    private let decoder: JSONDecoder
    private let encoder = JSONEncoder()
    private let session: URLSession
    private let baseURL: () -> URL
    private let telemetry: (any APIEventReceiving)?
    private let logger = Logger(subsystem: "com.trailbox.ios", category: "network")

    init(
        session: URLSession = .shared,
        baseURL: @escaping () -> URL = { AppConfiguration.apiBaseURL },
        telemetry: (any APIEventReceiving)? = TelemetryManager.shared
    ) {
        self.session = session
        self.baseURL = baseURL
        self.telemetry = telemetry
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let iso = ISO8601DateFormatter()
            if let date = iso.date(from: value) { return date }
            let fractionalISO = ISO8601DateFormatter()
            fractionalISO.formatOptions.insert(.withFractionalSeconds)
            if let date = fractionalISO.date(from: value) { return date }
            for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss.SSSSSS", "yyyy-MM-dd HH:mm:ss"] {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = format
                if let date = formatter.date(from: value) { return date }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(value)")
        }
        encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    func request<Response: Decodable>(_ path: String, method: String = "GET", body: (any Encodable)? = nil, token: String? = nil) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL())?.absoluteURL else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, http) = try await performData(request, sourcePath: path)
        try validate(http, data: data, sourcePath: path)
        return try decode(Response.self, from: data, sourcePath: path)
    }

    func uploadTrack(fileURL: URL, name: String?, city: String, tags: String, sport: String, trackKind: String = "activity", isPublic: Bool, showContributor: Bool, recommendationReason: String? = nil, token: String) async throws -> Track {
        guard let url = URL(string: "/tracks", relativeTo: baseURL())?.absoluteURL else { throw APIError.invalidResponse }
        let boundary = "TrailBox-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func appendField(_ key: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n".utf8))
        }
        if let name, !name.isEmpty { appendField("name", name) }
        appendField("city", city); appendField("tags", tags); appendField("sport", sport); appendField("track_kind", trackKind)
        appendField("is_public", isPublic ? "true" : "false"); appendField("show_contributor", showContributor ? "true" : "false")
        if let recommendationReason, !recommendationReason.isEmpty { appendField("recommendation_reason", recommendationReason) }
        let filename = fileURL.lastPathComponent
        let fileData = try Data(contentsOf: fileURL)
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(fileData); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let sourcePath = trackKind == "route_contribution" ? "/tracks/contribution-upload" : "/tracks/activity-upload"
        let (data, http) = try await performUpload(request, body: body, sourcePath: sourcePath)
        try validate(http, data: data, sourcePath: sourcePath, fallback: "上传失败")
        return try decode(Track.self, from: data, sourcePath: sourcePath)
    }

    func previewAdminTracks(fileURLs: [URL], keepOriginalName: Bool = true, token: String) async throws -> AdminBatchPreviewResult {
        guard let url = URL(string: "/admin/tracks/batch/preview", relativeTo: baseURL())?.absoluteURL else { throw APIError.invalidResponse }
        let boundary = "TrailBox-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"keep_original_name\"\r\n\r\n\(keepOriginalName ? "true" : "false")\r\n".utf8))
        for fileURL in fileURLs {
            let filename = fileURL.lastPathComponent
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"files\"; filename=\"\(filename)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
            body.append(try Data(contentsOf: fileURL))
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))

        let sourcePath = "/admin/tracks/batch/preview"
        let (data, http) = try await performUpload(request, body: body, sourcePath: sourcePath)
        try validate(http, data: data, sourcePath: sourcePath, fallback: "批量解析失败")
        return try decode(AdminBatchPreviewResult.self, from: data, sourcePath: sourcePath)
    }

    func commitAdminTracks(draftID: String, items: [AdminBatchCommitItem], token: String) async throws -> AdminBatchUploadResult {
        struct Request: Encodable { let draftID: String; let items: [AdminBatchCommitItem] }
        return try await request("/admin/tracks/batch/commit", method: "POST", body: Request(draftID: draftID, items: items), token: token)
    }

    func uploadAdminTracks(fileURLs: [URL], keepOriginalName: Bool = true, token: String) async throws -> AdminBatchUploadResult {
        guard let url = URL(string: "/admin/tracks/batch", relativeTo: baseURL())?.absoluteURL else { throw APIError.invalidResponse }
        let boundary = "TrailBox-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"keep_original_name\"\r\n\r\n\(keepOriginalName ? "true" : "false")\r\n".utf8))
        for fileURL in fileURLs {
            let filename = fileURL.lastPathComponent
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"files\"; filename=\"\(filename)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
            body.append(try Data(contentsOf: fileURL))
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))

        let sourcePath = "/admin/tracks/batch"
        let (data, http) = try await performUpload(request, body: body, sourcePath: sourcePath)
        try validate(http, data: data, sourcePath: sourcePath, fallback: "批量上传失败")
        return try decode(AdminBatchUploadResult.self, from: data, sourcePath: sourcePath)
    }

    func suggestMetadata(fileURL: URL, token: String?) async throws -> TrackMetadataSuggestion {
        guard let url = URL(string: "/tracks/suggest-metadata", relativeTo: baseURL())?.absoluteURL else { throw APIError.invalidResponse }
        let boundary = "TrailBox-\(UUID().uuidString)"
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let filename = fileURL.lastPathComponent
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8)
        body.append(try Data(contentsOf: fileURL)); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let sourcePath = "/tracks/suggest-metadata"
        let (data, http) = try await performUpload(request, body: body, sourcePath: sourcePath)
        try validate(http, data: data, sourcePath: sourcePath, fallback: "无法自动推荐路线信息")
        return try decode(TrackMetadataSuggestion.self, from: data, sourcePath: sourcePath)
    }

    func getITRAProfile(token: String) async throws -> ITRAProfile? {
        try await request("/users/me/itra-profile", token: token)
    }

    func searchITRAProfile(query: String, token: String) async throws -> ITRASearchResponse {
        guard var components = URLComponents(url: baseURL().appendingPathComponent("integrations/itra/search"), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "query", value: query)]
        guard let url = components.url else { throw APIError.invalidResponse }
        return try await request(url.absoluteString, token: token)
    }

    func updateITRAProfile(_ profile: ITRAProfileUpdateRequest, token: String) async throws -> ITRAProfile {
        try await request("/users/me/itra-profile", method: "PATCH", body: profile, token: token)
    }

    func getITRAProfileDetail(runnerID: String, profileURL: String?, token: String) async throws -> ITRAProfileDetail {
        var path = "/integrations/itra/profile/\(runnerID)"
        if let profileURL, var components = URLComponents(string: path) {
            components.queryItems = [URLQueryItem(name: "profile_url", value: profileURL)]
            path = components.string ?? path
        }
        return try await request(path, token: token)
    }

    func parseITRAProfileHTML(_ html: String, profileURL: String?, token: String) async throws -> ITRAProfileDetail {
        let requestBody = ITRAParseHTMLRequest(html: html, profileURL: profileURL)
        return try await request("/integrations/itra/profile/parse-html", method: "POST", body: requestBody, token: token)
    }

    func fetchPublicITRAHTML(profileURL: String) async throws -> String {
        guard let url = URL(string: profileURL) else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let sourcePath = "/integrations/itra/public-html"
        let (data, http) = try await performData(request, sourcePath: sourcePath)
        guard (200..<300).contains(http.statusCode), let html = String(data: data, encoding: .utf8) else {
            if !(200..<300).contains(http.statusCode) { recordHTTPFailure(statusCode: http.statusCode, sourcePath: sourcePath) }
            else { recordFailure(category: .decoding, sourcePath: sourcePath) }
            throw APIError.server("无法读取 ITRA 公开资料页")
        }
        return html
    }

    func deleteITRAProfile(token: String) async throws {
        try await requestVoid("/users/me/itra-profile", method: "DELETE", token: token)
    }

    func requestVoid(_ path: String, method: String, body: (any Encodable)? = nil, token: String) async throws {
        let url = URL(string: path, relativeTo: baseURL())!.absoluteURL
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = try encoder.encode(AnyEncodable(body)); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, http) = try await performData(request, sourcePath: path)
        try validate(http, data: data, sourcePath: path, fallback: "请求失败")
    }

    func downloadGPX(trackID: String, token: String?) async throws -> URL {
        let sourcePath = "/tracks/download.gpx"
        let url = URL(string: "/tracks/\(trackID)/download.gpx", relativeTo: baseURL())!.absoluteURL
        var request = URLRequest(url: url)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (temporaryURL, http) = try await performDownload(request, sourcePath: sourcePath)
        try validate(http, data: Data(), sourcePath: sourcePath, fallback: "下载 GPX 失败")
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("trailbox-\(trackID).gpx")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: temporaryURL, to: destination)
        return destination
    }

    private func performData(_ request: URLRequest, sourcePath: String) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                recordFailure(category: .decoding, sourcePath: sourcePath)
                throw APIError.invalidResponse
            }
            return (data, http)
        } catch {
            if error is APIError { throw error }
            recordFailure(category: TelemetryFailureCategory.classify(error), sourcePath: sourcePath)
            throw error
        }
    }

    private func performUpload(_ request: URLRequest, body: Data, sourcePath: String) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.upload(for: request, from: body)
            guard let http = response as? HTTPURLResponse else {
                recordFailure(category: .decoding, sourcePath: sourcePath)
                throw APIError.invalidResponse
            }
            return (data, http)
        } catch {
            if error is APIError { throw error }
            recordFailure(category: TelemetryFailureCategory.classify(error), sourcePath: sourcePath)
            throw error
        }
    }

    private func performDownload(_ request: URLRequest, sourcePath: String) async throws -> (URL, HTTPURLResponse) {
        do {
            let (url, response) = try await session.download(for: request)
            guard let http = response as? HTTPURLResponse else {
                recordFailure(category: .decoding, sourcePath: sourcePath)
                throw APIError.invalidResponse
            }
            return (url, http)
        } catch {
            if error is APIError { throw error }
            recordFailure(category: TelemetryFailureCategory.classify(error), sourcePath: sourcePath)
            throw error
        }
    }

    private func validate(_ http: HTTPURLResponse, data: Data, sourcePath: String, fallback: String? = nil) throws {
        if http.statusCode == 401 {
            recordHTTPFailure(statusCode: http.statusCode, sourcePath: sourcePath)
            throw APIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            recordHTTPFailure(statusCode: http.statusCode, sourcePath: sourcePath)
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw APIError.server(detail ?? fallback ?? String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)")
        }
    }

    private func decode<Response: Decodable>(_ type: Response.Type, from data: Data, sourcePath: String) throws -> Response {
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            recordFailure(category: .decoding, sourcePath: sourcePath)
            throw APIError.server("服务器返回的数据格式不正确，请确认服务已更新后重试")
        }
    }

    private func recordHTTPFailure(statusCode: Int, sourcePath: String) {
        let category: TelemetryFailureCategory
        let group: TelemetryHTTPStatusGroup?
        switch statusCode {
        case 401:
            category = .unauthorized
            group = .clientError
        case 400..<500:
            category = .http4xx
            group = .clientError
        case 500..<600:
            category = .http5xx
            group = .serverError
        default:
            category = .unknown
            group = nil
        }
        recordFailure(category: category, sourcePath: sourcePath, statusGroup: group)
    }

    private func recordFailure(
        category: TelemetryFailureCategory,
        sourcePath: String,
        statusGroup: TelemetryHTTPStatusGroup? = nil
    ) {
        let source = TelemetryEndpointClassifier.source(for: sourcePath)
        logger.error("request failed source=\(source.rawValue, privacy: .public) category=\(category.rawValue, privacy: .public)")
        guard let telemetry else { return }
        Task { await telemetry.recordAPIFailure(source: source, category: category, statusGroup: statusGroup) }
    }
}

private struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void
    init(_ value: any Encodable) { encodeValue = value.encode }
    func encode(to encoder: Encoder) throws { try encodeValue(encoder) }
}
