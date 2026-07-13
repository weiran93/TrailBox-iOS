import Foundation

enum DepartureRiskLevel: String, Codable, Equatable {
    case regular
    case attention
    case high

    var title: String {
        switch self {
        case .regular: return "常规准备"
        case .attention: return "需要留意"
        case .high: return "风险较高"
        }
    }
}

struct DepartureChecklistItem: Codable, Identifiable, Equatable {
    let id: UUID
    let key: String
    let title: String
    let detail: String?
    let systemImage: String
    var isCompleted: Bool
}

struct DeparturePlan: Codable, Identifiable, Equatable {
    let id: UUID
    let trackID: String
    let routeName: String
    let city: String?
    let distanceM: Double
    let elevationGainM: Double
    var plannedStart: Date
    let estimatedDurationMin: Int?
    let estimatedDurationMax: Int?
    let sunsetHour: Int?
    let sunsetMinute: Int?
    let weatherDate: Date?
    let weatherSummary: String
    let weatherUpdatedAt: Date?
    let riskLevel: DepartureRiskLevel
    let riskSummary: String
    let facilitySummary: String
    let sourceSummary: String
    var checklist: [DepartureChecklistItem]
    let createdAt: Date
    var updatedAt: Date

    var completedItemCount: Int { checklist.filter(\.isCompleted).count }
    var progress: Double {
        guard !checklist.isEmpty else { return 0 }
        return Double(completedItemCount) / Double(checklist.count)
    }

    var expectedFinishStart: Date? {
        estimatedDurationMin.flatMap { Calendar.current.date(byAdding: .minute, value: $0, to: plannedStart) }
    }

    var expectedFinishEnd: Date? {
        estimatedDurationMax.flatMap { Calendar.current.date(byAdding: .minute, value: $0, to: plannedStart) }
    }

    var sunsetOnPlannedDay: Date? {
        guard let sunsetHour, let sunsetMinute else { return nil }
        return Calendar.current.date(bySettingHour: sunsetHour, minute: sunsetMinute, second: 0, of: plannedStart)
    }

    var latestSafeStart: Date? {
        guard let sunset = sunsetOnPlannedDay, let maximum = estimatedDurationMax else { return nil }
        return Calendar.current.date(byAdding: .minute, value: -(maximum + 60), to: sunset)
    }

    var startsAfterSafeTime: Bool {
        guard let latestSafeStart else { return false }
        return plannedStart > latestSafeStart
    }
}

@MainActor
final class DeparturePlanStore: ObservableObject {
    @Published private(set) var plans: [DeparturePlan] = []
    private var activeUserID: Int?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func activate(userID: Int?) {
        guard activeUserID != userID else { return }
        activeUserID = userID
        guard let userID,
              let data = defaults.data(forKey: storageKey(userID)),
              let decoded = try? JSONDecoder().decode([DeparturePlan].self, from: data) else {
            plans = []
            return
        }
        plans = decoded.sorted { $0.plannedStart < $1.plannedStart }
    }

    func plan(id: UUID) -> DeparturePlan? {
        plans.first { $0.id == id }
    }

    func plan(for trackID: String) -> DeparturePlan? {
        plans.first { $0.trackID == trackID }
    }

    func upsert(_ plan: DeparturePlan) {
        guard activeUserID != nil else { return }
        var updated = plan
        updated.updatedAt = Date()
        if let index = plans.firstIndex(where: { $0.id == updated.id }) {
            plans[index] = updated
        } else {
            plans.append(updated)
        }
        plans.sort { $0.plannedStart < $1.plannedStart }
        persist()
    }

    func delete(id: UUID) {
        plans.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        guard let activeUserID,
              let data = try? JSONEncoder().encode(plans) else { return }
        defaults.set(data, forKey: storageKey(activeUserID))
    }

    private func storageKey(_ userID: Int) -> String {
        "trailbox.departure-plans.user-\(userID)"
    }
}

enum DeparturePlanFactory {
    static func make(
        track: Track,
        analysis: RouteAnalysis?,
        personalFit: RoutePersonalFit?,
        weather: RouteWeather?,
        conditions: [RouteCondition],
        pois: [RoutePOI],
        discoveredPOICount: Int,
        existing: DeparturePlan?
    ) -> DeparturePlan {
        let now = Date()
        let baseStart = existing?.plannedStart ?? nextMorning(from: now)
        let weatherIndex = forecastIndex(for: baseStart, weather: weather)
        let sunset = weather?.daily.sunset?[safe: weatherIndex]
        let sunsetComponents = sunset.flatMap(timeComponents)
        let minimum = personalFit?.estimatedDurationMin ?? analysis?.estimatedDurationMin
        let maximum = personalFit?.estimatedDurationMax ?? analysis?.estimatedDurationMax
        let recommendedStart = existing?.plannedStart ?? adjustedStart(
            baseStart,
            sunsetHour: sunsetComponents?.hour,
            sunsetMinute: sunsetComponents?.minute,
            maximumDuration: maximum
        )

        let rainProbability = weather?.daily.precipitationProbabilityMax?[safe: weatherIndex]
        let wind = weather?.daily.windSpeedMax?[safe: weatherIndex] ?? weather?.current.windGusts
        let warningCondition = conditions.first { $0.severity == "warning" }
        let verifiedCount = pois.filter { $0.status == "verified" }.count
        let mapCount = pois.filter { $0.status != "verified" }.count + discoveredPOICount
        let risk = riskSummary(
            analysis: analysis,
            warningCondition: warningCondition,
            rainProbability: rainProbability,
            wind: wind,
            verifiedPOICount: verifiedCount,
            mapPOICount: mapCount,
            maximumDuration: maximum
        )

        let weatherSummary = weatherSummary(
            weather: weather,
            index: weatherIndex,
            rainProbability: rainProbability,
            wind: wind
        )
        let facilitySummary = facilitySummary(verifiedCount: verifiedCount, mapCount: mapCount)
        let checklist = checklist(
            analysis: analysis,
            warningCondition: warningCondition,
            rainProbability: rainProbability,
            wind: wind,
            verifiedPOICount: verifiedCount,
            mapPOICount: mapCount,
            existing: existing
        )

        var sources: [String] = ["基础轨迹"]
        if analysis != nil { sources.append("路线分析") }
        if personalFit != nil { sources.append("个人能力") }
        if weather != nil { sources.append("动态天气") }
        if !conditions.isEmpty { sources.append("跑友路况") }
        if !pois.isEmpty || discoveredPOICount > 0 { sources.append("设施信息") }

        return DeparturePlan(
            id: existing?.id ?? UUID(),
            trackID: track.id,
            routeName: track.name,
            city: track.city,
            distanceM: track.distanceM,
            elevationGainM: track.elevationGainM,
            plannedStart: recommendedStart,
            estimatedDurationMin: minimum,
            estimatedDurationMax: maximum,
            sunsetHour: sunsetComponents?.hour,
            sunsetMinute: sunsetComponents?.minute,
            weatherDate: weatherDate(weather, index: weatherIndex),
            weatherSummary: weatherSummary,
            weatherUpdatedAt: weather?.updatedAt,
            riskLevel: risk.level,
            riskSummary: risk.summary,
            facilitySummary: facilitySummary,
            sourceSummary: sources.joined(separator: "、"),
            checklist: checklist,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
    }

    private static func nextMorning(from date: Date) -> Date {
        let calendar = Calendar.current
        let today = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: date) ?? date
        if today > date.addingTimeInterval(30 * 60) { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? date.addingTimeInterval(24 * 60 * 60)
    }

    private static func adjustedStart(
        _ base: Date,
        sunsetHour: Int?,
        sunsetMinute: Int?,
        maximumDuration: Int?
    ) -> Date {
        guard let sunsetHour, let sunsetMinute, let maximumDuration,
              let sunset = Calendar.current.date(bySettingHour: sunsetHour, minute: sunsetMinute, second: 0, of: base),
              let latest = Calendar.current.date(byAdding: .minute, value: -(maximumDuration + 60), to: sunset) else {
            return base
        }
        guard latest > Date().addingTimeInterval(30 * 60) else { return base }
        return min(base, latest)
    }

    private static func forecastIndex(for date: Date, weather: RouteWeather?) -> Int {
        guard let days = weather?.daily.time, !days.isEmpty else { return 0 }
        let target = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return days.firstIndex { value in
            guard let day = dayDate(value) else { return false }
            return Calendar.current.dateComponents([.year, .month, .day], from: day) == target
        } ?? 0
    }

    private static func weatherDate(_ weather: RouteWeather?, index: Int) -> Date? {
        weather?.daily.time?[safe: index].flatMap(dayDate)
    }

    private static func dayDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(value.prefix(10)))
    }

    private static func timeComponents(_ value: String) -> (hour: Int, minute: Int)? {
        let time = value.split(separator: "T").last.map(String.init) ?? value
        let values = time.split(separator: ":").compactMap { Int($0) }
        guard values.count >= 2 else { return nil }
        return (values[0], values[1])
    }

    private static func weatherSummary(
        weather: RouteWeather?,
        index: Int,
        rainProbability: Int?,
        wind: Double?
    ) -> String {
        guard let weather else { return "动态天气暂不可用，出发前请自行确认。" }
        var parts: [String] = []
        if let minimum = weather.daily.temperatureMin?[safe: index],
           let maximum = weather.daily.temperatureMax?[safe: index] {
            parts.append("\(Int(minimum.rounded()))–\(Int(maximum.rounded()))°")
        } else if let temperature = weather.current.temperature {
            parts.append("当前 \(Int(temperature.rounded()))°")
        }
        if let rainProbability { parts.append("降雨 \(rainProbability)%") }
        if let wind { parts.append("最大风速 \(Int(wind.rounded())) km/h") }
        return parts.isEmpty ? "已获取路线附近动态天气。" : parts.joined(separator: " · ")
    }

    private static func facilitySummary(verifiedCount: Int, mapCount: Int) -> String {
        if verifiedCount > 0 {
            return "有 \(verifiedCount) 处跑友确认设施，仍建议准备基础补给。"
        }
        if mapCount > 0 {
            return "发现 \(mapCount) 处地图设施，补水与营业情况尚未核实。"
        }
        return "沿途设施尚未核实，请按无补给条件准备。"
    }

    private static func riskSummary(
        analysis: RouteAnalysis?,
        warningCondition: RouteCondition?,
        rainProbability: Int?,
        wind: Double?,
        verifiedPOICount: Int,
        mapPOICount: Int,
        maximumDuration: Int?
    ) -> (level: DepartureRiskLevel, summary: String) {
        if let warningCondition {
            if let description = warningCondition.description, !description.isEmpty {
                return (.high, description)
            }
            return (.high, "近期有\(conditionTitle(warningCondition.conditionType))反馈，出发前请再次确认。")
        }
        if let rainProbability, rainProbability >= 60 {
            return (.high, "降雨概率较高，注意湿滑、失温和能见度变化。")
        }
        if let wind, wind >= 55 {
            return (.high, "风力较强，山脊和其他暴露路段需要谨慎通过。")
        }
        if analysis?.difficultyScore ?? 0 >= 80 || (maximumDuration ?? 0) >= 480 {
            return (.attention, "路线强度或预计耗时较高，请优先确认体力、照明和补给。")
        }
        if verifiedPOICount == 0, mapPOICount > 0 {
            return (.attention, "沿途设施来自地图检索，尚未经过跑友确认。")
        }
        return (.regular, "当前没有突出风险信息，仍建议出发前复查天气和路况。")
    }

    private static func checklist(
        analysis: RouteAnalysis?,
        warningCondition: RouteCondition?,
        rainProbability: Int?,
        wind: Double?,
        verifiedPOICount: Int,
        mapPOICount: Int,
        existing: DeparturePlan?
    ) -> [DepartureChecklistItem] {
        func item(_ key: String, _ title: String, _ detail: String? = nil, _ image: String) -> DepartureChecklistItem {
            let previous = existing?.checklist.first { $0.key == key }
            return DepartureChecklistItem(
                id: previous?.id ?? UUID(),
                key: key,
                title: title,
                detail: detail,
                systemImage: image,
                isCompleted: previous?.isCompleted ?? false
            )
        }

        var items: [DepartureChecklistItem] = [
            item("offline-track", "下载离线轨迹", "弱网环境下仍可查看路线", "arrow.down.circle.fill")
        ]
        if let water = analysis?.preparation?.recommendedWaterL {
            items.append(item("water", "携带至少 \(String(format: "%.1f", water)) L 饮水", nil, "drop.fill"))
        } else {
            items.append(item("water", "按无补给条件准备饮水", nil, "drop.fill"))
        }
        if let count = analysis?.preparation?.recommendedSupplyCount, count > 0 {
            items.append(item("supplies", "准备 \(count) 次补给", "包含备用能量与电解质", "takeoutbag.and.cup.and.straw.fill"))
        }

        var equipmentKeys = Set<String>()
        for equipment in analysis?.preparation?.equipment.prefix(5) ?? [] {
            let key = "equipment-\(equipment)"
            equipmentKeys.insert(key)
            items.append(item(key, equipment, nil, "backpack.fill"))
        }
        if analysis?.preparation?.headlampRecommended == true,
           !equipmentKeys.contains(where: { $0.contains("头灯") }) {
            items.append(item("headlamp", "头灯与备用电量", nil, "flashlight.on.fill"))
        }
        if let rainProbability, rainProbability >= 40 {
            items.append(item("rain", "准备防雨与保暖层", "预计降雨概率 \(rainProbability)%", "cloud.rain.fill"))
        }
        if let wind, wind >= 45 {
            items.append(item("wind", "检查防风层和帽子固定", "预计最大风速约 \(Int(wind.rounded())) km/h", "wind"))
        }
        if warningCondition != nil {
            items.append(item("condition", "出发前复查近期路况", nil, "exclamationmark.triangle.fill"))
        }
        if verifiedPOICount == 0 {
            items.append(item(
                "facilities",
                mapPOICount > 0 ? "核实地图设施的营业与可用情况" : "按沿途无可靠设施准备",
                nil,
                "mappin.and.ellipse"
            ))
        }
        items.append(item("share", "向同行或家人分享路线", "同步预计返回时间和应急联系方式", "person.2.fill"))
        return items
    }

    private static func conditionTitle(_ type: String) -> String {
        switch type {
        case "closure": return "封路"
        case "construction": return "施工"
        case "snow": return "积雪"
        case "mud": return "泥泞"
        case "supply": return "补给变化"
        case "signal": return "信号情况"
        default: return "路线风险"
        }
    }
}

enum DeparturePlanFormat {
    static func dayAndTime(_ date: Date) -> String {
        date.formatted(.dateTime.month().day().weekday(.abbreviated).hour().minute())
    }

    static func time(_ date: Date?) -> String {
        date?.formatted(.dateTime.hour().minute()) ?? "待估算"
    }

    static func duration(minimum: Int?, maximum: Int?) -> String {
        guard let minimum, let maximum else { return "待估算" }
        return "\(minutes(minimum))–\(minutes(maximum))"
    }

    static func finishRange(_ plan: DeparturePlan) -> String {
        guard let start = plan.expectedFinishStart, let end = plan.expectedFinishEnd else { return "待估算" }
        return "\(time(start))–\(time(end))"
    }

    static func updated(_ date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(.dateTime.month().day().hour().minute())
    }

    private static func minutes(_ value: Int) -> String {
        if value < 60 { return "\(value)分" }
        let hours = value / 60
        let minutes = value % 60
        return minutes == 0 ? "\(hours)小时" : "\(hours)小时\(minutes)分"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
