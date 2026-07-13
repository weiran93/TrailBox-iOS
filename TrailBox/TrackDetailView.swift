import MapKit
import SwiftUI
import Charts
import AVFoundation
import Speech

private struct RouteMetrics {
    struct GradeSample: Identifiable {
        let id: Int
        let distanceM: Double
        let grade: Double

        var category: GradeCategory {
            if grade > 3 { return .climb }
            if grade < -3 { return .descent }
            return .flat
        }
    }

    struct GradeSegment: Identifiable {
        let id: Int
        let category: GradeCategory
        let samples: [GradeSample]
    }

    enum GradeCategory: String, CaseIterable {
        case climb, descent, flat

        var title: String { switch self { case .climb: "上坡"; case .descent: "下坡"; case .flat: "平路" } }
        var color: Color {
            switch self {
            case .climb: TrailBoxColor.primary
            case .descent: TrailBoxColor.warning
            case .flat: TrailBoxColor.stone
            }
        }
    }

    let elevationRange: Double?
    let maximumGrade: Double?
    let averageGrade: Double?
    let difficulty: String?
    let gradeSamples: [GradeSample]

    var gradeSegments: [GradeSegment] {
        let maximumSampleCount = 180
        let step = max(1, Int(ceil(Double(gradeSamples.count) / Double(maximumSampleCount))))
        var displaySamples = gradeSamples.enumerated().compactMap { index, sample in
            index.isMultiple(of: step) ? sample : nil
        }
        if let last = gradeSamples.last, displaySamples.last?.id != last.id {
            displaySamples.append(last)
        }
        for extreme in [gradeSamples.max(by: { $0.grade < $1.grade }), gradeSamples.min(by: { $0.grade < $1.grade })].compactMap({ $0 }) {
            if !displaySamples.contains(where: { $0.id == extreme.id }) {
                displaySamples.append(extreme)
            }
        }
        displaySamples.sort { $0.id < $1.id }
        guard let first = displaySamples.first else { return [] }
        var segments: [GradeSegment] = []
        var category = first.category
        var samples = [first]

        for sample in displaySamples.dropFirst() {
            if sample.category == category {
                samples.append(sample)
            } else {
                segments.append(GradeSegment(id: segments.count, category: category, samples: samples))
                samples = [samples.last!, sample]
                category = sample.category
            }
        }
        segments.append(GradeSegment(id: segments.count, category: category, samples: samples))
        return segments
    }

    init(points: [TrackPoint]) {
        let validPoints = points.compactMap { point -> TrackPoint? in point.altitude == nil ? nil : point }
        guard validPoints.count > 1 else {
            elevationRange = nil; maximumGrade = nil; averageGrade = nil; difficulty = nil; gradeSamples = []
            return
        }

        let altitudes = validPoints.compactMap(\.altitude)
        elevationRange = altitudes.max().flatMap { maximum in altitudes.min().map { maximum - $0 } }

        var distances = [0.0]
        for index in 1..<validPoints.count {
            let previous = CLLocation(latitude: validPoints[index - 1].lat, longitude: validPoints[index - 1].lon)
            let current = CLLocation(latitude: validPoints[index].lat, longitude: validPoints[index].lon)
            distances.append(distances[index - 1] + current.distance(from: previous))
        }

        var grades: [Double] = []
        for index in validPoints.indices {
            let centerDistance = distances[index]
            var startIndex = index
            var endIndex = index
            while startIndex > 0 && centerDistance - distances[startIndex] < 100 { startIndex -= 1 }
            while endIndex < validPoints.count - 1 && distances[endIndex] - centerDistance < 100 { endIndex += 1 }

            var gradeSum = 0.0
            var gradeCount = 0
            for segmentIndex in (startIndex + 1)...endIndex {
                let segmentDistance = distances[segmentIndex] - distances[segmentIndex - 1]
                guard segmentDistance >= 3,
                      let currentAltitude = validPoints[segmentIndex].altitude,
                      let previousAltitude = validPoints[segmentIndex - 1].altitude else { continue }
                gradeSum += (currentAltitude - previousAltitude) / segmentDistance * 100
                gradeCount += 1
            }
            grades.append(min(35, max(-35, gradeCount > 0 ? gradeSum / Double(gradeCount) : 0)))
        }

        gradeSamples = zip(distances, grades).enumerated().map { GradeSample(id: $0.offset, distanceM: $0.element.0, grade: $0.element.1) }
        maximumGrade = grades.dropFirst().map(\.magnitude).max()
        averageGrade = grades.isEmpty ? nil : grades.reduce(0, +) / Double(grades.count)

        let totalDistanceKm = (distances.last ?? 0) / 1_000
        let elevationGain = zip(altitudes.dropFirst(), altitudes).reduce(0.0) { $0 + max(0, $1.0 - $1.1) }
        guard totalDistanceKm > 0 else { difficulty = nil; return }
        let climbDensity = elevationGain / totalDistanceKm
        if totalDistanceKm >= 50 || climbDensity >= 140 { difficulty = "极难" }
        else if totalDistanceKm >= 30 || climbDensity >= 90 { difficulty = "困难" }
        else if totalDistanceKm >= 15 || climbDensity >= 50 { difficulty = "中等" }
        else { difficulty = "简单" }
    }
}

private struct NavigationDestination: Identifiable {
    let id = UUID()
    let point: TrackPoint
    let name: String
}

private enum NavigationProvider: Identifiable {
    case apple, amap(URL), baidu(URL), tencent(URL), google(URL)

    var id: String { title }
    var title: String { switch self { case .apple: "苹果地图"; case .amap: "高德地图"; case .baidu: "百度地图"; case .tencent: "腾讯地图"; case .google: "Google Maps" } }
    var url: URL? { switch self { case .apple: nil; case .amap(let url), .baidu(let url), .tencent(let url), .google(let url): url } }
}

private struct NavigationProviderSheet: View {
    let destinationName: String
    let providers: [NavigationProvider]
    let selectProvider: (NavigationProvider) -> Void

    var body: some View {
        if #available(iOS 16.4, *) {
            content.presentationCornerRadius(24)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Text("导航到「\(destinationName)」")
                .font(.subheadline)
                .foregroundStyle(TrailBoxColor.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)

            ForEach(providers) { provider in
                Button { selectProvider(provider) } label: {
                    HStack {
                        Text(provider.title).font(.body.weight(.medium)).foregroundStyle(TrailBoxColor.text)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(TrailBoxColor.secondaryText)
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 56)
                }
                .overlay(alignment: .bottom) { Divider().padding(.leading, 20) }
            }
        }
        .presentationDetents([.height(CGFloat(54 + providers.count * 56))])
        .presentationDragIndicator(.visible)
    }
}

private struct RouteStartActionSheet: View {
    let routeName: String
    let decisionTitle: String
    let decisionLevel: String
    let decisionColor: Color
    let planTitle: String
    let isPlanLoading: Bool
    let isSaved: Bool
    let isSaving: Bool
    let navigateToStart: () -> Void
    let openPlan: () -> Void
    let exportGPX: () -> Void
    let toggleSaved: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(TrailBoxColor.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("准备出发")
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                                .foregroundStyle(TrailBoxColor.text)
                            Text(routeName)
                                .font(.subheadline)
                                .foregroundStyle(TrailBoxColor.secondaryText)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 7) {
                        Circle().fill(decisionColor).frame(width: 7, height: 7)
                        Text("\(decisionLevel) · \(decisionTitle)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(decisionColor)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(decisionColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }

                VStack(spacing: 10) {
                    actionButton(
                        title: "导航到起点",
                        subtitle: "选择苹果地图、高德等导航应用",
                        systemImage: "location.fill",
                        color: TrailBoxColor.primary,
                        action: navigateToStart
                    )
                    actionButton(
                        title: planTitle,
                        subtitle: "结合天气、日落、补给生成清单",
                        systemImage: "calendar.badge.checkmark",
                        color: TrailBoxColor.sky,
                        isLoading: isPlanLoading,
                        action: openPlan
                    )
                    actionButton(
                        title: "导出 GPX",
                        subtitle: "发送到手表、导航设备或其他应用",
                        systemImage: "square.and.arrow.down",
                        color: TrailBoxColor.moss,
                        action: exportGPX
                    )
                    actionButton(
                        title: isSaved ? "取消收藏路线" : "收藏路线",
                        subtitle: isSaved ? "从我的收藏路线中移除" : "稍后在我的收藏路线中查看",
                        systemImage: isSaved ? "bookmark.slash.fill" : "bookmark.fill",
                        color: TrailBoxColor.warning,
                        isLoading: isSaving,
                        action: toggleSaved
                    )
                }

                Text("导航和 GPX 导出无需登录；出发计划与收藏会保存到你的账号。")
                    .font(.caption2)
                    .foregroundStyle(TrailBoxColor.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .background(TrailPageBackground())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func actionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        color: Color,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Group {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(color)
                    }
                }
                .frame(width: 40, height: 40)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(TrailBoxColor.text)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(TrailBoxColor.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TrailBoxColor.secondaryText)
            }
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(TrailBoxColor.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(TrailBoxColor.border, lineWidth: 0.75))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

private extension CharacterSet {
    static let urlQueryValueAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=?+"))
}

private func wgs84ToGCJ02(latitude: Double, longitude: Double) -> (latitude: Double, longitude: Double) {
    guard (72.004...137.8347).contains(longitude), (0.8293...55.8271).contains(latitude) else { return (latitude, longitude) }
    let deltaLatitude = transformLatitude(longitude - 105, latitude - 35)
    let deltaLongitude = transformLongitude(longitude - 105, latitude - 35)
    let radians = latitude * .pi / 180
    let eccentricity = 0.00669342162296594323
    let magic = 1 - eccentricity * pow(sin(radians), 2)
    let sqrtMagic = sqrt(magic)
    return (
        latitude + deltaLatitude * 180 / ((6_335_552.717000426 * (1 - eccentricity)) / (magic * sqrtMagic) * .pi),
        longitude + deltaLongitude * 180 / (6_378_245 / sqrtMagic * cos(radians) * .pi)
    )
}

private func gcj02ToBD09(latitude: Double, longitude: Double) -> (latitude: Double, longitude: Double) {
    let z = sqrt(longitude * longitude + latitude * latitude) + 0.00002 * sin(latitude * .pi * 3000 / 180)
    let theta = atan2(latitude, longitude) + 0.000003 * cos(longitude * .pi * 3000 / 180)
    return (z * sin(theta) + 0.006, z * cos(theta) + 0.0065)
}

private func transformLatitude(_ longitude: Double, _ latitude: Double) -> Double {
    var value = -100 + 2 * longitude + 3 * latitude + 0.2 * latitude * latitude + 0.1 * longitude * latitude + 0.2 * sqrt(abs(longitude))
    value += (20 * sin(6 * longitude * .pi) + 20 * sin(2 * longitude * .pi)) * 2 / 3
    value += (20 * sin(latitude * .pi) + 40 * sin(latitude / 3 * .pi)) * 2 / 3
    return value + (160 * sin(latitude / 12 * .pi) + 320 * sin(latitude * .pi / 30)) * 2 / 3
}

private func transformLongitude(_ longitude: Double, _ latitude: Double) -> Double {
    var value = 300 + longitude + 2 * latitude + 0.1 * longitude * longitude + 0.1 * longitude * latitude + 0.1 * sqrt(abs(longitude))
    value += (20 * sin(6 * longitude * .pi) + 20 * sin(2 * longitude * .pi)) * 2 / 3
    value += (20 * sin(longitude * .pi) + 40 * sin(longitude / 3 * .pi)) * 2 / 3
    return value + (150 * sin(longitude / 12 * .pi) + 300 * sin(longitude / 30 * .pi)) * 2 / 3
}

@MainActor
final class TrackDetailViewModel: ObservableObject {
    enum State { case loading, content(Track), failed(String) }
    @Published var state: State = .loading
    func load(id: String, isPublic: Bool, token: String?) async {
        state = .loading
        do {
            // 如果用户已登录，优先用 /tracks/{id}，它会返回 user_id（当当前用户是贡献者时），
            // 这样公开路线的详情页也能判断是否是本人并显示删除入口。
            let path = (isPublic && token == nil) ? "/tracks/\(id)/public" : "/tracks/\(id)"
            state = .content(try await APIClient.shared.request(path, token: token))
        }
        catch { state = .failed(ErrorMessage.display(error)) }
    }
}

private enum RouteDetailSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case analysis
    case facilities
    case community
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .analysis: return "分析"
        case .facilities: return "设施"
        case .community: return "跑友"
        case .profile: return "剖面"
        }
    }
}

private struct RouteDecisionPoint: Identifiable {
    let systemImage: String
    let text: String
    let color: Color
    var id: String { "\(systemImage)-\(text)" }
}

private struct RouteDecisionSummary {
    let title: String
    let level: String
    let explanation: String
    let color: Color
    let systemImage: String
    let points: [RouteDecisionPoint]
    let sourceText: String
    let isUpdating: Bool

    var animationKey: String {
        ([title, level, explanation, sourceText] + points.map(\.text)).joined(separator: "|")
    }
}

private struct RouteTrustSummary {
    let availableCount: Int
    let totalCount: Int
    let headline: String
    let detail: String
    let color: Color
}

private struct DetailSectionTitle: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(TrailBoxColor.primaryDark)
                .frame(width: 30, height: 30)
                .background(
                    TrailBoxColor.primary.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(TrailBoxColor.text)
        }
    }
}

struct TrackDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var savedRoutes: SavedRoutesStore
    @EnvironmentObject private var departurePlans: DeparturePlanStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel = TrackDetailViewModel()
    @StateObject private var routeIntelligence = RouteIntelligenceStore()
    @StateObject private var voiceRecorder = FeelingRecorder()
    @State private var showEdit = false
    @State private var showDeleteConfirmation = false
    @State private var showDeleteSuccess = false
    @State private var shareFile: ActivityFile?
    @State private var actionError: String?
    @State private var aiAnalysis: AIAnalysis?
    @State private var isAnalyzing = false
    @State private var revealedAISectionCount = Int.max
    @State private var isVoiceGestureActive = false
    @State private var capturedVoiceText = ""
    @State private var showFullscreenMap = false
    @State private var showSharePreview = false
    @State private var showReport = false
    @State private var showRouteFeedback = false
    @State private var showStartRouteSheet = false
    @State private var navigationDestination: NavigationDestination?
    @State private var departurePlanDraft: DeparturePlan?
    @State private var selectedRouteSection: RouteDetailSection = .overview
    @Namespace private var routeSectionSelection
    let trackID: String
    let isPublicSource: Bool
    let onDeleted: (() async -> Void)?
    let onSaved: (() async -> Void)?

    init(trackID: String, isPublicSource: Bool, onDeleted: (() async -> Void)? = nil, onSaved: (() async -> Void)? = nil) {
        self.trackID = trackID
        self.isPublicSource = isPublicSource
        self.onDeleted = onDeleted
        self.onSaved = onSaved
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message): EmptyStateView(title: "加载失败", systemImage: "exclamationmark.triangle", message: message)
            case .content(let track): details(track)
            }
        }
        .background(TrailPageBackground())
        .navigationTitle(isPublicSource ? "轨迹详情" : "记录详情")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.token) { await viewModel.load(id: trackID, isPublic: isPublicSource, token: session.token) }
        .task(id: "\(trackID)-\(session.token ?? "guest")") {
            if isPublicSource {
                await routeIntelligence.load(trackID: trackID, token: session.token)
            } else if let token = session.token {
                await routeIntelligence.loadActivityMatches(activityID: trackID, token: token)
            }
        }
        .sheet(item: $navigationDestination) { destination in
            NavigationProviderSheet(
                destinationName: destination.name,
                providers: navigationProviders(for: destination),
                selectProvider: { provider in openNavigation(provider, destination: destination) }
            )
        }
        .sheet(item: $departurePlanDraft) { plan in
            NavigationStack {
                DeparturePlanView(plan: plan, dismissOnSave: true)
            }
        }
    }

    private func isOwner(of track: Track) -> Bool {
        guard let currentUserID = session.user?.id, let trackUserID = track.userID else { return false }
        return currentUserID == trackUserID
    }

    private func details(_ track: Track) -> some View {
        let metrics = RouteMetrics(points: track.points)
        return ZStack(alignment: .top) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                        if isPublicSource {
                            publicRouteHero(track)
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        } else {
                            activityHero(track)
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                            activityOverviewCard(track)
                                .padding(.horizontal, 16)
                        }
                        if !isPublicSource {
                            ZStack(alignment: .topTrailing) {
                                TrackMap(points: track.points, pois: routeMapPOIs)
                                    .frame(height: 280)
                                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                                            .stroke(.white.opacity(0.68), lineWidth: 0.8)
                                    )
                                Button { showFullscreenMap = true } label: {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(TrailBoxColor.text)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .trailBoxGlass(in: Circle())
                                .padding(12)
                            }
                            .padding(.horizontal, 16)
                            .shadow(color: TrailBoxColor.primaryDark.opacity(0.12), radius: 14, y: 7)
                        }
                        if !isPublicSource, let start = track.points.first, let end = track.points.last {
                            HStack(spacing: 12) {
                                endpointButton(title: "起点", point: start, trackName: track.name, color: TrailBoxColor.primaryDark)
                                endpointButton(title: "终点", point: end, trackName: track.name, color: TrailBoxColor.danger)
                            }
                            .padding(.horizontal, 16)
                        }

                        if !isPublicSource, !routeIntelligence.activityMatches.isEmpty {
                            activityMatchesCard
                                .padding(.horizontal, 16)
                        }

                        if !isPublicSource {
                            analysisCard(track)
                        }

                        if isPublicSource {
                            routeGuideCard(track, metrics: metrics)
                                .padding(.horizontal, 16)
                                .id(RouteDetailSection.overview)

                            Section {
                                Color.clear.frame(height: 0).id(RouteDetailSection.analysis)
                                routeIntelligenceSections(track)

                                Color.clear.frame(height: 0).id(RouteDetailSection.profile)
                                ElevationChart(points: track.points, title: "海拔剖面")
                                    .padding(.horizontal, 16)
                                GradeChart(metrics: metrics)
                                    .padding(.horizontal, 16)
                                trackMetadataSection(track)
                                routeRecommendationSection(track)
                            } header: {
                                routeSectionNavigator(scrollProxy)
                                    .zIndex(3)
                            }
                        } else {
                            ElevationChart(points: track.points, title: "海拔剖面")
                                .padding(.horizontal, 16)
                            GradeChart(metrics: metrics)
                                .padding(.horizontal, 16)
                            ActivityCharts(points: track.points)
                                .padding(.horizontal, 16)
                            trackMetadataSection(track)
                        }
                    }
                    .padding(.bottom, 24)
                }
                .refreshable {
                    if isPublicSource {
                        await routeIntelligence.load(trackID: track.id, token: session.token)
                    } else if let token = session.token {
                        await routeIntelligence.loadActivityMatches(activityID: track.id, token: token)
                    }
                }
            }
            if isVoiceGestureActive && voiceRecorder.isRecording {
                VoiceTranscriptBubble(transcript: voiceRecorder.transcript)
                    .padding(.horizontal, 32)
                    .padding(.top, 112)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isPublicSource {
                    Button {
                        guard let token = session.token else {
                            session.requireAuthentication()
                            return
                        }
                        Task { await savedRoutes.toggle(trackID: track.id, token: token) }
                    } label: {
                        if savedRoutes.savingTrackIDs.contains(track.id) {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: savedRoutes.isSaved(track.id) ? "bookmark.fill" : "bookmark")
                        }
                    }
                    .disabled(savedRoutes.savingTrackIDs.contains(track.id))
                    .accessibilityLabel(savedRoutes.savingTrackIDs.contains(track.id) ? "正在更新收藏" : (savedRoutes.isSaved(track.id) ? "取消收藏路线" : "收藏路线"))
                }
                if !isPublicSource {
                    Menu {
                        Button("编辑记录") { showEdit = true }
                        Button("删除记录", role: .destructive) { showDeleteConfirmation = true }
                    } label: { Image(systemName: "ellipsis") }
                } else {
                    Menu {
                        Button {
                            Task { await routeIntelligence.load(trackID: track.id, token: session.token) }
                        } label: {
                            Label("刷新路线情报", systemImage: "arrow.clockwise")
                        }
                        .disabled(routeIntelligence.isLoading)
                        Divider()
                        if isOwner(of: track) {
                            Button("编辑路线") { showEdit = true }
                            Button("删除路线", role: .destructive) { showDeleteConfirmation = true }
                        } else {
                            Button("举报路线", role: .destructive) {
                                guard session.isAuthenticated else { session.requireAuthentication(); return }
                                showReport = true
                            }
                            if let publicID = track.contributorPublicID, track.showContributor {
                                Button("屏蔽该贡献者", role: .destructive) { blockContributor(publicID) }
                            }
                        }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            EditTrackView(track: track) {
                Task {
                    await viewModel.load(id: trackID, isPublic: isPublicSource, token: session.token)
                    await onSaved?()
                }
            }
        }
        .sheet(item: $shareFile) { ActivityFileView(url: $0.url) }
        .alert(isPublicSource ? "删除这条路线？" : "删除这条记录？", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { delete(track) }
        } message: { Text("删除后不可恢复。") }
        .alert("删除成功", isPresented: $showDeleteSuccess) {
            Button("确定") { finishDeleting() }
        } message: {
            Text("该记录已删除。")
        }
        .alert("操作失败", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) { Button("确定", role: .cancel) {} } message: { Text(actionError ?? "") }
        .sheet(isPresented: $showFullscreenMap) { NavigationStack { TrackMap(points: track.points, pois: routeMapPOIs).ignoresSafeArea(edges: .bottom).navigationTitle(track.name).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { showFullscreenMap = false } } } } }
        .sheet(isPresented: $showSharePreview) { SharePreviewView(source: isPublicSource ? .exploreRoute : .activity, data: RouteShareData.make(from: track, source: isPublicSource ? .exploreRoute : .activity)) }
        .sheet(isPresented: $showReport) { ReportTrackView(trackID: track.id) }
        .sheet(isPresented: $showRouteFeedback) {
            RouteFeedbackView(trackID: track.id) {
                await routeIntelligence.load(trackID: track.id, token: session.token)
            }
        }
        .sheet(isPresented: $showStartRouteSheet) {
            routeStartActionSheet(track)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { detailActions(track) }
        .task(id: track.id) {
            guard isPublicSource else { return }
            await routeIntelligence.discoverNearbyPOIs(trackID: track.id, points: track.points)
        }
    }

    @ViewBuilder
    private func routeIntelligenceSections(_ track: Track) -> some View {
        if routeIntelligence.isLoadingAnalysis && routeIntelligence.analysis == nil {
            routeSkeletonCard(title: "正在生成路线分析", rows: 3)
                .padding(.horizontal, 16)
                .transition(.opacity)
        } else if routeIntelligence.analysis == nil, let message = routeIntelligence.analysisErrorMessage {
            SectionCard {
                HStack(spacing: 12) {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(TrailBoxColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("重试") {
                        Task { await routeIntelligence.refreshAnalysis(trackID: track.id, token: session.token) }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal, 16)
            .transition(.opacity)
        }

        if let fit = routeIntelligence.personalFit {
            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        DetailSectionTitle(title: "与你的能力匹配", systemImage: "figure.run.circle.fill")
                        Spacer()
                        Text("\(Int(fit.score.rounded()))%")
                            .font(.title2.weight(.heavy))
                            .foregroundStyle(fit.score >= 80 ? TrailBoxColor.primaryDark : .orange)
                    }
                    HStack(spacing: 8) {
                        Text(fit.level)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(fit.score >= 80 ? TrailBoxColor.primaryDark : .orange, in: Capsule())
                        if let minimum = fit.estimatedDurationMin, let maximum = fit.estimatedDurationMax {
                            Text("预计 \(formatMinutes(minimum))–\(formatMinutes(maximum))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TrailBoxColor.secondaryText)
                        }
                    }
                    Text(fit.reason)
                        .font(.subheadline)
                        .foregroundStyle(TrailBoxColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    sourceFootnote(fit.source)
                }
            }
            .padding(.horizontal, 16)

        }

        if let analysis = routeIntelligence.analysis {
            SectionCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        DetailSectionTitle(title: "路线分析", systemImage: "chart.line.uptrend.xyaxis")
                        Spacer()
                        Text(analysis.difficultyLevel)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(difficultyColor(analysis.difficultyScore), in: Capsule())
                    }
                    HStack(spacing: 0) {
                        intelligenceMetric(analysis.routeTypeDisplay, "路线形态")
                        intelligenceMetric(analysis.estimatedDurationDisplay, "预计用时")
                        intelligenceMetric("\(Int(analysis.difficultyScore))", "难度分")
                    }
                    Divider()
                    ForEach(analysis.features, id: \.self) { feature in
                        Label(feature, systemImage: "sparkles")
                            .font(.subheadline)
                            .foregroundStyle(TrailBoxColor.text)
                    }
                    if let start = analysis.hardestSegmentStartM, let end = analysis.hardestSegmentEndM {
                        Label(
                            "困难路段：\(DisplayFormat.distance(start))–\(DisplayFormat.distance(end))",
                            systemImage: "mountain.2.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    }
                    sourceFootnote(analysis.source)
                }
            }
            .padding(.horizontal, 16)

            if let preparation = analysis.preparation {
                SectionCard {
                    VStack(alignment: .leading, spacing: 12) {
                        DetailSectionTitle(title: "出发准备", systemImage: "backpack.fill")
                        HStack(spacing: 0) {
                            intelligenceMetric(preparation.recommendedWaterL.map { String(format: "%.1f L", $0) } ?? "-", "建议饮水")
                            intelligenceMetric(preparation.recommendedSupplyCount.map { "\($0) 次" } ?? "-", "补给次数")
                            intelligenceMetric(preparation.headlampRecommended == true ? "建议携带" : "按需携带", "头灯")
                        }
                        if !preparation.equipment.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(preparation.equipment, id: \.self) { item in
                                    Label(item, systemImage: "checkmark")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(TrailBoxColor.primaryDark)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 6)
                                        .background(TrailBoxColor.primary.opacity(0.1), in: Capsule())
                                }
                            }
                        }
                        ForEach(preparation.safetyNotes, id: \.self) { note in
                            Label(note, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        sourceFootnote("根据路线距离、爬升与预计用时自动估算")
                    }
                }
                .padding(.horizontal, 16)
            }
        }

        if routeIntelligence.analysis != nil,
           let message = routeIntelligence.analysisErrorMessage {
            routeRefreshIssue(message, systemImage: "chart.line.uptrend.xyaxis") {
                Task { await routeIntelligence.refreshAnalysis(trackID: track.id, token: session.token) }
            }
            .padding(.horizontal, 16)
        }

        if let weather = routeIntelligence.weather {
            weatherCard(weather)
                .padding(.horizontal, 16)
                .transition(.opacity)
        } else if routeIntelligence.isLoadingWeather {
            routeSkeletonCard(title: "正在获取路线天气", rows: 2)
                .padding(.horizontal, 16)
                .transition(.opacity)
        } else if let message = routeIntelligence.weatherErrorMessage {
            SectionCard {
                HStack(spacing: 12) {
                    Label(message, systemImage: "cloud.sun")
                        .font(.subheadline)
                        .foregroundStyle(TrailBoxColor.secondaryText)
                    Spacer(minLength: 8)
                    Button("重试") {
                        Task { await routeIntelligence.refreshWeather(trackID: track.id) }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal, 16)
            .transition(.opacity)
        }

        if routeIntelligence.weather != nil,
           let message = routeIntelligence.weatherErrorMessage {
            routeRefreshIssue(message, systemImage: "cloud.sun") {
                Task { await routeIntelligence.refreshWeather(trackID: track.id) }
            }
            .padding(.horizontal, 16)
        }

        Color.clear.frame(height: 0).id(RouteDetailSection.facilities)
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                DetailSectionTitle(title: "沿途设施", systemImage: "mappin.and.ellipse")
                if (routeIntelligence.isLoadingPOIs || routeIntelligence.isDiscoveringPOIs)
                    && routeIntelligence.pois.isEmpty
                    && routeIntelligence.discoveredPOIs.isEmpty {
                    RouteSkeletonRows(count: 3)
                        .transition(.opacity)
                } else if routeIntelligence.pois.isEmpty && routeIntelligence.discoveredPOIs.isEmpty {
                    Label("路线附近暂未找到停车、厕所、补给或医院信息", systemImage: "mappin.slash")
                        .font(.subheadline)
                        .foregroundStyle(TrailBoxColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                } else {
                    ForEach(routeIntelligence.pois.prefix(6)) { poi in
                        HStack(spacing: 10) {
                            Image(systemName: poiIcon(poi.type))
                                .foregroundStyle(TrailBoxColor.primaryDark)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(poi.name).font(.subheadline.weight(.semibold))
                                Text(poi.distanceAlongRouteM.map { "路线第 \(DisplayFormat.distance($0))" } ?? "路线附近")
                                    .font(.caption)
                                    .foregroundStyle(TrailBoxColor.secondaryText)
                            }
                            Spacer()
                            Text(poi.status == "verified" ? "已确认" : "地图信息")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(poi.status == "verified" ? TrailBoxColor.primaryDark : TrailBoxColor.secondaryText)
                        }
                    }
                    ForEach(routeIntelligence.discoveredPOIs.prefix(max(0, 6 - routeIntelligence.pois.count))) { poi in
                        HStack(spacing: 10) {
                            Image(systemName: poiIcon(poi.type))
                                .foregroundStyle(TrailBoxColor.primaryDark)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(poi.name).font(.subheadline.weight(.semibold))
                                Text(poi.distanceAlongRouteM.map { "路线第 \(DisplayFormat.distance($0)) · 偏离 \(DisplayFormat.distance(poi.distanceFromRouteM))" } ?? "路线附近")
                                    .font(.caption)
                                    .foregroundStyle(TrailBoxColor.secondaryText)
                            }
                            Spacer()
                            Text("地图信息")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(TrailBoxColor.secondaryText)
                        }
                    }
                }
                if routeIntelligence.analysis?.canManage == true, let token = session.token, !routeIntelligence.discoveredPOIs.isEmpty {
                    Divider()
                    Button {
                        Task {
                            await routeIntelligence.confirmDiscoveredPOIs(trackID: track.id, token: token)
                        }
                    } label: {
                        HStack {
                            if routeIntelligence.isSavingPOIs {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "checkmark.seal.fill")
                            }
                            Text(routeIntelligence.isSavingPOIs ? "正在保存…" : "确认并保存这些设施")
                            Spacer()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TrailBoxColor.primaryDark)
                    }
                    .buttonStyle(.plain)
                    .disabled(routeIntelligence.isSavingPOIs)
                }
                if let message = routeIntelligence.errorMessage {
                    Divider()
                    HStack(alignment: .top, spacing: 10) {
                        Label(message, systemImage: "mappin.slash")
                            .font(.caption)
                            .foregroundStyle(TrailBoxColor.danger)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("重试") {
                            Task { await routeIntelligence.retryPOIs(trackID: track.id, token: session.token) }
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TrailBoxColor.primaryDark)
                    }
                }
                sourceFootnote("地图数据与跑友确认")
            }
        }
        .padding(.horizontal, 16)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: routeIntelligence.isDiscoveringPOIs)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: routeIntelligence.pois.count + routeIntelligence.discoveredPOIs.count)

        Color.clear.frame(height: 0).id(RouteDetailSection.community)
        if !routeIntelligence.conditions.isEmpty {
            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    DetailSectionTitle(title: "近期路况", systemImage: "exclamationmark.triangle.fill")
                    ForEach(routeIntelligence.conditions.prefix(4)) { condition in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: condition.severity == "warning" ? "exclamationmark.triangle.fill" : "info.circle.fill")
                                .foregroundStyle(condition.severity == "warning" ? .orange : TrailBoxColor.primaryDark)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(conditionTitle(condition.conditionType)).font(.subheadline.weight(.semibold))
                                if let description = condition.description {
                                    Text(description).font(.caption).foregroundStyle(TrailBoxColor.secondaryText)
                                }
                                Text("更新于 \(DisplayFormat.date(condition.observedAt))")
                                    .font(.caption2)
                                    .foregroundStyle(TrailBoxColor.secondaryText)
                            }
                        }
                    }
                    sourceFootnote("跑友近期反馈")
                }
            }
            .padding(.horizontal, 16)
        }

        if let completions = routeIntelligence.completions, completions.count > 0 {
            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        DetailSectionTitle(title: "跑友完成记录", systemImage: "checkmark.circle.fill")
                        Spacer()
                        Text("\(completions.count) 次")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(TrailBoxColor.primaryDark)
                    }
                    HStack(spacing: 0) {
                        intelligenceMetric(completions.averageDurationSec.map(DisplayFormat.duration) ?? "-", "平均用时")
                        intelligenceMetric(completions.fastestDurationSec.map(DisplayFormat.duration) ?? "-", "最快用时")
                        intelligenceMetric(completions.recent.first.map { $0.direction == "reverse" ? "反向" : "正向" } ?? "-", "最近方向")
                    }
                    sourceFootnote(completions.source)
                }
            }
            .padding(.horizontal, 16)
        }

        if let reviews = routeIntelligence.reviews, reviews.count > 0 {
            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        DetailSectionTitle(title: "跑友评价", systemImage: "star.fill")
                        Spacer()
                        Text("\(reviews.count) 条").font(.caption).foregroundStyle(TrailBoxColor.secondaryText)
                    }
                    HStack(spacing: 0) {
                        intelligenceMetric(reviewAverage(reviews, "difficulty_rating"), "难度")
                        intelligenceMetric(reviewAverage(reviews, "scenery_rating"), "风景")
                        intelligenceMetric(reviewAverage(reviews, "navigation_rating"), "导航")
                    }
                    ForEach(reviews.items.prefix(2)) { review in
                        if let comment = review.comment, !comment.isEmpty {
                            Text("“\(comment)”")
                                .font(.subheadline)
                                .foregroundStyle(TrailBoxColor.text)
                                .padding(.top, 4)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }

        SectionCard {
            Button {
                guard session.isAuthenticated else {
                    session.requireAuthentication()
                    return
                }
                showRouteFeedback = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.bubble.fill")
                        .font(.title3)
                        .foregroundStyle(TrailBoxColor.primaryDark)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("完成过这条路线？")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TrailBoxColor.text)
                        Text("反馈难度、路况和补给，帮助其他跑友")
                            .font(.caption)
                            .foregroundStyle(TrailBoxColor.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TrailBoxColor.secondaryText)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    private func routeGuideCard(_ track: Track, metrics: RouteMetrics) -> some View {
        let decision = routeDecision(for: track)
        let trust = routeTrustSummary(for: track)
        return SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    DetailSectionTitle(title: "路线说明书", systemImage: "map.fill")
                    Spacer(minLength: 8)
                    if decision.isUpdating {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("正在更新路线信息")
                    }
                    Text(decision.level)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(decision.color)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(decision.color.opacity(0.11), in: Capsule())
                }

                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: decision.systemImage)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(decision.color)
                        .frame(width: 42, height: 42)
                        .background(decision.color.opacity(0.11), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(decision.title)
                            .font(.system(size: 21, weight: .heavy, design: .rounded))
                            .foregroundStyle(TrailBoxColor.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(decision.explanation)
                            .font(.subheadline)
                            .foregroundStyle(TrailBoxColor.secondaryText)
                            .lineSpacing(2)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 0) {
                    routeSnapshotMetric(DisplayFormat.distance(track.distanceM), "距离", TrailBoxColor.text)
                    routeSnapshotMetric(DisplayFormat.elevation(track.elevationGainM), "累计爬升", TrailBoxColor.primaryDark)
                    routeSnapshotMetric(metrics.maximumGrade.map(formatGrade) ?? "-", "最大坡度", TrailBoxColor.warning)
                    routeSnapshotMetric(routeDurationText(for: track), "预计用时", TrailBoxColor.sky)
                }
                .padding(.vertical, 12)
                .background(TrailBoxColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(decision.points.dropFirst().prefix(3))) { point in
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: point.systemImage)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(point.color)
                                .frame(width: 28, height: 28)
                                .background(point.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            Text(point.text)
                                .font(.subheadline)
                                .foregroundStyle(TrailBoxColor.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(trust.color)
                        .frame(width: 36, height: 36)
                        .background(trust.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text("路线资料")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(TrailBoxColor.text)
                            Text("\(trust.availableCount)/\(trust.totalCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(trust.color)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(trust.color.opacity(0.1), in: Capsule())
                        }
                        Text(trust.headline)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TrailBoxColor.text)
                        Text(trust.detail)
                            .font(.caption2)
                            .foregroundStyle(TrailBoxColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(trust.color.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Label(routeGuideSourceText(for: track, decision: decision), systemImage: "clock.arrow.circlepath")
                    .font(.caption2)
                    .foregroundStyle(TrailBoxColor.secondaryText)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: decision.animationKey)
        .accessibilityElement(children: .contain)
    }

    private var isDeparturePlanLoading: Bool {
        routeIntelligence.isLoadingAnalysis
            || routeIntelligence.isLoadingWeather
            || routeIntelligence.isLoadingPOIs
    }

    private func routeDurationText(for track: Track) -> String {
        if let minimum = routeIntelligence.personalFit?.estimatedDurationMin ?? routeIntelligence.analysis?.estimatedDurationMin,
           let maximum = routeIntelligence.personalFit?.estimatedDurationMax ?? routeIntelligence.analysis?.estimatedDurationMax {
            return compactDurationRange(minimum: minimum, maximum: maximum)
        }

        let distanceHours = max(0, track.distanceM / 1_000) / 5.5
        let climbHours = max(0, track.elevationGainM) / 650
        let estimate = max(0.5, distanceHours + climbHours)
        let minimum = Int((estimate * 0.82 * 60 / 15).rounded() * 15)
        let maximum = max(minimum + 30, Int((estimate * 1.2 * 60 / 15).rounded() * 15))
        return compactDurationRange(minimum: minimum, maximum: maximum)
    }

    private func compactDurationRange(minimum: Int, maximum: Int) -> String {
        if maximum < 60 { return "\(minimum)–\(maximum)分" }
        let lowerHours = max(1, Int(floor(Double(minimum) / 60)))
        let upperHours = max(lowerHours + 1, Int(ceil(Double(maximum) / 60)))
        return "\(lowerHours)–\(upperHours)h"
    }

    private func routeTrustSummary(for track: Track) -> RouteTrustSummary {
        let hasTrack = track.points.count > 1
        let hasAnalysis = routeIntelligence.analysis != nil
        let hasWeather = routeIntelligence.weather != nil
        let hasFacilities = !routeIntelligence.pois.isEmpty || !routeIntelligence.discoveredPOIs.isEmpty
        let hasCommunity = !routeIntelligence.conditions.isEmpty
            || (routeIntelligence.reviews?.count ?? 0) > 0
            || (routeIntelligence.completions?.count ?? 0) > 0
        let availableCount = [hasTrack, hasAnalysis, hasWeather, hasFacilities, hasCommunity].filter { $0 }.count
        let verifiedPOICount = routeIntelligence.pois.filter { $0.status == "verified" }.count
        let mapPOICount = routeIntelligence.pois.filter { $0.status != "verified" }.count + routeIntelligence.discoveredPOIs.count
        let completionCount = routeIntelligence.completions?.count ?? 0

        let headline: String
        let color: Color
        if availableCount >= 5 {
            headline = "基础与动态资料较完整"
            color = TrailBoxColor.primaryDark
        } else if availableCount >= 3 {
            headline = "核心路线资料已就绪"
            color = TrailBoxColor.sky
        } else {
            headline = "基础轨迹可用，动态资料待补充"
            color = TrailBoxColor.warning
        }

        var evidence: [String] = []
        if completionCount > 0 { evidence.append("跑友完成 \(completionCount) 次") }
        if verifiedPOICount > 0 { evidence.append("\(verifiedPOICount) 处设施已确认") }
        else if mapPOICount > 0 { evidence.append("\(mapPOICount) 处地图设施待核实") }
        if evidence.isEmpty { evidence.append("跑友验证信息仍待补充") }
        evidence.append("不等同于路线安全认证")

        return RouteTrustSummary(
            availableCount: availableCount,
            totalCount: 5,
            headline: headline,
            detail: evidence.joined(separator: " · "),
            color: color
        )
    }

    private func routeGuideSourceText(for track: Track, decision: RouteDecisionSummary) -> String {
        var items: [String] = []
        if let contributor = track.contributorName, track.showContributor {
            items.append("贡献者 \(contributor)")
        }
        if let createdAt = track.createdAt {
            items.append(createdAt.formatted(.dateTime.year().month().day()))
        }
        if let checkedAt = routeIntelligence.lastCheckedAt {
            items.append("情报检查 \(checkedAt.formatted(.dateTime.hour().minute()))")
        }
        items.append(decision.sourceText)
        return items.joined(separator: " · ")
    }

    private func departurePlanButtonTitle(for track: Track) -> String {
        if departurePlans.plan(for: track.id) != nil { return "查看出发计划" }
        return isDeparturePlanLoading ? "正在整理计划信息" : "生成出发计划"
    }

    private func openDeparturePlan(for track: Track) {
        guard session.isAuthenticated else {
            session.requireAuthentication()
            return
        }
        let existing = departurePlans.plan(for: track.id)
        if isDeparturePlanLoading, let existing {
            departurePlanDraft = existing
            return
        }
        departurePlanDraft = DeparturePlanFactory.make(
            track: track,
            analysis: routeIntelligence.analysis,
            personalFit: routeIntelligence.personalFit,
            weather: routeIntelligence.weather,
            conditions: routeIntelligence.conditions,
            pois: routeIntelligence.pois,
            discoveredPOICount: routeIntelligence.discoveredPOIs.count,
            existing: existing
        )
    }

    private func routeDecision(for track: Track) -> RouteDecisionSummary {
        let warningCondition = routeIntelligence.conditions.first { $0.severity == "warning" }
        let fit = routeIntelligence.personalFit
        let analysis = routeIntelligence.analysis

        let title: String
        let level: String
        let color: Color
        let systemImage: String
        if warningCondition != nil {
            title = "路线存在近期风险"
            level = "路况提醒"
            color = TrailBoxColor.warning
            systemImage = "exclamationmark.triangle.fill"
        } else if let fit, fit.score < 55 {
            title = "建议谨慎评估"
            level = "谨慎"
            color = TrailBoxColor.warning
            systemImage = "gauge.with.dots.needle.33percent"
        } else if let analysis, analysis.difficultyScore >= 80 {
            title = "高难路线，充分准备"
            level = analysis.difficultyLevel
            color = TrailBoxColor.danger
            systemImage = "mountain.2.fill"
        } else if let fit, fit.score >= 80 {
            title = "与你当前能力匹配"
            level = fit.level
            color = TrailBoxColor.primaryDark
            systemImage = "checkmark.circle.fill"
        } else if let fit {
            title = "具备挑战条件"
            level = fit.level
            color = TrailBoxColor.primaryDark
            systemImage = "figure.run.circle.fill"
        } else if let analysis {
            title = analysis.difficultyScore >= 60 ? "进阶路线，建议做好准备" : "路线强度相对友好"
            level = analysis.difficultyLevel
            color = analysis.difficultyScore >= 60 ? TrailBoxColor.warning : TrailBoxColor.primaryDark
            systemImage = analysis.difficultyScore >= 60 ? "mountain.2.fill" : "checkmark.circle.fill"
        } else if track.distanceM >= 30_000 || track.elevationGainM >= 1_500 {
            title = "长距离路线，建议充分准备"
            level = "进阶"
            color = TrailBoxColor.warning
            systemImage = "mountain.2.fill"
        } else {
            title = routeIntelligence.isLoading ? "正在整理出发建议" : "基础路线信息已就绪"
            level = routeIntelligence.isLoading ? "更新中" : "待完善"
            color = TrailBoxColor.primaryDark
            systemImage = routeIntelligence.isLoading ? "arrow.triangle.2.circlepath" : "map.fill"
        }

        let explanation: String
        if let warningCondition,
           let description = warningCondition.description,
           !description.isEmpty {
            explanation = description
        } else if let warningCondition {
            explanation = "跑友反馈近期存在\(conditionTitle(warningCondition.conditionType))，出发前请再次确认。"
        } else if let fit {
            explanation = fit.reason
        } else if let feature = analysis?.features.first {
            explanation = feature
        } else if routeIntelligence.isLoadingAnalysis {
            explanation = "正在结合轨迹强度、天气、设施和近期路况生成建议。"
        } else {
            explanation = "先参考距离与爬升规划体力和补给，动态信息将在可用时自动补充。"
        }

        var points: [RouteDecisionPoint] = []
        if let minimum = fit?.estimatedDurationMin ?? analysis?.estimatedDurationMin,
           let maximum = fit?.estimatedDurationMax ?? analysis?.estimatedDurationMax {
            points.append(RouteDecisionPoint(
                systemImage: "clock.fill",
                text: "预计用时 \(formatMinutes(minimum))–\(formatMinutes(maximum))",
                color: TrailBoxColor.sky
            ))
        } else {
            points.append(RouteDecisionPoint(
                systemImage: "clock",
                text: routeIntelligence.isLoadingAnalysis ? "预计用时正在计算" : "暂无可靠用时估算，请预留充足机动时间",
                color: TrailBoxColor.secondaryText
            ))
        }

        if let weather = routeIntelligence.weather {
            let rainProbability = weather.daily.precipitationProbabilityMax?.first
            if let rainProbability, rainProbability >= 40 {
                points.append(RouteDecisionPoint(
                    systemImage: "cloud.rain.fill",
                    text: "降雨概率最高 \(rainProbability)%，注意防滑和保暖",
                    color: TrailBoxColor.warning
                ))
            } else if let gust = weather.current.windGusts, gust >= 45 {
                points.append(RouteDecisionPoint(
                    systemImage: "wind",
                    text: "当前阵风约 \(Int(gust.rounded())) km/h，暴露路段需谨慎",
                    color: TrailBoxColor.warning
                ))
            } else if let sunset = weather.daily.sunset?.first {
                points.append(RouteDecisionPoint(
                    systemImage: "sunset.fill",
                    text: "日落 \(clockTime(sunset))，建议至少提前 1 小时结束",
                    color: TrailBoxColor.warning
                ))
            } else {
                points.append(RouteDecisionPoint(
                    systemImage: "cloud.sun.fill",
                    text: "已获取路线附近动态天气，出发前请再次确认",
                    color: TrailBoxColor.sky
                ))
            }
        } else {
            points.append(RouteDecisionPoint(
                systemImage: "cloud.sun",
                text: routeIntelligence.isLoadingWeather ? "正在检查天气和日落时间" : "动态天气暂不可用，出发前请自行确认",
                color: routeIntelligence.isLoadingWeather ? TrailBoxColor.sky : TrailBoxColor.secondaryText
            ))
        }

        if let warningCondition {
            points.append(RouteDecisionPoint(
                systemImage: "exclamationmark.triangle.fill",
                text: "近期路况：\(conditionTitle(warningCondition.conditionType))",
                color: TrailBoxColor.warning
            ))
        } else if let preparation = analysis?.preparation,
                  let safetyNote = preparation.safetyNotes.first {
            points.append(RouteDecisionPoint(
                systemImage: "backpack.fill",
                text: safetyNote,
                color: TrailBoxColor.moss
            ))
        } else if analysis?.preparation?.headlampRecommended == true {
            points.append(RouteDecisionPoint(
                systemImage: "flashlight.on.fill",
                text: "建议携带头灯，并准备备用电量",
                color: TrailBoxColor.moss
            ))
        }

        let verifiedPOICount = routeIntelligence.pois.filter { $0.status == "verified" }.count
        let mapPOICount = routeIntelligence.pois.filter { $0.status != "verified" }.count + routeIntelligence.discoveredPOIs.count
        if verifiedPOICount > 0 {
            points.append(RouteDecisionPoint(
                systemImage: "checkmark.seal.fill",
                text: "有 \(verifiedPOICount) 处跑友确认设施，仍建议携带基础补给",
                color: TrailBoxColor.primaryDark
            ))
        } else if mapPOICount > 0 {
            points.append(RouteDecisionPoint(
                systemImage: "mappin.and.ellipse",
                text: "发现 \(mapPOICount) 处地图设施，尚未核实补水可靠性",
                color: TrailBoxColor.warning
            ))
        } else {
            points.append(RouteDecisionPoint(
                systemImage: "waterbottle.fill",
                text: (routeIntelligence.isLoadingPOIs || routeIntelligence.isDiscoveringPOIs)
                    ? "正在检查沿途停车、厕所、补给和医院信息"
                    : "沿途设施尚未核实，请自备饮水和补给",
                color: TrailBoxColor.secondaryText
            ))
        }

        var sources: [String] = []
        if fit != nil { sources.append("个人能力") }
        if analysis != nil { sources.append("轨迹计算") }
        if routeIntelligence.weather != nil { sources.append("动态天气") }
        if !routeIntelligence.conditions.isEmpty { sources.append("跑友路况") }
        if !routeIntelligence.pois.isEmpty || !routeIntelligence.discoveredPOIs.isEmpty { sources.append("设施信息") }
        if sources.isEmpty { sources.append("基础轨迹") }

        return RouteDecisionSummary(
            title: title,
            level: level,
            explanation: explanation,
            color: color,
            systemImage: systemImage,
            points: points,
            sourceText: sources.joined(separator: "、"),
            isUpdating: routeIntelligence.isLoadingAnalysis
                || routeIntelligence.isLoadingWeather
                || routeIntelligence.isLoadingPOIs
                || routeIntelligence.isDiscoveringPOIs
        )
    }

    private func routeSectionNavigator(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            ForEach(RouteDetailSection.allCases) { section in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.85)) {
                        selectedRouteSection = section
                        proxy.scrollTo(section, anchor: UnitPoint(x: 0.5, y: 0.12))
                    }
                } label: {
                    Text(section.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selectedRouteSection == section ? Color.white : TrailBoxColor.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if selectedRouteSection == section {
                                Capsule()
                                    .fill(TrailBoxColor.primaryDark)
                                    .matchedGeometryEffect(id: "route-section-pill", in: routeSectionSelection)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedRouteSection == section ? .isSelected : [])
            }
        }
        .padding(4)
        .trailBoxGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func trackMetadataSection(_ track: Track) -> some View {
        if track.city != nil || !track.tagList.isEmpty {
            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    DetailSectionTitle(
                        title: isPublicSource ? "路线信息" : "记录信息",
                        systemImage: "info.circle.fill"
                    )
                    if let city = track.city {
                        HStack {
                            Text("城市").foregroundStyle(TrailBoxColor.secondaryText)
                            Spacer()
                            Text(city).fontWeight(.semibold)
                        }
                    }
                    if !track.tagList.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("标签")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(TrailBoxColor.secondaryText)
                            Text(track.tagList.joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(TrailBoxColor.secondaryText)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func routeRecommendationSection(_ track: Track) -> some View {
        if let reason = track.recommendationReason, !reason.isEmpty {
            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    DetailSectionTitle(title: "路线推荐", systemImage: "quote.bubble.fill")
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(TrailBoxColor.primary.opacity(0.35))
                            .frame(width: 3)

                        VStack(alignment: .leading, spacing: 10) {
                            Text(reason)
                                .font(.subheadline)
                                .lineSpacing(3)
                                .foregroundStyle(TrailBoxColor.text)
                                .fixedSize(horizontal: false, vertical: true)

                            if let contributor = track.contributorName, track.showContributor {
                                Text("—— \(contributor) 推荐")
                                    .font(.caption)
                                    .foregroundStyle(TrailBoxColor.secondaryText)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func routeSkeletonCard(title: String, rows: Int) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TrailBoxColor.secondaryText)
                }
                RouteSkeletonRows(count: rows)
            }
        }
    }

    private func routeRefreshIssue(
        _ message: String,
        systemImage: String,
        retry: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Label(message, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(TrailBoxColor.warning)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("重试", action: retry)
                .font(.caption.weight(.bold))
                .foregroundStyle(TrailBoxColor.primaryDark)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .background(TrailBoxColor.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func weatherCard(_ weather: RouteWeather) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    DetailSectionTitle(title: "路线天气", systemImage: weatherIcon(weather.current.weatherCode))
                    Spacer()
                    if let temperature = weather.current.temperature {
                        Text("\(Int(temperature.rounded()))°")
                            .font(.title2.weight(.bold))
                    }
                }
                HStack(spacing: 0) {
                    intelligenceMetric(weather.current.apparentTemperature.map { "\(Int($0.rounded()))°" } ?? "-", "体感")
                    intelligenceMetric(weather.daily.precipitationProbabilityMax?.first.map { "\($0)%" } ?? "-", "降雨")
                    intelligenceMetric(weather.current.windGusts.map { "\(Int($0.rounded())) km/h" } ?? "-", "阵风")
                }
                if let sunset = weather.daily.sunset?.first {
                    Label("日落 \(clockTime(sunset))，请按预计用时预留至少 1 小时安全余量", systemImage: "sunset.fill")
                        .font(.caption)
                        .foregroundStyle(TrailBoxColor.secondaryText)
                }
                sourceFootnote("\(weather.source) · 动态天气")
            }
        }
    }

    private func intelligenceMetric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.subheadline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.65)
            Text(label).font(.caption2).foregroundStyle(TrailBoxColor.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func sourceFootnote(_ source: String) -> some View {
        Label(source, systemImage: "checkmark.seal")
            .font(.caption2)
            .foregroundStyle(TrailBoxColor.secondaryText)
    }

    private func difficultyColor(_ score: Double) -> Color {
        if score >= 80 { return .red }
        if score >= 60 { return .orange }
        if score >= 40 { return .yellow.opacity(0.85) }
        return TrailBoxColor.primaryDark
    }

    private func formatMinutes(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)小时\(minutes % 60 == 0 ? "" : "\(minutes % 60)分")" : "\(minutes)分"
    }

    private func weatherIcon(_ code: Int?) -> String {
        guard let code else { return "cloud.sun.fill" }
        if code == 0 { return "sun.max.fill" }
        if [1, 2, 3].contains(code) { return "cloud.sun.fill" }
        if (51...67).contains(code) || (80...82).contains(code) { return "cloud.rain.fill" }
        if (71...77).contains(code) || (85...86).contains(code) { return "cloud.snow.fill" }
        if code >= 95 { return "cloud.bolt.rain.fill" }
        return "cloud.fill"
    }

    private func clockTime(_ value: String) -> String {
        value.split(separator: "T").last.map(String.init) ?? value
    }

    private func poiIcon(_ type: String) -> String {
        switch type {
        case "parking": return "parkingsign.circle.fill"
        case "restroom": return "figure.dress.line.vertical.figure"
        case "store", "supply": return "cart.fill"
        case "hospital": return "cross.case.fill"
        case "transit": return "bus.fill"
        case "camp": return "tent.fill"
        default: return "mappin.circle.fill"
        }
    }

    private func conditionTitle(_ type: String) -> String {
        switch type {
        case "closure": return "封路"
        case "construction": return "施工"
        case "snow": return "积雪"
        case "mud": return "泥泞"
        case "supply": return "补给变化"
        case "signal": return "信号情况"
        default: return "路线提醒"
        }
    }

    private func reviewAverage(_ summary: RouteReviewSummary, _ key: String) -> String {
        summary.averages[key].map { String(format: "%.1f", $0) } ?? "-"
    }

    private var routeMapPOIs: [RouteMapPOI] {
        let saved = routeIntelligence.pois.map {
            RouteMapPOI(id: "saved-\($0.id)", name: $0.name, type: $0.type, latitude: $0.latitude, longitude: $0.longitude)
        }
        let discovered = routeIntelligence.discoveredPOIs.map {
            RouteMapPOI(id: "map-\($0.id)", name: $0.name, type: $0.type, latitude: $0.latitude, longitude: $0.longitude)
        }
        return Array((saved + discovered).prefix(12))
    }

    private var activityMatchesCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                DetailSectionTitle(title: "匹配到公开路线", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                ForEach(routeIntelligence.activityMatches.prefix(3)) { match in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(match.routeName ?? "公开路线")
                                .font(.subheadline.weight(.semibold))
                            Text(match.matchType == "complete" ? "已完成路线" : "完成部分路线")
                                .font(.caption)
                                .foregroundStyle(TrailBoxColor.secondaryText)
                        }
                        Spacer()
                        Text("\(Int((match.coverageRatio * 100).rounded()))%")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(TrailBoxColor.primaryDark)
                    }
                }
                sourceFootnote("根据轨迹空间覆盖率自动匹配")
            }
        }
    }

    private func detailActions(_ track: Track) -> some View {
        FloatingActionBar {
            HStack(spacing: 12) {
                if isPublicSource {
                    Button { showStartRouteSheet = true } label: {
                        Label("一键出发", systemImage: "figure.run")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
                    .trailBoxGlass(tint: TrailBoxColor.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button { showSharePreview = true } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 52, height: 52)
                    }
                    .foregroundStyle(TrailBoxColor.primaryDark)
                    .buttonStyle(.plain)
                    .trailBoxGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("分享路线")
                } else {
                    Button { download(track) } label: {
                        Label("导出 GPX", systemImage: "square.and.arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .foregroundStyle(TrailBoxColor.primaryDark)
                    .buttonStyle(.plain)
                    .trailBoxGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button { showSharePreview = true } label: {
                        Label("分享记录", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
                    .trailBoxGlass(tint: TrailBoxColor.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    private func routeStartActionSheet(_ track: Track) -> some View {
        let decision = routeDecision(for: track)
        let planIsLoading = departurePlans.plan(for: track.id) == nil && isDeparturePlanLoading
        return RouteStartActionSheet(
            routeName: track.name,
            decisionTitle: decision.title,
            decisionLevel: decision.level,
            decisionColor: decision.color,
            planTitle: departurePlanButtonTitle(for: track),
            isPlanLoading: planIsLoading,
            isSaved: savedRoutes.isSaved(track.id),
            isSaving: savedRoutes.savingTrackIDs.contains(track.id),
            navigateToStart: {
                dismissStartRouteSheet {
                    guard let start = track.points.first else { return }
                    navigationDestination = NavigationDestination(point: start, name: "\(track.name) 起点")
                }
            },
            openPlan: {
                dismissStartRouteSheet { openDeparturePlan(for: track) }
            },
            exportGPX: {
                dismissStartRouteSheet { download(track) }
            },
            toggleSaved: {
                dismissStartRouteSheet {
                    guard let token = session.token else {
                        session.requireAuthentication()
                        return
                    }
                    Task { await savedRoutes.toggle(trackID: track.id, token: token) }
                }
            }
        )
    }

    private func dismissStartRouteSheet(then action: @escaping () -> Void) {
        showStartRouteSheet = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24, execute: action)
    }

    private func publicRouteHero(_ track: Track) -> some View {
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .bottomLeading) {
                TrackMap(points: track.points, pois: routeMapPOIs)
                    .frame(height: 330)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.12), .black.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 7) {
                        if let city = track.city, !city.isEmpty {
                            Label(city, systemImage: "mappin.and.ellipse")
                                .font(.caption.weight(.bold))
                        }
                        if let tag = track.tagList.first {
                            Text(tag).font(.caption.weight(.bold))
                        }
                    }
                    .foregroundStyle(.white.opacity(0.92))

                    Text(track.name)
                        .font(.system(size: 27, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .shadow(color: .black.opacity(0.32), radius: 4, y: 2)

                    if let description = track.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(2)
                    }
                }
                .padding(18)
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.58), lineWidth: 0.8))

            Button { showFullscreenMap = true } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(TrailBoxColor.text)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .trailBoxGlass(in: Circle())
            .padding(12)
        }
        .shadow(color: TrailBoxColor.primaryDark.opacity(0.18), radius: 18, y: 9)
    }

    private func routeSnapshotMetric(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(TrailBoxColor.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func activityHero(_ track: Track) -> some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [TrailBoxColor.primaryDark, TrailBoxColor.primary, TrailBoxColor.moss],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, size in
                for index in 0..<5 {
                    var contour = Path()
                    let baseY = size.height * CGFloat(0.18 + Double(index) * 0.19)
                    contour.move(to: CGPoint(x: -16, y: baseY))
                    contour.addCurve(
                        to: CGPoint(x: size.width + 16, y: baseY - 6),
                        control1: CGPoint(x: size.width * 0.28, y: baseY - 26),
                        control2: CGPoint(x: size.width * 0.72, y: baseY + 22)
                    )
                    context.stroke(contour, with: .color(.white.opacity(0.09)), lineWidth: 1)
                }
            }
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 15) {
                Label(activityDateText(track.startTime ?? track.createdAt), systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.76))

                Text(track.name)
                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 8) {
                    activityHeroChip(track.sport ?? "运动记录", systemImage: "figure.run")
                    activityHeroChip(track.isPublic ? "已公开" : "仅自己可见", systemImage: track.isPublic ? "globe.asia.australia.fill" : "lock.fill")
                }
            }
            .padding(20)
        }
        .frame(minHeight: 182)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.32), lineWidth: 0.8))
        .shadow(color: TrailBoxColor.primaryDark.opacity(0.18), radius: 18, y: 9)
    }

    private func activityHeroChip(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.black.opacity(0.16), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.7))
    }

    private func activityOverviewCard(_ track: Track) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 15) {
                DetailSectionTitle(title: "运动概览", systemImage: "speedometer")
                HStack(spacing: 0) {
                    routeSnapshotMetric(DisplayFormat.distance(track.distanceM), "距离", TrailBoxColor.text)
                    routeSnapshotMetric(track.durationSec.map(DisplayFormat.duration) ?? "-", "用时", TrailBoxColor.sky)
                    routeSnapshotMetric(DisplayFormat.elevation(track.elevationGainM), "累计爬升", TrailBoxColor.primaryDark)
                    routeSnapshotMetric(track.points.compactMap(\.altitude).max().map(DisplayFormat.elevation) ?? "-", "最高海拔", TrailBoxColor.warning)
                }
            }
        }
    }

    private func activityDateText(_ date: Date?) -> String {
        guard let date else { return "记录时间待补充" }
        return date.formatted(.dateTime.year().month().day().weekday(.abbreviated).hour().minute())
    }

    private func analysisCard(_ track: Track) -> some View {
        let resolvedAnalysis = aiAnalysis ?? track.aiAnalysisText.map { AIAnalysis(legacyText: $0) }
        return SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                DetailSectionTitle(title: "AI 运动分析", systemImage: "sparkles")
                if isAnalyzing {
                    PwaAIAnalysisProgress()
                        .transition(reduceMotion ? .identity : .opacity)
                } else if let resolvedAnalysis {
                    if !capturedVoiceText.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "waveform")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(TrailBoxColor.primaryDark)
                                .frame(width: 32, height: 32)
                                .background(TrailBoxColor.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("你说的体感")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(TrailBoxColor.secondaryText)
                                Text(capturedVoiceText)
                                    .font(.subheadline)
                                    .foregroundStyle(TrailBoxColor.text)
                                    .lineLimit(3)
                            }
                        }
                        .padding(12)
                        .background(TrailBoxColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    AIAnalysisResultView(
                        analysis: resolvedAnalysis,
                        revealedSectionCount: revealedAISectionCount
                    )
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("把数据变成下一次能执行的建议")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TrailBoxColor.text)
                        Text("可以先说一句体感，也可以直接根据轨迹、爬升和运动数据生成复盘。")
                            .font(.caption)
                            .foregroundStyle(TrailBoxColor.secondaryText)
                            .lineSpacing(3)
                    }
                    if !capturedVoiceText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("这次感受").font(.caption.weight(.bold)).foregroundStyle(TrailBoxColor.secondaryText)
                                Spacer()
                                Button {
                                    capturedVoiceText = ""
                                    voiceRecorder.cancel()
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(TrailBoxColor.secondaryText)
                                        .frame(width: 32, height: 32)
                                }
                                .buttonStyle(.plain)
                                .trailBoxGlass(in: Circle())
                                .accessibilityLabel("删除本次语音录入")
                            }
                            Text(capturedVoiceText).font(.subheadline).foregroundStyle(TrailBoxColor.text).lineLimit(3)
                        }
                        .padding(12)
                        .background(TrailBoxColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    VStack(spacing: 9) {
                        AIRecordingGlyph(isActive: isVoiceGestureActive)
                        Text(isVoiceGestureActive ? "松手结束录音" : capturedVoiceText.isEmpty ? "按住说说这次感受" : "按住重新说")
                            .font(.headline.weight(.bold))
                        Text(isVoiceGestureActive ? "正在听你说…" : "一句话就够，例如：后半程腿很沉")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 108)
                    .background(
                        LinearGradient(
                            colors: isVoiceGestureActive
                                ? [TrailBoxColor.primaryDark, .black.opacity(0.82)]
                                : [TrailBoxColor.primaryDark, TrailBoxColor.primary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.24), lineWidth: 0.8)
                    )
                    .shadow(color: TrailBoxColor.primaryDark.opacity(0.16), radius: 12, y: 6)
                    .scaleEffect(isVoiceGestureActive && !reduceMotion ? 0.985 : 1)
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isVoiceGestureActive)
                    .gesture(voiceStartGesture())
                    .accessibilityLabel(capturedVoiceText.isEmpty ? "按住说说这次感受" : "按住重新录入体感")
                    .accessibilityHint("按住开始录音，松手结束")

                    Button {
                        analyze(track, feeling: ActivityFeeling(overallFeeling: nil, processTags: [], bodyTags: [], routeEnvTags: [], painDetails: [], voiceText: capturedVoiceText, textNote: ""))
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(TrailBoxColor.primaryDark)
                                .frame(width: 36, height: 36)
                                .background(TrailBoxColor.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(capturedVoiceText.isEmpty ? "直接分析这次记录" : "结合体感开始分析")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(TrailBoxColor.text)
                                Text(capturedVoiceText.isEmpty ? "不补充体感，先根据运动数据生成" : "把刚才的感受一起交给 AI 判断")
                                    .font(.caption)
                                    .foregroundStyle(TrailBoxColor.secondaryText)
                            }
                            Spacer(minLength: 6)
                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(TrailBoxColor.primaryDark)
                        }
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 60)
                        .background(TrailBoxColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(TrailBoxColor.border, lineWidth: 0.75)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
    }
    private func voiceStartGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isVoiceGestureActive {
                    isVoiceGestureActive = true
                    voiceRecorder.beginPress()
                }
            }
            .onEnded { value in
                isVoiceGestureActive = false
                voiceRecorder.endPress()
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    if voiceRecorder.hasTranscript { capturedVoiceText = voiceRecorder.transcript }
                }
            }
    }
    private func formatGrade(_ grade: Double) -> String { String(format: "%+.1f%%", grade) }

    private func difficultyMetric(_ difficulty: String?) -> some View {
        VStack(spacing: 3) {
            Text(difficulty ?? "-")
                .font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(difficultyColor(difficulty))
            Text("难度评级").font(.caption).foregroundStyle(TrailBoxColor.secondaryText).lineLimit(1)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private func difficultyColor(_ difficulty: String?) -> Color {
        switch difficulty {
        case "中等": .orange
        case "困难": .red
        case "极难": .purple
        default: TrailBoxColor.primaryDark
        }
    }

    private func endpointButton(title: String, point: TrackPoint, trackName: String, color: Color) -> some View {
        Button { navigationDestination = NavigationDestination(point: point, name: "\(trackName) \(title)") } label: {
            HStack(spacing: 8) { Circle().fill(color).frame(width: 10, height: 10); VStack(alignment: .leading, spacing: 2) { Text(title).font(.caption).foregroundStyle(TrailBoxColor.secondaryText); Text("导航").font(.subheadline.weight(.semibold)).foregroundStyle(TrailBoxColor.text) }; Spacer(); Image(systemName: "arrow.triangle.turn.up.right.diamond").foregroundStyle(TrailBoxColor.primaryDark) }
                .padding(12)
        }
        .buttonStyle(.plain)
        .trailBoxGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func navigationProviders(for destination: NavigationDestination) -> [NavigationProvider] {
        let point = destination.point
        let name = destination.name.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? destination.name
        let gcj02 = wgs84ToGCJ02(latitude: point.lat, longitude: point.lon)
        let bd09 = gcj02ToBD09(latitude: gcj02.latitude, longitude: gcj02.longitude)
        let amapAppURL = URL(string: "amapuri://route/plan/?dlat=\(gcj02.latitude)&dlon=\(gcj02.longitude)&dname=\(name)&dev=0&t=0")!
        let providers: [NavigationProvider] = [
            .apple,
            UIApplication.shared.canOpenURL(amapAppURL) ? .amap(amapAppURL) : nil,
            URL(string: "baidumap://map/direction?destination=latlng:\(bd09.latitude),\(bd09.longitude)%7Cname:\(name)&mode=driving").flatMap { UIApplication.shared.canOpenURL($0) ? .baidu($0) : nil },
            URL(string: "qqmap://map/routeplan?type=drive&to=\(name)&tocoord=\(gcj02.latitude),\(gcj02.longitude)").flatMap { UIApplication.shared.canOpenURL($0) ? .tencent($0) : nil },
            URL(string: "comgooglemaps://?daddr=\(point.lat),\(point.lon)&directionsmode=driving").flatMap { UIApplication.shared.canOpenURL($0) ? .google($0) : nil }
        ].compactMap { $0 }

        if providers.count > 1 { return providers }
        let amapWebURL = URL(string: "https://uri.amap.com/navigation?to=\(gcj02.longitude),\(gcj02.latitude),\(name)&mode=car&coordinate=gaode")!
        return [.apple, .amap(amapWebURL)]
    }

    private func openNavigation(_ provider: NavigationProvider, destination: NavigationDestination) {
        navigationDestination = nil
        if case .apple = provider {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: destination.point.lat, longitude: destination.point.lon)))
            item.name = destination.name
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
        } else if let url = provider.url {
            UIApplication.shared.open(url)
        }
    }

    private func download(_ track: Track) {
        if !isPublicSource, !session.isAuthenticated {
            session.requireAuthentication()
            return
        }
        let token = session.token
        Task {
            do {
                shareFile = ActivityFile(url: try await APIClient.shared.downloadGPX(trackID: track.id, token: token))
            } catch APIError.unauthorized {
                if isPublicSource {
                    actionError = "这条路线暂时无法公开导出 GPX。"
                } else {
                    session.handle(APIError.unauthorized)
                    session.requireAuthentication()
                }
            } catch {
                actionError = ErrorMessage.display(error)
            }
        }
    }

    private func delete(_ track: Track) {
        guard let token = session.token else { return }
        Task {
            do {
                try await APIClient.shared.requestVoid("/tracks/\(track.id)", method: "DELETE", token: token)
                showDeleteSuccess = true
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func finishDeleting() {
        Task {
            if let onDeleted {
                await onDeleted()
            }
            dismiss()
        }
    }

    private func blockContributor(_ publicID: String) {
        struct Request: Encodable { let publicID: String }
        guard let token = session.token else { session.requireAuthentication(); return }
        Task {
            do {
                try await APIClient.shared.requestVoid("/moderation/blocks", method: "POST", body: Request(publicID: publicID), token: token)
                dismiss()
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func analyze(_ track: Track, feeling: ActivityFeeling) {
        guard let token = session.token else {
            session.requireAuthentication()
            return
        }
        revealedAISectionCount = 0
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            isAnalyzing = true
        }
        Task {
            do {
                let result: AIAnalysisResponse = try await APIClient.shared.request(
                    "/tracks/\(track.id)/ai-analysis",
                    method: "POST",
                    body: AIAnalysisRequest(userFeeling: feeling),
                    token: token
                )
                aiAnalysis = result.analysis
                revealedAISectionCount = reduceMotion ? Int.max : 1
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                    isAnalyzing = false
                }
                guard !reduceMotion else { return }
                for count in 2...5 {
                    try? await Task.sleep(for: .milliseconds(140))
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                        revealedAISectionCount = count
                    }
                }
            } catch {
                actionError = ErrorMessage.display(error)
                revealedAISectionCount = Int.max
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    isAnalyzing = false
                }
            }
        }
    }
}

private struct RouteSkeletonRows: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<count, id: \.self) { index in
                HStack(spacing: 10) {
                    Circle()
                        .fill(TrailBoxColor.border.opacity(0.75))
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(TrailBoxColor.border.opacity(0.8))
                            .frame(width: CGFloat(172 - index * 12), height: 10)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(TrailBoxColor.border.opacity(0.55))
                            .frame(width: CGFloat(112 + index * 8), height: 8)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .opacity(isPulsing ? 0.5 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1).repeatCount(2, autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

private struct ReportTrackView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    let trackID: String
    @State private var reason = "不当内容"
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    private let reasons = ["不当内容", "侵犯权利", "危险或误导信息", "垃圾信息", "其他"]

    var body: some View {
        NavigationStack {
            Form {
                Section("举报原因") {
                    Picker("原因", selection: $reason) { ForEach(reasons, id: \.self) { Text($0).tag($0) } }
                }
                Section("补充说明（可选）") { TextField("说明问题", text: $details, axis: .vertical).lineLimit(3...6) }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(TrailBoxColor.danger) } }
            }
            .navigationTitle("举报路线")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button(isSubmitting ? "提交中…" : "提交") { submit() }.disabled(isSubmitting) }
            }
        }
    }

    private func submit() {
        struct Request: Encodable { let trackID: String; let reason: String; let details: String? }
        guard let token = session.token else { session.requireAuthentication(); return }
        isSubmitting = true
        Task {
            do {
                try await APIClient.shared.requestVoid("/moderation/reports", method: "POST", body: Request(trackID: trackID, reason: reason, details: details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : details), token: token)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

private struct PwaAIAnalysisProgress: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stepIndex = 0
    @State private var isPulsing = false
    private let steps = [
        "正在读取轨迹、爬升和运动数据",
        "正在判断这次运动的主要负荷",
        "正在把体感和数据放在一起理解",
        "正在整理成下一次可执行的建议"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(TrailBoxColor.primary.opacity(0.1))
                        .frame(width: 48, height: 48)
                        .scaleEffect(isPulsing && !reduceMotion ? 1.12 : 1)
                    Circle()
                        .stroke(TrailBoxColor.primary.opacity(0.22), lineWidth: 1)
                        .frame(width: 48, height: 48)
                    Image(systemName: "sparkles")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(TrailBoxColor.primaryDark)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("AI 正在复盘这次运动")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(TrailBoxColor.text)
                    AIShimmerText(text: steps[stepIndex])
                        .id(stepIndex)
                        .transition(
                            reduceMotion
                                ? .identity
                                : .asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity.combined(with: .move(edge: .top))
                                )
                        )
                }
            }

            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { index in
                    Capsule()
                        .fill(index <= stepIndex ? TrailBoxColor.primary : TrailBoxColor.border)
                        .frame(maxWidth: .infinity)
                        .frame(height: 4)
                }
            }

            VStack(alignment: .leading, spacing: 11) {
                ForEach(0..<3, id: \.self) { index in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(TrailBoxColor.primary.opacity(index == stepIndex % 3 ? 0.13 : 0.07))
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(TrailBoxColor.border.opacity(0.78))
                                .frame(width: CGFloat(132 + index * 26), height: 9)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(TrailBoxColor.border.opacity(0.5))
                                .frame(maxWidth: index == 1 ? 190 : 154)
                                .frame(height: 8)
                        }
                    }
                }
            }
            .padding(14)
            .background(TrailBoxColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("分析完成后会按“结论、原因、行动、恢复”逐项呈现。")
                .font(.caption2)
                .foregroundStyle(TrailBoxColor.secondaryText)
        }
        .padding(14)
        .background(TrailBoxColor.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TrailBoxColor.primary.opacity(0.13), lineWidth: 0.8)
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .task {
            while !Task.isCancelled && stepIndex < steps.count - 1 {
                try? await Task.sleep(for: .seconds(1.35))
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    stepIndex += 1
                }
            }
        }
    }
}

private struct AIShimmerText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSweeping = false
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(TrailBoxColor.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                LinearGradient(
                    colors: [.clear, TrailBoxColor.primaryDark, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: isSweeping ? 220 : -220)
                .mask {
                    Text(text)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                    isSweeping = true
                }
            }
    }
}

private struct AIRecordingGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false
    let isActive: Bool

    private let restingHeights: [CGFloat] = [10, 18, 12, 20]
    private let activeHeights: [CGFloat] = [20, 11, 22, 14]

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.14))
                .frame(width: 48, height: 48)
                .scaleEffect(isActive && isAnimating && !reduceMotion ? 1.13 : 1)

            if isActive {
                HStack(alignment: .center, spacing: 3) {
                    ForEach(restingHeights.indices, id: \.self) { index in
                        Capsule()
                            .fill(.white)
                            .frame(
                                width: 3,
                                height: isAnimating && !reduceMotion ? activeHeights[index] : restingHeights[index]
                            )
                            .animation(
                                reduceMotion
                                    ? nil
                                    : .easeInOut(duration: 0.48)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(index) * 0.07),
                                value: isAnimating
                            )
                    }
                }
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .onAppear { updateAnimation(for: isActive) }
        .onChange(of: isActive) { updateAnimation(for: $0) }
    }

    private func updateAnimation(for active: Bool) {
        isAnimating = false
        guard active, !reduceMotion else { return }
        DispatchQueue.main.async {
            isAnimating = true
        }
    }
}

private struct AIAnalysisResultView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let analysis: AIAnalysis
    let revealedSectionCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if revealedSectionCount > 0 {
                summaryCard
                    .transition(revealTransition)
            }
            if revealedSectionCount > 1, !analysis.detailAnalysis.mainReason.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textSection(
                    analysis.detailAnalysis.mainReason,
                    systemImage: "waveform.path.ecg",
                    tint: TrailBoxColor.sky
                )
                .transition(revealTransition)
            }
            if revealedSectionCount > 2, !analysis.detailAnalysis.nextActions.items.isEmpty {
                actionSection
                    .transition(revealTransition)
            }
            if revealedSectionCount > 3, !analysis.detailAnalysis.recoveryAdvice.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textSection(
                    analysis.detailAnalysis.recoveryAdvice,
                    systemImage: analysis.detailAnalysis.recoveryAdvice.title == "下次重点看" ? "eye.fill" : "heart.text.square.fill",
                    tint: TrailBoxColor.moss
                )
                .transition(revealTransition)
            }
            if revealedSectionCount > 4, let warning = analysis.detailAnalysis.riskWarning {
                textSection(
                    warning,
                    systemImage: "exclamationmark.triangle.fill",
                    tint: TrailBoxColor.warning
                )
                .transition(revealTransition)
            }
        }
    }

    private var summaryCard: some View {
        let fullConclusion = analysis.detailAnalysis.coreJudgment.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 9) {
            Label("本次结论", systemImage: "scope")
                .font(.caption.weight(.bold))
                .foregroundStyle(TrailBoxColor.primaryDark)
            Text(fullConclusion.isEmpty ? analysis.cardSummary : fullConclusion)
                .font(.body.weight(.semibold))
                .foregroundStyle(TrailBoxColor.text)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [TrailBoxColor.primary.opacity(0.12), TrailBoxColor.sand.opacity(0.38)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TrailBoxColor.primary.opacity(0.16), lineWidth: 0.8)
        )
    }

    private var actionSection: some View {
        analysisBlock(
            title: analysis.detailAnalysis.nextActions.title,
            systemImage: "checklist",
            tint: TrailBoxColor.primaryDark
        ) {
            VStack(alignment: .leading, spacing: 11) {
                ForEach(Array(analysis.detailAnalysis.nextActions.items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(TrailBoxColor.primaryDark, in: Circle())
                        Text(cleanedAction(item))
                            .font(.subheadline)
                            .foregroundStyle(TrailBoxColor.text)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func textSection(
        _ section: AIAnalysis.TextSection,
        systemImage: String,
        tint: Color
    ) -> some View {
        analysisBlock(title: section.title, systemImage: systemImage, tint: tint) {
            Text(section.content)
                .font(.subheadline)
                .foregroundStyle(TrailBoxColor.text)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func analysisBlock<Content: View>(
        title: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TrailBoxColor.text)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TrailBoxColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TrailBoxColor.border, lineWidth: 0.7)
        )
    }

    private var revealTransition: AnyTransition {
        reduceMotion
            ? .identity
            : .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .bottom)),
                removal: .opacity
            )
    }

    private func cleanedAction(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"^\s*\d+[\.、]\s*"#,
            with: "",
            options: .regularExpression
        )
    }
}

private struct VoiceTranscriptBubble: View {
    let transcript: String
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "waveform").foregroundStyle(TrailBoxColor.primaryDark)
            Text(transcript.isEmpty ? "正在听你说…" : transcript).font(.subheadline).foregroundStyle(TrailBoxColor.text).lineLimit(3)
            Spacer(minLength: 0)
        }.padding(14).background(TrailBoxColor.surface.opacity(0.96)).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)).shadow(color: .black.opacity(0.12), radius: 14, y: 6)
    }
}

private struct AnalysisDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let analysis: AIAnalysis; let reanalyze: () -> Void
    var body: some View { NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 14) { textCard(analysis.detailAnalysis.coreJudgment); textCard(analysis.detailAnalysis.mainReason); SectionCard { VStack(alignment: .leading, spacing: 10) { Text(analysis.detailAnalysis.nextActions.title).font(.headline); ForEach(Array(analysis.detailAnalysis.nextActions.items.enumerated()), id: \.offset) { Text("\($0.offset + 1). \($0.element)").font(.subheadline).fixedSize(horizontal: false, vertical: true) } } }; textCard(analysis.detailAnalysis.recoveryAdvice); if let warning = analysis.detailAnalysis.riskWarning { SectionCard { VStack(alignment: .leading, spacing: 6) { Text(warning.title).font(.headline).foregroundStyle(.orange); Text(warning.content).font(.subheadline) } }.background(Color.orange.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12)) } }.padding(16) }.background(TrailBoxColor.background).navigationTitle("AI 运动分析").toolbar { ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }; ToolbarItem(placement: .topBarTrailing) { Button("重新分析") { reanalyze() } } } } }
    private func textCard(_ section: AIAnalysis.TextSection) -> some View { SectionCard { VStack(alignment: .leading, spacing: 7) { Text(section.title).font(.headline); Text(section.content).font(.subheadline).lineSpacing(4) } } }
}

private struct AnalysisLoadingView: View { @State private var index = 0; private let messages = ["正在判断主要负荷来源", "正在结合你的身体反馈", "正在生成改进建议", "正在整理恢复建议"]; var body: some View { VStack(spacing: 16) { ProgressView().scaleEffect(1.4); Text("AI 正在分析这次运动").font(.title3.bold()); Text("正在结合运动数据、你的体感反馈和路线特征。\n\(messages[index])").font(.subheadline).foregroundStyle(TrailBoxColor.secondaryText).multilineTextAlignment(.center) }.task { while !Task.isCancelled { try? await Task.sleep(for: .seconds(1.5)); index = (index + 1) % messages.count } }.frame(maxWidth: .infinity, maxHeight: .infinity).background(TrailBoxColor.background) } }

@MainActor private final class FeelingRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var transcript = ""
    @Published var statusText = "按住说话"
    @Published var elapsedText = "正在录音…"
    var hasTranscript: Bool { !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isPressing = false

    func beginPress() {
        guard !isPressing else { return }
        isPressing = true
        transcript = ""
        statusText = "正在准备录音…"
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else { self.isPressing = false; self.statusText = "需要麦克风权限"; return }
                self.requestSpeechAuthorization()
            }
        }
    }

    func endPress() {
        isPressing = false
        guard isRecording else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        isRecording = false
        statusText = hasTranscript ? "按住重新说" : "没听清，按住重试"
    }

    func cancel() {
        endPress()
        transcript = ""
        statusText = "按住说话"
    }

    private func requestSpeechAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                guard status == .authorized else { self.isPressing = false; self.statusText = "需要语音识别权限"; return }
                self.startEngineIfStillPressed()
            }
        }
    }

    private func startEngineIfStillPressed() {
        guard isPressing, !isRecording else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement)
            try AVAudioSession.sharedInstance().setActive(true)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request
            recognitionTask?.cancel()
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in self?.request?.append(buffer) }
            engine.prepare()
            try engine.start()
            isRecording = true
            statusText = "正在听你说…"
            recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, _ in
                DispatchQueue.main.async { if let result { self?.transcript = result.bestTranscription.formattedString } }
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                self?.endPress()
            }
        } catch {
            isPressing = false
            statusText = "录音失败，请重试"
        }
    }
}

private struct ActivityFile: Identifiable { let url: URL; var id: URL { url } }

private struct ActivityFileView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct EditTrackView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    let track: Track
    let didSave: () -> Void
    @State private var name: String
    @State private var city: String
    @State private var tags: String
    @State private var sport: String
    @State private var isPublic: Bool
    @State private var showContributor: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(track: Track, didSave: @escaping () -> Void) {
        self.track = track; self.didSave = didSave
        _name = State(initialValue: track.name); _city = State(initialValue: track.city ?? "北京"); _tags = State(initialValue: track.tags ?? "")
        _sport = State(initialValue: track.sport ?? "越野跑"); _isPublic = State(initialValue: track.isPublic); _showContributor = State(initialValue: track.showContributor)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("记录信息") { TextField("记录名称", text: $name); TextField("城市", text: $city); TextField("标签", text: $tags); Picker("运动类型", selection: $sport) { Text("越野跑").tag("越野跑"); Text("徒步").tag("徒步") } }
                Section("公开设置") { Toggle("公开为探索路线", isOn: $isPublic); Toggle("展示贡献者昵称", isOn: $showContributor) }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(TrailBoxColor.danger) } }
            }.navigationTitle(track.isPublic ? "编辑路线" : "编辑记录").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }; ToolbarItem(placement: .topBarTrailing) { Button(isSaving ? "保存中…" : "保存") { save() }.disabled(isSaving || name.isEmpty) } }
        }
    }

    private func save() {
        struct Update: Encodable { let name: String; let city: String; let tags: String; let sport: String; let isPublic: Bool; let showContributor: Bool }
        guard let token = session.token else { return }; isSaving = true
        Task { do { try await APIClient.shared.requestVoid("/tracks/\(track.id)", method: "PATCH", body: Update(name: name, city: city, tags: tags, sport: sport, isPublic: isPublic, showContributor: showContributor), token: token); didSave(); dismiss() } catch { errorMessage = error.localizedDescription }; isSaving = false }
    }
}

private struct ElevationProfileSample: Identifiable {
    let id: Int
    let distanceKM: Double
    let altitude: Double
}

private func profileDistanceLabel(_ distance: Double) -> String {
    String(format: distance < 10 ? "%.1f km" : "%.0f km", distance)
}

private struct ElevationChart: View {
    let title: String
    private let samples: [ElevationProfileSample]
    private let minimumAltitude: Double?
    private let maximumAltitude: Double?
    private let averageAltitude: Double?

    init(points: [TrackPoint], title: String) {
        self.title = title
        let distances = ActivityChartSampleBuilder.cumulativeDistances(for: points)
        let validSamples = zip(points, distances).enumerated().compactMap { index, pair -> ElevationProfileSample? in
            guard let altitude = pair.0.altitude else { return nil }
            return ElevationProfileSample(id: index, distanceKM: pair.1 / 1_000, altitude: altitude)
        }
        let altitudes = validSamples.map(\.altitude)
        minimumAltitude = altitudes.min()
        maximumAltitude = altitudes.max()
        averageAltitude = altitudes.isEmpty ? nil : altitudes.reduce(0, +) / Double(altitudes.count)
        let maximumSampleCount = 180
        let step = max(1, Int(ceil(Double(validSamples.count) / Double(maximumSampleCount))))
        var displaySamples = validSamples.enumerated().compactMap { index, sample in
            index.isMultiple(of: step) ? sample : nil
        }
        if let last = validSamples.last, displaySamples.last?.id != last.id {
            displaySamples.append(last)
        }
        for extreme in [validSamples.max(by: { $0.altitude < $1.altitude }), validSamples.min(by: { $0.altitude < $1.altitude })].compactMap({ $0 }) {
            if !displaySamples.contains(where: { $0.id == extreme.id }) {
                displaySamples.append(extreme)
            }
        }
        displaySamples.sort { $0.id < $1.id }
        samples = displaySamples
    }

    private var altitudeDomain: ClosedRange<Double> {
        guard let minimumAltitude, let maximumAltitude else { return 0...100 }
        let padding = max(10, (maximumAltitude - minimumAltitude) * 0.12)
        return (minimumAltitude - padding)...(maximumAltitude + padding)
    }

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 15) {
                DetailSectionTitle(title: title, systemImage: "mountain.2.fill")

                if samples.isEmpty {
                    Text("暂无海拔数据")
                        .font(.subheadline)
                        .foregroundStyle(TrailBoxColor.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    HStack(spacing: 0) {
                        profileMetric(minimumAltitude.map(DisplayFormat.elevation) ?? "-", "最低")
                        profileMetric(maximumAltitude.map(DisplayFormat.elevation) ?? "-", "最高")
                        profileMetric(averageAltitude.map(DisplayFormat.elevation) ?? "-", "平均")
                    }

                    Chart(samples) { sample in
                        AreaMark(
                            x: .value("距离", sample.distanceKM),
                            yStart: .value("基准", altitudeDomain.lowerBound),
                            yEnd: .value("海拔", sample.altitude)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [TrailBoxColor.primary.opacity(0.32), TrailBoxColor.primary.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("距离", sample.distanceKM),
                            y: .value("海拔", sample.altitude)
                        )
                        .foregroundStyle(TrailBoxColor.primaryDark)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                    }
                    .chartYScale(domain: altitudeDomain)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                                .foregroundStyle(TrailBoxColor.border)
                            AxisValueLabel {
                                if let distance = value.as(Double.self) {
                                    Text(profileDistanceLabel(distance))
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(TrailBoxColor.secondaryText)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                                .foregroundStyle(TrailBoxColor.border)
                            AxisValueLabel {
                                if let altitude = value.as(Double.self) {
                                    Text("\(altitude, specifier: "%.0f") m")
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(TrailBoxColor.secondaryText)
                        }
                    }
                    .chartPlotStyle { plotArea in
                        plotArea
                            .background(TrailBoxColor.surfaceMuted.opacity(0.42))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .frame(height: 210)

                    Label("横轴按沿途距离展示", systemImage: "arrow.left.and.right")
                        .font(.caption2)
                        .foregroundStyle(TrailBoxColor.secondaryText)
                }
            }
        }
    }

    private func profileMetric(_ value: String, _ title: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TrailBoxColor.text)
            Text(title)
                .font(.caption2)
                .foregroundStyle(TrailBoxColor.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct GradeChart: View {
    let metrics: RouteMetrics

    private var maximumUphill: Double? {
        metrics.gradeSamples.map(\.grade).filter { $0 > 0 }.max()
    }

    private var maximumDownhill: Double? {
        metrics.gradeSamples.map(\.grade).filter { $0 < 0 }.min()
    }

    private var gradeDomain: ClosedRange<Double> {
        let maximumMagnitude = metrics.gradeSamples.map { abs($0.grade) }.max() ?? 10
        let bound = min(35, max(10, ceil(maximumMagnitude / 5) * 5))
        return (-bound)...bound
    }

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 15) {
                DetailSectionTitle(title: "坡度剖面", systemImage: "chart.xyaxis.line")
                if metrics.gradeSamples.isEmpty {
                    Text("暂无可用于计算坡度的海拔数据")
                        .font(.subheadline)
                        .foregroundStyle(TrailBoxColor.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    HStack(spacing: 0) {
                        gradeMetric(metrics.averageGrade.map(formatGrade) ?? "-", "平均坡度", TrailBoxColor.stone)
                        gradeMetric(maximumUphill.map(formatGrade) ?? "-", "最大上坡", TrailBoxColor.primary)
                        gradeMetric(maximumDownhill.map(formatGrade) ?? "-", "最大下坡", TrailBoxColor.warning)
                    }

                    HStack(spacing: 14) {
                        ForEach(RouteMetrics.GradeCategory.allCases, id: \.self) { category in
                            HStack(spacing: 5) {
                                Circle().fill(category.color).frame(width: 7, height: 7)
                                Text(category.title).font(.caption).foregroundStyle(TrailBoxColor.secondaryText)
                            }
                        }
                    }
                    Chart {
                        RuleMark(y: .value("零坡度", 0)).foregroundStyle(TrailBoxColor.border)
                        ForEach(metrics.gradeSegments) { segment in
                            ForEach(segment.samples) { sample in
                                AreaMark(
                                    x: .value("距离", sample.distanceM / 1_000),
                                    yStart: .value("基准", 0),
                                    yEnd: .value("坡度", sample.grade),
                                    series: .value("区段填充", segment.id)
                                )
                                .foregroundStyle(segment.category.color.opacity(0.13))
                                .interpolationMethod(.catmullRom)

                                LineMark(
                                    x: .value("距离", sample.distanceM / 1_000),
                                    y: .value("坡度", sample.grade),
                                    series: .value("区段", segment.id)
                                )
                                .foregroundStyle(segment.category.color)
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                .interpolationMethod(.catmullRom)
                            }
                        }
                    }
                    .chartYScale(domain: gradeDomain)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                                .foregroundStyle(TrailBoxColor.border)
                            AxisValueLabel {
                                if let distance = value.as(Double.self) {
                                    Text(profileDistanceLabel(distance))
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(TrailBoxColor.secondaryText)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                                .foregroundStyle(TrailBoxColor.border)
                            AxisValueLabel {
                                if let grade = value.as(Double.self) {
                                    Text("\(grade, specifier: "%.0f")%")
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(TrailBoxColor.secondaryText)
                        }
                    }
                    .chartLegend(.hidden)
                    .chartPlotStyle { plotArea in
                        plotArea
                            .background(TrailBoxColor.surfaceMuted.opacity(0.42))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .frame(height: 210)
                }
            }
        }
    }

    private func gradeMetric(_ value: String, _ title: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(TrailBoxColor.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatGrade(_ grade: Double) -> String {
        String(format: "%+.1f%%", grade)
    }
}

private struct ActivityCharts: View {
    let points: [TrackPoint]

    private let heartRateSamples: [ActivityChartSample]
    private let paceSamples: [ActivityChartSample]

    init(points: [TrackPoint]) {
        self.points = points
        heartRateSamples = ActivityChartSampleBuilder.heartRateSamples(from: points)
        paceSamples = ActivityChartSampleBuilder.paceSamples(from: points)
    }

    var body: some View {
        VStack(spacing: 16) {
            chart(title: "心率变化", systemImage: "heart.fill", samples: heartRateSamples, color: TrailBoxColor.danger, unit: "bpm")
            chart(title: "配速变化", systemImage: "speedometer", samples: paceSamples, color: TrailBoxColor.sky, unit: "min/km")
        }
    }

    private func chart(title: String, systemImage: String, samples: [ActivityChartSample], color: Color, unit: String) -> some View {
        let minimum = samples.map(\.value).min() ?? 0
        let maximum = samples.map(\.value).max() ?? 1
        let padding = max(0.5, (maximum - minimum) * 0.14)
        let lowerBound = max(0, minimum - padding)
        let upperBound = maximum + padding
        let average = samples.isEmpty ? nil : samples.reduce(0) { $0 + $1.value } / Double(samples.count)

        return SectionCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    DetailSectionTitle(title: title, systemImage: systemImage)
                    Spacer()
                    if let average {
                        Text("均值 \(formattedActivityValue(average, unit: unit)) \(unit)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(TrailBoxColor.secondaryText)
                    }
                }
                if samples.isEmpty {
                    Text("暂无可用数据")
                        .font(.subheadline)
                        .foregroundStyle(TrailBoxColor.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    Chart(samples) { sample in
                        AreaMark(
                            x: .value("距离", sample.distanceKM),
                            yStart: .value("基准", lowerBound),
                            yEnd: .value(unit, sample.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [color.opacity(0.24), color.opacity(0.025)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("距离", sample.distanceKM),
                            y: .value(unit, sample.value)
                        )
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                    }
                    .chartYScale(domain: lowerBound...upperBound)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                                .foregroundStyle(TrailBoxColor.border)
                            AxisValueLabel {
                                if let distance = value.as(Double.self) {
                                    Text(profileDistanceLabel(distance))
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(TrailBoxColor.secondaryText)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                                .foregroundStyle(TrailBoxColor.border)
                            AxisValueLabel {
                                if let metric = value.as(Double.self) {
                                    Text(metric, format: .number.precision(.fractionLength(unit == "bpm" ? 0 : 1)))
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(TrailBoxColor.secondaryText)
                        }
                    }
                    .chartPlotStyle { plotArea in
                        plotArea
                            .background(TrailBoxColor.surfaceMuted.opacity(0.42))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .frame(height: 190)
                }
            }
        }
    }

    private func formattedActivityValue(_ value: Double, unit: String) -> String {
        String(format: unit == "bpm" ? "%.0f" : "%.1f", value)
    }
}

private struct ActivityChartSample: Identifiable {
    let id: Int
    let distanceKM: Double
    let value: Double
}

/// Produces display-only samples. Raw track points remain available to the rest of the detail view.
private enum ActivityChartSampleBuilder {
    private static let maximumSampleCount = 120

    static func heartRateSamples(from points: [TrackPoint]) -> [ActivityChartSample] {
        let samples = bucketedSamples(from: points) { point in
            guard let heartRate = point.heartRate, (40...230).contains(heartRate) else { return nil }
            return Double(heartRate)
        }
        return exponentiallySmoothed(samples, alpha: 0.35)
    }

    static func paceSamples(from points: [TrackPoint]) -> [ActivityChartSample] {
        let samples = bucketedSamples(from: points) { point in
            // FIT/GPX speed is meters per second. Ignore stopped and implausibly fast readings.
            guard let speed = point.speed, speed >= 0.4, speed <= 8.5 else { return nil }
            let minutesPerKilometer = 1_000 / speed / 60
            return (2...42).contains(minutesPerKilometer) ? minutesPerKilometer : nil
        }
        return medianSmoothed(samples, windowSize: 7)
    }

    private static func bucketedSamples(
        from points: [TrackPoint],
        value: (TrackPoint) -> Double?
    ) -> [ActivityChartSample] {
        guard points.count > 1 else { return [] }
        let distances = cumulativeDistances(for: points)
        guard let totalDistance = distances.last, totalDistance > 0 else { return [] }

        // 100 m buckets remove high-frequency jitter. For very long routes the bucket grows
        // just enough to cap rendering work at roughly 120 points.
        let bucketWidth = max(100, totalDistance / Double(maximumSampleCount))
        var buckets: [Int: [(distance: Double, value: Double)]] = [:]

        for (point, distance) in zip(points, distances) {
            guard let metric = value(point) else { continue }
            let bucket = Int(distance / bucketWidth)
            buckets[bucket, default: []].append((distance, metric))
        }

        return buckets.keys.sorted().compactMap { bucket in
            guard let values = buckets[bucket], !values.isEmpty else { return nil }
            let distances = values.map(\.distance).sorted()
            let metrics = values.map(\.value).sorted()
            return ActivityChartSample(
                id: bucket,
                distanceKM: median(of: distances) / 1_000,
                value: median(of: metrics)
            )
        }
    }

    static func cumulativeDistances(for points: [TrackPoint]) -> [Double] {
        let recorded = points.compactMap(\.distance)
        if recorded.count == points.count,
           let first = recorded.first,
           let last = recorded.last,
           last > first,
           zip(recorded, recorded.dropFirst()).allSatisfy({ $0 <= $1 }) {
            return recorded.map { $0 - first }
        }

        var result = [0.0]
        for (previous, current) in zip(points, points.dropFirst()) {
            let from = CLLocation(latitude: previous.lat, longitude: previous.lon)
            let to = CLLocation(latitude: current.lat, longitude: current.lon)
            result.append(result.last! + from.distance(from: to))
        }
        return result
    }

    private static func exponentiallySmoothed(_ samples: [ActivityChartSample], alpha: Double) -> [ActivityChartSample] {
        guard var previous = samples.first?.value else { return [] }
        return samples.map { sample in
            previous += alpha * (sample.value - previous)
            return ActivityChartSample(id: sample.id, distanceKM: sample.distanceKM, value: previous)
        }
    }

    private static func medianSmoothed(_ samples: [ActivityChartSample], windowSize: Int) -> [ActivityChartSample] {
        let radius = windowSize / 2
        return samples.indices.map { index in
            let lower = max(samples.startIndex, index - radius)
            let upper = min(samples.endIndex, index + radius + 1)
            return ActivityChartSample(id: samples[index].id, distanceKM: samples[index].distanceKM, value: median(of: Array(samples[lower..<upper].map(\.value))))
        }
    }

    private static func median(of values: [Double]) -> Double {
        let middle = values.count / 2
        return values.count.isMultiple(of: 2) ? (values[middle - 1] + values[middle]) / 2 : values[middle]
    }
}

struct RouteMapPOI: Identifiable, Equatable {
    let id: String
    let name: String
    let type: String
    let latitude: Double
    let longitude: Double
}

struct TrackMap: UIViewRepresentable {
    let points: [TrackPoint]
    var pois: [RouteMapPOI] = []

    func makeUIView(context: Context) -> MKMapView { let map = MKMapView(); map.isRotateEnabled = false; map.showsCompass = false; return map }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays); map.removeAnnotations(map.annotations)
        let coordinates = points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        guard coordinates.count > 1 else { return }
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        map.addOverlay(polyline)
        let start = MKPointAnnotation(); start.coordinate = coordinates[0]; start.title = "起点"
        let end = MKPointAnnotation(); end.coordinate = coordinates[coordinates.count - 1]; end.title = "终点"
        map.addAnnotations([start, end])
        map.addAnnotations(pois.map { poi in
            let annotation = MKPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude)
            annotation.title = poi.name
            annotation.subtitle = poi.type
            return annotation
        })
        map.setVisibleMapRect(polyline.boundingMapRect, edgePadding: UIEdgeInsets(top: 36, left: 28, bottom: 36, right: 28), animated: false)
        map.delegate = context.coordinator
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer { let renderer = MKPolylineRenderer(overlay: overlay); renderer.strokeColor = UIColor(red: 0.09, green: 0.42, blue: 0.23, alpha: 1); renderer.lineWidth = 4; renderer.lineJoin = .round; renderer.lineCap = .round; return renderer }
    }
}
