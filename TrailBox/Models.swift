import Foundation

struct TokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let user: User

    enum CodingKeys: String, CodingKey { case accessToken = "access_token", tokenType = "token_type", user }
}

struct User: Codable, Equatable {
    let id: Int
    let username: String?
    let publicID: String?
    let nickname: String?
    let isAdmin: Bool
    let hasDeepSeekAPIKey: Bool

    enum CodingKeys: String, CodingKey {
        case id, username, nickname
        case publicID = "public_id"
        case isAdmin = "is_admin"
        case hasDeepSeekAPIKey = "has_deepseek_api_key"
    }
}

struct TrackPoint: Codable, Equatable {
    let lat: Double
    let lon: Double
    let altitude: Double?
    let timestamp: Date?
    let heartRate: Int?
    let cadence: Int?
    let speed: Double?
    let distance: Double?
    let grade: Double?

    enum CodingKeys: String, CodingKey { case lat, lon, altitude, timestamp, cadence, speed, distance, grade; case heartRate = "heart_rate" }
}

struct Track: Codable, Identifiable, Equatable {
    let id: String
    let userID: Int?
    let name: String
    let description: String?
    let city: String?
    let tags: String?
    let distanceM: Double
    let elevationGainM: Double
    let elevationLossM: Double
    let durationSec: Double?
    let startTime: Date?
    let sport: String?
    let isPublic: Bool
    let showContributor: Bool
    let contributorName: String?
    let contributorPublicID: String?
    let points: [TrackPoint]
    let createdAt: Date?
    let aiAnalysisText: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, city, tags, sport, points
        case userID = "user_id"; case distanceM = "distance_m"; case elevationGainM = "elevation_gain_m"; case elevationLossM = "elevation_loss_m"
        case durationSec = "duration_sec"; case startTime = "start_time"; case isPublic = "is_public"; case showContributor = "show_contributor"
        case contributorName = "contributor_name"; case contributorPublicID = "contributor_public_id"; case createdAt = "created_at"; case aiAnalysisText = "ai_analysis_text"
    }

    var tagList: [String] { (tags ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
}

struct ConfiguredTag: Codable, Identifiable { let id: Int; let name: String; let sortOrder: Int; enum CodingKeys: String, CodingKey { case id, name; case sortOrder = "sort_order" } }

struct AdminBatchOperationError: Codable, Identifiable {
    let id: String?
    let filename: String?
    let error: String

    var identifier: String { id ?? filename ?? UUID().uuidString }
}

struct AdminBatchUploadResult: Codable {
    let tracks: [Track]
    let errors: [AdminBatchOperationError]
}

struct TrackMetadataSuggestion: Codable {
    let name: String?
    let city: String?
    let tags: [String]?
    let sport: String?
}

struct ActivityFeeling: Encodable {
    let overallFeeling: String?
    let processTags: [String]
    let bodyTags: [String]
    let routeEnvTags: [String]
    let painDetails: [PainDetail]
    let voiceText: String
    let textNote: String

    var hasInput: Bool {
        overallFeeling != nil || !processTags.isEmpty || !bodyTags.isEmpty || !routeEnvTags.isEmpty || !painDetails.isEmpty || !voiceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !textNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct PainDetail: Codable, Identifiable, Equatable {
    let bodyPart: String
    let severity: String
    var id: String { bodyPart }
}

struct AIAnalysisRequest: Encodable { let userFeeling: ActivityFeeling }

struct AIAnalysis: Codable, Equatable {
    let cardSummary: String
    let detailAnalysis: DetailAnalysis

    struct DetailAnalysis: Codable, Equatable {
        let coreJudgment: TextSection
        let mainReason: TextSection
        let nextActions: ActionSection
        let recoveryAdvice: TextSection
        let riskWarning: TextSection?
    }

    struct TextSection: Codable, Equatable { let title: String; let content: String }
    struct ActionSection: Codable, Equatable { let title: String; let items: [String] }

    init(legacyText: String) {
        let cleaned = legacyText.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        func section(_ title: String) -> String {
            let markers = ["【\(title)】", title]
            guard let marker = markers.first(where: { cleaned.range(of: $0) != nil }), let range = cleaned.range(of: marker) else { return "" }
            let remainder = String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return remainder.components(separatedBy: "【").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? remainder
        }
        let core = section("核心判断")
        let reason = section("为什么会这样")
        let recovery = section("恢复建议")
        let actionsText = section("下次怎么改")
        let actions = actionsText.split(whereSeparator: { $0.isNewline }).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        cardSummary = core.isEmpty ? String(cleaned.prefix(70)) : String(core.prefix(70))
        detailAnalysis = DetailAnalysis(
            coreJudgment: TextSection(title: "核心判断", content: core.isEmpty ? String(cleaned.prefix(120)) : core),
            mainReason: TextSection(title: "为什么会这样", content: reason.isEmpty ? "本次建议由运动数据和你的体感共同生成。" : reason),
            nextActions: ActionSection(title: "下次怎么改", items: actions.isEmpty ? ["下次运动后继续补充体感，便于获得更具体的建议。"] : actions),
            recoveryAdvice: TextSection(title: "恢复建议", content: recovery.isEmpty ? "接下来1-2天根据身体感受安排轻松活动和恢复。" : recovery),
            riskWarning: nil
        )
    }
}

struct AIAnalysisResponse: Codable {
    let trackID: String?
    let model: String?
    let analysis: AIAnalysis
    let rawAnalysis: String
    let cached: Bool?
    enum CodingKeys: String, CodingKey { case model, analysis, cached; case trackID = "track_id" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trackID = try container.decodeIfPresent(String.self, forKey: .trackID)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        cached = try container.decodeIfPresent(Bool.self, forKey: .cached)
        if let wrapped = try? container.decode(AIAnalysis.self, forKey: .analysis) {
            analysis = wrapped
            rawAnalysis = Self.format(wrapped)
        } else if let legacyText = try? container.decode(String.self, forKey: .analysis) {
            analysis = AIAnalysis(legacyText: legacyText)
            rawAnalysis = legacyText
        } else {
            analysis = try AIAnalysis(from: decoder)
            rawAnalysis = Self.format(analysis)
        }
    }

    private static func format(_ analysis: AIAnalysis) -> String {
        var sections = [
            "【\(analysis.detailAnalysis.coreJudgment.title)】\n\(analysis.detailAnalysis.coreJudgment.content)",
            "【\(analysis.detailAnalysis.mainReason.title)】\n\(analysis.detailAnalysis.mainReason.content)",
            "【\(analysis.detailAnalysis.nextActions.title)】\n\(analysis.detailAnalysis.nextActions.items.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))",
            "【\(analysis.detailAnalysis.recoveryAdvice.title)】\n\(analysis.detailAnalysis.recoveryAdvice.content)"
        ]
        if let warning = analysis.detailAnalysis.riskWarning { sections.append("【\(warning.title)】\n\(warning.content)") }
        return sections.joined(separator: "\n\n")
    }
}

struct AdminStats: Codable { let total: Int; let `public`: Int; let `private`: Int }

struct AdminAISettings: Codable {
    let prompt: String
    let hasDefaultDeepSeekAPIKey: Bool

    enum CodingKeys: String, CodingKey {
        case prompt
        case hasDefaultDeepSeekAPIKey = "has_default_deepseek_api_key"
    }
}

struct ModerationReport: Codable, Identifiable {
    let id: Int
    let trackID: String
    let reason: String
    let details: String?
    let createdAt: Date
    enum CodingKeys: String, CodingKey { case id, reason, details; case trackID = "track_id"; case createdAt = "created_at" }
}
