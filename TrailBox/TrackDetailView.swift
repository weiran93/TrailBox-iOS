import MapKit
import SwiftUI
import Charts
import AVFoundation
import Speech

@MainActor
final class TrackDetailViewModel: ObservableObject {
    enum State { case loading, content(Track), failed(String) }
    @Published var state: State = .loading
    func load(id: String, isPublic: Bool, token: String?) async {
        state = .loading
        do { let path = isPublic ? "/tracks/\(id)/public" : "/tracks/\(id)"; state = .content(try await APIClient.shared.request(path, token: token)) }
        catch { state = .failed(error.localizedDescription) }
    }
}

struct TrackDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = TrackDetailViewModel()
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
    let trackID: String
    let isPublicSource: Bool
    let onDeleted: (() async -> Void)?

    init(trackID: String, isPublicSource: Bool, onDeleted: (() async -> Void)? = nil) {
        self.trackID = trackID
        self.isPublicSource = isPublicSource
        self.onDeleted = onDeleted
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
        .preference(key: BottomBarVisibilityPreferenceKey.self, value: false)
        .task { await viewModel.load(id: trackID, isPublic: isPublicSource, token: session.token) }
    }

    private func details(_ track: Track) -> some View {
        ZStack(alignment: .top) {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isPublicSource {
                    VStack(alignment: .leading, spacing: 5) { Text(track.name).font(.title2.bold()).foregroundStyle(TrailBoxColor.text); if let description = track.description { Text(description).font(.subheadline).foregroundStyle(TrailBoxColor.secondaryText) } }.padding(.horizontal, 16).padding(.top, 8)
                } else { activityHero(track).padding(.horizontal, 16).padding(.top, 8) }
                if !isPublicSource { analysisCard(track) }
                ZStack(alignment: .topTrailing) {
                    TrackMap(points: track.points).frame(height: 280)
                    Button { showFullscreenMap = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").padding(10).background(.white.opacity(0.92)).clipShape(Circle()) }.padding(12)
                }
                if let start = track.points.first, let end = track.points.last {
                    HStack(spacing: 12) {
                        endpointButton(title: "起点", point: start, color: TrailBoxColor.primaryDark)
                        endpointButton(title: "终点", point: end, color: TrailBoxColor.danger)
                    }.padding(.horizontal, 16)
                }
                SectionCard { HStack { metric(DisplayFormat.distance(track.distanceM), "距离"); Spacer(); metric(DisplayFormat.elevation(track.elevationGainM), "爬升"); Spacer(); metric(DisplayFormat.elevation(track.elevationLossM), "下降"); Spacer(); metric(track.points.compactMap(\.altitude).max().map(DisplayFormat.elevation) ?? "-", "最高海拔") } }.padding(.horizontal, 16)
                if isPublicSource { SectionCard { HStack { metric(elevationRange(track.points), "海拔落差"); Spacer(); metric(maxGrade(track.points), "最大坡度") } }.padding(.horizontal, 16) }
                ElevationChart(points: track.points, title: "海拔剖面").padding(.horizontal, 16)
                if !isPublicSource {
                    ActivityCharts(points: track.points).padding(.horizontal, 16)
                } else {
                    GradeChart(points: track.points).padding(.horizontal, 16)
                }
                if track.city != nil || !track.tagList.isEmpty { SectionCard { VStack(alignment: .leading, spacing: 10) { if let city = track.city { HStack { Text("城市").foregroundStyle(TrailBoxColor.secondaryText); Spacer(); Text(city).fontWeight(.semibold) } }; if !track.tagList.isEmpty { Divider(); VStack(alignment: .leading, spacing: 6) { Text("标签").font(.headline); Text(track.tagList.joined(separator: " · ")).font(.subheadline).foregroundStyle(TrailBoxColor.secondaryText) } } } }.padding(.horizontal, 16) }
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
                if !isPublicSource {
                    Menu {
                        Button("编辑记录") { showEdit = true }
                        Button("删除记录", role: .destructive) { showDeleteConfirmation = true }
                    } label: { Image(systemName: "ellipsis") }
                } else {
                    Menu {
                        Button("举报路线", role: .destructive) {
                            guard session.isAuthenticated else { session.requireAuthentication(); return }
                            showReport = true
                        }
                        if let publicID = track.contributorPublicID {
                            Button("屏蔽该贡献者", role: .destructive) { blockContributor(publicID) }
                        }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
        }
        .sheet(isPresented: $showEdit) { EditTrackView(track: track) { Task { await viewModel.load(id: trackID, isPublic: isPublicSource, token: session.token) } } }
        .sheet(item: $shareFile) { ActivityFileView(url: $0.url) }
        .confirmationDialog("删除这条记录？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) { delete(track) }
        } message: { Text("删除后不可恢复。") }
        .alert("删除成功", isPresented: $showDeleteSuccess) {
            Button("确定") { finishDeleting() }
        } message: {
            Text("该记录已删除。")
        }
        .alert("操作失败", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) { Button("确定", role: .cancel) {} } message: { Text(actionError ?? "") }
        .sheet(isPresented: $showFullscreenMap) { NavigationStack { TrackMap(points: track.points).ignoresSafeArea(edges: .bottom).navigationTitle(track.name).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { showFullscreenMap = false } } } } }
        .sheet(isPresented: $showSharePreview) { SharePreviewView(source: isPublicSource ? .exploreRoute : .activity, data: RouteShareData.make(from: track, source: isPublicSource ? .exploreRoute : .activity)) }
        .sheet(isPresented: $showReport) { ReportTrackView(trackID: track.id) }
        .safeAreaInset(edge: .bottom, spacing: 0) { detailActions(track) }
    }

    private func detailActions(_ track: Track) -> some View {
        HStack(spacing: 12) {
            Button { download(track) } label: {
                Label("下载 GPX", systemImage: "arrow.down.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .foregroundStyle(TrailBoxColor.primaryDark)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(TrailBoxColor.primary.opacity(0.35)))

            Button { showSharePreview = true } label: {
                Label(isPublicSource ? "分享路线" : "分享记录", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .foregroundStyle(.white)
            .background(TrailBoxColor.primary)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.white.shadow(.drop(color: .black.opacity(0.08), radius: 8, y: -3)))
    }

    private func metric(_ value: String, _ label: String) -> some View { VStack(alignment: .leading, spacing: 3) { Text(value).font(.headline).foregroundStyle(TrailBoxColor.text); Text(label).font(.caption).foregroundStyle(TrailBoxColor.secondaryText) } }
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
                                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(TrailBoxColor.secondaryText).frame(width: 32, height: 32).background(.white).clipShape(Circle())
                                }.accessibilityLabel("删除本次语音录入")
                            }
                            Text(capturedVoiceText).font(.subheadline).foregroundStyle(TrailBoxColor.text).lineLimit(3)
                        }.padding(12).background(TrailBoxColor.background).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Label(isVoiceGestureActive ? "松手结束录音" : capturedVoiceText.isEmpty ? "按住说说这次感受" : "按住重新说", systemImage: isVoiceGestureActive ? "waveform" : "mic.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 56)
                            .background(isVoiceGestureActive ? Color.black : TrailBoxColor.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                            .gesture(voiceStartGesture())
                    Button(capturedVoiceText.isEmpty ? "跳过体感，直接分析" : "开始 AI 分析") {
                        analyze(track, feeling: ActivityFeeling(overallFeeling: nil, processTags: [], bodyTags: [], routeEnvTags: [], painDetails: [], voiceText: capturedVoiceText, textNote: ""))
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TrailBoxColor.primaryDark)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                    .background(TrailBoxColor.primary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(TrailBoxColor.primary.opacity(0.25)))
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
    private func elevationRange(_ points: [TrackPoint]) -> String { let values = points.compactMap(\.altitude); guard let min = values.min(), let max = values.max() else { return "-" }; return DisplayFormat.elevation(max - min) }
    private func maxGrade(_ points: [TrackPoint]) -> String { guard let value = points.compactMap(\.grade).max() else { return "-" }; return String(format: "%.1f%%", value) }

    private func endpointButton(title: String, point: TrackPoint, color: Color) -> some View {
        Button { openInMaps(point, name: "\(trackID) \(title)") } label: {
            HStack(spacing: 8) { Circle().fill(color).frame(width: 10, height: 10); VStack(alignment: .leading, spacing: 2) { Text(title).font(.caption).foregroundStyle(TrailBoxColor.secondaryText); Text("导航").font(.subheadline.weight(.semibold)).foregroundStyle(TrailBoxColor.text) }; Spacer(); Image(systemName: "arrow.triangle.turn.up.right.diamond").foregroundStyle(TrailBoxColor.primaryDark) }
                .padding(12).background(.white).clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(TrailBoxColor.border))
        }
    }

    private func openInMaps(_ point: TrackPoint, name: String) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)))
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }

    private func download(_ track: Track) {
        Task { do { shareFile = ActivityFile(url: try await APIClient.shared.downloadGPX(trackID: track.id, token: session.token)) } catch { actionError = error.localizedDescription } }
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
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                VStack(alignment: .leading, spacing: 4) {
                    if let title = block.title { Text("【\(title)】").font(.subheadline.weight(.bold)) }
                    Text(block.content).font(.subheadline).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                }
            }
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
        }.padding(14).background(.white.opacity(0.96)).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)).shadow(color: .black.opacity(0.12), radius: 14, y: 6)
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
            }.navigationTitle("编辑记录").navigationBarTitleDisplayMode(.inline)
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
    let points: [TrackPoint]
    var body: some View {
        SectionCard { VStack(alignment: .leading, spacing: 10) { Text("坡度剖面").font(.headline); Chart(Array(points.enumerated()), id: \.offset) { index, point in if let grade = point.grade { LineMark(x: .value("点", index), y: .value("坡度", grade)).foregroundStyle(.orange) } }.chartXAxis(.hidden).frame(height: 160) } }
    }
}

private struct ActivityCharts: View {
    let points: [TrackPoint]
    var body: some View {
        VStack(spacing: 16) {
            chart(title: "心率变化", values: points.map(\.heartRate).map { $0.map(Double.init) }, color: .red, unit: "bpm")
            chart(title: "配速变化", values: points.map(\.speed), color: .blue, unit: "km/h")
        }
    }
    private func chart(title: String, values: [Double?], color: Color, unit: String) -> some View {
        SectionCard { VStack(alignment: .leading, spacing: 10) { Text(title).font(.headline); Chart(Array(values.enumerated()), id: \.offset) { index, value in if let value { LineMark(x: .value("点", index), y: .value(unit, value)).foregroundStyle(color).interpolationMethod(.catmullRom) } }.chartXAxis(.hidden).frame(height: 160) } }
    }
}

struct TrackMap: UIViewRepresentable {
    let points: [TrackPoint]

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
        map.setVisibleMapRect(polyline.boundingMapRect, edgePadding: UIEdgeInsets(top: 36, left: 28, bottom: 36, right: 28), animated: false)
        map.delegate = context.coordinator
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer { let renderer = MKPolylineRenderer(overlay: overlay); renderer.strokeColor = UIColor(red: 0.09, green: 0.42, blue: 0.23, alpha: 1); renderer.lineWidth = 4; renderer.lineJoin = .round; renderer.lineCap = .round; return renderer }
    }
}
