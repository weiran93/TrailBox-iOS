import SwiftUI

@MainActor
final class ContributionViewModel: ObservableObject {
    enum State { case loading, content, empty, failed(String) }
    @Published var state: State = .loading
    @Published var tracks: [Track] = []

    func load(token: String, isRefresh: Bool = false) async {
        guard isRefresh || tracks.isEmpty else { return }
        state = .loading
        do {
            tracks = try await APIClient.shared.request("/tracks/contributions?include_points=true&limit=200&offset=0", token: token)
            state = tracks.isEmpty ? .empty : .content
        } catch {
            state = .failed(ErrorMessage.display(error))
        }
    }
}

@MainActor
struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var savedRoutes: SavedRoutesStore
    @EnvironmentObject private var departurePlans: DeparturePlanStore
    @Binding var showAuthentication: Bool

    @StateObject private var itraViewModel = ITRAProfileViewModel()
    @StateObject private var contributionViewModel = ContributionViewModel()
    @State private var navigationPath: [ProfileDestination] = []

    private enum ProfileDestination: Hashable {
        case departurePlans
        case departurePlan(UUID)
        case contributions
        case savedRoutes
        case itraProfile
        case track(String)
        case settings
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if session.isAuthenticated {
                    authenticatedContent
                } else {
                    loginPrompt
                }
            }
            .background(TrailPageBackground())
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        navigationPath.append(.settings)
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                }
            }
            .navigationDestination(for: ProfileDestination.self) { destination in
                switch destination {
                case .departurePlans:
                    DeparturePlansView { planID in
                        navigationPath.append(.departurePlan(planID))
                    }
                case .departurePlan(let planID):
                    if let plan = departurePlans.plan(id: planID) {
                        DeparturePlanView(plan: plan, dismissOnSave: false) {
                            navigationPath.append(.track(plan.trackID))
                        }
                    } else {
                        EmptyStateView(title: "计划不存在", systemImage: "calendar.badge.exclamationmark", message: "这份出发计划可能已被删除。")
                    }
                case .contributions:
                    MyContributionsView(tracks: contributionViewModel.tracks) {
                        Task {
                            guard let token = session.token else { return }
                            await contributionViewModel.load(token: token, isRefresh: true)
                        }
                    }
                case .savedRoutes:
                    SavedRoutesView()
                case .itraProfile:
                    if let profile = itraViewModel.profile {
                        ITRAProfileDetailView(profile: profile) {
                            itraViewModel.setProfile(nil)
                        }
                    } else {
                        ITRAProfileLookupView(profile: itraViewModel.profile) { profile in
                            itraViewModel.setProfile(profile)
                        }
                    }
                case .track(let trackID):
                    TrackDetailView(
                        trackID: trackID,
                        isPublicSource: true,
                        onDeleted: { await refreshContributions() },
                        onSaved: { await refreshContributions() }
                    )
                case .settings:
                    SettingsView()
                }
            }
        }
        .toolbar(navigationPath.isEmpty ? .visible : .hidden, for: .tabBar)
        .task {
            guard session.isAuthenticated, let token = session.token else { return }
            async let itra: Void = itraViewModel.load(token: token)
            async let contributions: Void = contributionViewModel.load(token: token)
            _ = await (itra, contributions)
        }
        .onChange(of: session.isAuthenticated) { isAuthenticated in
            guard isAuthenticated else {
                contributionViewModel.tracks = []
                contributionViewModel.state = .empty
                return
            }
            guard let token = session.token else { return }
            Task {
                async let itra: Void = itraViewModel.load(token: token)
                async let contributions: Void = contributionViewModel.load(token: token)
                _ = await (itra, contributions)
            }
        }
    }

    private var authenticatedContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                userHeader
                    .padding(.top, 4)

                profileSection(title: "出发计划", actionTitle: departurePlans.plans.isEmpty ? nil : "查看全部") {
                    departurePlanPreview
                } action: {
                    navigationPath.append(.departurePlans)
                }

                profileSection(title: "收藏路线", actionTitle: savedRoutes.tracks.isEmpty ? nil : "查看全部") {
                    savedRoutesPreview
                } action: {
                    navigationPath.append(.savedRoutes)
                }

                profileSection(title: "ITRA 运动档案") {
                    Button {
                        navigationPath.append(.itraProfile)
                    } label: {
                        SectionCard {
                            ITRAProfileRow(profile: itraViewModel.profile, isLoading: itraViewModel.isLoading)
                        }
                    }
                    .buttonStyle(.plain)
                }

                profileSection(title: "我的贡献", actionTitle: contributionViewModel.tracks.isEmpty ? nil : "查看全部") {
                    contributionPreview
                } action: {
                    navigationPath.append(.contributions)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private var departurePlanPreview: some View {
        if let plan = featuredDeparturePlan {
            Button {
                navigationPath.append(.departurePlan(plan.id))
            } label: {
                DeparturePlanCard(plan: plan)
            }
            .buttonStyle(.plain)
        } else {
            SectionCard {
                HStack(spacing: 14) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title2)
                        .foregroundStyle(TrailBoxColor.primaryDark)
                        .frame(width: 44, height: 44)
                        .background(TrailBoxColor.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("还没有出发计划")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TrailBoxColor.text)
                        Text("在路线详情生成时间建议和准备清单。")
                            .font(.caption)
                            .foregroundStyle(TrailBoxColor.secondaryText)
                    }
                }
            }
        }
    }

    private var featuredDeparturePlan: DeparturePlan? {
        let now = Date()
        return departurePlans.plans.first { ($0.expectedFinishEnd ?? $0.plannedStart) >= now }
            ?? departurePlans.plans.last
    }

    private var loginPrompt: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "person.circle")
                .font(.system(size: 64))
                .foregroundStyle(TrailBoxColor.secondaryText)
            Text("登录后查看个人内容")
                .font(.headline)
                .foregroundStyle(TrailBoxColor.text)
            Text("管理你的贡献路线、ITRA 资料和账户设置")
                .font(.subheadline)
                .foregroundStyle(TrailBoxColor.secondaryText)
                .multilineTextAlignment(.center)
            Button {
                showAuthentication = true
            } label: {
                Text("登录 / 注册")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .trailBoxGlass(tint: TrailBoxColor.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 32)
            Spacer()
        }
        .padding(32)
    }

    private var userHeader: some View {
        ZStack {
            LinearGradient(
                colors: [TrailBoxColor.primaryDark, TrailBoxColor.primary, TrailBoxColor.moss],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Canvas { context, size in
                for index in 0..<5 {
                    let y = CGFloat(20 + index * 38)
                    var contour = Path()
                    contour.move(to: CGPoint(x: -24, y: y))
                    contour.addCurve(
                        to: CGPoint(x: size.width + 24, y: y + 6),
                        control1: CGPoint(x: size.width * 0.3, y: y - 28),
                        control2: CGPoint(x: size.width * 0.72, y: y + 30)
                    )
                    context.stroke(contour, with: .color(.white.opacity(0.08)), lineWidth: 1)
                }
            }
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 15) {
                    Text(userInitial)
                        .font(.system(size: 25, weight: .heavy, design: .rounded))
                        .foregroundStyle(TrailBoxColor.primaryDark)
                        .frame(width: 64, height: 64)
                        .background(TrailBoxColor.sand, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 2))

                    VStack(alignment: .leading, spacing: 7) {
                        Text(session.user?.nickname ?? session.user?.username ?? "小野box 用户")
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        HStack(spacing: 8) {
                            Text("ID \(session.user?.publicID ?? "-")")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(1)

                            Label(itraViewModel.profile == nil ? "完善 ITRA" : "ITRA 已绑定", systemImage: itraViewModel.profile == nil ? "person.badge.plus" : "checkmark.seal.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(.black.opacity(0.16), in: Capsule())
                        }
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 0) {
                    profileHeroMetric("\(savedRoutes.tracks.count)", label: "收藏路线")
                    profileHeroMetric("\(contributionViewModel.tracks.count)", label: "贡献路线")
                    profileHeroMetric(itraViewModel.profile?.performanceIndex.map(String.init) ?? "—", label: "ITRA 分数")
                }
                .padding(.vertical, 12)
                .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.3), lineWidth: 0.8))
        .shadow(color: TrailBoxColor.primaryDark.opacity(0.18), radius: 18, y: 9)
    }

    @ViewBuilder
    private var savedRoutesPreview: some View {
        if let track = savedRoutes.tracks.first {
            Button {
                navigationPath.append(.savedRoutes)
            } label: {
                SectionCard {
                    HStack(spacing: 14) {
                        RouteThumbnail(points: track.points, reservesBottomOverlay: false)
                            .frame(width: 104, height: 78)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(TrailBoxColor.border, lineWidth: 0.75))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(track.name).font(.subheadline.weight(.semibold)).foregroundStyle(TrailBoxColor.text).lineLimit(1)
                            Text("已收藏 \(savedRoutes.tracks.count) 条 · \(DisplayFormat.distance(track.distanceM))")
                                .font(.caption).foregroundStyle(TrailBoxColor.secondaryText)
                            Label(track.city ?? "路线详情", systemImage: "mappin.and.ellipse")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(TrailBoxColor.stone)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(TrailBoxColor.secondaryText)
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            SectionCard {
                HStack(spacing: 14) {
                    Image(systemName: "bookmark")
                        .font(.title2)
                        .foregroundStyle(TrailBoxColor.primaryDark)
                        .frame(width: 44, height: 44)
                        .background(TrailBoxColor.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("还没有收藏路线").font(.subheadline.weight(.semibold)).foregroundStyle(TrailBoxColor.text)
                        Text("在探索页点击书签，把感兴趣的路线留到以后。")
                            .font(.caption).foregroundStyle(TrailBoxColor.secondaryText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var contributionPreview: some View {
        switch contributionViewModel.state {
        case .loading:
            SectionCard { ProgressView("正在加载贡献路线").frame(maxWidth: .infinity, minHeight: 76) }
        case .failed:
            SectionCard {
                VStack(spacing: 10) {
                    Text("贡献路线加载失败").font(.subheadline).foregroundStyle(TrailBoxColor.secondaryText)
                    Button("重新加载") { Task { await refreshContributions() } }
                }
                .frame(maxWidth: .infinity, minHeight: 76)
            }
        case .empty:
            SectionCard {
                HStack(spacing: 14) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(TrailBoxColor.primaryDark)
                        .frame(width: 44, height: 44)
                        .background(TrailBoxColor.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("贡献第一条路线").font(.subheadline.weight(.semibold)).foregroundStyle(TrailBoxColor.text)
                        Text("前往探索页贡献跑过的好路线，让更多山友发现它。")
                            .font(.caption).foregroundStyle(TrailBoxColor.secondaryText)
                    }
                }
            }
        case .content:
            if let track = latestContribution {
                Button {
                    navigationPath.append(.track(track.id))
                } label: {
                    SectionCard {
                        HStack(spacing: 14) {
                            RouteThumbnail(points: track.points, reservesBottomOverlay: false)
                                .frame(width: 104, height: 78)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(TrailBoxColor.border, lineWidth: 0.75))

                            VStack(alignment: .leading, spacing: 5) {
                                Text(track.name).font(.subheadline.weight(.semibold)).foregroundStyle(TrailBoxColor.text).lineLimit(1)
                                Text([track.city, DisplayFormat.distance(track.distanceM)].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(TrailBoxColor.secondaryText)
                                Label("最近贡献", systemImage: "leaf.fill")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(TrailBoxColor.primaryDark)
                            }

                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(TrailBoxColor.secondaryText)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func profileSection<Content: View>(
        title: String,
        actionTitle: String? = nil,
        @ViewBuilder content: () -> Content,
        action: @escaping () -> Void = {}
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline).foregroundStyle(TrailBoxColor.text)
                Spacer()
                if let actionTitle {
                    Button(actionTitle, action: action)
                        .font(.subheadline.weight(.semibold))
                }
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func profileHeroMetric(_ value: String, label: String) -> some View {
        VStack(spacing: 5) {
            Text(value).font(.title3.weight(.heavy)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.68)
            Text(label).font(.caption2.weight(.medium)).foregroundStyle(.white.opacity(0.68))
        }
        .frame(maxWidth: .infinity)
    }

    private var userInitial: String {
        let name = session.user?.nickname ?? session.user?.username ?? "小"
        return String(name.prefix(1)).uppercased()
    }

    private var latestContribution: Track? {
        contributionViewModel.tracks.max { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    private func refreshContributions() async {
        guard let token = session.token else { return }
        await contributionViewModel.load(token: token, isRefresh: true)
    }
}

struct SavedRoutesView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var savedRoutes: SavedRoutesStore
    @State private var query = ""
    @State private var selectedCity: String?
    @State private var sort = SavedRouteSort.savedOrder
    @State private var selectedTrackID: String?

    private enum SavedRouteSort: String, CaseIterable, Identifiable {
        case savedOrder = "收藏顺序"
        case newest = "最新发布"
        case shortest = "距离最短"
        case longest = "距离最长"
        case highestClimb = "爬升最高"

        var id: String { rawValue }
    }

    var body: some View {
        List {
            if savedRoutes.tracks.isEmpty {
                Section {
                    EmptyStateView(title: "还没有收藏路线", systemImage: "bookmark", message: "去探索页收藏感兴趣的路线吧")
                        .frame(minHeight: 320)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if visibleTracks.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        EmptyStateView(title: "没有匹配路线", systemImage: "magnifyingglass", message: "试试修改搜索词或城市筛选。")
                            .frame(minHeight: 250)
                        Button("重置筛选") {
                            query = ""
                            selectedCity = nil
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(visibleTracks) { track in
                    Button {
                        selectedTrackID = track.id
                    } label: {
                        TrackCard(track: track, isActivity: false)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("取消收藏", role: .destructive) {
                            guard let token = session.token else { return }
                            Task { await savedRoutes.toggle(trackID: track.id, token: token) }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .background(TrailBoxColor.background)
        .navigationTitle("收藏路线")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "搜索名称、城市或标签")
        .navigationDestination(isPresented: Binding(
            get: { selectedTrackID != nil },
            set: { if !$0 { selectedTrackID = nil } }
        )) {
            if let selectedTrackID {
                TrackDetailView(trackID: selectedTrackID, isPublicSource: true)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("排序", selection: $sort) {
                        ForEach(SavedRouteSort.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    Picker("城市", selection: $selectedCity) {
                        Text("全部城市").tag(String?.none)
                        ForEach(availableCities, id: \.self) { city in
                            Text(city).tag(Optional(city))
                        }
                    }
                } label: {
                    Label("筛选与排序", systemImage: "line.3.horizontal.decrease")
                }
            }
        }
        .task {
            await savedRoutes.load(token: session.token)
        }
        .refreshable {
            await savedRoutes.load(token: session.token)
        }
    }

    private var availableCities: [String] {
        Array(Set(savedRoutes.tracks.compactMap(\.city).filter { !$0.isEmpty })).sorted()
    }

    private var visibleTracks: [Track] {
        let filtered = savedRoutes.tracks.filter { track in
            savedRoutes.isSaved(track.id)
                && (selectedCity == nil || track.city == selectedCity)
                && (query.isEmpty || [track.name, track.city ?? "", track.tags ?? ""]
                    .joined(separator: " ")
                    .localizedCaseInsensitiveContains(query))
        }
        switch sort {
        case .savedOrder:
            return filtered
        case .newest:
            return filtered.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        case .shortest:
            return filtered.sorted { $0.distanceM < $1.distanceM }
        case .longest:
            return filtered.sorted { $0.distanceM > $1.distanceM }
        case .highestClimb:
            return filtered.sorted { $0.elevationGainM > $1.elevationGainM }
        }
    }
}

struct ITRAProfileRow: View {
    let profile: ITRAProfile?
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.title3)
                .foregroundStyle(TrailBoxColor.primaryDark)
                .frame(width: 36, height: 36)
                .background(TrailBoxColor.primary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("ITRA 能力资料")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TrailBoxColor.text)
                    Text(profile == nil ? "实验功能" : "已绑定")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(profile == nil ? TrailBoxColor.primaryDark : .white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(profile == nil ? TrailBoxColor.primary.opacity(0.12) : TrailBoxColor.primaryDark)
                        .clipShape(Capsule())
                }
                Text(profile == nil ? "关联你的 ITRA 公开资料，展示分数和基础信息" : (profile?.displayName ?? "ITRA Runner"))
                    .font(.caption)
                    .foregroundStyle(TrailBoxColor.secondaryText)
                    .lineLimit(1)
            }

            Spacer()
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TrailBoxColor.secondaryText)
            }
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}
