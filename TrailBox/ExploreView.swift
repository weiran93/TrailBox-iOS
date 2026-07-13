import SwiftUI

private enum RouteEstimate {
    static func hours(for track: Track) -> Double {
        let distanceHours = max(0, track.distanceM / 1_000) / 5.5
        let climbHours = max(0, track.elevationGainM) / 650
        return max(0.5, distanceHours + climbHours)
    }

    static func durationText(for track: Track) -> String {
        let estimate = hours(for: track)
        let lower = roundedHalfHour(max(0.5, estimate * 0.82))
        let upper = roundedHalfHour(max(lower + 0.5, estimate * 1.2))
        return "\(formatHours(lower))–\(formatHours(upper))小时"
    }

    private static func roundedHalfHour(_ value: Double) -> Double {
        (value * 2).rounded() / 2
    }

    private static func formatHours(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

fileprivate enum RouteIntent: String, CaseIterable, Identifiable {
    case quick
    case halfDay
    case fullDay
    case beginner
    case climbing
    case longDistance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quick: return "2 小时左右"
        case .halfDay: return "半日路线"
        case .fullDay: return "全天挑战"
        case .beginner: return "新手友好"
        case .climbing: return "爬升训练"
        case .longDistance: return "长距离"
        }
    }

    var subtitle: String {
        switch self {
        case .quick: return "短时出发"
        case .halfDay: return "约 2–5 小时"
        case .fullDay: return "预留一整天"
        case .beginner: return "距离与爬升适中"
        case .climbing: return "高爬升密度"
        case .longDistance: return "25 km 以上"
        }
    }

    var systemImage: String {
        switch self {
        case .quick: return "clock.fill"
        case .halfDay: return "sun.horizon.fill"
        case .fullDay: return "sun.max.fill"
        case .beginner: return "leaf.fill"
        case .climbing: return "mountain.2.fill"
        case .longDistance: return "point.topleft.down.to.point.bottomright.curvepath"
        }
    }

    func matches(_ track: Track) -> Bool {
        let hours = RouteEstimate.hours(for: track)
        let distanceKM = track.distanceM / 1_000
        let climbDensity = distanceKM > 0 ? track.elevationGainM / distanceKM : 0
        switch self {
        case .quick:
            return hours <= 2.5
        case .halfDay:
            return hours > 2.5 && hours <= 5.5
        case .fullDay:
            return hours > 5.5
        case .beginner:
            return distanceKM <= 15 && track.elevationGainM <= 700 && climbDensity < 60
        case .climbing:
            return track.elevationGainM >= 1_000 || climbDensity >= 80
        case .longDistance:
            return distanceKM >= 25
        }
    }
}

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
    @Published fileprivate var selectedIntent: RouteIntent?

    var cities: [String] { Array(Set(tracks.compactMap(\.city))).sorted() }
    fileprivate var availableIntents: [RouteIntent] {
        RouteIntent.allCases.filter { intent in tracks.contains(where: intent.matches) }
    }
    var sheetFilterCount: Int {
        [selectedCity != nil, distanceRange != "all", sortBy != "newest"].filter { $0 }.count
    }
    var hasActiveFilters: Bool {
        selectedIntent != nil || selectedTag != nil || selectedCity != nil || distanceRange != "all" || sortBy != "newest" || !trimmedKeyword.isEmpty
    }
    var activeFilterSummary: String {
        var items: [String] = []
        if let selectedIntent { items.append(selectedIntent.title) }
        if let selectedTag { items.append(selectedTag) }
        if let selectedCity { items.append(selectedCity) }
        if distanceRange != "all" { items.append(distanceRangeTitle) }
        if sortBy != "newest" { items.append(sortTitle) }
        if !trimmedKeyword.isEmpty { items.append("“\(trimmedKeyword)”") }
        return items.joined(separator: " · ")
    }
    var filteredTracks: [Track] {
        let result = tracks.filter { track in
            (selectedIntent == nil || selectedIntent?.matches(track) == true)
            && (selectedTag == nil || track.tagList.contains(selectedTag ?? "")) && (selectedCity == nil || track.city == selectedCity)
            && (trimmedKeyword.isEmpty || [track.name, track.city ?? "", track.tags ?? "", track.description ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(trimmedKeyword))
            && (distanceRange == "all" || (distanceRange == "short" && track.distanceM <= 10_000) || (distanceRange == "medium" && track.distanceM > 10_000 && track.distanceM <= 30_000) || (distanceRange == "long" && track.distanceM > 30_000 && track.distanceM <= 50_000) || (distanceRange == "ultra" && track.distanceM >= 50_000))
        }
        switch sortBy { case "distanceDesc": return result.sorted { $0.distanceM > $1.distanceM }; case "elevationDesc": return result.sorted { $0.elevationGainM > $1.elevationGainM }; default: return result.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) } }
    }

    func resetFilters() {
        selectedIntent = nil
        selectedTag = nil
        selectedCity = nil
        keyword = ""
        distanceRange = "all"
        sortBy = "newest"
    }

    private var trimmedKeyword: String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var distanceRangeTitle: String {
        switch distanceRange {
        case "short": return "≤10 km"
        case "medium": return "10–30 km"
        case "long": return "30–50 km"
        case "ultra": return "≥50 km"
        default: return "全部距离"
        }
    }

    private var sortTitle: String {
        switch sortBy {
        case "distanceDesc": return "距离最长"
        case "elevationDesc": return "爬升最高"
        default: return "最新发布"
        }
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
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .frame(width: 30, height: 30)
                            if viewModel.sheetFilterCount > 0 {
                                Text("\(viewModel.sheetFilterCount)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 16, height: 16)
                                    .background(TrailBoxColor.danger, in: Circle())
                            }
                        }
                        .frame(width: 34, height: 32)
                    }
                    .accessibilityLabel(viewModel.sheetFilterCount > 0 ? "筛选，已启用 \(viewModel.sheetFilterCount) 项" : "筛选")
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
            if !viewModel.availableIntents.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("这次想怎么跑？")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(TrailBoxColor.text)
                            .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(viewModel.availableIntents) { intent in
                                    intentButton(intent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 2)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

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

            if viewModel.hasActiveFilters {
                Section {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("当前显示 \(viewModel.filteredTracks.count) 条匹配路线")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(TrailBoxColor.text)
                            Text(viewModel.activeFilterSummary)
                                .font(.caption)
                                .foregroundStyle(TrailBoxColor.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Button("清除") { viewModel.resetFilters() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TrailBoxColor.primaryDark)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(TrailBoxColor.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(TrailBoxColor.border, lineWidth: 0.75))
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if viewModel.filteredTracks.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.title2)
                            .foregroundStyle(TrailBoxColor.secondaryText)
                        Text("暂无匹配路线").font(.headline)
                        Text("试试调整筛选条件").font(.subheadline).foregroundStyle(TrailBoxColor.secondaryText)
                        if viewModel.hasActiveFilters {
                            Button("清除全部筛选") { viewModel.resetFilters() }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(TrailBoxColor.primaryDark)
                                .frame(minHeight: 44)
                        }
                    }
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
        .scrollContentBackground(.hidden)
        .background(TrailPageBackground())
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
            Group {
                if savedRoutes.savingTrackIDs.contains(trackID) {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: savedRoutes.isSaved(trackID) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(savedRoutes.isSaved(trackID) ? TrailBoxColor.primaryDark : TrailBoxColor.text)
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.borderless)
        .trailBoxGlass(interactive: !savedRoutes.savingTrackIDs.contains(trackID), in: Circle())
        .contentShape(Circle())
        .zIndex(2)
        .disabled(savedRoutes.savingTrackIDs.contains(trackID))
        .accessibilityLabel(savedRoutes.savingTrackIDs.contains(trackID) ? "正在更新收藏" : (savedRoutes.isSaved(trackID) ? "取消收藏路线" : "收藏路线"))
    }

    private func tagButton(_ title: String, tag: String?) -> some View {
        Button(title) { viewModel.selectedTag = tag }
            .font(.subheadline.weight(.semibold)).padding(.horizontal, 13).padding(.vertical, 8)
            .background(viewModel.selectedTag == tag ? TrailBoxColor.primaryDark : TrailBoxColor.surface)
            .foregroundStyle(viewModel.selectedTag == tag ? .white : TrailBoxColor.text)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(viewModel.selectedTag == tag ? Color.clear : TrailBoxColor.border, lineWidth: 0.75))
            .shadow(color: viewModel.selectedTag == tag ? TrailBoxColor.primaryDark.opacity(0.16) : .clear, radius: 8, y: 3)
    }

    private func intentButton(_ intent: RouteIntent) -> some View {
        let isSelected = viewModel.selectedIntent == intent
        let count = viewModel.tracks.filter(intent.matches).count
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectedIntent = isSelected ? nil : intent
            }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Image(systemName: intent.systemImage)
                        .font(.system(size: 15, weight: .bold))
                    Spacer(minLength: 12)
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(isSelected ? Color.white.opacity(0.18) : TrailBoxColor.primary.opacity(0.09), in: Capsule())
                }
                Text(intent.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(intent.subtitle)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.76) : TrailBoxColor.secondaryText)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white : TrailBoxColor.primaryDark)
            .padding(12)
            .frame(width: 128, height: 82, alignment: .leading)
            .background(isSelected ? TrailBoxColor.primaryDark : TrailBoxColor.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(isSelected ? Color.clear : TrailBoxColor.border, lineWidth: 0.75)
            )
            .shadow(color: TrailBoxColor.primaryDark.opacity(isSelected ? 0.15 : 0.06), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(intent.title)，\(count) 条路线")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ExploreFilterSheet: View {
    @ObservedObject var viewModel: ExploreViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCity: String?
    @State private var distanceRange: String
    @State private var sortBy: String

    init(viewModel: ExploreViewModel) {
        self.viewModel = viewModel
        _selectedCity = State(initialValue: viewModel.selectedCity)
        _distanceRange = State(initialValue: viewModel.distanceRange)
        _sortBy = State(initialValue: viewModel.sortBy)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("排序") {
                    Picker("排序", selection: $sortBy) {
                        Text("最新发布").tag("newest")
                        Text("距离最长").tag("distanceDesc")
                        Text("爬升最高").tag("elevationDesc")
                    }
                }
                Section("城市") {
                    Picker("城市", selection: $selectedCity) {
                        Text("全部城市").tag(String?.none)
                        ForEach(viewModel.cities, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                }
                Section("距离") {
                    Picker("距离", selection: $distanceRange) {
                        Text("全部距离").tag("all")
                        Text("≤10 km").tag("short")
                        Text("10–30 km").tag("medium")
                        Text("30–50 km").tag("long")
                        Text("≥50 km").tag("ultra")
                    }
                }
                Section {
                    Button("恢复默认") {
                        selectedCity = nil
                        distanceRange = "all"
                        sortBy = "newest"
                    }
                    .foregroundStyle(TrailBoxColor.danger)
                } footer: {
                    Text("关闭页面不会应用尚未确认的修改。")
                }
            }
            .navigationTitle("筛选与排序")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("应用") {
                        viewModel.selectedCity = selectedCity
                        viewModel.distanceRange = distanceRange
                        viewModel.sortBy = sortBy
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
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
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                LinearGradient(colors: [.black.opacity(0.2), .clear, .black.opacity(0.76)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("路线负荷 · \(routeEffort)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.52), in: Capsule())
                        Spacer()
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.name)
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(1)
                        }
                    }
                }.padding(14)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    if let city = track.city, !city.isEmpty {
                        Label(city, systemImage: "mappin.and.ellipse")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TrailBoxColor.stone)
                    }
                    Spacer(minLength: 0)
                    if let sport = track.sport, !sport.isEmpty {
                        Text(sport)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TrailBoxColor.primaryDark)
                    }
                }
                if !track.tagList.isEmpty {
                    Text(track.tagList.prefix(3).map { "#\($0)" }.joined(separator: "   "))
                        .font(.caption)
                        .foregroundStyle(TrailBoxColor.secondaryText)
                        .lineLimit(1)
                }
                HStack(spacing: 0) {
                    exploreStat(DisplayFormat.distance(track.distanceM), "距离", TrailBoxColor.text)
                    exploreStat(compactElevation(track.elevationGainM), "累计爬升", TrailBoxColor.primaryDark)
                    exploreStat(RouteEstimate.durationText(for: track), "参考用时", routeEffortColor)
                }
                .padding(.vertical, 12)
                .background(TrailBoxColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(14)
        }
        .background(TrailBoxColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(TrailBoxColor.border, lineWidth: 0.75))
        .shadow(color: TrailBoxColor.primaryDark.opacity(0.11), radius: 16, y: 8)
    }

    private var activityCard: some View {
        VStack(spacing: 0) {
            ZStack {
                RouteThumbnail(points: track.points)
                    .frame(maxWidth: .infinity)
                    .frame(height: 126)
                LinearGradient(colors: [.black.opacity(0.08), .clear, .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(track.isPublic ? "公开记录" : "私人记录")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.48), in: Capsule())
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.name)
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text(activityMetadata)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)
                    }
                }
                .padding(14)
            }

            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 0) {
                    activityStat(DisplayFormat.distance(track.distanceM), "距离", TrailBoxColor.text)
                    activityStat(durationText, "用时", TrailBoxColor.sky)
                    activityStat(DisplayFormat.elevation(track.elevationGainM), "累计爬升", TrailBoxColor.primaryDark)
                }
                .padding(.vertical, 11)
                .background(TrailBoxColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let analysis = track.aiAnalysisText, !analysis.isEmpty {
                    Button { aiExpanded.toggle() } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(TrailBoxColor.primaryDark)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("AI 运动复盘").font(.caption.weight(.bold)).foregroundStyle(TrailBoxColor.primaryDark)
                                    Spacer()
                                    Image(systemName: aiExpanded ? "chevron.up" : "chevron.down")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(TrailBoxColor.secondaryText)
                                }
                                if aiExpanded {
                                    Text(coreAnalysis(analysis))
                                        .font(.caption)
                                        .foregroundStyle(TrailBoxColor.text)
                                        .lineLimit(3)
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(TrailBoxColor.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else {
                    Label("进入详情生成 AI 运动复盘", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TrailBoxColor.secondaryText)
                }
            }
            .padding(14)
        }
        .background(TrailBoxColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(TrailBoxColor.border, lineWidth: 0.75))
        .shadow(color: TrailBoxColor.primaryDark.opacity(0.09), radius: 14, y: 7)
    }

    private func activityStat(_ value: String, _ label: String, _ color: Color) -> some View { VStack(spacing: 4) { Text(value).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7); Text(label).font(.caption2.weight(.medium)).foregroundStyle(TrailBoxColor.secondaryText) }.frame(maxWidth: .infinity) }

    private func exploreStat(_ value: String, _ label: String, _ color: Color) -> some View { VStack(spacing: 4) { Text(value).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.72); Text(label).font(.caption2.weight(.medium)).foregroundStyle(TrailBoxColor.secondaryText) }.frame(maxWidth: .infinity) }
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
    private var activityMetadata: String { [activityDateAndSport, track.city].compactMap { value in value?.isEmpty == false ? value : nil }.joined(separator: " · ") }
    private var durationText: String { guard let seconds = track.durationSec, seconds > 0 else { return "-" }; return String(format: "%d:%02d", Int(seconds) / 3600, (Int(seconds) % 3600) / 60) }
    private func coreAnalysis(_ text: String) -> String { let sections = text.components(separatedBy: "【核心判断】"); let body = sections.count > 1 ? sections[1].components(separatedBy: "【").first ?? text : text; return body.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct RouteThumbnail: View {
    let points: [TrackPoint]
    var reservesBottomOverlay = true

    var body: some View { Canvas { context, size in
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [TrailBoxColor.sand.opacity(0.9), TrailBoxColor.surfaceMuted, TrailBoxColor.moss.opacity(0.32)]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
        for index in 0..<8 {
            let y = CGFloat(8 + index * 25)
            var contour = Path()
            contour.move(to: CGPoint(x: -20, y: y + (index.isMultiple(of: 2) ? 10 : -10)))
            contour.addCurve(to: CGPoint(x: size.width + 20, y: y), control1: CGPoint(x: size.width * 0.25, y: y - 22), control2: CGPoint(x: size.width * 0.72, y: y + 22))
            context.stroke(contour, with: .color(TrailBoxColor.primaryDark.opacity(index.isMultiple(of: 3) ? 0.16 : 0.09)), lineWidth: index.isMultiple(of: 3) ? 1.2 : 0.8)
        }
        guard points.count > 1 else { return }
        // Full route cards reserve space for their bottom title overlay. Compact previews do not.
        let horizontalPadding: CGFloat = reservesBottomOverlay ? 20 : 14
        let topPadding: CGFloat = reservesBottomOverlay ? 16 : 12
        let bottomPadding: CGFloat = reservesBottomOverlay ? 56 : 12
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
        context.stroke(path, with: .color(.white.opacity(0.82)), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color(TrailBoxColor.primaryDark), style: StrokeStyle(lineWidth: 3.8, lineCap: .round, lineJoin: .round))
        for (point, color) in [(points.first!, TrailBoxColor.primary), (points.last!, TrailBoxColor.warning)] {
            let center = position(point)
            context.fill(Path(ellipseIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)), with: .color(.white.opacity(0.94)))
            context.fill(Path(ellipseIn: CGRect(x: center.x - 4.5, y: center.y - 4.5, width: 9, height: 9)), with: .color(color))
        }
    } }
}
