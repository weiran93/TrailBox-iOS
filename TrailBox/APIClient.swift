import Foundation

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

final class APIClient {
    static let shared = APIClient()
    private let decoder: JSONDecoder
    private let encoder = JSONEncoder()

    private init() {
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
        guard let url = URL(string: path, relativeTo: AppConfiguration.apiBaseURL)?.absoluteURL else {
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
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw APIError.server(detail ?? String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)")
        }
        return try decoder.decode(Response.self, from: data)
    }

    func uploadTrack(fileURL: URL, name: String?, city: String, tags: String, sport: String, isPublic: Bool, showContributor: Bool, token: String) async throws -> Track {
        guard let url = URL(string: "/tracks", relativeTo: AppConfiguration.apiBaseURL)?.absoluteURL else { throw APIError.invalidResponse }
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
        appendField("city", city); appendField("tags", tags); appendField("sport", sport)
        appendField("is_public", isPublic ? "true" : "false"); appendField("show_contributor", showContributor ? "true" : "false")
        let filename = fileURL.lastPathComponent
        let fileData = try Data(contentsOf: fileURL)
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(fileData); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw APIError.server((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String ?? "上传失败") }
        return try decoder.decode(Track.self, from: data)
    }

    func uploadAdminTracks(fileURLs: [URL], token: String) async throws -> AdminBatchUploadResult {
        guard let url = URL(string: "/admin/tracks/batch", relativeTo: AppConfiguration.apiBaseURL)?.absoluteURL else { throw APIError.invalidResponse }
        let boundary = "TrailBox-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        for fileURL in fileURLs {
            let filename = fileURL.lastPathComponent
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"files\"; filename=\"\(filename)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
            body.append(try Data(contentsOf: fileURL))
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw APIError.server(detail ?? "批量上传失败")
        }
        return try decoder.decode(AdminBatchUploadResult.self, from: data)
    }

    func suggestMetadata(fileURL: URL, token: String?) async throws -> TrackMetadataSuggestion {
        guard let url = URL(string: "/tracks/suggest-metadata", relativeTo: AppConfiguration.apiBaseURL)?.absoluteURL else { throw APIError.invalidResponse }
        let boundary = "TrailBox-\(UUID().uuidString)"
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let filename = fileURL.lastPathComponent
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8)
        body.append(try Data(contentsOf: fileURL)); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.server("无法自动推荐路线信息") }
        return try decoder.decode(TrackMetadataSuggestion.self, from: data)
    }

    func requestVoid(_ path: String, method: String, body: (any Encodable)? = nil, token: String) async throws {
        let url = URL(string: path, relativeTo: AppConfiguration.apiBaseURL)!.absoluteURL
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = try encoder.encode(AnyEncodable(body)); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw APIError.server((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String ?? "请求失败") }
    }

    func downloadGPX(trackID: String, token: String?) async throws -> URL {
        let url = URL(string: "/tracks/\(trackID)/download.gpx", relativeTo: AppConfiguration.apiBaseURL)!.absoluteURL
        var request = URLRequest(url: url)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw APIError.server("下载 GPX 失败") }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("trailbox-\(trackID).gpx")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: temporaryURL, to: destination)
        return destination
    }
}

private struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void
    init(_ value: any Encodable) { encodeValue = value.encode }
    func encode(to encoder: Encoder) throws { try encodeValue(encoder) }
}
