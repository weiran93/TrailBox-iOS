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

    enum CodingKeys: String, CodingKey { case id, username, nickname; case publicID = "public_id"; case isAdmin = "is_admin" }
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

struct TrackMetadataSuggestion: Codable {
    let name: String?
    let city: String?
    let tags: [String]?
    let sport: String?
}

struct AIAnalysisResponse: Codable { let trackID: String; let model: String; let analysis: String; let cached: Bool; enum CodingKeys: String, CodingKey { case model, analysis, cached; case trackID = "track_id" } }

struct AdminStats: Codable { let total: Int; let `public`: Int; let `private`: Int }
