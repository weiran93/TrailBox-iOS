import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class MyTracksViewModel: ObservableObject {
    enum State { case loading, content, empty, failed(String) }
    @Published var state: State = .loading
    @Published var tracks: [Track] = []
    func load(token: String) async { state = .loading; do { tracks = try await APIClient.shared.request("/tracks/my?include_points=true", token: token); state = tracks.isEmpty ? .empty : .content } catch { state = .failed(error.localizedDescription) } }
}

struct MyTracksView: View {
    @EnvironmentObject private var session: SessionStore
    @Binding var showAuthentication: Bool
    @StateObject private var viewModel = MyTracksViewModel()
    @State private var showUpload = false
    @State private var showSettings = false
    @State private var statsRange: StatsRange = .month

    private enum StatsRange: String, CaseIterable, Identifiable { case month = "本月", all = "全部"; var id: String { rawValue } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("我的记录").font(.title2.bold()).foregroundStyle(TrailBoxColor.text)
                    Spacer()
                    Button { showUpload = true } label: { Text("上传记录").font(.subheadline.weight(.semibold)).foregroundStyle(TrailBoxColor.primaryDark) }
                    Button { showSettings = true } label: { Image(systemName: "gearshape").foregroundStyle(TrailBoxColor.text).padding(.leading, 12) }
                }.padding(.horizontal, 16).frame(height: 56).background(.white)
                switch viewModel.state {
                case .loading: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty: EmptyStateView(title: "还没有轨迹", systemImage: "figure.run", message: "从运动 App 分享 .fit 或 .gpx 文件到小野box")
                case .failed(let message): EmptyStateView(title: "加载失败", systemImage: "exclamationmark.triangle", message: message)
                case .content: ScrollView { LazyVStack(spacing: 12) { summary; ForEach(viewModel.tracks) { track in NavigationLink { TrackDetailView(trackID: track.id, isPublicSource: false) } label: { TrackCard(track: track, isActivity: true) }.buttonStyle(.plain) } }.padding(16) }
                }
            }.background(TrailBoxColor.background).toolbar(.hidden, for: .navigationBar)
                .task { if let token = session.token { await viewModel.load(token: token) } else { showAuthentication = true } }
                .sheet(isPresented: $showUpload) { UploadTrackView { if let token = session.token { Task { await viewModel.load(token: token) } } } }
                .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var summary: some View {
        let statTracks = filteredForStatistics
        return SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack { VStack(alignment: .leading, spacing: 2) { Text("训练统计").font(.headline); Text(statsRange == .month ? "本自然月" : "全部记录").font(.caption).foregroundStyle(TrailBoxColor.secondaryText) }; Spacer(); Picker("统计范围", selection: $statsRange) { ForEach(StatsRange.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).frame(width: 130) }
                HStack(spacing: 0) {
                metric("\(statTracks.count)", "记录")
                Spacer()
                metric(DisplayFormat.distance(statTracks.reduce(0) { $0 + $1.distanceM }), "总距离")
                Spacer()
                metric(totalDuration(statTracks), "总用时")
                Spacer()
                metric(DisplayFormat.elevation(statTracks.reduce(0) { $0 + $1.elevationGainM }), "累计爬升")
                }
            }
        }
    }
    private var filteredForStatistics: [Track] {
        guard statsRange == .month else { return viewModel.tracks }
        let calendar = Calendar.current
        return viewModel.tracks.filter { track in guard let date = track.startTime ?? track.createdAt else { return false }; return calendar.isDate(date, equalTo: Date(), toGranularity: .month) }
    }
    private func totalDuration(_ tracks: [Track]) -> String { let seconds = Int(tracks.reduce(0) { $0 + ($1.durationSec ?? 0) }); guard seconds > 0 else { return "-" }; return seconds >= 3600 ? "\(seconds / 3600)h \((seconds % 3600) / 60)m" : "\(seconds / 60)m" }
    private func metric(_ value: String, _ label: String) -> some View { VStack(alignment: .leading) { Text(value).font(.headline); Text(label).font(.caption).foregroundStyle(TrailBoxColor.secondaryText) } }
}

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var deepSeekKey = ""
    @State private var message: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("用户信息") {
                    LabeledContent("公开 ID", value: session.user?.publicID ?? "-")
                    LabeledContent("用户名", value: session.user?.username ?? "-")
                }
                if session.user?.isAdmin == true { Section("管理后台") { NavigationLink("管理公开轨迹与上传内容") { AdminDashboardView() } } }
                Section("昵称") { TextField("昵称", text: $nickname); Button("保存昵称") { saveProfile() }.disabled(isSaving) }
                Section("修改密码") { SecureField("旧密码", text: $oldPassword); SecureField("新密码（至少 8 位）", text: $newPassword); Button("修改密码") { changePassword() }.disabled(isSaving || oldPassword.isEmpty || newPassword.count < 8) }
                Section("AI 分析") { SecureField("DeepSeek API Key（可选）", text: $deepSeekKey); Button("保存 DeepSeek Key") { saveProfile() }.disabled(isSaving) }
                Section { Button("退出登录", role: .destructive) { session.logout(); dismiss() } }
                if let message { Section { Text(message).foregroundStyle(TrailBoxColor.secondaryText) } }
            }
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } } }
            .onAppear { nickname = session.user?.nickname ?? "" }
        }
    }

    private func saveProfile() {
        struct Request: Encodable { let nickname: String?; let deepseekApiKey: String? }
        guard let token = session.token else { return }; isSaving = true
        Task { do { let user: User = try await APIClient.shared.request("/users/me", method: "PATCH", body: Request(nickname: nickname.isEmpty ? nil : nickname, deepseekApiKey: deepSeekKey.isEmpty ? nil : deepSeekKey), token: token); session.update(user: user); message = "已保存" } catch { message = error.localizedDescription }; isSaving = false }
    }

    private func changePassword() {
        struct Request: Encodable { let oldPassword: String; let newPassword: String }
        guard let token = session.token else { return }; isSaving = true
        Task { do { let user: User = try await APIClient.shared.request("/users/me/change-password", method: "POST", body: Request(oldPassword: oldPassword, newPassword: newPassword), token: token); session.update(user: user); oldPassword = ""; newPassword = ""; message = "密码已修改" } catch { message = error.localizedDescription }; isSaving = false }
    }
}

struct AdminDashboardView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var stats: AdminStats?
    @State private var error: String?
    @State private var tracks: [Track] = []
    @State private var query = ""
    @State private var publicOnly = false
    var body: some View {
        Group { if let stats { List { Section("统计") { metric("全部轨迹", stats.total); metric("公开路线", stats.public); metric("私有记录", stats.private) }; Section("筛选") { TextField("搜索名称、城市或标签", text: $query).onSubmit { Task { await loadTracks() } }; Toggle("仅公开路线", isOn: $publicOnly).onChange(of: publicOnly) { _ in Task { await loadTracks() } } }; Section("最近轨迹") { ForEach(tracks) { track in VStack(alignment: .leading, spacing: 3) { Text(track.name); Text("\(track.city ?? "-") · \(track.isPublic ? "公开" : "私有")").font(.caption).foregroundStyle(TrailBoxColor.secondaryText) } } } } } else if let error { EmptyStateView(title: "加载失败", systemImage: "exclamationmark.triangle", message: error) } else { ProgressView() } }
            .navigationTitle("管理后台").task { await load() }
    }
    private func metric(_ title: String, _ value: Int) -> some View { SectionCard { HStack { Text(title); Spacer(); Text("\(value)").font(.title3.bold()).foregroundStyle(TrailBoxColor.primaryDark) } } }
    private func load() async { guard let token = session.token else { return }; do { stats = try await APIClient.shared.request("/admin/stats", token: token); await loadTracks() } catch { self.error = error.localizedDescription } }
    private func loadTracks() async { guard let token = session.token else { return }; var path = "/admin/tracks?limit=20"; if !query.isEmpty { path += "&q=" + query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)! }; if publicOnly { path += "&is_public=true" }; do { tracks = try await APIClient.shared.request(path, token: token) } catch { self.error = error.localizedDescription } }
}

struct UploadTrackView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    let didUpload: () -> Void
    @State private var showFileImporter = false
    @State private var selectedFile: URL?
    @State private var name = ""
    @State private var city = "北京"
    @State private var tags = ""
    @State private var sport = "越野跑"
    @State private var isPublic = true
    @State private var showContributor = true
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var suggestionStatus = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("选择文件") {
                    Button(selectedFile?.lastPathComponent ?? "选择 FIT / GPX / KML 文件") { showFileImporter = true }
                    Text("FIT 文件作为个人运动记录保存；公开后仅展示路线基础信息。").font(.footnote).foregroundStyle(TrailBoxColor.secondaryText)
                    if !suggestionStatus.isEmpty { Text(suggestionStatus).font(.footnote).foregroundStyle(TrailBoxColor.secondaryText) }
                }
                Section("记录信息") {
                    TextField("记录名称", text: $name)
                    TextField("城市", text: $city)
                    TextField("标签（逗号分隔）", text: $tags)
                    Picker("运动类型", selection: $sport) { Text("越野跑").tag("越野跑"); Text("徒步").tag("徒步") }
                }
                Section("公开设置") {
                    Toggle("公开为探索路线", isOn: $isPublic)
                    Toggle("展示贡献者昵称", isOn: $showContributor)
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(TrailBoxColor.danger) } }
            }
            .navigationTitle("上传记录").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button(isUploading ? "上传中…" : "上传") { upload() }.disabled(selectedFile == nil || isUploading) }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.data]) { result in
                guard case .success(let url) = result else { return }
                selectedFile = url
                if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
                suggest(for: url)
            }
        }
    }

    private func upload() {
        guard let selectedFile, let token = session.token else { return }
        isUploading = true; errorMessage = nil
        Task {
            let access = selectedFile.startAccessingSecurityScopedResource()
            defer { if access { selectedFile.stopAccessingSecurityScopedResource() } }
            do {
                _ = try await APIClient.shared.uploadTrack(fileURL: selectedFile, name: name.isEmpty ? selectedFile.deletingPathExtension().lastPathComponent : name, city: city, tags: tags, sport: sport, isPublic: isPublic, showContributor: showContributor, token: token)
                didUpload(); dismiss()
            } catch { errorMessage = error.localizedDescription }
            isUploading = false
        }
    }

    private func suggest(for fileURL: URL) {
        suggestionStatus = "正在根据轨迹位置推荐路线信息…"
        Task {
            let access = fileURL.startAccessingSecurityScopedResource()
            defer { if access { fileURL.stopAccessingSecurityScopedResource() } }
            do {
                let suggestion = try await APIClient.shared.suggestMetadata(fileURL: fileURL, token: session.token)
                if let name = suggestion.name { self.name = name }
                if let city = suggestion.city { self.city = city }
                if let tags = suggestion.tags, !tags.isEmpty { self.tags = tags.joined(separator: ",") }
                if let sport = suggestion.sport, ["越野跑", "徒步"].contains(sport) { self.sport = sport }
                suggestionStatus = "已自动推荐路线信息，可继续手动修改。"
            } catch { suggestionStatus = "暂时无法自动推荐，可手动填写。" }
        }
    }
}
