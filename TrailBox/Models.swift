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
    let recommendationReason: String?
    let contributorName: String?
    let contributorPublicID: String?
    let points: [TrackPoint]
    let createdAt: Date?
    let aiAnalysisText: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, city, tags, sport, points
        case userID = "user_id"; case distanceM = "distance_m"; case elevationGainM = "elevation_gain_m"; case elevationLossM = "elevation_loss_m"
        case durationSec = "duration_sec"; case startTime = "start_time"; case isPublic = "is_public"; case showContributor = "show_contributor"
        case recommendationReason = "recommendation_reason"
        case contributorName = "contributor_name"; case contributorPublicID = "contributor_public_id"; case createdAt = "created_at"; case aiAnalysisText = "ai_analysis_text"
    }

    // List endpoints intentionally omit the high-volume GPS payload. Detail endpoints
    // still return it, so callers can use one model for both response shapes.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userID = try container.decodeIfPresent(Int.self, forKey: .userID)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        tags = try container.decodeIfPresent(String.self, forKey: .tags)
        distanceM = try container.decode(Double.self, forKey: .distanceM)
        elevationGainM = try container.decode(Double.self, forKey: .elevationGainM)
        elevationLossM = try container.decode(Double.self, forKey: .elevationLossM)
        durationSec = try container.decodeIfPresent(Double.self, forKey: .durationSec)
        startTime = try container.decodeIfPresent(Date.self, forKey: .startTime)
        sport = try container.decodeIfPresent(String.self, forKey: .sport)
        isPublic = try container.decode(Bool.self, forKey: .isPublic)
        showContributor = try container.decode(Bool.self, forKey: .showContributor)
        recommendationReason = try container.decodeIfPresent(String.self, forKey: .recommendationReason)
        contributorName = try container.decodeIfPresent(String.self, forKey: .contributorName)
        contributorPublicID = try container.decodeIfPresent(String.self, forKey: .contributorPublicID)
        points = try container.decodeIfPresent([TrackPoint].self, forKey: .points) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        aiAnalysisText = try container.decodeIfPresent(String.self, forKey: .aiAnalysisText)
    }

    var tagList: [String] { (tags ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
}

struct TrackBox: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String?
    let isPublic: Bool
    let createdAt: Date?
    let tracks: [Track]

    enum CodingKeys: String, CodingKey {
        case id, name, description, tracks
        case isPublic = "is_public"
        case createdAt = "created_at"
    }
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

struct AdminBatchPreviewItem: Codable, Identifiable, Equatable {
    let id: String
    let filename: String
    let name: String
    let city: String?
    let tags: String?
    let sport: String?
    let isPublic: Bool
    let showContributor: Bool
    let distanceM: Double
    let elevationGainM: Double
    let elevationLossM: Double
    let durationSec: Double?
    let startTime: Date?

    enum CodingKeys: String, CodingKey {
        case id, filename, name, city, tags, sport
        case isPublic = "is_public"; case showContributor = "show_contributor"
        case distanceM = "distance_m"; case elevationGainM = "elevation_gain_m"; case elevationLossM = "elevation_loss_m"
        case durationSec = "duration_sec"; case startTime = "start_time"
    }
}

struct AdminBatchPreviewResult: Codable {
    let draftID: String
    let items: [AdminBatchPreviewItem]
    let errors: [AdminBatchOperationError]

    enum CodingKeys: String, CodingKey { case draftID = "draft_id"; case items, errors }
}

struct AdminBatchCommitItem: Encodable {
    let id: String
    let filename: String
    let name: String
    let city: String?
    let tags: String?
    let sport: String
    let isPublic: Bool
    let showContributor: Bool
}

struct TrackMetadataSuggestion: Codable {
    let name: String?
    let nameCandidates: [String]?
    let city: String?
    let tags: [String]?
    let sport: String?
    let distanceM: Double?
    let elevationGainM: Double?
    let durationSec: Double?
    let points: [TrackPoint]?

    enum CodingKeys: String, CodingKey {
        case name, city, tags, sport, points
        case nameCandidates = "name_candidates"
        case distanceM = "distance_m"
        case elevationGainM = "elevation_gain_m"
        case durationSec = "duration_sec"
    }
}

struct RouteAnalysis: Codable, Equatable {
    struct Preparation: Codable, Equatable {
        let recommendedWaterL: Double?
        let recommendedSupplyCount: Int?
        let headlampRecommended: Bool?
        let equipment: [String]
        let safetyNotes: [String]

        enum CodingKeys: String, CodingKey {
            case equipment
            case recommendedWaterL = "recommended_water_l"; case recommendedSupplyCount = "recommended_supply_count"
            case headlampRecommended = "headlamp_recommended"; case safetyNotes = "safety_notes"
        }
    }

    let trackID: String
    let routeType: String
    let difficultyScore: Double
    let difficultyLevel: String
    let fitnessScore: Double
    let elevationScore: Double
    let estimatedDurationMin: Int?
    let estimatedDurationMax: Int?
    let highestElevationM: Double?
    let lowestElevationM: Double?
    let maximumGradePercent: Double?
    let averageClimbGradePercent: Double?
    let longestClimbDistanceM: Double?
    let longestClimbGainM: Double?
    let hardestSegmentStartM: Double?
    let hardestSegmentEndM: Double?
    let ascentRatio: Double?
    let descentRatio: Double?
    let flatRatio: Double?
    let features: [String]
    let preparation: Preparation?
    let source: String
    let updatedAt: Date
    let canManage: Bool?

    enum CodingKeys: String, CodingKey {
        case features, preparation, source
        case trackID = "track_id"; case routeType = "route_type"
        case difficultyScore = "difficulty_score"; case difficultyLevel = "difficulty_level"
        case fitnessScore = "fitness_score"; case elevationScore = "elevation_score"
        case estimatedDurationMin = "estimated_duration_min"; case estimatedDurationMax = "estimated_duration_max"
        case highestElevationM = "highest_elevation_m"; case lowestElevationM = "lowest_elevation_m"
        case maximumGradePercent = "maximum_grade_percent"; case averageClimbGradePercent = "average_climb_grade_percent"
        case longestClimbDistanceM = "longest_climb_distance_m"; case longestClimbGainM = "longest_climb_gain_m"
        case hardestSegmentStartM = "hardest_segment_start_m"; case hardestSegmentEndM = "hardest_segment_end_m"
        case ascentRatio = "ascent_ratio"; case descentRatio = "descent_ratio"; case flatRatio = "flat_ratio"
        case updatedAt = "updated_at"; case canManage = "can_manage"
    }
}

struct RoutePersonalFit: Codable, Equatable {
    let score: Double
    let level: String
    let reason: String
    let longestDistanceM: Double
    let largestGainM: Double
    let estimatedDurationMin: Int?
    let estimatedDurationMax: Int?
    let source: String

    enum CodingKeys: String, CodingKey {
        case score, level, reason, source
        case longestDistanceM = "longest_distance_m"; case largestGainM = "largest_gain_m"
        case estimatedDurationMin = "estimated_duration_min"; case estimatedDurationMax = "estimated_duration_max"
    }
}

struct RoutePOI: Codable, Identifiable, Equatable {
    let id: Int
    let type: String
    let name: String
    let latitude: Double
    let longitude: Double
    let distanceAlongRouteM: Double?
    let distanceFromRouteM: Double?
    let source: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, type, name, latitude, longitude, source, status
        case distanceAlongRouteM = "distance_along_route_m"; case distanceFromRouteM = "distance_from_route_m"
    }
}

struct RoutePOIInput: Encodable {
    let type: String
    let name: String
    let latitude: Double
    let longitude: Double
    let distanceAlongRouteM: Double?
    let distanceFromRouteM: Double?
    let source: String
}

struct RouteCondition: Codable, Identifiable, Equatable {
    let id: Int
    let conditionType: String
    let severity: String
    let description: String?
    let latitude: Double?
    let longitude: Double?
    let observedAt: Date
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, severity, description, latitude, longitude
        case conditionType = "condition_type"; case observedAt = "observed_at"; case expiresAt = "expires_at"
    }
}

struct RouteReview: Codable, Identifiable, Equatable {
    let id: Int
    let difficultyRating: Int?
    let sceneryRating: Int?
    let navigationRating: Int?
    let supplyRating: Int?
    let signalRating: Int?
    let isRecommended: Bool?
    let comment: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, comment
        case difficultyRating = "difficulty_rating"; case sceneryRating = "scenery_rating"
        case navigationRating = "navigation_rating"; case supplyRating = "supply_rating"
        case signalRating = "signal_rating"; case isRecommended = "is_recommended"; case updatedAt = "updated_at"
    }
}

struct RouteReviewSummary: Codable, Equatable {
    let count: Int
    let averages: [String: Double]
    let items: [RouteReview]
}

struct RouteReviewInput: Encodable {
    let difficultyRating: Int?
    let sceneryRating: Int?
    let navigationRating: Int?
    let supplyRating: Int?
    let signalRating: Int?
    let isRecommended: Bool?
    let comment: String?
}

struct RouteConditionInput: Encodable {
    let conditionType: String
    let severity: String
    let description: String?
}

struct RouteMatch: Codable, Identifiable, Equatable {
    let id: Int
    let trackID: String
    let routeName: String?
    let activityID: String
    let coverageRatio: Double
    let direction: String
    let matchType: String
    let matchedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, direction
        case trackID = "track_id"; case routeName = "route_name"; case activityID = "activity_id"; case coverageRatio = "coverage_ratio"
        case matchType = "match_type"; case matchedAt = "matched_at"
    }
}

struct RouteCompletionSummary: Codable, Equatable {
    struct Recent: Codable, Equatable {
        let matchedAt: Date
        let coverageRatio: Double
        let direction: String
        let matchType: String
        let durationSec: Double?

        enum CodingKeys: String, CodingKey {
            case direction
            case matchedAt = "matched_at"; case coverageRatio = "coverage_ratio"
            case matchType = "match_type"; case durationSec = "duration_sec"
        }
    }

    let count: Int
    let averageDurationSec: Double?
    let fastestDurationSec: Double?
    let slowestDurationSec: Double?
    let recent: [Recent]
    let source: String

    enum CodingKeys: String, CodingKey {
        case count, recent, source
        case averageDurationSec = "average_duration_sec"; case fastestDurationSec = "fastest_duration_sec"
        case slowestDurationSec = "slowest_duration_sec"
    }
}

struct RouteWeather: Codable, Equatable {
    struct Current: Codable, Equatable {
        let temperature: Double?
        let apparentTemperature: Double?
        let precipitation: Double?
        let weatherCode: Int?
        let windSpeed: Double?
        let windGusts: Double?

        enum CodingKeys: String, CodingKey {
            case precipitation
            case temperature = "temperature_2m"; case apparentTemperature = "apparent_temperature"
            case weatherCode = "weather_code"; case windSpeed = "wind_speed_10m"; case windGusts = "wind_gusts_10m"
        }
    }

    struct Daily: Codable, Equatable {
        let time: [String]?
        let sunrise: [String]?
        let sunset: [String]?
        let temperatureMax: [Double]?
        let temperatureMin: [Double]?
        let precipitationProbabilityMax: [Int]?
        let windSpeedMax: [Double]?

        enum CodingKeys: String, CodingKey {
            case time, sunrise, sunset
            case temperatureMax = "temperature_2m_max"; case temperatureMin = "temperature_2m_min"
            case precipitationProbabilityMax = "precipitation_probability_max"; case windSpeedMax = "wind_speed_10m_max"
        }
    }

    let current: Current
    let daily: Daily
    let timezone: String?
    let source: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey { case current, daily, timezone, source; case updatedAt = "updated_at" }
}

struct ITRAProfile: Codable, Equatable {
    let runnerID: String
    let profileURL: String
    let displayName: String?
    let gender: String?
    let nationality: String?
    let age: String?
    let ageGroup: String?
    let performanceIndex: Int?
    let latestResultSummary: String?
    let lookupSource: String?
    let lookupConfidence: Double?
    let lastQuery: String?
    let lastCheckedAt: Date?

    enum CodingKeys: String, CodingKey {
        case gender, nationality, age
        case runnerID = "runner_id"
        case profileURL = "profile_url"
        case displayName = "display_name"
        case ageGroup = "age_group"
        case performanceIndex = "performance_index"
        case latestResultSummary = "latest_result_summary"
        case lookupSource = "lookup_source"
        case lookupConfidence = "lookup_confidence"
        case lastQuery = "last_query"
        case lastCheckedAt = "last_checked_at"
    }
}

struct ITRASearchCandidate: Codable, Identifiable, Equatable {
    let runnerID: String
    let profileURL: String
    let displayName: String?
    let gender: String?
    let nationality: String?
    let age: String?
    let ageGroup: String?
    let performanceIndex: Int?
    let latestResultSummary: String?
    let lookupSource: String
    let lookupConfidence: Double

    var id: String { runnerID }

    enum CodingKeys: String, CodingKey {
        case gender, nationality, age
        case runnerID = "runner_id"
        case profileURL = "profile_url"
        case displayName = "display_name"
        case ageGroup = "age_group"
        case performanceIndex = "performance_index"
        case latestResultSummary = "latest_result_summary"
        case lookupSource = "lookup_source"
        case lookupConfidence = "lookup_confidence"
    }
}

struct ITRASearchResponse: Codable {
    let query: String
    let candidates: [ITRASearchCandidate]
}

struct ITRAProfileUpdateRequest: Encodable {
    let runnerID: String
    let profileURL: String
    let displayName: String?
    let gender: String?
    let nationality: String?
    let age: String?
    let ageGroup: String?
    let performanceIndex: Int?
    let latestResultSummary: String?
    let lookupSource: String?
    let lookupConfidence: Double?
    let lastQuery: String?

    enum CodingKeys: String, CodingKey {
        case gender, nationality, age
        case runnerID = "runner_id"
        case profileURL = "profile_url"
        case displayName = "display_name"
        case ageGroup = "age_group"
        case performanceIndex = "performance_index"
        case latestResultSummary = "latest_result_summary"
        case lookupSource = "lookup_source"
        case lookupConfidence = "lookup_confidence"
        case lastQuery = "last_query"
    }
}

struct ITRAProfileDetail: Codable, Equatable {
    let profile: ITRAProfileSummary
    let summaryStats: ITRASummaryStats
    let rankings: ITRARankingStats
    let raceResults: [ITRARaceResult]
    let bestItems: [ITRABestItem]
    let dataSource: String
    let isPartial: Bool

    enum CodingKeys: String, CodingKey {
        case profile, rankings
        case summaryStats = "summary_stats"
        case raceResults = "race_results"
        case bestItems = "best_items"
        case dataSource = "data_source"
        case isPartial = "is_partial"
    }
}

struct ITRAProfileSummary: Codable, Equatable {
    let runnerID: String
    let profileURL: String
    let displayName: String?
    let gender: String?
    let nationality: String?
    let age: String?
    let ageGroup: String?
    let performanceIndex: Int?
    let publicLevel: String?
    let lastCheckedAt: String?

    enum CodingKeys: String, CodingKey {
        case gender, nationality, age
        case runnerID = "runner_id"
        case profileURL = "profile_url"
        case displayName = "display_name"
        case ageGroup = "age_group"
        case performanceIndex = "performance_index"
        case publicLevel = "public_level"
        case lastCheckedAt = "last_checked_at"
    }
}

struct ITRASummaryStats: Codable, Equatable {
    let totalRaces: Int?
    let finishRate: Double?
    let totalTime: String?
    let totalDistanceKM: Double?
    let totalElevationGainM: Int?

    enum CodingKeys: String, CodingKey {
        case totalRaces = "total_races"
        case finishRate = "finish_rate"
        case totalTime = "total_time"
        case totalDistanceKM = "total_distance_km"
        case totalElevationGainM = "total_elevation_gain_m"
    }
}

struct ITRARankingStats: Codable, Equatable {
    let countryRank: String?
    let countryCount: String?
    let continentRank: String?
    let continentCount: String?
    let worldRank: String?
    let worldCount: String?
    let worldPercentile: Double?

    enum CodingKeys: String, CodingKey {
        case countryRank = "country_rank"
        case countryCount = "country_count"
        case continentRank = "continent_rank"
        case continentCount = "continent_count"
        case worldRank = "world_rank"
        case worldCount = "world_count"
        case worldPercentile = "world_percentile"
    }
}

struct ITRARaceResult: Codable, Identifiable, Equatable {
    let date: String?
    let name: String?
    let localName: String?
    let country: String?
    let status: String?
    let itraPoints: Int?
    let time: String?
    let distanceKM: Double?
    let elevationGainM: Int?
    let averagePace: String?
    let effortPace: String?
    let rank: String?
    let rankTotal: String?
    let genderRank: String?
    let genderTotal: String?
    let totalParticipants: Int?
    let finisherLevel: Int?
    let mountainLevel: Int?
    let distanceCategory: String?

    var id: String { "\(date ?? "")-\(name ?? UUID().uuidString)" }

    enum CodingKeys: String, CodingKey {
        case date, name, country, status, time, rank
        case localName = "local_name"
        case itraPoints = "itra_points"
        case distanceKM = "distance_km"
        case elevationGainM = "elevation_gain_m"
        case averagePace = "average_pace"
        case effortPace = "effort_pace"
        case rankTotal = "rank_total"
        case genderRank = "gender_rank"
        case genderTotal = "gender_total"
        case totalParticipants = "total_participants"
        case finisherLevel = "finisher_level"
        case mountainLevel = "mountain_level"
        case distanceCategory = "distance_category"
    }
}

struct ITRABestItem: Codable, Identifiable, Equatable {
    let title: String
    let value: String
    let raceName: String?

    var id: String { "\(title)-\(value)-\(raceName ?? "")" }

    enum CodingKeys: String, CodingKey {
        case title, value
        case raceName = "race_name"
    }
}

struct ITRAParseHTMLRequest: Encodable {
    let html: String
    let profileURL: String?

    enum CodingKeys: String, CodingKey {
        case html
        case profileURL = "profile_url"
    }
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
