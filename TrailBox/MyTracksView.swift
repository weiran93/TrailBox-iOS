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
    @State private var navigationPath = NavigationPath()
    @State private var statsRange: StatsRange = .month

    private enum StatsRange: String, CaseIterable, Identifiable { case month = "本月", all = "全部"; var id: String { rawValue } }

    var body: some View {
        NavigationStack(path: $navigationPath) {
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
                case .content: ScrollView { LazyVStack(spacing: 12) { summary; ForEach(viewModel.tracks) { track in NavigationLink { TrackDetailView(trackID: track.id, isPublicSource: false, onDeleted: refreshTracks) } label: { TrackCard(track: track, isActivity: true) }.buttonStyle(.plain) } }.padding(16) }
                }
            }.background(TrailBoxColor.background).toolbar(.hidden, for: .navigationBar)
                .task { if let token = session.token { await viewModel.load(token: token) } else { showAuthentication = true } }
                .sheet(isPresented: $showUpload) {
                    UploadTrackView { track in
                        if let token = session.token { Task { await viewModel.load(token: token) } }
                        navigationPath.append(track.id)
                    }
                }
                .sheet(isPresented: $showSettings) { SettingsView() }
                .navigationDestination(for: String.self) { trackID in
                    TrackDetailView(trackID: trackID, isPublicSource: false, onDeleted: refreshTracks)
                }
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
    private func refreshTracks() async {
        guard let token = session.token else { return }
        await viewModel.load(token: token)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var accountActionMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("用户信息") {
                    LabeledContent("公开 ID", value: session.user?.publicID ?? "-")
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
                Section("关于与支持") {
                    NavigationLink("隐私政策") { PrivacyPolicyView() }
                    Button("联系我们") {
                        if let url = URL(string: "mailto:\(AppConfiguration.supportEmail)") { openURL(url) }
                    }
                }
                Section { Button("退出登录", role: .destructive) { session.logout(); dismiss() } }
            }
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } } }
            .confirmationDialog("永久删除账户？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button(isDeletingAccount ? "删除中…" : "删除账户及所有数据", role: .destructive) { deleteAccount() }
                    .disabled(isDeletingAccount)
                Button("取消", role: .cancel) { }
            } message: {
                Text("你的私有记录、已公开路线、轨迹文件和 AI 分析将被永久删除，且无法恢复。")
            }
            .alert("账户操作", isPresented: Binding(get: { accountActionMessage != nil }, set: { if !$0 { accountActionMessage = nil } })) {
                Button("确定", role: .cancel) { }
            } message: { Text(accountActionMessage ?? "") }
        }
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
    var body: some View {
        Group { if let stats { List { Section("统计") { metric("全部轨迹", stats.total); metric("公开路线", stats.public); metric("私有记录", stats.private) }; Section("筛选") { TextField("搜索名称、城市或标签", text: $query).onSubmit { Task { await loadTracks() } }; Toggle("仅公开路线", isOn: $publicOnly).onChange(of: publicOnly) { _ in Task { await loadTracks() } } }; Section("最近轨迹") { ForEach(tracks) { track in VStack(alignment: .leading, spacing: 3) { Text(track.name); Text("\(track.city ?? "-") · \(track.isPublic ? "公开" : "私有")").font(.caption).foregroundStyle(TrailBoxColor.secondaryText) } } } } } else if let error { EmptyStateView(title: "加载失败", systemImage: "exclamationmark.triangle", message: error) } else { ProgressView() } }
            .navigationTitle("管理后台").task { await load() }
    }
    private func metric(_ title: String, _ value: Int) -> some View { SectionCard { HStack { Text(title); Spacer(); Text("\(value)").font(.title3.bold()).foregroundStyle(TrailBoxColor.primaryDark) } } }
    private func load() async { guard let token = session.token else { return }; do { stats = try await APIClient.shared.request("/admin/stats", token: token); await loadTracks() } catch { self.error = error.localizedDescription } }
    private func loadTracks() async { guard let token = session.token else { return }; var path = "/admin/tracks?limit=20"; if !query.isEmpty { path += "&q=" + query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)! }; if publicOnly { path += "&is_public=true" }; do { tracks = try await APIClient.shared.request(path, token: token) } catch { self.error = error.localizedDescription } }
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
    @Environment(\.dismiss) private var dismiss
    let didUpload: (Track) -> Void
    @State private var showFileImporter = false
    @State private var selectedFile: URL?
    @State private var name = ""
    @State private var city = "北京"
    @State private var tags = ""
    @State private var sport = "越野跑"
    @State private var isPublic = true
    @State private var showContributor = true
    @State private var isUploading = false
    @State private var isSuggestingMetadata = false
    @State private var errorMessage: String?
    @State private var suggestionStatus = ""

    private var isBusy: Bool { isUploading || isSuggestingMetadata }

    var body: some View {
        NavigationStack {
            ZStack {
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
                .disabled(isBusy)

                if isSuggestingMetadata { metadataLoadingOverlay }
            }
            .navigationTitle("上传记录").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() }.disabled(isBusy) }
                ToolbarItem(placement: .topBarTrailing) { Button(isUploading ? "上传中…" : "上传") { upload() }.disabled(selectedFile == nil || isBusy) }
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
        guard !isSuggestingMetadata, let selectedFile, let token = session.token else { return }
        isUploading = true; errorMessage = nil
        Task {
            let access = selectedFile.startAccessingSecurityScopedResource()
            defer { if access { selectedFile.stopAccessingSecurityScopedResource() } }
            do {
                let track = try await APIClient.shared.uploadTrack(fileURL: selectedFile, name: name.isEmpty ? selectedFile.deletingPathExtension().lastPathComponent : name, city: city, tags: tags, sport: sport, isPublic: isPublic, showContributor: showContributor, token: token)
                didUpload(track); dismiss()
            } catch { errorMessage = error.localizedDescription }
            isUploading = false
        }
    }

    private func suggest(for fileURL: URL) {
        isSuggestingMetadata = true
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
            isSuggestingMetadata = false
        }
    }

    private var metadataLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text("正在分析路线信息…").font(.headline)
                Text("正在识别记录名称、城市和标签")
                    .font(.footnote)
                    .foregroundStyle(TrailBoxColor.secondaryText)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在分析路线信息")
    }
}
