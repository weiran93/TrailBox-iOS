import Foundation
import MapKit

struct DiscoveredRoutePOI: Identifiable, Equatable {
    let id: String
    let type: String
    let name: String
    let latitude: Double
    let longitude: Double
    let distanceAlongRouteM: Double?
    let distanceFromRouteM: Double
}

@MainActor
final class RouteIntelligenceStore: ObservableObject {
    private enum POIErrorKind: Equatable {
        case loading
        case saving
    }

    private static var discoveredPOICache: [String: [DiscoveredRoutePOI]] = [:]
    private var poiErrorKind: POIErrorKind?

    @Published private(set) var analysis: RouteAnalysis?
    @Published private(set) var personalFit: RoutePersonalFit?
    @Published private(set) var weather: RouteWeather?
    @Published private(set) var pois: [RoutePOI] = []
    @Published private(set) var discoveredPOIs: [DiscoveredRoutePOI] = []
    @Published private(set) var conditions: [RouteCondition] = []
    @Published private(set) var reviews: RouteReviewSummary?
    @Published private(set) var activityMatches: [RouteMatch] = []
    @Published private(set) var completions: RouteCompletionSummary?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingAnalysis = false
    @Published private(set) var isLoadingWeather = false
    @Published private(set) var isLoadingPOIs = false
    @Published private(set) var isDiscoveringPOIs = false
    @Published private(set) var isSavingPOIs = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var analysisErrorMessage: String?
    @Published private(set) var weatherErrorMessage: String?
    @Published private(set) var lastCheckedAt: Date?

    func load(trackID: String, token: String?) async {
        while isLoading {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if Task.isCancelled { return }
        }
        isLoading = true
        errorMessage = nil
        poiErrorKind = nil

        async let analysisTask: Void = refreshAnalysis(trackID: trackID, token: token)
        async let weatherTask: Void = refreshWeather(trackID: trackID)
        async let poiTask: Void = refreshPOIs(trackID: trackID)
        async let communityTask: Void = refreshCommunity(trackID: trackID)
        _ = await (analysisTask, weatherTask, poiTask, communityTask)

        lastCheckedAt = Date()
        isLoading = false
    }

    func refreshAnalysis(trackID: String, token: String?) async {
        guard !isLoadingAnalysis else { return }
        isLoadingAnalysis = true
        analysisErrorMessage = nil
        defer { isLoadingAnalysis = false }

        async let analysisResult: RouteAnalysis? = optionalRequest("/tracks/\(trackID)/analysis", token: token)
        async let fitResult: RoutePersonalFit? = token == nil
            ? nil
            : optionalRequest("/tracks/\(trackID)/personal-fit", token: token)
        let fetchedAnalysis = await analysisResult
        let fetchedFit = await fitResult

        if let fetchedAnalysis {
            analysis = fetchedAnalysis
        } else {
            analysisErrorMessage = analysis == nil
                ? "路线分析暂时不可用，基础轨迹信息仍可正常查看。"
                : "路线分析刷新失败，正在显示上次结果。"
        }
        if token == nil {
            personalFit = nil
        } else if let fetchedFit {
            personalFit = fetchedFit
        }
    }

    func refreshWeather(trackID: String) async {
        guard !isLoadingWeather else { return }
        isLoadingWeather = true
        weatherErrorMessage = nil
        defer { isLoadingWeather = false }

        let fetchedWeather: RouteWeather? = await optionalRequest("/tracks/\(trackID)/weather")
        if let fetchedWeather {
            weather = fetchedWeather
        } else {
            weatherErrorMessage = weather == nil
                ? "路线天气暂时不可用，请稍后重试。"
                : "天气刷新失败，正在显示上次结果。"
        }
    }

    func refreshPOIs(trackID: String) async {
        guard !isLoadingPOIs else { return }
        isLoadingPOIs = true
        errorMessage = nil
        poiErrorKind = nil
        defer { isLoadingPOIs = false }

        let fetchedPOIs: [RoutePOI]? = await optionalRequest("/tracks/\(trackID)/pois")
        if let fetchedPOIs {
            pois = fetchedPOIs
            if !fetchedPOIs.isEmpty { discoveredPOIs = [] }
        } else {
            poiErrorKind = .loading
            errorMessage = pois.isEmpty
                ? "设施信息暂时不可用，可稍后重试或查看地图发现结果。"
                : "设施信息刷新失败，正在显示上次结果。"
        }
    }

    private func refreshCommunity(trackID: String) async {
        async let conditionResult: [RouteCondition]? = optionalRequest("/tracks/\(trackID)/conditions")
        async let reviewResult: RouteReviewSummary? = optionalRequest("/tracks/\(trackID)/reviews")
        async let completionResult: RouteCompletionSummary? = optionalRequest("/tracks/\(trackID)/completions")
        if let fetchedConditions = await conditionResult { conditions = fetchedConditions }
        if let fetchedReviews = await reviewResult { reviews = fetchedReviews }
        if let fetchedCompletions = await completionResult { completions = fetchedCompletions }
    }

    func discoverNearbyPOIs(trackID: String, points: [TrackPoint]) async {
        guard points.count > 1, discoveredPOIs.isEmpty else { return }
        isDiscoveringPOIs = true
        defer { isDiscoveringPOIs = false }

        for _ in 0..<40 where isLoadingPOIs {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if Task.isCancelled { return }
        }
        guard pois.isEmpty else { return }
        if let cached = Self.discoveredPOICache[trackID] {
            discoveredPOIs = cached
            return
        }

        let anchorIndexes = Array(Set([0, points.count / 2, points.count - 1])).sorted()
        let queries = [
            ("停车场", "parking"),
            ("公共厕所", "restroom"),
            ("便利店", "supply"),
            ("医院", "hospital"),
        ]
        var results: [DiscoveredRoutePOI] = []
        var cumulativeDistances = Array(repeating: 0.0, count: points.count)
        if points.count > 1 {
            for index in 1..<points.count {
                let previous = CLLocation(latitude: points[index - 1].lat, longitude: points[index - 1].lon)
                let current = CLLocation(latitude: points[index].lat, longitude: points[index].lon)
                cumulativeDistances[index] = cumulativeDistances[index - 1] + current.distance(from: previous)
            }
        }

        for anchorIndex in anchorIndexes {
            let anchor = points[anchorIndex]
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: anchor.lat, longitude: anchor.lon),
                latitudinalMeters: 4_000,
                longitudinalMeters: 4_000
            )
            for (query, type) in queries {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = query
                request.region = region
                guard let response = try? await MKLocalSearch(request: request).start() else { continue }
                for item in response.mapItems.prefix(3) {
                    let coordinate = item.placemark.coordinate
                    let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    let nearest = points.enumerated().min { lhs, rhs in
                        location.distance(from: CLLocation(latitude: lhs.element.lat, longitude: lhs.element.lon)) <
                        location.distance(from: CLLocation(latitude: rhs.element.lat, longitude: rhs.element.lon))
                    }
                    guard let nearest else { continue }
                    let distance = location.distance(from: CLLocation(latitude: nearest.element.lat, longitude: nearest.element.lon))
                    guard distance <= 1_000 else { continue }
                    let name = item.name ?? query
                    let key = "\(type)-\(name)-\(String(format: "%.4f", coordinate.latitude))-\(String(format: "%.4f", coordinate.longitude))"
                    let isDuplicate = results.contains { existing in
                        guard existing.type == type, existing.name == name else { return false }
                        return location.distance(from: CLLocation(latitude: existing.latitude, longitude: existing.longitude)) < 1_500
                    }
                    guard !isDuplicate else { continue }
                    results.append(DiscoveredRoutePOI(
                        id: key,
                        type: type,
                        name: name,
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude,
                        distanceAlongRouteM: nearest.element.distance ?? cumulativeDistances[nearest.offset],
                        distanceFromRouteM: distance
                    ))
                }
            }
        }
        let discovered = Array(results.sorted { ($0.distanceAlongRouteM ?? 0) < ($1.distanceAlongRouteM ?? 0) }.prefix(12))
        discoveredPOIs = discovered
        if Self.discoveredPOICache.count >= 30, let evictedKey = Self.discoveredPOICache.keys.first {
            Self.discoveredPOICache.removeValue(forKey: evictedKey)
        }
        Self.discoveredPOICache[trackID] = discovered
    }

    func confirmDiscoveredPOIs(trackID: String, token: String) async {
        guard !discoveredPOIs.isEmpty else { return }
        isSavingPOIs = true
        errorMessage = nil
        poiErrorKind = nil
        let inputs = discoveredPOIs.map {
            RoutePOIInput(
                type: $0.type,
                name: $0.name,
                latitude: $0.latitude,
                longitude: $0.longitude,
                distanceAlongRouteM: $0.distanceAlongRouteM,
                distanceFromRouteM: $0.distanceFromRouteM,
                source: "apple_maps"
            )
        }
        do {
            let saved: [RoutePOI] = try await APIClient.shared.request(
                "/tracks/\(trackID)/pois",
                method: "POST",
                body: inputs,
                token: token
            )
            pois = saved
            discoveredPOIs = []
            Self.discoveredPOICache.removeValue(forKey: trackID)
        } catch {
            poiErrorKind = .saving
            errorMessage = "设施确认失败，请稍后重试。"
        }
        isSavingPOIs = false
    }

    func retryPOIs(trackID: String, token: String?) async {
        if poiErrorKind == .saving, let token {
            await confirmDiscoveredPOIs(trackID: trackID, token: token)
        } else {
            await refreshPOIs(trackID: trackID)
        }
    }

    func loadActivityMatches(activityID: String, token: String) async {
        activityMatches = (try? await APIClient.shared.request(
            "/tracks/activity/\(activityID)/matches",
            token: token
        )) ?? []
    }

    private func optionalRequest<Response: Decodable>(_ path: String, token: String? = nil) async -> Response? {
        try? await APIClient.shared.request(path, token: token)
    }
}

extension RouteAnalysis {
    var routeTypeDisplay: String {
        switch routeType {
        case "loop": return "环线"
        case "near_loop": return "近似环线"
        case "point_to_point": return "点到点"
        default: return "待识别"
        }
    }

    var estimatedDurationDisplay: String {
        guard let minimum = estimatedDurationMin, let maximum = estimatedDurationMax else { return "待估算" }
        return "\(Self.duration(minimum))–\(Self.duration(maximum))"
    }

    private static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder) 分" }
        if remainder == 0 { return "\(hours) 小时" }
        return "\(hours) 小时 \(remainder) 分"
    }
}
