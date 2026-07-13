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
        var color: Color { switch self { case .climb: .green; case .descent: .orange; case .flat: .gray } }
    }

    let elevationRange: Double?
    let maximumGrade: Double?
    let averageGrade: Double?
    let difficulty: String?
    let gradeSamples: [GradeSample]

    var gradeSegments: [GradeSegment] {
        guard let first = gradeSamples.first else { return [] }
        var segments: [GradeSegment] = []
        var category = first.category
        var samples = [first]

        for sample in gradeSamples.dropFirst() {
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

struct TrackDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var savedRoutes: SavedRoutesStore
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
    @State private var aiAnalysisRaw: String?
    @State private var isAnalyzing = false
    @State private var isVoiceGestureActive = false
    @State private var capturedVoiceText = ""
    @State private var showFullscreenMap = false
    @State private var showSharePreview = false
    @State private var showReport = false
    @State private var showRouteFeedback = false
    @State private var navigationDestination: NavigationDestination?
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
        .background(TrailBoxColor.background)
        .navigationTitle(isPublicSource ? "轨迹详情" : "记录详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
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
    }

    private func isOwner(of track: Track) -> Bool {
        guard let currentUserID = session.user?.id, let trackUserID = track.userID else { return false }
        return currentUserID == trackUserID
    }

    private func details(_ track: Track) -> some View {
        let metrics = RouteMetrics(points: track.points)
        return ZStack(alignment: .top) {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isPublicSource {
                    VStack(alignment: .leading, spacing: 5) { Text(track.name).font(.title2.bold()).foregroundStyle(TrailBoxColor.text); if let description = track.description { Text(description).font(.subheadline).foregroundStyle(TrailBoxColor.secondaryText) } }.padding(.horizontal, 16).padding(.top, 8)
                } else { activityHero(track).padding(.horizontal, 16).padding(.top, 8) }
                if !isPublicSource { analysisCard(track) }
                if !isPublicSource, !routeIntelligence.activityMatches.isEmpty {
                    activityMatchesCard
                        .padding(.horizontal, 16)
                }
                ZStack(alignment: .topTrailing) {
                    TrackMap(points: track.points, pois: routeMapPOIs).frame(height: 280)
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
                if let start = track.points.first, let end = track.points.last {
                    HStack(spacing: 12) {
                        endpointButton(title: "起点", point: start, trackName: track.name, color: TrailBoxColor.primaryDark)
                        endpointButton(title: "终点", point: end, trackName: track.name, color: TrailBoxColor.danger)
                    }.padding(.horizontal, 16)
                }
                SectionCard {
                    HStack(spacing: 0) {
                        metric(DisplayFormat.distance(track.distanceM), "距离")
                        metric(DisplayFormat.elevation(track.elevationGainM), "爬升")
                        metric(DisplayFormat.elevation(track.elevationLossM), "下降")
                        metric(track.points.compactMap(\.altitude).max().map(DisplayFormat.elevation) ?? "-", "最高海拔")
                    }
                }.padding(.horizontal, 16)
                if isPublicSource {
                    SectionCard {
                        HStack(spacing: 0) {
                            metric(metrics.elevationRange.map(DisplayFormat.elevation) ?? "-", "海拔落差")
                            metric(metrics.maximumGrade.map(formatGrade) ?? "-", "最大坡度")
                            metric(metrics.averageGrade.map(formatGrade) ?? "-", "平均坡度")
                            difficultyMetric(metrics.difficulty)
                        }
                    }.padding(.horizontal, 16)
                    routeIntelligenceSections(track)
                }
                ElevationChart(points: track.points, title: "海拔剖面").padding(.horizontal, 16)
                if !isPublicSource {
                    ActivityCharts(points: track.points).padding(.horizontal, 16)
                } else {
                    GradeChart(metrics: metrics).padding(.horizontal, 16)
                }
                if track.city != nil || !track.tagList.isEmpty { SectionCard { VStack(alignment: .leading, spacing: 10) { if let city = track.city { HStack { Text("城市").foregroundStyle(TrailBoxColor.secondaryText); Spacer(); Text(city).fontWeight(.semibold) } }; if !track.tagList.isEmpty { Divider(); VStack(alignment: .leading, spacing: 6) { Text("标签").font(.headline); Text(track.tagList.joined(separator: " · ")).font(.subheadline).foregroundStyle(TrailBoxColor.secondaryText) } } } }.padding(.horizontal, 16) }
                if let reason = track.recommendationReason, !reason.isEmpty, isPublicSource {
                    SectionCard {
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
                    .padding(.horizontal, 16)
                }
            }.padding(.bottom, 24)
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
                        Image(systemName: savedRoutes.isSaved(track.id) ? "bookmark.fill" : "bookmark")
                    }
                    .disabled(savedRoutes.savingTrackIDs.contains(track.id))
                    .accessibilityLabel(savedRoutes.isSaved(track.id) ? "取消收藏路线" : "收藏路线")
                }
                if !isPublicSource {
                    Menu {
                        Button("编辑记录") { showEdit = true }
                        Button("删除记录", role: .destructive) { showDeleteConfirmation = true }
                    } label: { Image(systemName: "ellipsis") }
                } else {
                    Menu {
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
        .safeAreaInset(edge: .bottom, spacing: 0) { detailActions(track) }
        .task(id: track.id) {
            guard isPublicSource else { return }
            await routeIntelligence.discoverNearbyPOIs(trackID: track.id, points: track.points)
        }
    }

    @ViewBuilder
    private func routeIntelligenceSections(_ track: Track) -> some View {
        if routeIntelligence.isLoading && routeIntelligence.analysis == nil {
            routeSkeletonCard(title: "正在生成路线分析", rows: 3)
                .padding(.horizontal, 16)
                .transition(.opacity)
        } else if routeIntelligence.analysis == nil, let message = routeIntelligence.errorMessage {
            SectionCard {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(TrailBoxColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .transition(.opacity)
        }

        if let fit = routeIntelligence.personalFit {
            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("与你的能力匹配", systemImage: "figure.run.circle.fill")
                            .font(.headline)
                            .foregroundStyle(TrailBoxColor.text)
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
                        Text("路线分析").font(.headline)
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
                        Text("出发准备").font(.headline)
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

        if let weather = routeIntelligence.weather {
            weatherCard(weather)
                .padding(.horizontal, 16)
                .transition(.opacity)
        } else if routeIntelligence.isLoading {
            routeSkeletonCard(title: "正在获取路线天气", rows: 2)
                .padding(.horizontal, 16)
                .transition(.opacity)
        }

        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("沿途设施").font(.headline)
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
                if let message = routeIntelligence.errorMessage, routeIntelligence.analysis != nil {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(TrailBoxColor.danger)
                }
                sourceFootnote("地图数据与跑友确认")
            }
        }
        .padding(.horizontal, 16)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: routeIntelligence.isDiscoveringPOIs)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: routeIntelligence.pois.count + routeIntelligence.discoveredPOIs.count)

        if !routeIntelligence.conditions.isEmpty {
            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("近期路况").font(.headline)
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
                        Label("跑友完成记录", systemImage: "checkmark.circle.fill")
                            .font(.headline)
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
                        Text("跑友评价").font(.headline)
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

    private func weatherCard(_ weather: RouteWeather) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("路线天气", systemImage: weatherIcon(weather.current.weatherCode))
                        .font(.headline)
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
                Label("匹配到公开路线", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.headline)
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
                Button { download(track) } label: {
                    Label("下载 GPX", systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .foregroundStyle(TrailBoxColor.primaryDark)
                .buttonStyle(.plain)
                .trailBoxGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button { showSharePreview = true } label: {
                    Label(isPublicSource ? "分享路线" : "分享记录", systemImage: "square.and.arrow.up")
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

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.headline).foregroundStyle(TrailBoxColor.text).lineLimit(1).minimumScaleFactor(0.8)
            Text(label).font(.caption).foregroundStyle(TrailBoxColor.secondaryText).lineLimit(1)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
    private func activityHero(_ track: Track) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(DisplayFormat.date(track.startTime ?? track.createdAt) + (track.sport.map { " · \($0)" } ?? "")).font(.subheadline).foregroundStyle(TrailBoxColor.secondaryText)
                Text(track.name).font(.system(.title2, design: .rounded, weight: .heavy))
                HStack { Text("基础耐力").font(.caption.weight(.bold)).foregroundStyle(TrailBoxColor.primaryDark).padding(.horizontal, 10).padding(.vertical, 6).background(TrailBoxColor.primary.opacity(0.12)).clipShape(Capsule()); Text(track.isPublic ? "公开路线" : "私有记录").font(.caption.weight(.bold)).foregroundStyle(track.isPublic ? TrailBoxColor.primaryDark : TrailBoxColor.secondaryText).padding(.horizontal, 10).padding(.vertical, 6).background((track.isPublic ? TrailBoxColor.primary : TrailBoxColor.secondaryText).opacity(0.12)).clipShape(Capsule()) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity)
    }
    private func analysisCard(_ track: Track) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("AI 运动分析", systemImage: "sparkles").font(.headline.weight(.bold))
                if isAnalyzing {
                    Text("分析中…").font(.headline.weight(.bold)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 14).background(TrailBoxColor.primary).clipShape(RoundedRectangle(cornerRadius: 10))
                    Divider()
                    PwaAIAnalysisProgress()
                } else if let rawAnalysis = aiAnalysisRaw ?? track.aiAnalysisText {
                    if !capturedVoiceText.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("本次感受").font(.caption.weight(.bold)).foregroundStyle(TrailBoxColor.secondaryText)
                            Text("“\(capturedVoiceText)”").font(.subheadline).foregroundStyle(TrailBoxColor.text).lineLimit(2)
                            Text("已用于生成本次 AI 分析").font(.caption).foregroundStyle(TrailBoxColor.secondaryText)
                        }
                        .padding(12)
                        .background(TrailBoxColor.background)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    if let summary = aiAnalysis?.cardSummary, !summary.isEmpty {
                        Text(summary)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(TrailBoxColor.text)
                            .lineSpacing(3)
                            .padding(12)
                            .background(TrailBoxColor.primary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Divider()
                    PwaAIAnalysisText(text: rawAnalysis)
                } else {
                    Text("说说这次感觉，AI 会结合数据给你更准确的建议。").font(.subheadline).foregroundStyle(TrailBoxColor.secondaryText)
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
                        }.padding(12).background(TrailBoxColor.background).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Label(isVoiceGestureActive ? "松手结束录音" : capturedVoiceText.isEmpty ? "按住说说这次感受" : "按住重新说", systemImage: isVoiceGestureActive ? "waveform" : "mic.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 56)
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                            .trailBoxGlass(
                                tint: isVoiceGestureActive ? .black : TrailBoxColor.primary,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .gesture(voiceStartGesture())
                    Button(capturedVoiceText.isEmpty ? "跳过体感，直接分析" : "开始 AI 分析") {
                        analyze(track, feeling: ActivityFeeling(overallFeeling: nil, processTags: [], bodyTags: [], routeEnvTags: [], painDetails: [], voiceText: capturedVoiceText, textNote: ""))
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TrailBoxColor.primaryDark)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                    .buttonStyle(.plain)
                    .trailBoxGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }.padding(.horizontal, 16)
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
        guard session.isAuthenticated, let token = session.token else {
            session.requireAuthentication()
            return
        }
        Task {
            do {
                shareFile = ActivityFile(url: try await APIClient.shared.downloadGPX(trackID: track.id, token: token))
            } catch APIError.unauthorized {
                session.handle(APIError.unauthorized)
                session.requireAuthentication()
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
        guard let token = session.token else { return }
        isAnalyzing = true
        Task { do { let result: AIAnalysisResponse = try await APIClient.shared.request("/tracks/\(track.id)/ai-analysis", method: "POST", body: AIAnalysisRequest(userFeeling: feeling), token: token); aiAnalysis = result.analysis; aiAnalysisRaw = result.rawAnalysis } catch { actionError = error.localizedDescription }; isAnalyzing = false }
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
    @State private var stepIndex = 0
    private let steps = [
        "读取这次运动的轨迹、心率、步频和坡度数据",
        "整理爬升、下降、配速波动和停留片段",
        "把关键训练信号交给 AI 教练判断",
        "正在生成简短建议，请稍等片刻"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("正在分析，请稍等…").font(.subheadline.weight(.semibold))
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 8) {
                    Text(index < stepIndex ? "✓" : index == stepIndex ? "…" : "")
                        .font(.subheadline.weight(.bold)).foregroundStyle(TrailBoxColor.primary).frame(width: 20)
                    Text(step).font(.caption).foregroundStyle(index <= stepIndex ? TrailBoxColor.text : TrailBoxColor.secondaryText)
                }.frame(minHeight: 24)
            }
        }
        .task {
            while !Task.isCancelled && stepIndex < steps.count - 1 {
                try? await Task.sleep(for: .seconds(1.8))
                guard !Task.isCancelled else { return }
                stepIndex += 1
            }
        }
    }
}

private struct PwaAIAnalysisText: View {
    let text: String
    private var blocks: [(title: String?, content: String)] {
        let pattern = #"【([^】]+)】"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [(nil, text)] }
        let source = text.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        guard !matches.isEmpty else { return [(nil, source)] }
        var result: [(String?, String)] = []
        for (index, match) in matches.enumerated() {
            let title = Range(match.range(at: 1), in: source).map { String(source[$0]) }
            let contentStart = match.range.location + match.range.length
            let contentEnd = index + 1 < matches.count ? matches[index + 1].range.location : (source as NSString).length
            let range = NSRange(location: contentStart, length: max(0, contentEnd - contentStart))
            let content = (source as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            result.append((title, content))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                VStack(alignment: .leading, spacing: 8) {
                    if let title = block.title {
                        Text("【\(title)】").font(.system(.headline, design: .rounded, weight: .bold)).foregroundStyle(TrailBoxColor.text)
                    }
                    contentView(for: block)
                }
                if index < blocks.count - 1 { Divider().overlay(TrailBoxColor.border) }
            }
        }
    }

    @ViewBuilder private func contentView(for block: (title: String?, content: String)) -> some View {
        if let title = block.title, title.contains("改进") || title.contains("怎么改") {
            let items = block.content.split(whereSeparator: { $0.isNewline }).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 9) {
                        Text("\(index + 1)").font(.caption.weight(.bold)).foregroundStyle(.white).frame(width: 20, height: 20).background(TrailBoxColor.primary).clipShape(Circle())
                        Text(item.replacingOccurrences(of: #"^\d+[\.、]\s*"#, with: "", options: .regularExpression)).font(.subheadline).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } else if let title = block.title, title == "注意" || title.contains("风险") {
            Text(block.content).font(.subheadline).lineSpacing(4).fixedSize(horizontal: false, vertical: true).padding(12).background(Color.orange.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            Text(block.content).font(.subheadline).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
        }
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

private struct ElevationChart: View {
    let points: [TrackPoint]
    let title: String
    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                if points.contains(where: { $0.altitude != nil }) {
                    Chart(Array(points.enumerated()), id: \.offset) { index, point in
                        if let altitude = point.altitude { AreaMark(x: .value("点", index), y: .value("海拔", altitude)).foregroundStyle(TrailBoxColor.primary.opacity(0.22)).interpolationMethod(.catmullRom); LineMark(x: .value("点", index), y: .value("海拔", altitude)).foregroundStyle(TrailBoxColor.primaryDark).interpolationMethod(.catmullRom) }
                    }.chartXAxis(.hidden).chartYAxis { AxisMarks(position: .leading) }.frame(height: 180)
                } else { Text("暂无海拔数据").font(.subheadline).foregroundStyle(TrailBoxColor.secondaryText).frame(maxWidth: .infinity, minHeight: 100) }
            }
        }
    }
}

private struct GradeChart: View {
    let metrics: RouteMetrics

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("坡度剖面").font(.headline)
                if metrics.gradeSamples.isEmpty {
                    Text("暂无可用于计算坡度的海拔数据").font(.subheadline).foregroundStyle(TrailBoxColor.secondaryText).frame(maxWidth: .infinity, minHeight: 100)
                } else {
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
                                LineMark(
                                    x: .value("距离", sample.distanceM / 1_000),
                                    y: .value("坡度", sample.grade),
                                    series: .value("区段", segment.id)
                                )
                                .foregroundStyle(segment.category.color)
                                .interpolationMethod(.catmullRom)
                            }
                        }
                    }
                    .chartXAxisLabel("距离 (km)")
                    .chartYAxisLabel("坡度 (%)")
                    .chartLegend(.hidden)
                    .frame(height: 180)
                }
            }
        }
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
            chart(title: "心率变化", samples: heartRateSamples, color: .red, unit: "bpm")
            chart(title: "配速变化", samples: paceSamples, color: .blue, unit: "min/km")
        }
    }

    private func chart(title: String, samples: [ActivityChartSample], color: Color, unit: String) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                if samples.isEmpty {
                    Text("暂无可用数据").font(.subheadline).foregroundStyle(TrailBoxColor.secondaryText).frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    Chart(samples) { sample in
                        LineMark(
                            x: .value("距离", sample.distanceKM),
                            y: .value(unit, sample.value)
                        )
                        .foregroundStyle(color)
                        .interpolationMethod(.monotone)
                    }
                    .chartXAxisLabel("距离 (km)")
                    .chartYAxisLabel(unit)
                    .frame(height: 160)
                }
            }
        }
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

    private static func cumulativeDistances(for points: [TrackPoint]) -> [Double] {
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
