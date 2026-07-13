import SwiftUI
import UniformTypeIdentifiers
import AVKit

@MainActor
final class MyTracksViewModel: ObservableObject {
    enum State { case loading, content, empty, failed(String) }
    @Published var state: State = .loading
    @Published var tracks: [Track] = []
    @Published private(set) var isLoadingMore = false
    @Published private(set) var canLoadMore = true

    func load(token: String, isRefresh: Bool = false) async {
        guard isRefresh || tracks.isEmpty else { return }
        state = .loading
        tracks = []
        canLoadMore = true
        await loadPage(token: token, reset: true)
    }

    func loadMore(token: String) async {
        guard case .content = state, canLoadMore, !isLoadingMore else { return }
        await loadPage(token: token, reset: false)
    }

    private func loadPage(token: String, reset: Bool) async {
        if !reset { isLoadingMore = true }
        do {
            let offset = reset ? 0 : tracks.count
            let page: [Track] = try await APIClient.shared.request("/tracks/my?include_points=true&limit=20&offset=\(offset)", token: token)
            if reset { tracks = page }
            else {
                let existingIDs = Set(tracks.map(\.id))
                tracks.append(contentsOf: page.filter { !existingIDs.contains($0.id) })
            }
            canLoadMore = page.count == 20 && !page.isEmpty
            state = tracks.isEmpty ? .empty : .content
        } catch {
            if reset { state = .failed(ErrorMessage.display(error)) }
        }
        isLoadingMore = false
    }
}

@MainActor
final class ITRAProfileViewModel: ObservableObject {
    @Published private(set) var profile: ITRAProfile?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func load(token: String) async {
        isLoading = true
        errorMessage = nil
        do {
            profile = try await APIClient.shared.getITRAProfile(token: token)
        } catch {
            errorMessage = ErrorMessage.display(error)
        }
        isLoading = false
    }

    func setProfile(_ profile: ITRAProfile?) {
        self.profile = profile
        errorMessage = nil
    }
}

@MainActor
final class ITRAProfileDetailViewModel: ObservableObject {
    @Published private(set) var detail: ITRAProfileDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func load(profile: ITRAProfile, token: String, forceRefresh: Bool = false) async {
        guard forceRefresh || detail == nil else { return }
        isLoading = true
        errorMessage = nil
        do {
            var loaded = try await APIClient.shared.getITRAProfileDetail(runnerID: profile.runnerID, profileURL: profile.profileURL, token: token)
            if loaded.isPartial, let html = try? await APIClient.shared.fetchPublicITRAHTML(profileURL: profile.profileURL) {
                loaded = try await APIClient.shared.parseITRAProfileHTML(html, profileURL: profile.profileURL, token: token)
            }
            detail = loaded
        } catch {
            errorMessage = ErrorMessage.display(error)
        }
        isLoading = false
    }
}

struct MyTracksView: View {
    @EnvironmentObject private var session: SessionStore
    @Binding var showAuthentication: Bool
    @StateObject private var viewModel = MyTracksViewModel()
    @State private var navigationPath: [Destination] = []
    @State private var statsRange: StatsRange = .month

    private enum StatsRange: String, CaseIterable, Identifiable { case month = "本月", all = "全部"; var id: String { rawValue } }
    private enum Destination: Hashable { case upload, track(String) }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                switch viewModel.state {
                case .loading: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty:
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            EmptyStateView(title: "还没有轨迹", systemImage: "figure.run", message: "从运动 App 分享 .fit 或 .gpx 文件到小野box")
                                .frame(minHeight: 260)
                        }
                        .padding(16)
                    }
                case .failed(let message): EmptyStateView(title: "加载失败", systemImage: "exclamationmark.triangle", message: message)
                case .content:
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            summary
                            ForEach(viewModel.tracks) { track in
                                Button {
                                    navigationPath.append(.track(track.id))
                                } label: {
                                    TrackCard(track: track, isActivity: true)
                                }
                                .buttonStyle(.plain)
                                .onAppear {
                                    if track.id == viewModel.tracks.last?.id, let token = session.token {
                                        Task { await viewModel.loadMore(token: token) }
                                    }
                                }
                            }
                            if viewModel.isLoadingMore {
                                ProgressView().padding(.vertical, 8)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(TrailPageBackground())
            .navigationTitle("运动记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        navigationPath.append(Destination.upload)
                    } label: {
                        Label("上传", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(TrailBoxColor.primaryDark, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
                .task(id: session.token) {
                    if let token = session.token {
                        await viewModel.load(token: token)
                    }
                }
                .navigationDestination(for: Destination.self) { destination in
                    switch destination {
                    case .upload:
                        UploadTrackView { track in
                            if let token = session.token { Task { await viewModel.load(token: token, isRefresh: true) } }
                            navigationPath = [.track(track.id)]
                        }
                    case .track(let trackID):
                        TrackDetailView(trackID: trackID, isPublicSource: false, onDeleted: refreshTracks, onSaved: refreshTracks)
                    }
                }
        }
        .toolbar(navigationPath.isEmpty ? .visible : .hidden, for: .tabBar)
    }

    private var summary: some View {
        let statTracks = filteredForStatistics
        let distance = statTracks.reduce(0) { $0 + $1.distanceM }
        let elevation = statTracks.reduce(0) { $0 + $1.elevationGainM }
        return ZStack {
            LinearGradient(
                colors: [TrailBoxColor.primaryDark, TrailBoxColor.primary, TrailBoxColor.moss],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Canvas { context, size in
                for index in 0..<5 {
                    var contour = Path()
                    let baseY = size.height * CGFloat(0.24 + Double(index) * 0.18)
                    contour.move(to: CGPoint(x: -20, y: baseY))
                    contour.addCurve(
                        to: CGPoint(x: size.width + 20, y: baseY - 8),
                        control1: CGPoint(x: size.width * 0.28, y: baseY - 34),
                        control2: CGPoint(x: size.width * 0.7, y: baseY + 28)
                    )
                    context.stroke(contour, with: .color(.white.opacity(0.09)), lineWidth: 1)
                }
            }
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("训练总览", systemImage: "figure.run.circle.fill")
                            .font(.headline)
                        Text(statsRange == .month ? "本自然月的运动积累" : "全部运动记录")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach(StatsRange.allCases) { range in
                            Button {
                                withAnimation(.easeOut(duration: 0.18)) { statsRange = range }
                            } label: {
                                Text(range.rawValue)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .background(statsRange == range ? .white.opacity(0.22) : .clear, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .background(.black.opacity(0.16), in: Capsule())
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(DisplayFormat.distance(distance))
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text("累计里程")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }

                HStack(spacing: 0) {
                    summaryMetric("\(statTracks.count)", "记录", systemImage: "checkmark.circle.fill")
                    summaryMetric(totalDuration(statTracks), "总用时", systemImage: "clock.fill")
                    summaryMetric(DisplayFormat.elevation(elevation), "累计爬升", systemImage: "mountain.2.fill")
                }
                .padding(.vertical, 12)
                .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .padding(20)
            .foregroundStyle(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.3), lineWidth: 0.8))
        .shadow(color: TrailBoxColor.primaryDark.opacity(0.18), radius: 18, y: 9)
    }

    private var filteredForStatistics: [Track] {
        guard statsRange == .month else { return viewModel.tracks }
        let calendar = Calendar.current
        return viewModel.tracks.filter { track in guard let date = track.startTime ?? track.createdAt else { return false }; return calendar.isDate(date, equalTo: Date(), toGranularity: .month) }
    }
    private func totalDuration(_ tracks: [Track]) -> String { let seconds = Int(tracks.reduce(0) { $0 + ($1.durationSec ?? 0) }); guard seconds > 0 else { return "-" }; return seconds >= 3600 ? "\(seconds / 3600)h \((seconds % 3600) / 60)m" : "\(seconds / 60)m" }
    private func summaryMetric(_ value: String, _ label: String, systemImage: String) -> some View {
        VStack(spacing: 5) {
            Label(value, systemImage: systemImage)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.68))
        }
        .frame(maxWidth: .infinity)
    }
    private func refreshTracks() async {
        guard let token = session.token else { return }
        await viewModel.load(token: token, isRefresh: true)
    }
}

struct MyContributionsView: View {
    let tracks: [Track]
    let onRefresh: () async -> Void

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if tracks.isEmpty {
                    EmptyStateView(
                        title: "还没有贡献的路线",
                        systemImage: "square.and.arrow.up",
                        message: "在探索页面点击「贡献路线」，上传你的第一条公开路线。"
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    ForEach(tracks) { track in
                        NavigationLink {
                            TrackDetailView(
                                trackID: track.id,
                                isPublicSource: true,
                                onDeleted: { await onRefresh() },
                                onSaved: { await onRefresh() }
                            )
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
        .navigationTitle("我贡献的路线")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ITRAProfileCard: View {
    let profile: ITRAProfile?
    let isLoading: Bool

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("ITRA 能力资料").font(.headline).foregroundStyle(TrailBoxColor.text)
                            Text(profile == nil ? "实验功能" : "已绑定")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(profile == nil ? TrailBoxColor.primaryDark : .white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(profile == nil ? TrailBoxColor.primary.opacity(0.12) : TrailBoxColor.primaryDark)
                                .clipShape(Capsule())
                        }
                        Text(profile == nil ? "关联你的 ITRA 公开资料，展示可查询到的分数和基础信息。" : (profile?.displayName ?? "ITRA Runner"))
                            .font(.subheadline)
                            .foregroundStyle(TrailBoxColor.secondaryText)
                            .lineLimit(2)
                    }
                    Spacer()
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(TrailBoxColor.secondaryText)
                    }
                }

                if let profile {
                    HStack(alignment: .lastTextBaseline, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.performanceIndex.map(String.init) ?? "未公开")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(TrailBoxColor.primaryDark)
                            Text("Performance Index").font(.caption).foregroundStyle(TrailBoxColor.secondaryText)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("ITRA ID \(profile.runnerID)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(TrailBoxColor.text)
                            Text(profileMeta(profile))
                                .font(.caption)
                                .foregroundStyle(TrailBoxColor.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    if let summary = profile.latestResultSummary, !summary.isEmpty {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(TrailBoxColor.secondaryText)
                            .lineLimit(2)
                    }
                    if let date = profile.lastCheckedAt {
                        Text("更新于 \(DisplayFormat.date(date))")
                            .font(.caption2)
                            .foregroundStyle(TrailBoxColor.secondaryText)
                    }
                } else {
                    HStack {
                        Label("查询 ITRA 资料", systemImage: "magnifyingglass")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TrailBoxColor.primaryDark)
                        Spacer()
                    }
                }
            }
        }
    }

    private func profileMeta(_ profile: ITRAProfile) -> String {
        [profile.nationality, profile.gender, profile.age.map { "\($0) 岁" }, profile.ageGroup].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " · ")
    }
}

struct ITRAProfileLookupView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var profile: ITRAProfile?
    @State private var query: String
    @State private var candidates: [ITRASearchCandidate] = []
    @State private var isSearching = false
    @State private var isSavingRunnerID: String?
    @State private var hasSearched = false
    @State private var errorMessage: String?

    let onProfileChanged: (ITRAProfile?) -> Void

    init(profile: ITRAProfile?, onProfileChanged: @escaping (ITRAProfile?) -> Void) {
        _profile = State(initialValue: profile)
        _query = State(initialValue: profile?.displayName ?? "")
        self.onProfileChanged = onProfileChanged
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let profile {
                    linkedProfileSection(profile)
                }
                searchSection
                resultSection
            }
            .padding(16)
        }
        .background(TrailBoxColor.background)
        .navigationTitle("ITRA 资料")
        .navigationBarTitleDisplayMode(.inline)
        .alert("ITRA 查询", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var searchSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("查询资料").font(.headline).foregroundStyle(TrailBoxColor.text)
                TextField("例如 ZHAO Weiran 或 ITRA 链接", text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(TrailBoxColor.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("ITRA 没有稳定公开 API。这里仅查询公开可见资料，结果可能不完整；也可以直接粘贴 ITRA 个人页链接。")
                    .font(.caption)
                    .foregroundStyle(TrailBoxColor.secondaryText)
                Button {
                    search()
                } label: {
                    HStack {
                        if isSearching { ProgressView().controlSize(.small).tint(.white) }
                        Text(isSearching ? "查询中…" : "查询 ITRA 资料")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || isSearching ? TrailBoxColor.border : TrailBoxColor.primaryDark)
                    .foregroundStyle(query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || isSearching ? TrailBoxColor.secondaryText : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || isSearching)
            }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("查询结果").font(.headline).foregroundStyle(TrailBoxColor.text)
                ForEach(candidates) { candidate in
                    ITRACandidateCard(candidate: candidate, isSaving: isSavingRunnerID == candidate.runnerID) {
                        bind(candidate)
                    }
                }
            }
        } else if hasSearched {
            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("未找到匹配资料").font(.headline).foregroundStyle(TrailBoxColor.text)
                    Text("可以尝试英文名、姓名中间加空格，或直接粘贴 ITRA 个人页链接。")
                        .font(.subheadline)
                        .foregroundStyle(TrailBoxColor.secondaryText)
                }
            }
        }
    }

    private func linkedProfileSection(_ profile: ITRAProfile) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(profile.displayName ?? "ITRA Runner").font(.headline).foregroundStyle(TrailBoxColor.text)
                    Spacer()
                    Text("已绑定")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(TrailBoxColor.primaryDark)
                        .clipShape(Capsule())
                }
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.performanceIndex.map(String.init) ?? "未公开")
                            .font(.title.bold())
                            .foregroundStyle(TrailBoxColor.primaryDark)
                        Text("Performance Index").font(.caption).foregroundStyle(TrailBoxColor.secondaryText)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ITRA ID \(profile.runnerID)").font(.subheadline.weight(.semibold))
                        Text([profile.nationality, profile.gender, profile.age.map { "\($0) 岁" }, profile.ageGroup].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(TrailBoxColor.secondaryText)
                    }
                    Spacer()
                }
                if let summary = profile.latestResultSummary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(TrailBoxColor.secondaryText)
                        .lineLimit(3)
                }
                HStack {
                    Text("数据来自 ITRA 公开资料页")
                        .font(.caption)
                        .foregroundStyle(TrailBoxColor.secondaryText)
                    Spacer()
                    Button("解除绑定", role: .destructive) { deleteProfile() }
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private func search() {
        guard let token = session.token else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        isSearching = true
        hasSearched = false
        errorMessage = nil
        Task {
            do {
                let response = try await APIClient.shared.searchITRAProfile(query: trimmed, token: token)
                candidates = response.candidates
                hasSearched = true
            } catch {
                candidates = []
                hasSearched = true
                errorMessage = ErrorMessage.display(error)
            }
            isSearching = false
        }
    }

    private func bind(_ candidate: ITRASearchCandidate) {
        guard let token = session.token else { return }
        isSavingRunnerID = candidate.runnerID
        errorMessage = nil
        Task {
            do {
                let request = ITRAProfileUpdateRequest(
                    runnerID: candidate.runnerID,
                    profileURL: candidate.profileURL,
                    displayName: candidate.displayName,
                    gender: candidate.gender,
                    nationality: candidate.nationality,
                    age: candidate.age,
                    ageGroup: candidate.ageGroup,
                    performanceIndex: candidate.performanceIndex,
                    latestResultSummary: candidate.latestResultSummary,
                    lookupSource: candidate.lookupSource,
                    lookupConfidence: candidate.lookupConfidence,
                    lastQuery: query.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                let updated = try await APIClient.shared.updateITRAProfile(request, token: token)
                profile = updated
                onProfileChanged(updated)
                dismiss()
            } catch {
                errorMessage = ErrorMessage.display(error)
            }
            isSavingRunnerID = nil
        }
    }

    private func deleteProfile() {
        guard let token = session.token else { return }
        Task {
            do {
                try await APIClient.shared.deleteITRAProfile(token: token)
                profile = nil
                candidates = []
                onProfileChanged(nil)
            } catch {
                errorMessage = ErrorMessage.display(error)
            }
        }
    }
}

private struct ITRACandidateCard: View {
    let candidate: ITRASearchCandidate
    let isSaving: Bool
    let bindAction: () -> Void

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.displayName ?? "ITRA Runner")
                            .font(.headline)
                            .foregroundStyle(TrailBoxColor.text)
                        Text("ITRA ID \(candidate.runnerID)")
                            .font(.caption)
                            .foregroundStyle(TrailBoxColor.secondaryText)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(candidate.performanceIndex.map(String.init) ?? "未公开")
                            .font(.title3.bold())
                            .foregroundStyle(TrailBoxColor.primaryDark)
                        Text("PI").font(.caption2).foregroundStyle(TrailBoxColor.secondaryText)
                    }
                }
                Text(candidateMeta)
                    .font(.caption)
                    .foregroundStyle(TrailBoxColor.secondaryText)
                    .lineLimit(2)
                if let summary = candidate.latestResultSummary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(TrailBoxColor.secondaryText)
                        .lineLimit(2)
                }
                HStack {
                    Text("来自 ITRA 公开资料页")
                        .font(.caption)
                        .foregroundStyle(TrailBoxColor.secondaryText)
                    Spacer()
                    Button(action: bindAction) {
                        Text(isSaving ? "绑定中…" : "绑定这个资料")
                            .font(.subheadline.weight(.semibold))
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private var candidateMeta: String {
        let source: String
        switch candidate.lookupSource {
        case "manual_url": source = "链接解析"
        case "itra_profile_page": source = "公开资料页"
        case "seeded_public_profile": source = "公开资料"
        default: source = "公开搜索"
        }
        let confidence = "\(Int(candidate.lookupConfidence * 100))%"
        let base = [candidate.nationality, candidate.gender, candidate.age.map { "\($0) 岁" }, candidate.ageGroup].compactMap { $0 }.joined(separator: " · ")
        return base.isEmpty ? "\(source) · 匹配度 \(confidence)" : "\(base) · \(source) · 匹配度 \(confidence)"
    }
}

struct ITRAProfileDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ITRAProfileDetailViewModel()
    @State private var selectedTab: Tab = .races
    @State private var actionError: String?

    let profile: ITRAProfile
    let onDeleted: () -> Void

    private enum Tab: String, CaseIterable, Identifiable {
        case races = "比赛记录"
        case stats = "统计"
        case rankings = "排名"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let detail = viewModel.detail {
                    profileHeader(detail)
                    summaryGrid(detail.summaryStats)
                    Picker("视图", selection: $selectedTab) {
                        ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch selectedTab {
                    case .races:
                        raceList(detail.raceResults)
                    case .stats:
                        statsSection(detail)
                    case .rankings:
                        rankingsSection(detail.rankings)
                    }
                    if detail.isPartial {
                        Text("当前只解析到部分公开资料，可稍后刷新重试。")
                            .font(.caption)
                            .foregroundStyle(TrailBoxColor.secondaryText)
                    }
                } else if viewModel.isLoading {
                    ProgressView("加载 ITRA 资料中…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else if let message = viewModel.errorMessage {
                    EmptyStateView(title: "加载失败", systemImage: "exclamationmark.triangle", message: message)
                        .frame(minHeight: 320)
                }
            }
            .padding(16)
        }
        .background(TrailBoxColor.background)
        .navigationTitle("ITRA 资料")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("刷新") {
                    if let token = session.token {
                        Task { await viewModel.load(profile: profile, token: token, forceRefresh: true) }
                    }
                }
                .disabled(viewModel.isLoading)
            }
        }
        .task(id: profile.runnerID) {
            if let token = session.token {
                await viewModel.load(profile: profile, token: token)
            }
        }
        .alert("ITRA 资料", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(actionError ?? "")
        }
    }

    private func profileHeader(_ detail: ITRAProfileDetail) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack(alignment: .bottomTrailing) {
                        Circle().fill(TrailBoxColor.background).frame(width: 82, height: 82)
                        Image(systemName: "person.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(TrailBoxColor.secondaryText.opacity(0.7))
                        Text(flagEmoji(detail.profile.nationality))
                            .font(.title3)
                            .frame(width: 28, height: 28)
                            .background(TrailBoxColor.surface)
                            .clipShape(Circle())
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text(detail.profile.displayName ?? profile.displayName ?? "ITRA Runner")
                                .font(.title2.bold())
                                .foregroundStyle(TrailBoxColor.text)
                            if detail.profile.gender?.lowercased().hasPrefix("m") == true {
                                Image(systemName: "mars").foregroundStyle(.cyan)
                            }
                        }
                        Text([detail.profile.ageGroup, detail.profile.runnerID].compactMap { $0 }.joined(separator: "  |  "))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TrailBoxColor.text)
                        HStack(spacing: 0) {
                            Text("表现分 \(detail.profile.performanceIndex.map(String.init) ?? "未公开")")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .padding(.horizontal, 11)
                                .frame(height: 38)
                                .background(.black)
                            Text(detail.profile.publicLevel ?? "等级未公开")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .padding(.horizontal, 11)
                                .frame(height: 38)
                                .background(TrailBoxColor.primary.opacity(0.7))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    Spacer()
                }
                HStack {
                    Text("数据源：\(sourceLabel(detail.dataSource))")
                        .font(.caption)
                        .foregroundStyle(TrailBoxColor.secondaryText)
                    Spacer()
                    Button("解除绑定", role: .destructive) { deleteProfile() }
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }

    private func summaryGrid(_ stats: ITRASummaryStats) -> some View {
        SectionCard {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                compactMetric("完赛场次", stats.totalRaces.map(String.init) ?? "-")
                compactMetric("总时间", stats.totalTime ?? "-")
                compactMetric("总距离", stats.totalDistanceKM.map { String(format: "%.1f km", $0) } ?? "-")
                compactMetric("总爬升", stats.totalElevationGainM.map { "+\($0.formatted()) m" } ?? "-")
            }
        }
    }

    private func raceList(_ races: [ITRARaceResult]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(races) { race in
                NavigationLink {
                    ITRARaceResultDetailView(race: race)
                } label: {
                    ITRARaceResultCard(race: race)
                }
                .buttonStyle(.plain)
            }
            if races.isEmpty {
                SectionCard {
                    Text("暂无公开比赛记录").foregroundStyle(TrailBoxColor.secondaryText)
                }
            }
        }
    }

    private func statsSection(_ detail: ITRAProfileDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionCard {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                    metricBlock("总场次", detail.summaryStats.totalRaces.map(String.init) ?? "-")
                    metricBlock("完赛率", detail.summaryStats.finishRate.map { String(format: "%.0f %%", $0) } ?? "-")
                    metricBlock("总时间", detail.summaryStats.totalTime ?? "-")
                    metricBlock("总距离", detail.summaryStats.totalDistanceKM.map { String(format: "%.1f km", $0) } ?? "-")
                    metricBlock("总爬升", detail.summaryStats.totalElevationGainM.map { "+\($0.formatted()) m" } ?? "-")
                }
            }
            ForEach(detail.bestItems) { item in
                SectionCard {
                    HStack(alignment: .top) {
                        Text(item.title).font(.subheadline).foregroundStyle(TrailBoxColor.text)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(item.value).font(.headline.bold()).foregroundStyle(TrailBoxColor.text)
                            if let raceName = item.raceName {
                                Text(raceName).font(.caption).foregroundStyle(TrailBoxColor.secondaryText).multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }
            }
        }
    }

    private func rankingsSection(_ rankings: ITRARankingStats) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("ITRA 表现分排名（世界前 \(rankings.worldPercentile.map { String(format: "%.2f", $0) } ?? "-") %）")
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                    metricBlock("国家排名", rankingText(rankings.countryRank, rankings.countryCount))
                    metricBlock("亚洲排名", rankingText(rankings.continentRank, rankings.continentCount))
                    metricBlock("世界排名", rankingText(rankings.worldRank, rankings.worldCount))
                }
            }
        }
    }

    private func deleteProfile() {
        guard let token = session.token else { return }
        Task {
            do {
                try await APIClient.shared.deleteITRAProfile(token: token)
                onDeleted()
                dismiss()
            } catch {
                actionError = ErrorMessage.display(error)
            }
        }
    }

    private func compactMetric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(TrailBoxColor.secondaryText).lineLimit(1)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(TrailBoxColor.text).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func metricBlock(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(TrailBoxColor.secondaryText)
            Text(value).font(.title3.bold()).foregroundStyle(TrailBoxColor.text).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rankingText(_ rank: String?, _ count: String?) -> String {
        guard let rank else { return "-" }
        return count.map { "\(rank)/\($0)" } ?? rank
    }

    private func sourceLabel(_ value: String) -> String {
        switch value {
        case "client_html": return "客户端公开页面解析"
        case "itra_profile_page": return "ITRA 公开资料页"
        case "seeded_public_profile": return "公开资料快照"
        default: return value
        }
    }

    private func flagEmoji(_ nationality: String?) -> String {
        nationality == "China" || nationality == "CHN" ? "🇨🇳" : "🏳️"
    }
}

private struct ITRARaceResultCard: View {
    let race: ITRARaceResult

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle().fill(TrailBoxColor.primary).frame(width: 12, height: 12)
                    Text(race.date ?? "-").font(.headline)
                    Text("中国大陆").font(.subheadline).foregroundStyle(TrailBoxColor.secondaryText)
                    Spacer()
                    if let points = race.itraPoints {
                        Text("Finisher  iTRA \(points)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(red: 205 / 255, green: 205 / 255, blue: 0))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                Text(race.name ?? "未命名比赛")
                    .font(.headline.bold())
                    .foregroundStyle(TrailBoxColor.text)
                    .underline()
                if let localName = race.localName {
                    Text(localName).font(.subheadline.bold()).foregroundStyle(TrailBoxColor.text)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    raceMetric("成绩", race.time ?? "-")
                    raceMetric("组别", raceGroupText)
                    raceMetric("平均配速", race.averagePace ?? "-")
                    raceMetric("等强配速", race.effortPace ?? "-")
                    raceMetric("总排名", race.rank.map { "\($0)/\(race.rankTotal ?? "-")" } ?? "-")
                    raceMetric("性别排名", race.genderRank.map { "\($0)/\(race.genderTotal ?? "-")" } ?? "-")
                }
            }
        }
    }

    private func raceMetric(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text("\(title)：").foregroundStyle(TrailBoxColor.secondaryText)
            Text(value.isEmpty ? "-" : value).foregroundStyle(title == "成绩" ? .orange : TrailBoxColor.text)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var raceGroupText: String {
        [
            race.distanceKM.map { String(format: "%.0fkm", $0) },
            race.elevationGainM.map { "\($0)m+" }
        ]
        .compactMap { $0 }
        .joined(separator: "/")
    }
}

struct ITRARaceResultDetailView: View {
    let race: ITRARaceResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(race.name ?? "比赛详情")
                    .font(.largeTitle.bold())
                    .foregroundStyle(TrailBoxColor.text)
                if let localName = race.localName {
                    Text(localName).font(.title2.bold()).foregroundStyle(TrailBoxColor.text)
                }
                Text("🇨🇳 China").font(.subheadline).foregroundStyle(TrailBoxColor.secondaryText)
                SectionCard {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                        detailMetric("ITRA积分", race.itraPoints.map(String.init) ?? "-")
                        detailMetric("距离", race.distanceKM.map { String(format: "%.2fkm", $0) } ?? "-")
                        detailMetric("累计爬升", race.elevationGainM.map { "+\($0)m" } ?? "-")
                        detailMetric("参赛人数", race.totalParticipants.map(String.init) ?? race.rankTotal ?? "-")
                        detailMetric("比赛日期", race.date ?? "-")
                        detailMetric("成绩", race.time ?? "-")
                        detailMetric("山地等级", race.mountainLevel.map(String.init) ?? "-")
                        detailMetric("完赛最低表现分", race.finisherLevel.map(String.init) ?? "-")
                    }
                }
                SectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("个人成绩").font(.headline)
                        detailRow("总排名", race.rank.map { "\($0)/\(race.rankTotal ?? "-")" } ?? "-")
                        detailRow("性别排名", race.genderRank.map { "\($0)/\(race.genderTotal ?? "-")" } ?? "-")
                        detailRow("平均配速", race.averagePace ?? "-")
                        detailRow("等强配速", race.effortPace ?? "-")
                    }
                }
            }
            .padding(16)
        }
        .background(TrailBoxColor.background)
        .navigationTitle("比赛详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(TrailBoxColor.secondaryText)
            Text(value).font(.headline).foregroundStyle(TrailBoxColor.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(TrailBoxColor.secondaryText)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .font(.subheadline)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showDeleteConfirmation = false
    @State private var showLogoutConfirmation = false
    @State private var isDeletingAccount = false
    @State private var accountActionMessage: String?

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    var body: some View {
        Form {
            Section("用户信息") {
                LabeledContent("ID", value: session.user?.publicID ?? "-")
                LabeledContent("用户名", value: session.user?.username ?? "-")
            }
            if session.user?.isAdmin == true {
                Section("管理后台") {
                    NavigationLink("管理后台") { AdminDashboardView() }
                    NavigationLink("AI 服务配置") { AdminAISettingsView() }
                    NavigationLink("内容举报") { AdminReportsView() }
                }
            }
            Section("个人资料") {
                NavigationLink {
                    NicknameSettingsView(nickname: session.user?.nickname ?? "")
                } label: {
                    LabeledContent("昵称", value: session.user?.nickname ?? "未设置")
                }
            }
            Section("AI 分析") {
                NavigationLink {
                    DeepSeekKeySettingsView()
                } label: {
                    HStack {
                        Text("DeepSeek API Key")
                        Spacer()
                        Text(session.user?.hasDeepSeekAPIKey == true ? "已保存" : "未配置")
                            .foregroundStyle(session.user?.hasDeepSeekAPIKey == true ? .green : TrailBoxColor.secondaryText)
                    }
                }
            }
            Section("账户安全") {
                NavigationLink("修改密码") { ChangePasswordView() }
                Button("删除账户", role: .destructive) { showDeleteConfirmation = true }
            }
            Section {
                NavigationLink("隐私政策") { PrivacyPolicyView() }
                Button("联系我们") {
                    if let url = URL(string: "mailto:\(AppConfiguration.supportEmail)") { openURL(url) }
                }
            } header: {
                Text("关于与支持")
            } footer: {
                HStack {
                    Spacer()
                    Text("v\(appVersion)").font(.caption).foregroundStyle(TrailBoxColor.secondaryText)
                    Spacer()
                }
            }

            Section {
                Button("退出登录", role: .destructive) { showLogoutConfirmation = true }
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.red.opacity(0.08))
        }
        .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("永久删除账户？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button(isDeletingAccount ? "删除中…" : "删除账户及所有数据", role: .destructive) { deleteAccount() }
                .disabled(isDeletingAccount)
            Button("取消", role: .cancel) { }
        } message: {
            Text("你的私有记录、已公开路线、轨迹文件和 AI 分析将被永久删除，且无法恢复。")
        }
        .confirmationDialog("退出登录？", isPresented: $showLogoutConfirmation, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { session.logout(); dismiss() }
            Button("取消", role: .cancel) { }
        }
        .alert("账户操作", isPresented: Binding(get: { accountActionMessage != nil }, set: { if !$0 { accountActionMessage = nil } })) {
            Button("确定", role: .cancel) { }
        } message: { Text(accountActionMessage ?? "") }
    }

    private func deleteAccount() {
        isDeletingAccount = true
        Task {
            do {
                try await session.deleteAccount()
                dismiss()
            } catch {
                accountActionMessage = error.localizedDescription
            }
            isDeletingAccount = false
        }
    }
}

struct PrivacyPolicyView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("生效日期：2026 年 6 月 21 日").font(.footnote).foregroundStyle(TrailBoxColor.secondaryText)
                privacySection("1. 我们收集的信息", "为注册和使用小野box，我们会处理你提供的用户名、昵称，以及你上传的轨迹文件、路线位置、运动指标、路线名称和标签。你主动使用语音记录或填写感受时，我们也会处理对应的语音转写和文字内容。")
                privacySection("2. 信息如何使用", "这些信息仅用于账号登录、保存和展示运动记录、生成路线数据、提供搜索筛选以及你主动请求的运动分析。公开路线只会在你开启“公开为探索路线”后展示；你可选择是否展示贡献者昵称。")
                privacySection("3. 第三方处理", "当你主动使用 AI 分析功能时，必要的运动数据和你输入的感受会发送给 AI 服务商，以生成分析结果。我们不会将你的信息用于广告定向或出售给他人。")
                privacySection("4. 保存与删除", "信息会在提供服务所需期间保存。你可在“设置 → 账户安全 → 删除账户”中删除账户；我们将删除账户、轨迹文件、公开内容和分析数据，法律要求保留的信息除外。")
                privacySection("5. 你的选择", "你可以不公开路线、关闭贡献者昵称展示、退出登录，或在公开路线详情中举报内容、屏蔽贡献者。")
                privacySection("6. 联系我们", "如有隐私问题、删除请求或投诉，请联系 \(AppConfiguration.supportEmail)。")
                Button("联系隐私支持") {
                    if let url = URL(string: "mailto:\(AppConfiguration.supportEmail)") { openURL(url) }
                }
                .frame(maxWidth: .infinity).buttonStyle(.bordered)
            }
            .padding(16)
        }
        .navigationTitle("隐私政策")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func privacySection(_ title: String, _ content: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            Text(content).font(.subheadline).foregroundStyle(TrailBoxColor.secondaryText)
        }
    }
}

struct NicknameSettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var nickname: String
    @State private var isSaving = false
    @State private var message: String?

    init(nickname: String) { _nickname = State(initialValue: nickname) }

    var body: some View {
        Form {
            Section("昵称") { TextField("小野box 用户", text: $nickname) }
        }
        .navigationTitle("昵称")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSaving ? "保存中…" : "保存") { save() }
                    .disabled(isSaving || nickname == (session.user?.nickname ?? ""))
            }
        }
        .alert("昵称已保存", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("完成") { dismiss() }
        } message: { Text(message ?? "") }
    }

    private func save() {
        struct Request: Encodable { let nickname: String? }
        guard let token = session.token else { return }; isSaving = true
        Task { do { let user: User = try await APIClient.shared.request("/users/me", method: "PATCH", body: Request(nickname: nickname.isEmpty ? nil : nickname), token: token); session.update(user: user); message = "保存成功" } catch { message = error.localizedDescription }; isSaving = false }
    }
}

struct DeepSeekKeySettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var deepSeekKey = ""
    @State private var isSaving = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("个人 DeepSeek API Key") {
                SecureField("输入 DeepSeek API Key", text: $deepSeekKey)
                if session.user?.hasDeepSeekAPIKey == true {
                    Label("当前已保存个人 Key", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("尚未保存个人 Key。配置后将优先用于 AI 分析。")
                        .foregroundStyle(TrailBoxColor.secondaryText)
                }
            }
        }
        .navigationTitle("AI 分析")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSaving ? "保存中…" : "保存") { save() }
                    .disabled(isSaving || deepSeekKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .alert("DeepSeek API Key 已保存", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("知道了", role: .cancel) { }
        } message: { Text(message ?? "") }
    }

    private func save() {
        struct Request: Encodable { let deepseekApiKey: String }
        guard let token = session.token else { return }; isSaving = true
        Task { do { let user: User = try await APIClient.shared.request("/users/me", method: "PATCH", body: Request(deepseekApiKey: deepSeekKey.trimmingCharacters(in: .whitespacesAndNewlines)), token: token); session.update(user: user); deepSeekKey = ""; message = "该 Key 已安全保存，并会优先用于你的 AI 分析。" } catch { message = error.localizedDescription }; isSaving = false }
    }
}

struct ChangePasswordView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var isSaving = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("修改密码") {
                SecureField("旧密码", text: $oldPassword)
                SecureField("新密码（至少 8 位）", text: $newPassword)
            }
        }
        .navigationTitle("修改密码")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSaving ? "保存中…" : "保存") { changePassword() }
                    .disabled(isSaving || oldPassword.isEmpty || newPassword.count < 8)
            }
        }
        .alert("密码已修改", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("完成") { dismiss() }
        } message: { Text(message ?? "") }
    }

    private func changePassword() {
        struct Request: Encodable { let oldPassword: String; let newPassword: String }
        guard let token = session.token else { return }; isSaving = true
        Task { do { let user: User = try await APIClient.shared.request("/users/me/change-password", method: "POST", body: Request(oldPassword: oldPassword, newPassword: newPassword), token: token); session.update(user: user); oldPassword = ""; newPassword = ""; message = "密码已成功修改。" } catch { message = error.localizedDescription }; isSaving = false }
    }
}

struct AdminDashboardView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var stats: AdminStats?
    @State private var error: String?
    @State private var tracks: [Track] = []
    @State private var query = ""
    @State private var publicOnly = false
    @State private var trackPendingDeletion: Track?
    @State private var actionError: String?
    var body: some View {
        Group { if let stats { List { Section("统计") { metric("全部轨迹", stats.total); metric("公开路线", stats.public); metric("私有记录", stats.private) }; Section("管理工具") { NavigationLink("批量上传轨迹") { AdminBatchUploadView() }; NavigationLink("标签配置") { AdminTagSettingsView() } }; Section("筛选") { TextField("搜索名称、城市或标签", text: $query).onSubmit { Task { await loadTracks() } }; Toggle("仅公开路线", isOn: $publicOnly).onChange(of: publicOnly) { _ in Task { await loadTracks() } } }; Section("最近轨迹") { ForEach(tracks) { track in NavigationLink { AdminTrackEditView(track: track) { Task { await loadTracks() } } } label: { VStack(alignment: .leading, spacing: 3) { Text(track.name); Text("\(track.city ?? "-") · \(track.isPublic ? "公开" : "私有")").font(.caption).foregroundStyle(TrailBoxColor.secondaryText) } }.swipeActions(allowsFullSwipe: false) { Button("删除", role: .destructive) { trackPendingDeletion = track } } } } } } else if let error { EmptyStateView(title: "加载失败", systemImage: "exclamationmark.triangle", message: error) } else { ProgressView() } }
            .navigationTitle("管理后台").task { await load() }
            .confirmationDialog("删除轨迹？", isPresented: Binding(get: { trackPendingDeletion != nil }, set: { if !$0 { trackPendingDeletion = nil } }), titleVisibility: .visible) {
                Button("删除", role: .destructive) { if let track = trackPendingDeletion { delete(track) } }
                Button("取消", role: .cancel) { trackPendingDeletion = nil }
            } message: { Text("将永久删除“\(trackPendingDeletion?.name ?? "")”，此操作不可撤销。") }
            .alert("删除失败", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) { Button("确定", role: .cancel) {} } message: { Text(actionError ?? "") }
    }
    private func metric(_ title: String, _ value: Int) -> some View { SectionCard { HStack { Text(title); Spacer(); Text("\(value)").font(.title3.bold()).foregroundStyle(TrailBoxColor.primaryDark) } } }
    private func load() async { guard let token = session.token else { return }; do { stats = try await APIClient.shared.request("/admin/stats", token: token); await loadTracks() } catch { self.error = error.localizedDescription } }
    private func loadTracks() async { guard let token = session.token else { return }; var path = "/admin/tracks?limit=20"; if !query.isEmpty { path += "&q=" + query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)! }; if publicOnly { path += "&is_public=true" }; do { tracks = try await APIClient.shared.request(path, token: token) } catch { self.error = error.localizedDescription } }
    private func delete(_ track: Track) { guard let token = session.token else { return }; trackPendingDeletion = nil; Task { do { try await APIClient.shared.requestVoid("/admin/tracks/\(track.id)", method: "DELETE", token: token); tracks.removeAll { $0.id == track.id }; await load() } catch { actionError = error.localizedDescription } } }
}

struct AdminTrackEditView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    let track: Track
    let onSaved: () -> Void

    @State private var name: String
    @State private var description: String
    @State private var city: String
    @State private var tags: String
    @State private var sport: String
    @State private var isPublic: Bool
    @State private var showContributor: Bool
    @State private var isLoadingDetail = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(track: Track, onSaved: @escaping () -> Void) {
        self.track = track
        self.onSaved = onSaved
        _name = State(initialValue: track.name)
        _description = State(initialValue: track.description ?? "")
        _city = State(initialValue: track.city ?? "")
        _tags = State(initialValue: track.tags ?? "")
        _sport = State(initialValue: track.sport ?? "越野跑")
        _isPublic = State(initialValue: track.isPublic)
        _showContributor = State(initialValue: track.showContributor)
    }

    var body: some View {
        Form {
            Section("基础信息") {
                TextField("名称", text: $name)
                TextField("城市", text: $city)
                TextField("标签", text: $tags)
                Picker("运动类型", selection: $sport) {
                    Text("越野跑").tag("越野跑")
                    Text("徒步").tag("徒步")
                }
            }
            Section("描述") {
                TextEditor(text: $description).frame(minHeight: 100)
            }
            Section("发布设置") {
                Toggle("公开到探索路线", isOn: $isPublic)
                Toggle("展示贡献者昵称", isOn: $showContributor)
            }
            Section("轨迹数据") {
                LabeledContent("距离", value: DisplayFormat.distance(track.distanceM))
                LabeledContent("爬升", value: DisplayFormat.elevation(track.elevationGainM))
            }
            if isLoadingDetail {
                Section { ProgressView("加载详情中…") }
            }
        }
        .navigationTitle("编辑路线")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSaving ? "保存中…" : "保存") { save() }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .task { await loadDetail() }
        .alert("保存失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("确定", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func loadDetail() async {
        guard let token = session.token else { return }
        isLoadingDetail = true
        do {
            let detail: Track = try await APIClient.shared.request("/admin/tracks/\(track.id)", token: token)
            name = detail.name
            description = detail.description ?? ""
            city = detail.city ?? ""
            tags = detail.tags ?? ""
            sport = detail.sport ?? "越野跑"
            isPublic = detail.isPublic
            showContributor = detail.showContributor
        } catch {
            errorMessage = ErrorMessage.display(error)
        }
        isLoadingDetail = false
    }

    private func save() {
        struct Request: Encodable {
            let name: String
            let description: String?
            let city: String?
            let tags: String?
            let sport: String
            let isPublic: Bool
            let showContributor: Bool
        }
        guard let token = session.token else { return }
        func optional(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = Request(
            name: trimmedName,
            description: optional(description),
            city: optional(city),
            tags: optional(tags),
            sport: sport,
            isPublic: isPublic,
            showContributor: showContributor
        )
        isSaving = true
        Task {
            do {
                let _: Track = try await APIClient.shared.request("/admin/tracks/\(track.id)", method: "PATCH", body: request, token: token)
                onSaved()
                dismiss()
            } catch {
                errorMessage = ErrorMessage.display(error)
            }
            isSaving = false
        }
    }
}

struct AdminTagSettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var tagsText = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("标签") {
                TextEditor(text: $tagsText).frame(minHeight: 130)
                Text("用逗号或换行分隔。顺序决定“探索路线”顶部筛选标签的展示顺序。删除后不会移除已有轨迹上的标签。")
                    .font(.footnote).foregroundStyle(TrailBoxColor.secondaryText)
            }
            if let message { Section { Text(message).foregroundStyle(TrailBoxColor.secondaryText) } }
        }
        .navigationTitle("标签配置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSaving ? "保存中…" : "保存") { save() }
                    .disabled(isLoading || isSaving)
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let token = session.token else { return }
        do {
            let tags: [ConfiguredTag] = try await APIClient.shared.request("/admin/tags", token: token)
            tagsText = tags.map(\.name).joined(separator: ",")
        } catch { message = error.localizedDescription }
        isLoading = false
    }

    private func save() {
        struct Request: Encodable { let names: [String] }
        guard let token = session.token else { return }
        let names = tagsText.split(whereSeparator: { $0 == "," || $0 == "，" || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
            .filter { !$0.isEmpty }
        isSaving = true; message = nil
        Task {
            do {
                let tags: [ConfiguredTag] = try await APIClient.shared.request("/admin/tags", method: "PUT", body: Request(names: names), token: token)
                tagsText = tags.map(\.name).joined(separator: ",")
                message = "标签已保存"
            } catch { message = error.localizedDescription }
            isSaving = false
        }
    }
}

struct AdminBatchUploadView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var showFileImporter = false
    @State private var selectedFiles: [URL] = []
    @State private var isUploading = false
    @State private var draftID: String?
    @State private var previewItems: [AdminBatchPreviewItem] = []
    @State private var errorMessage: String?
    @State private var showEditor = false
    @State private var keepOriginalName = true

    var body: some View {
        Form {
            Section("上传收集的轨迹") {
                Text("选择一个或多个 FIT、GPX 或 KML 文件。系统会先识别名称、城市和标签，确认保存后再发布。")
                    .font(.footnote).foregroundStyle(TrailBoxColor.secondaryText)
                Toggle("保留轨迹原名", isOn: $keepOriginalName)
                Text("关闭后将按起终点和沿途地标自动生成路线名。")
                    .font(.footnote).foregroundStyle(TrailBoxColor.secondaryText)
                Button("选择文件") { showFileImporter = true }
                if !selectedFiles.isEmpty {
                    ForEach(selectedFiles, id: \.self) { file in
                        HStack {
                            Text(file.lastPathComponent).lineLimit(1)
                            Spacer()
                            Button(role: .destructive) { selectedFiles.removeAll { $0 == file } } label: { Image(systemName: "xmark.circle.fill") }
                        }
                    }
                }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(TrailBoxColor.danger) } }
        }
        .navigationTitle("批量上传轨迹")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isUploading ? "解析中…" : "解析并编辑") { upload() }
                    .disabled(selectedFiles.isEmpty || isUploading)
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            selectedFiles = urls
        }
        .navigationDestination(isPresented: $showEditor) {
            if let draftID {
                AdminBatchEditView(draftID: draftID, items: previewItems)
            }
        }
    }

    private func upload() {
        guard let token = session.token else { return }
        isUploading = true; errorMessage = nil
        Task {
            let files = selectedFiles
            let scopedFiles = files.filter { $0.startAccessingSecurityScopedResource() }
            defer { scopedFiles.forEach { $0.stopAccessingSecurityScopedResource() } }
            do {
                let result = try await APIClient.shared.previewAdminTracks(fileURLs: files, keepOriginalName: keepOriginalName, token: token)
                if result.items.isEmpty {
                    errorMessage = result.errors.map(\.error).joined(separator: "\n")
                } else {
                    draftID = result.draftID
                    previewItems = result.items
                    selectedFiles = []
                    if !result.errors.isEmpty { errorMessage = "\(result.errors.count) 个文件解析失败：\(result.errors.map(\.error).joined(separator: "；"))" }
                    showEditor = true
                }
            } catch { errorMessage = error.localizedDescription }
            isUploading = false
        }
    }
}

struct AdminBatchEditView: View {
    struct EditableTrack: Identifiable {
        let id: String
        let filename: String
        var name: String
        var city: String
        var tags: String
        var sport: String
        var isPublic: Bool
        var showContributor: Bool
        let distanceM: Double
        let elevationGainM: Double

        init(_ item: AdminBatchPreviewItem) {
            id = item.id; filename = item.filename; name = item.name; city = item.city ?? ""; tags = item.tags ?? ""; sport = item.sport ?? "越野跑"
            isPublic = item.isPublic; showContributor = item.showContributor; distanceM = item.distanceM; elevationGainM = item.elevationGainM
        }
    }

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    let draftID: String
    @State private var tracks: [EditableTrack]
    @State private var globalCity = ""
    @State private var globalTags = ""
    @State private var globalSport = ""
    @State private var globalPublic = true
    @State private var globalContributor = true
    @State private var isSaving = false
    @State private var message: String?

    init(draftID: String, items: [AdminBatchPreviewItem]) {
        self.draftID = draftID
        _tracks = State(initialValue: items.map(EditableTrack.init))
    }

    var body: some View {
        Form {
            Section("统一设置") {
                TextField("城市（留空不修改）", text: $globalCity)
                TextField("标签（留空不修改）", text: $globalTags)
                Picker("运动类型", selection: $globalSport) { Text("不修改").tag(""); Text("越野跑").tag("越野跑"); Text("徒步").tag("徒步") }
                Toggle("公开到探索路线", isOn: $globalPublic)
                Toggle("展示贡献者昵称", isOn: $globalContributor)
                Button("应用到全部") { applyToAll() }
            }
            Section("逐条调整") {
                ForEach($tracks) { $track in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(track.filename)
                            .font(.caption)
                            .foregroundStyle(TrailBoxColor.secondaryText)
                        TextField("名称", text: $track.name)
                        TextField("城市", text: $track.city)
                        TextField("标签", text: $track.tags)
                        Picker("运动类型", selection: $track.sport) { Text("越野跑").tag("越野跑"); Text("徒步").tag("徒步") }
                        Toggle("公开", isOn: $track.isPublic)
                        Toggle("展示贡献者", isOn: $track.showContributor)
                        Text("\(DisplayFormat.distance(track.distanceM)) · 爬升 \(DisplayFormat.elevation(track.elevationGainM))")
                            .font(.caption).foregroundStyle(TrailBoxColor.secondaryText)
                    }.padding(.vertical, 4)
                }
            }
            if let message { Section { Text(message).foregroundStyle(TrailBoxColor.secondaryText) } }
        }
        .navigationTitle("批量编辑轨迹")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSaving ? "保存中…" : "保存全部") { save() }.disabled(tracks.isEmpty || isSaving)
            }
        }
    }

    private func applyToAll() {
        for index in tracks.indices {
            if !globalCity.isEmpty { tracks[index].city = globalCity }
            if !globalTags.isEmpty { tracks[index].tags = globalTags }
            if !globalSport.isEmpty { tracks[index].sport = globalSport }
            tracks[index].isPublic = globalPublic
            tracks[index].showContributor = globalContributor
        }
    }

    private func save() {
        guard let token = session.token else { return }
        let items = tracks.map {
            AdminBatchCommitItem(
                id: $0.id,
                filename: $0.filename,
                name: $0.name,
                city: $0.city.isEmpty ? nil : $0.city,
                tags: $0.tags.isEmpty ? nil : $0.tags,
                sport: $0.sport,
                isPublic: $0.isPublic,
                showContributor: $0.showContributor
            )
        }
        isSaving = true; message = nil
        Task {
            do {
                let result = try await APIClient.shared.commitAdminTracks(draftID: draftID, items: items, token: token)
                if result.errors.isEmpty { message = "\(result.tracks.count) 条轨迹已发布" }
                else { message = "\(result.tracks.count) 条已发布，\(result.errors.count) 条失败" }
            } catch { message = error.localizedDescription }
            isSaving = false
        }
    }
}

struct AdminAISettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var sharedKey = ""
    @State private var settings: AdminAISettings?
    @State private var message: String?
    @State private var isSaving = false

    var body: some View {
        Form {
            Section("公用 DeepSeek API Key") {
                SecureField("输入公用 API Key", text: $sharedKey)
                Text(settings?.hasDefaultDeepSeekAPIKey == true ? "已配置公用 Key；未配置个人 Key 的用户将使用它。" : "尚未配置公用 Key。未配置个人 Key 的用户无法生成 AI 分析。")
                    .font(.footnote).foregroundStyle(TrailBoxColor.secondaryText)
            }
            if let message { Section { Text(message).foregroundStyle(TrailBoxColor.secondaryText) } }
        }
        .navigationTitle("AI 服务配置")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSaving ? "保存中…" : "保存") { save() }
                    .disabled(sharedKey.isEmpty || isSaving || settings == nil)
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let token = session.token else { return }
        do { settings = try await APIClient.shared.request("/admin/ai-settings", token: token) }
        catch { message = error.localizedDescription }
    }

    private func save() {
        struct Request: Encodable {
            let prompt: String
            let defaultDeepseekApiKey: String

            enum CodingKeys: String, CodingKey {
                case prompt
                case defaultDeepseekApiKey = "default_deepseek_api_key"
            }
        }
        guard let token = session.token, let prompt = settings?.prompt else { return }
        isSaving = true
        Task {
            do {
                let saved: AdminAISettings = try await APIClient.shared.request("/admin/ai-settings", method: "PATCH", body: Request(prompt: prompt, defaultDeepseekApiKey: sharedKey), token: token)
                settings = saved; sharedKey = ""; message = "公用 Key 已保存"
            } catch { message = error.localizedDescription }
            isSaving = false
        }
    }
}

struct AdminReportsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var reports: [ModerationReport] = []
    @State private var error: String?

    var body: some View {
        Group {
            if let error { EmptyStateView(title: "加载失败", systemImage: "exclamationmark.triangle", message: error) }
            else if reports.isEmpty { EmptyStateView(title: "暂无待处理举报", systemImage: "checkmark.shield", message: "所有公开路线目前均无需处理。") }
            else { List(reports) { report in
                VStack(alignment: .leading, spacing: 6) {
                    Text(report.reason).font(.headline)
                    Text("路线 \(report.trackID)").font(.caption).foregroundStyle(TrailBoxColor.secondaryText)
                    if let details = report.details, !details.isEmpty { Text(details).font(.subheadline) }
                    HStack {
                        Button("保留") { resolve(report, hideTrack: false) }
                        Button("下架路线", role: .destructive) { resolve(report, hideTrack: true) }
                    }
                }.padding(.vertical, 4)
            } }
        }
        .navigationTitle("内容举报")
        .task { await load() }
    }

    private func load() async {
        guard let token = session.token else { return }
        do { reports = try await APIClient.shared.request("/admin/reports", token: token) }
        catch { self.error = error.localizedDescription }
    }

    private func resolve(_ report: ModerationReport, hideTrack: Bool) {
        struct Request: Encodable { let hideTrack: Bool }
        guard let token = session.token else { return }
        Task {
            do {
                try await APIClient.shared.requestVoid("/admin/reports/\(report.id)/resolve", method: "POST", body: Request(hideTrack: hideTrack), token: token)
                reports.removeAll { $0.id == report.id }
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct UploadTrackView: View {
    @EnvironmentObject private var session: SessionStore
    let didUpload: (Track) -> Void
    @State private var showFileImporter = false
    @State private var selectedFile: URL?
    @State private var name = ""
    @State private var city = "北京"
    @State private var cityOptions = ["北京"]
    @State private var tags = ""
    @State private var sport = "越野跑"
    @State private var isPublic = true
    @State private var showContributor = true
    @State private var isUploading = false
    @State private var isSuggestingMetadata = false
    @State private var errorMessage: String?
    @State private var suggestionStatus = ""
    @State private var nameWasEdited = false
    @State private var cityWasEdited = false
    @State private var tagsWereEdited = false
    @State private var sportWasEdited = false
    @State private var suggestionRequestID = UUID()
    @State private var tutorialPlayer = AVPlayer(url: URL(string: "https://runfast.fun/assets/videos/coros-fit-export.mp4")!)

    private var allowedFileTypes: [UTType] {
        ["fit", "gpx", "kml"].compactMap { UTType(filenameExtension: $0) } + [.data]
    }

    private var uploadButtonTitle: String { isUploading ? "上传中…" : "上传运动记录" }

    var body: some View {
        ZStack {
            Form {
                Section("选择文件") {
                    VStack(alignment: .leading, spacing: 10) {
                        Button { showFileImporter = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.badge.plus").font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(selectedFile?.lastPathComponent ?? "选择 FIT 文件").font(.subheadline.weight(.bold))
                                    Text(selectedFile == nil ? "支持 .fit、.gpx、.kml" : "点击更换文件").font(.caption)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.bold))
                            }
                            .foregroundStyle(TrailBoxColor.primaryDark)
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(TrailBoxColor.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(TrailBoxColor.primary.opacity(0.35)))
                        }
                        .buttonStyle(.plain)
                        Text("FIT 文件会作为个人运动记录保存；公开后只贡献路线基础信息。")
                            .font(.footnote).foregroundStyle(TrailBoxColor.secondaryText)
                    }
                    uploadGuide
                }
                Section("记录信息") {
                    TextField("记录名称", text: editedBinding($name, didEdit: $nameWasEdited))
                    Picker("城市", selection: editedBinding($city, didEdit: $cityWasEdited)) {
                        ForEach(cityOptions, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("标签（逗号分隔）", text: editedBinding($tags, didEdit: $tagsWereEdited))
                    Picker("运动类型", selection: editedBinding($sport, didEdit: $sportWasEdited)) {
                        Text("越野跑").tag("越野跑")
                        Text("徒步").tag("徒步")
                    }
                    if !suggestionStatus.isEmpty {
                        HStack(spacing: 7) {
                            if isSuggestingMetadata { ProgressView().controlSize(.small) }
                            Text(suggestionStatus)
                        }
                        .font(.footnote).foregroundStyle(TrailBoxColor.secondaryText)
                    }
                }
                Section("公开设置") {
                    VStack(alignment: .leading, spacing: 14) {
                        settingToggle("公开为探索路线", description: "上传成功后出现在探索路线，只展示路线基础信息。", isOn: $isPublic)
                        settingToggle("在探索路线展示贡献者昵称", description: "公开卡片中显示你的昵称，方便标记路线来源。", isOn: $showContributor)
                    }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(TrailBoxColor.danger) } }
            }
            .disabled(isUploading)
            .navigationTitle("上传记录").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                let isDisabled = selectedFile == nil || isUploading || isSuggestingMetadata
                FloatingActionBar {
                    Button(uploadButtonTitle) { if !isDisabled { upload() } }
                        .font(.headline.weight(.bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .buttonStyle(.plain)
                        .trailBoxGlass(
                            tint: isDisabled ? TrailBoxColor.secondaryText.opacity(0.45) : TrailBoxColor.primary,
                            interactive: !isDisabled,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .allowsHitTesting(!isDisabled)
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: allowedFileTypes) { result in
                guard case .success(let url) = result else { return }
                selectFile(url)
            }
            if isUploading { uploadingOverlay }
        }
        .background(TrailBoxColor.background)
    }

    private func upload() {
        guard !isSuggestingMetadata, let selectedFile, let token = session.token else { return }
        isUploading = true; errorMessage = nil
        Task {
            let access = selectedFile.startAccessingSecurityScopedResource()
            defer { if access { selectedFile.stopAccessingSecurityScopedResource() } }
            do {
                let submittedName = nameWasEdited ? name.trimmingCharacters(in: .whitespacesAndNewlines) : nil
                let track = try await APIClient.shared.uploadTrack(fileURL: selectedFile, name: submittedName, city: city, tags: normalizedTags, sport: sport, isPublic: isPublic, showContributor: showContributor, token: token)
                let _: [RouteMatch]? = try? await APIClient.shared.request(
                    "/tracks/match-activity/\(track.id)",
                    method: "POST",
                    token: token
                )
                didUpload(track)
            } catch { errorMessage = error.localizedDescription }
            isUploading = false
        }
    }

    private func suggest(for fileURL: URL) {
        let requestID = UUID()
        suggestionRequestID = requestID
        isSuggestingMetadata = true
        suggestionStatus = "正在根据轨迹位置识别路线名称、城市和标签…"
        Task {
            let access = fileURL.startAccessingSecurityScopedResource()
            defer { if access { fileURL.stopAccessingSecurityScopedResource() } }
            do {
                let suggestion = try await APIClient.shared.suggestMetadata(fileURL: fileURL, token: session.token)
                guard requestID == suggestionRequestID else { return }
                var applied: [String] = []
                if let name = suggestion.name, !nameWasEdited { self.name = name; applied.append("路线：\(name)") }
                if let city = suggestion.city, !cityWasEdited {
                    if !cityOptions.contains(city) { cityOptions.append(city) }
                    self.city = city
                    applied.append("城市：\(city)")
                }
                if let tags = suggestion.tags, !tags.isEmpty, !tagsWereEdited { self.tags = tags.joined(separator: ","); applied.append("标签：\(tags.joined(separator: ","))") }
                if let sport = suggestion.sport, ["越野跑", "徒步"].contains(sport), !sportWasEdited { self.sport = sport; applied.append("运动类型：\(sport)") }
                suggestionStatus = applied.isEmpty ? "未匹配到可自动填写的信息，可手动填写后上传。" : "已自动推荐 \(applied.joined(separator: "，"))"
            } catch {
                guard requestID == suggestionRequestID else { return }
                suggestionStatus = "暂时无法自动推荐标签，可手动填写后上传。"
            }
            if requestID == suggestionRequestID { isSuggestingMetadata = false }
        }
    }

    private var normalizedTags: String {
        var seen = Set<String>()
        return tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ",")
    }

    private var uploadingOverlay: some View {
        ZStack {
            TrailBoxColor.background.ignoresSafeArea()
            VStack(spacing: 18) {
                ProgressView().controlSize(.large).tint(TrailBoxColor.primaryDark)
                VStack(spacing: 7) {
                    Text("正在上传运动记录").font(.title3.weight(.bold)).foregroundStyle(TrailBoxColor.text)
                    Text("正在保存轨迹文件并解析路线数据，请勿退出页面。")
                        .font(.subheadline).foregroundStyle(TrailBoxColor.secondaryText).multilineTextAlignment(.center)
                }
            }
            .padding(32).frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在上传运动记录，请勿退出页面")
    }

    private var uploadGuide: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                Text("以高驰 App 为例：找到这次已同步的运动记录，导出 .fit 文件，再回到小野box选择文件。佳明等平台也按同样方式导出。")
                guideStep("打开运动 App", "在高驰、佳明等手表配套 App 中找到已同步完成的运动记录。")
                guideStep("导出 .fit 文件", "在记录详情使用分享或导出入口，保存到“文件”App。")
                guideStep("回到小野box上传", "选择刚导出的 .fit 文件并补充路线信息。")
                VideoPlayer(player: tutorialPlayer)
                    .frame(height: 195)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .font(.footnote).foregroundStyle(TrailBoxColor.secondaryText)
            .padding(.top, 4)
        } label: {
            Label("还没有运动文件？查看如何从运动 App 导出", systemImage: "lightbulb")
                .font(.footnote)
                .foregroundStyle(TrailBoxColor.secondaryText)
        }
    }

    private func guideStep(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(TrailBoxColor.text)
            Text(detail)
        }
    }

    private func settingToggle(_ title: String, description: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(title, isOn: isOn)
            Text(description).font(.footnote).foregroundStyle(TrailBoxColor.secondaryText)
        }
        .padding(.vertical, 3)
    }

    private func editedBinding(_ value: Binding<String>, didEdit: Binding<Bool>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue },
            set: { newValue in
                value.wrappedValue = newValue
                didEdit.wrappedValue = true
            }
        )
    }

    private func selectFile(_ url: URL) {
        guard ["fit", "gpx", "kml"].contains(url.pathExtension.lowercased()) else {
            errorMessage = "仅支持 .fit、.gpx 和 .kml 文件。"
            return
        }
        selectedFile = url
        suggestionRequestID = UUID()
        name = url.deletingPathExtension().lastPathComponent
        cityOptions.removeAll { $0 != "北京" }
        city = "北京"; tags = ""; sport = "越野跑"
        nameWasEdited = false; cityWasEdited = false; tagsWereEdited = false; sportWasEdited = false
        errorMessage = nil
        suggestionStatus = "准备识别路线名称、城市和标签…"
        suggest(for: url)
    }
}
