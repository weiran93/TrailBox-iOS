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
            let allTracks: [Track] = try await APIClient.shared.request("/tracks/my?include_points=true&limit=200&offset=0", token: token)
            tracks = allTracks.filter { $0.isPublic }
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
    @Binding var showAuthentication: Bool

    @StateObject private var itraViewModel = ITRAProfileViewModel()
    @StateObject private var contributionViewModel = ContributionViewModel()
    @State private var navigationPath: [ProfileDestination] = []

    private enum ProfileDestination: Hashable {
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
            .background(TrailBoxColor.background)
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

                profileStats

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
        HStack(spacing: 16) {
            Text(userInitial)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 62, height: 62)
                .background(TrailBoxColor.primaryDark, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.65), lineWidth: 2))

            VStack(alignment: .leading, spacing: 7) {
                Text(session.user?.nickname ?? session.user?.username ?? "小野box 用户")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(TrailBoxColor.text)

                HStack(spacing: 8) {
                    Text("ID \(session.user?.publicID ?? "-")")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(TrailBoxColor.secondaryText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(TrailBoxColor.surface.opacity(0.8), in: Capsule())

                    Label(itraViewModel.profile == nil ? "完善档案" : "ITRA 已绑定", systemImage: itraViewModel.profile == nil ? "person.badge.plus" : "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TrailBoxColor.primaryDark)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TrailBoxColor.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(TrailBoxColor.primary.opacity(0.18), lineWidth: 0.75))
    }

    private var profileStats: some View {
        SectionCard {
            HStack(spacing: 0) {
                profileMetric("\(contributionViewModel.tracks.count)", label: "贡献路线")
                Divider().frame(height: 38)
                profileMetric(compactDistance, label: "公开里程")
                Divider().frame(height: 38)
                profileMetric(itraViewModel.profile?.performanceIndex.map(String.init) ?? "—", label: "ITRA 分数")
            }
        }
    }

    @ViewBuilder
    private var savedRoutesPreview: some View {
        if let track = savedRoutes.tracks.first {
            Button {
                navigationPath.append(.savedRoutes)
            } label: {
                SectionCard {
                    HStack(spacing: 14) {
                        Image(systemName: "bookmark.fill")
                            .font(.title2)
                            .foregroundStyle(TrailBoxColor.primaryDark)
                            .frame(width: 48, height: 48)
                            .background(TrailBoxColor.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(track.name).font(.subheadline.weight(.semibold)).foregroundStyle(TrailBoxColor.text).lineLimit(1)
                            Text("已收藏 \(savedRoutes.tracks.count) 条 · \(DisplayFormat.distance(track.distanceM))")
                                .font(.caption).foregroundStyle(TrailBoxColor.secondaryText)
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
                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                                .font(.title2)
                                .foregroundStyle(TrailBoxColor.primaryDark)
                                .frame(width: 48, height: 48)
                                .background(TrailBoxColor.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                            VStack(alignment: .leading, spacing: 5) {
                                Text(track.name).font(.subheadline.weight(.semibold)).foregroundStyle(TrailBoxColor.text).lineLimit(1)
                                Text([track.city, DisplayFormat.distance(track.distanceM)].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(TrailBoxColor.secondaryText)
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

    private func profileMetric(_ value: String, label: String) -> some View {
        VStack(spacing: 5) {
            Text(value).font(.title3.weight(.bold)).foregroundStyle(TrailBoxColor.text).lineLimit(1).minimumScaleFactor(0.75)
            Text(label).font(.caption).foregroundStyle(TrailBoxColor.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private var userInitial: String {
        let name = session.user?.nickname ?? session.user?.username ?? "小"
        return String(name.prefix(1)).uppercased()
    }

    private var compactDistance: String {
        let kilometers = contributionViewModel.tracks.reduce(0) { $0 + $1.distanceM } / 1_000
        if kilometers >= 100 { return String(format: "%.0f km", kilometers) }
        return String(format: "%.1f km", kilometers)
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

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if savedRoutes.tracks.isEmpty {
                    EmptyStateView(title: "还没有收藏路线", systemImage: "bookmark", message: "去探索页收藏感兴趣的路线吧")
                        .frame(minHeight: 320)
                } else {
                    ForEach(savedRoutes.tracks) { track in
                        NavigationLink {
                            TrackDetailView(trackID: track.id, isPublicSource: true)
                        } label: {
                            TrackCard(track: track, isActivity: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(TrailBoxColor.background)
        .navigationTitle("收藏路线")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await savedRoutes.load(token: session.token)
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
