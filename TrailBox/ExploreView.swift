import SwiftUI

@MainActor
final class ExploreViewModel: ObservableObject {
    enum State { case loading, content, empty, failed(String) }
    @Published var state: State = .loading
    @Published var tracks: [Track] = []
    @Published private(set) var isLoadingMore = false
    @Published private(set) var canLoadMore = true
    @Published var tags: [ConfiguredTag] = []
    @Published var selectedTag: String?
    @Published var selectedCity: String?
    @Published var keyword = ""
    @Published var distanceRange = "all"
    @Published var sortBy = "newest"

    var cities: [String] { Array(Set(tracks.compactMap(\.city))).sorted() }
    var filteredTracks: [Track] {
        let result = tracks.filter { track in
            (selectedTag == nil || track.tagList.contains(selectedTag!)) && (selectedCity == nil || track.city == selectedCity)
            && (keyword.isEmpty || [track.name, track.city ?? "", track.tags ?? "", track.description ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(keyword))
            && (distanceRange == "all" || (distanceRange == "short" && track.distanceM <= 10_000) || (distanceRange == "medium" && track.distanceM > 10_000 && track.distanceM <= 30_000) || (distanceRange == "long" && track.distanceM > 30_000 && track.distanceM <= 50_000) || (distanceRange == "ultra" && track.distanceM >= 50_000))
        }
        switch sortBy { case "distanceDesc": return result.sorted { $0.distanceM > $1.distanceM }; case "elevationDesc": return result.sorted { $0.elevationGainM > $1.elevationGainM }; default: return result.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) } }
    }

    func load(token: String? = nil, isRefresh: Bool = false) async {
        // 只有首次无数据或主动刷新时才重新加载；从详情页返回等场景直接保持现有列表
        guard isRefresh || tracks.isEmpty else { return }
        if tracks.isEmpty { state = .loading }
        canLoadMore = true
        await loadPage(token: token, reset: true)
        // 下拉刷新时让指示器至少显示 0.8s，避免请求过快时用户感觉没刷新
        if isRefresh {
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
    }

    func loadMore(token: String? = nil) async {
        guard case .content = state, canLoadMore, !isLoadingMore else { return }
        await loadPage(token: token, reset: false)
    }

    private func loadPage(token: String?, reset: Bool) async {
        if !reset { isLoadingMore = true }
        do {
            let offset = reset ? 0 : tracks.count
            async let fetchedTracks: [Track] = APIClient.shared.request("/tracks/public?include_points=true&limit=20&offset=\(offset)", token: token)
            async let fetchedTags: [ConfiguredTag]? = reset ? APIClient.shared.request("/tags") : nil
            let page = try await fetchedTracks
            if reset {
                tracks = page
                tags = (try? await fetchedTags) ?? []
            } else {
                let existingIDs = Set(tracks.map(\.id))
                tracks.append(contentsOf: page.filter { !existingIDs.contains($0.id) })
            }
            canLoadMore = page.count == 20 && !page.isEmpty
            state = tracks.isEmpty ? .empty : .content
        } catch {
            // 只有无数据时才显示失败页；有数据时刷新失败保持当前列表
            if reset && tracks.isEmpty { state = .failed(ErrorMessage.display(error)) }
        }
        isLoadingMore = false
    }
}

struct ExploreView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var savedRoutes: SavedRoutesStore
    @Binding var showAuthentication: Bool
    @StateObject private var viewModel = ExploreViewModel()
    @State private var showFilters = false
    @State private var showContributeSheet = false
    @State private var pendingContributeAfterAuthentication = false
    @State private var pendingSavedTrackID: String?
    @State private var navigationPath: [String] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                switch viewModel.state {
                case .loading: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty: EmptyStateView(title: "暂无公开轨迹", systemImage: "map", message: "成为第一个上传公开路线的人吧")
                case .failed(let message): EmptyStateView(title: "加载失败", systemImage: "exclamationmark.triangle", message: message).overlay(alignment: .bottom) { Button("重试") { Task { await viewModel.load(isRefresh: true) } }.padding() }
                case .content: content
                }
            }
            .background(TrailBoxColor.background)
            .navigationTitle("探索路线")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.keyword, prompt: "搜索路线、城市、标签")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showFilters = true } label: {
                        Label("筛选", systemImage: "line.3.horizontal.decrease")
                    }
                    Button { openContribution() } label: {
                        Label("贡献", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(TrailBoxColor.primaryDark, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .task { await viewModel.load(token: session.token) }
            .sheet(isPresented: $showFilters) { ExploreFilterSheet(viewModel: viewModel) }
            .sheet(isPresented: $showContributeSheet) {
                NavigationStack {
                    ContributeRouteView { _ in
                        Task { await viewModel.load(token: session.token, isRefresh: true) }
                    }
                }
            }
            .navigationDestination(for: String.self) { trackID in
                TrackDetailView(
                    trackID: trackID,
                    isPublicSource: true,
                    onDeleted: { await viewModel.load(token: session.token, isRefresh: true) },
                    onSaved: { await viewModel.load(token: session.token, isRefresh: true) }
                )
            }
            .onChange(of: session.isAuthenticated) { isAuthenticated in
                guard isAuthenticated else { return }
                if pendingContributeAfterAuthentication {
                    pendingContributeAfterAuthentication = false
                    showContributeSheet = true
                }
                if let trackID = pendingSavedTrackID, let token = session.token {
                    pendingSavedTrackID = nil
                    Task { await savedRoutes.toggle(trackID: trackID, token: token) }
                }
            }
        }
        .toolbar(navigationPath.isEmpty ? .visible : .hidden, for: .tabBar)
    }

    private func openContribution() {
        if session.isAuthenticated {
            showContributeSheet = true
        } else {
            pendingContributeAfterAuthentication = true
            showAuthentication = true
        }
    }

    private var content: some View {
        List {
            if !viewModel.tags.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            tagButton("全部", tag: nil)
                            ForEach(viewModel.tags) { tag in tagButton(tag.name, tag: tag.name) }
                        }.padding(.horizontal, 16)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if viewModel.filteredTracks.isEmpty {
                Section {
                    VStack(spacing: 8) { Image(systemName: "line.3.horizontal.decrease.circle").font(.title2).foregroundStyle(TrailBoxColor.secondaryText); Text("暂无匹配路线").font(.headline); Text("试试调整筛选条件").font(.subheadline).foregroundStyle(TrailBoxColor.secondaryText) }
                        .frame(maxWidth: .infinity).padding(.top, 48)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(viewModel.filteredTracks) { track in
                    ZStack(alignment: .topTrailing) {
                        Button { navigationPath.append(track.id) } label: { TrackCard(track: track, isActivity: false) }
                            .buttonStyle(.plain)
                        savedRouteButton(track.id)
                            .padding(12)
                    }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .onAppear { if track.id == viewModel.filteredTracks.last?.id { Task { await viewModel.loadMore(token: session.token) } } }
                }
                if viewModel.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .refreshable { @MainActor in
            await viewModel.load(token: session.token, isRefresh: true)
        }
    }

    private func savedRouteButton(_ trackID: String) -> some View {
        Button {
            guard let token = session.token else {
                pendingSavedTrackID = trackID
                showAuthentication = true
                return
            }
            Task { await savedRoutes.toggle(trackID: trackID, token: token) }
        } label: {
            Image(systemName: savedRoutes.isSaved(trackID) ? "bookmark.fill" : "bookmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(savedRoutes.isSaved(trackID) ? TrailBoxColor.primaryDark : TrailBoxColor.text)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.borderless)
        .trailBoxGlass(interactive: !savedRoutes.savingTrackIDs.contains(trackID), in: Circle())
        .contentShape(Circle())
        .zIndex(2)
        .disabled(savedRoutes.savingTrackIDs.contains(trackID))
        .accessibilityLabel(savedRoutes.isSaved(trackID) ? "取消收藏路线" : "收藏路线")
    }

    private func tagButton(_ title: String, tag: String?) -> some View {
        Button(title) { viewModel.selectedTag = tag }
            .font(.subheadline.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 7)
            .background(viewModel.selectedTag == tag ? TrailBoxColor.primary : TrailBoxColor.surface)
            .foregroundStyle(viewModel.selectedTag == tag ? .white : TrailBoxColor.text)
            .clipShape(Capsule()).overlay(Capsule().stroke(viewModel.selectedTag == tag ? TrailBoxColor.primary : TrailBoxColor.border))
    }
}

private struct ExploreFilterSheet: View {
    @ObservedObject var viewModel: ExploreViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View { NavigationStack { Form { Section("排序") { Picker("排序", selection: $viewModel.sortBy) { Text("最新发布").tag("newest"); Text("距离最长").tag("distanceDesc"); Text("爬升最高").tag("elevationDesc") } }; Section("城市") { Picker("城市", selection: $viewModel.selectedCity) { Text("全部城市").tag(String?.none); ForEach(viewModel.cities, id: \.self) { Text($0).tag(Optional($0)) } } }; Section("距离") { Picker("距离", selection: $viewModel.distanceRange) { Text("全部距离").tag("all"); Text("≤10 km").tag("short"); Text("10–30 km").tag("medium"); Text("30–50 km").tag("long"); Text("≥50 km").tag("ultra") } } }.navigationTitle("筛选与排序").toolbar { ToolbarItem(placement: .topBarLeading) { Button("重置") { viewModel.selectedCity = nil; viewModel.distanceRange = "all"; viewModel.sortBy = "newest" } }; ToolbarItem(placement: .topBarTrailing) { Button("确定") { dismiss() } } } } }
}

struct TrackCard: View {
    let track: Track
    let isActivity: Bool
    @State private var aiExpanded = true

    var body: some View {
        if isActivity { activityCard } else { exploreCard }
    }

    private var exploreCard: some View {
        VStack(spacing: 0) {
            ZStack {
                RouteThumbnail(points: track.points)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16.0 / 8.0, contentMode: .fit)
                LinearGradient(colors: [.black.opacity(0.18), .clear, .black.opacity(0.64)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("路线负荷 · \(routeEffort)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.5), in: Capsule())
                        Spacer()
                    }
                    Spacer()
                    Text(track.name).font(.headline.bold()).foregroundStyle(.white).lineLimit(2).shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                }.padding(14)
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text(subtitle).font(.caption).foregroundStyle(TrailBoxColor.secondaryText)
                    Spacer(minLength: 0)
                    if let city = track.city, !city.isEmpty {
                        Text(city).font(.caption.weight(.medium)).foregroundStyle(TrailBoxColor.primaryDark).padding(.horizontal, 8).padding(.vertical, 4).background(TrailBoxColor.primary.opacity(0.12)).clipShape(Capsule())
                    }
                }
                if !track.tagList.isEmpty { HStack(spacing: 5) { ForEach(track.tagList.prefix(3), id: \.self) { Text($0).font(.caption.weight(.medium)).foregroundStyle(TrailBoxColor.primaryDark).padding(.horizontal, 8).padding(.vertical, 4).background(TrailBoxColor.primary.opacity(0.12)).clipShape(Capsule()) } } }
                Divider().overlay(TrailBoxColor.border)
                HStack(spacing: 0) {
                    exploreStat(DisplayFormat.distance(track.distanceM), "距离", TrailBoxColor.text)
                    exploreStat(compactElevation(track.elevationGainM), "爬升", TrailBoxColor.primary)
                    exploreStat(climbDensityText, "爬升密度", routeEffortColor)
                }
            }.padding(16)
        }
        .background(TrailBoxColor.surface).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }

    private var activityCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.name).font(.headline).foregroundStyle(TrailBoxColor.text).lineLimit(2)
                        Text(activityDateAndSport).font(.caption).foregroundStyle(TrailBoxColor.secondaryText)
                    }
                    Spacer()
                    Text(track.isPublic ? "公开" : "私有").font(.caption.weight(.semibold)).foregroundStyle(track.isPublic ? TrailBoxColor.primaryDark : TrailBoxColor.secondaryText).padding(.horizontal, 8).padding(.vertical, 4).background(track.isPublic ? TrailBoxColor.primary.opacity(0.12) : TrailBoxColor.secondaryText.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Divider().padding(.vertical, 12)
                HStack { activityStat(DisplayFormat.distance(track.distanceM), "距离"); activityStat(durationText, "用时"); activityStat(DisplayFormat.elevation(track.elevationGainM), "爬升") }
                if let analysis = track.aiAnalysisText, !analysis.isEmpty { Button { aiExpanded.toggle() } label: { VStack(alignment: .leading, spacing: 6) { HStack { Text("AI 分析结论").font(.caption.weight(.bold)).foregroundStyle(TrailBoxColor.primaryDark); Spacer(); Text(aiExpanded ? "收起" : "展开").font(.caption).foregroundStyle(TrailBoxColor.secondaryText) }; if aiExpanded { Text(coreAnalysis(analysis)).font(.caption).foregroundStyle(TrailBoxColor.text).fixedSize(horizontal: false, vertical: true) } }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(TrailBoxColor.primary.opacity(0.06)).overlay(RoundedRectangle(cornerRadius: 10).stroke(TrailBoxColor.primary.opacity(0.16))).clipShape(RoundedRectangle(cornerRadius: 10)).padding(.top, 10) }.buttonStyle(.plain) } else { Text("AI 分析").font(.caption.weight(.semibold)).foregroundStyle(TrailBoxColor.secondaryText).padding(.horizontal, 12).padding(.vertical, 7).overlay(RoundedRectangle(cornerRadius: 9).stroke(TrailBoxColor.border)).padding(.top, 10) }
            }
        }
    }

    private func activityStat(_ value: String, _ label: String) -> some View { VStack(spacing: 4) { Text(value).font(.title3).foregroundStyle(TrailBoxColor.text); Text(label).font(.caption).foregroundStyle(TrailBoxColor.secondaryText) }.frame(maxWidth: .infinity) }

    private func exploreStat(_ value: String, _ label: String, _ color: Color) -> some View { VStack(spacing: 3) { Text(value).font(.title3.bold()).foregroundStyle(color); Text(label).font(.caption).foregroundStyle(TrailBoxColor.secondaryText) }.frame(maxWidth: .infinity) }
    private func compactElevation(_ value: Double) -> String { value >= 1000 ? String(format: "%.2fk", value / 1000) : String(format: "%.0f", value) }

    private var climbDensity: Double {
        guard track.distanceM > 0 else { return 0 }
        return track.elevationGainM / (track.distanceM / 1_000)
    }

    private var climbDensityText: String {
        track.distanceM > 0 ? "\(Int(climbDensity.rounded())) m/km" : "-"
    }

    private var routeEffort: String {
        let distanceKM = track.distanceM / 1_000
        if distanceKM >= 50 || climbDensity >= 140 { return "极限" }
        if distanceKM >= 30 || climbDensity >= 90 { return "挑战" }
        if distanceKM >= 15 || climbDensity >= 50 { return "进阶" }
        return "轻量"
    }

    private var routeEffortColor: Color {
        switch routeEffort {
        case "极限": return .red
        case "挑战": return .orange
        case "进阶": return .yellow.opacity(0.85)
        default: return TrailBoxColor.primaryDark
        }
    }

    private func stat(_ value: String, label: String) -> some View { VStack(alignment: .leading, spacing: 2) { Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(TrailBoxColor.text); Text(label).font(.caption2).foregroundStyle(TrailBoxColor.secondaryText) } }

    private var subtitle: String {
        if isActivity { return DisplayFormat.date(track.startTime ?? track.createdAt) }
        guard track.showContributor else { return "" }
        return "贡献者 " + (track.contributorName ?? track.contributorPublicID ?? "小野box 用户")
    }
    private var activityDateAndSport: String { subtitle + (track.sport.map { " · \($0)" } ?? "") }
    private var durationText: String { guard let seconds = track.durationSec, seconds > 0 else { return "-" }; return String(format: "%d:%02d", Int(seconds) / 3600, (Int(seconds) % 3600) / 60) }
    private func coreAnalysis(_ text: String) -> String { let sections = text.components(separatedBy: "【核心判断】"); let body = sections.count > 1 ? sections[1].components(separatedBy: "【").first ?? text : text; return body.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct RouteThumbnail: View {
    let points: [TrackPoint]
    var body: some View { Canvas { context, size in
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [Color(red: 0.93, green: 0.96, blue: 0.93), Color(red: 0.83, green: 0.89, blue: 0.84)]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
        for index in 0..<6 {
            let y = CGFloat(14 + index * 27)
            var contour = Path()
            contour.move(to: CGPoint(x: -20, y: y + (index.isMultiple(of: 2) ? 10 : -10)))
            contour.addCurve(to: CGPoint(x: size.width + 20, y: y), control1: CGPoint(x: size.width * 0.25, y: y - 22), control2: CGPoint(x: size.width * 0.72, y: y + 22))
            context.stroke(contour, with: .color(Color(red: 0.22, green: 0.36, blue: 0.26).opacity(0.12)), lineWidth: 1)
        }
        guard points.count > 1 else { return }
        // Only the bottom title overlays the image; leave a small perimeter around the route elsewhere.
        let horizontalPadding: CGFloat = 20
        let topPadding: CGFloat = 16
        let bottomPadding: CGFloat = 56
        let drawableWidth = max(1, size.width - 2 * horizontalPadding)
        let drawableHeight = max(1, size.height - topPadding - bottomPadding)

        // Use a single scale for both axes so changes to the card aspect ratio do not distort the route.
        let centerLatitude = points.map(\.lat).reduce(0, +) / Double(points.count)
        let longitudeScale = cos(centerLatitude * .pi / 180)
        let projectedPoints = points.map { CGPoint(x: CGFloat($0.lon * longitudeScale), y: CGFloat($0.lat)) }
        guard let minX = projectedPoints.map(\.x).min(), let maxX = projectedPoints.map(\.x).max(),
              let minY = projectedPoints.map(\.y).min(), let maxY = projectedPoints.map(\.y).max() else { return }
        let routeWidth = max(maxX - minX, 0.000_000_01)
        let routeHeight = max(maxY - minY, 0.000_000_01)
        let scale = min(drawableWidth / routeWidth, drawableHeight / routeHeight)
        let offsetX = horizontalPadding + (drawableWidth - routeWidth * scale) / 2
        let offsetY = topPadding + (drawableHeight - routeHeight * scale) / 2

        func position(_ point: TrackPoint) -> CGPoint {
            let x = CGFloat(point.lon * longitudeScale)
            return CGPoint(
                x: offsetX + (x - minX) * scale,
                y: offsetY + (maxY - CGFloat(point.lat)) * scale
            )
        }
        var path = Path(); path.move(to: position(points[0])); for point in points.dropFirst() { path.addLine(to: position(point)) }
        context.stroke(path, with: .color(Color(red: 0.09, green: 0.42, blue: 0.23)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
        for (point, color) in [(points.first!, Color.green), (points.last!, Color.red)] { context.fill(Path(ellipseIn: CGRect(x: position(point).x - 5, y: position(point).y - 5, width: 10, height: 10)), with: .color(color)) }
    } }
}
