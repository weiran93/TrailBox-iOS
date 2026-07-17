import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ContributeRouteView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var telemetry: TelemetryConsentController
    @Environment(\.dismiss) private var dismiss

    let didUpload: (Track) -> Void

    @State private var selectedFile: URL?
    @State private var name = ""
    @State private var nameWasEdited = false
    @State private var recommendationReason = ""
    @State private var city = "北京"
    @State private var cityOptions = ["北京"]
    @State private var tags = ""
    @State private var tagsWereEdited = false
    @State private var sport = "越野跑"
    @State private var sportWasEdited = false
    @State private var showContributor = true

    @State private var showFileImporter = false
    @State private var isSuggestingMetadata = false
    @State private var isUploading = false
    @State private var suggestionStatus = ""
    @State private var suggestionRequestID = UUID()
    @State private var errorMessage: String?

    @State private var lastSuggestion: TrackMetadataSuggestion?
    @State private var parseError: String?
    @State private var fileSizeText: String?
    @State private var fileFormatText: String?
    @State private var nameCandidates: [String] = []

    private var allowedFileTypes: [UTType] {
        ["fit", "gpx", "kml"].compactMap { UTType(filenameExtension: $0) } + [.data]
    }

    private var canUpload: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedFile != nil && !isUploading && !isSuggestingMetadata
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 16) {
                    fileSection
                    nameSection
                    recommendationSection
                    infoSection
                    contributorSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
            .background(TrailBoxColor.background)

            bottomUploadBar
        }
        .navigationTitle("贡献路线")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") { dismiss() }
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: allowedFileTypes) { result in
            guard case .success(let url) = result else { return }
            selectFile(url)
        }
        .alert("上传失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("确定", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: - Sections

    private var fileSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("选择轨迹文件").font(.headline).foregroundStyle(TrailBoxColor.text)

                Button { showFileImporter = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selectedFile == nil ? "doc.badge.plus" : "doc.text")
                            .font(.title3)
                            .foregroundStyle(TrailBoxColor.primaryDark)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedFile?.lastPathComponent ?? "点击选择文件")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(TrailBoxColor.text)
                            Text(fileInfoSubtitle)
                                .font(.caption)
                                .foregroundStyle(TrailBoxColor.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(TrailBoxColor.secondaryText)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(TrailBoxColor.primary.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(TrailBoxColor.primary.opacity(0.3), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                if let parseError, !parseError.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(parseError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if let previewPoints = lastSuggestion?.points, previewPoints.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        TrackMap(points: previewPoints)
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        HStack(spacing: 16) {
                            filePreviewMetric(lastSuggestion?.distanceM.map(DisplayFormat.distance) ?? "-", "距离")
                            filePreviewMetric(lastSuggestion?.elevationGainM.map(DisplayFormat.elevation) ?? "-", "累计爬升")
                            filePreviewMetric(lastSuggestion?.durationSec.map(DisplayFormat.duration) ?? "-", "运动时长")
                        }
                    }
                } else if isSuggestingMetadata {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在解析轨迹信息…")
                            .font(.caption)
                            .foregroundStyle(TrailBoxColor.secondaryText)
                        Spacer()
                    }
                    .padding(12)
                }

                Text("上传的轨迹文件会作为路线基础数据，公开后供其他用户浏览和下载。")
                    .font(.caption)
                    .foregroundStyle(TrailBoxColor.secondaryText)
            }
        }
    }

    private var fileInfoSubtitle: String {
        if let format = fileFormatText, let size = fileSizeText {
            return "\(format) · \(size)"
        } else if let format = fileFormatText {
            return format
        } else {
            return "支持 .fit、.gpx、.kml 格式"
        }
    }

    private func filePreviewMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(TrailBoxColor.text)
            Text(label).font(.caption2).foregroundStyle(TrailBoxColor.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nameSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 4) {
                    Text("路线名称").font(.headline).foregroundStyle(TrailBoxColor.text)
                    Text("*").font(.headline).foregroundStyle(.red)
                    Spacer()
                    Button { generateNameWithAI() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                            Text(nameCandidates.isEmpty ? "AI 生成" : "重新生成")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TrailBoxColor.primaryDark)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(TrailBoxColor.primary.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSuggestingMetadata || selectedFile == nil)
                    .opacity(selectedFile == nil ? 0.5 : 1)
                }

                TextField("给这条路线起个名字", text: Binding(
                    get: { name },
                    set: { name = $0; nameWasEdited = true }
                ))
                .font(.subheadline)
                .padding(12)
                .background(TrailBoxColor.surface)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(TrailBoxColor.border))

                if !nameCandidates.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI 推荐名称，点击即可使用：")
                            .font(.caption)
                            .foregroundStyle(TrailBoxColor.secondaryText)

                        FlowLayout(spacing: 8) {
                            ForEach(nameCandidates, id: \.self) { candidate in
                                Button {
                                    name = candidate
                                    nameWasEdited = true
                                } label: {
                                    Text(candidate)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(name == candidate ? .white : TrailBoxColor.primaryDark)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(name == candidate ? TrailBoxColor.primary : TrailBoxColor.primary.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if !suggestionStatus.isEmpty {
                    HStack(spacing: 6) {
                        if isSuggestingMetadata { ProgressView().controlSize(.small) }
                        Text(suggestionStatus)
                            .font(.caption)
                            .foregroundStyle(TrailBoxColor.secondaryText)
                    }
                }

                if selectedFile == nil {
                    Text("提示：先选择轨迹文件后，AI 才能根据路线位置推荐名称。")
                        .font(.caption)
                        .foregroundStyle(TrailBoxColor.secondaryText)
                }
            }
        }
    }

    private var recommendationSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("推荐理由").font(.headline).foregroundStyle(TrailBoxColor.text)
                    Spacer()
                    Text("\(recommendationReason.count)/200")
                        .font(.caption)
                        .foregroundStyle(recommendationReason.count > 200 ? .red : TrailBoxColor.secondaryText)
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $recommendationReason)
                        .font(.subheadline)
                        .frame(minHeight: 90)
                        .padding(8)
                        .background(TrailBoxColor.surface)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(TrailBoxColor.border))

                    if recommendationReason.isEmpty {
                        Text("说说这条路线的亮点，吸引其他山友来跑…")
                            .font(.subheadline)
                            .foregroundStyle(TrailBoxColor.secondaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }

                Text("选填。好的推荐语能让更多人发现这条路线。")
                    .font(.caption)
                    .foregroundStyle(TrailBoxColor.secondaryText)
            }
        }
    }

    private var infoSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("路线信息").font(.headline).foregroundStyle(TrailBoxColor.text)

                VStack(alignment: .leading, spacing: 6) {
                    Text("城市").font(.caption.weight(.medium)).foregroundStyle(TrailBoxColor.secondaryText)
                    Menu {
                        ForEach(cityOptions, id: \.self) { option in
                            Button {
                                city = option
                            } label: {
                                if option == city {
                                    Label(option, systemImage: "checkmark")
                                } else {
                                    Text(option)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "location.fill")
                                .foregroundStyle(TrailBoxColor.primaryDark)
                            Text(city)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(TrailBoxColor.text)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TrailBoxColor.secondaryText)
                        }
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(TrailBoxColor.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(TrailBoxColor.primary.opacity(0.22)))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("标签").font(.caption.weight(.medium)).foregroundStyle(TrailBoxColor.secondaryText)
                    TextField("用逗号分隔，如：越野跑，训练，拉练", text: Binding(
                        get: { tags },
                        set: { tags = $0; tagsWereEdited = true }
                    ))
                    .font(.subheadline)
                    .padding(12)
                    .background(TrailBoxColor.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(TrailBoxColor.border))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("运动类型").font(.caption.weight(.medium)).foregroundStyle(TrailBoxColor.secondaryText)
                    Picker("运动类型", selection: Binding(
                        get: { sport },
                        set: { sport = $0; sportWasEdited = true }
                    )) {
                        Text("越野跑").tag("越野跑")
                        Text("徒步").tag("徒步")
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private var contributorSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 5) {
                Toggle("展示贡献者昵称", isOn: $showContributor)
                Text("开启后，其他用户在探索路线和详情页可以看到你的昵称。")
                    .font(.caption)
                    .foregroundStyle(TrailBoxColor.secondaryText)
            }
        }
    }

    private var bottomUploadBar: some View {
        FloatingActionBar(bottomPadding: 24) {
            Button {
                upload()
            } label: {
                Text(isUploading ? "上传中…" : "上传并贡献路线")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .disabled(!canUpload)
            .buttonStyle(.plain)
            .trailBoxGlass(
                tint: canUpload ? TrailBoxColor.primary : TrailBoxColor.secondaryText.opacity(0.45),
                interactive: canUpload,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    // MARK: - Actions

    private func selectFile(_ url: URL) {
        guard ["fit", "gpx", "kml"].contains(url.pathExtension.lowercased()) else {
            errorMessage = "仅支持 .fit、.gpx 和 .kml 文件。"
            return
        }

        // 文件大小校验：超过 50MB 提示但允许继续
        let maxSize: Int64 = 50 * 1024 * 1024
        if let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, Int64(fileSize) > maxSize {
            errorMessage = "文件超过 50MB，可能导致上传较慢或失败。"
        } else {
            errorMessage = nil
        }

        selectedFile = url
        fileFormatText = url.pathExtension.uppercased()
        fileSizeText = formatFileSize(url)
        lastSuggestion = nil
        parseError = nil
        nameCandidates = []
        suggestionRequestID = UUID()
        name = url.deletingPathExtension().lastPathComponent
        nameWasEdited = false
        cityOptions.removeAll { $0 != "北京" }
        city = "北京"
        tags = ""
        sport = "越野跑"
        tagsWereEdited = false
        sportWasEdited = false
        suggestionStatus = "正在识别路线信息…"
        suggest(for: url)
    }

    private func formatFileSize(_ url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    private func generateNameWithAI() {
        guard let selectedFile else {
            errorMessage = "请先选择轨迹文件，AI 才能生成路线名称。"
            return
        }
        suggest(for: selectedFile, forceName: true)
    }

    private func suggest(for fileURL: URL, forceName: Bool = false) {
        let requestID = UUID()
        suggestionRequestID = requestID
        isSuggestingMetadata = true
        suggestionStatus = "正在根据轨迹位置推荐信息…"

        Task {
            let access = fileURL.startAccessingSecurityScopedResource()
            defer { if access { fileURL.stopAccessingSecurityScopedResource() } }

            do {
                let suggestion = try await APIClient.shared.suggestMetadata(fileURL: fileURL, token: session.token)
                guard requestID == suggestionRequestID else { return }
                lastSuggestion = suggestion
                parseError = nil

                var applied: [String] = []

                // AI 只提供候选；用户明确点击候选后才替换文件名。
                if forceName {
                    let candidates = suggestion.nameCandidates?.filter { !$0.isEmpty }
                    if let candidates, !candidates.isEmpty {
                        nameCandidates = candidates
                    } else if let suggestedName = suggestion.name, !suggestedName.isEmpty {
                        nameCandidates = [suggestedName]
                    } else {
                        nameCandidates = []
                    }
                    if !nameCandidates.isEmpty { applied.append("名称候选") }
                }

                if let suggestedCity = suggestion.city {
                    if !cityOptions.contains(suggestedCity) { cityOptions.append(suggestedCity) }
                    city = suggestedCity
                    applied.append("城市")
                }

                if let suggestedTags = suggestion.tags, !suggestedTags.isEmpty, !tagsWereEdited {
                    tags = suggestedTags.joined(separator: ",")
                    applied.append("标签")
                }

                if let suggestedSport = suggestion.sport, ["越野跑", "徒步"].contains(suggestedSport), !sportWasEdited {
                    sport = suggestedSport
                    applied.append("运动类型")
                }

                suggestionStatus = applied.isEmpty ? "已识别文件，未匹配到可自动填写的信息。" : "已自动推荐 \(applied.joined(separator: "、"))"
            } catch {
                guard requestID == suggestionRequestID else { return }
                lastSuggestion = nil
                nameCandidates = []
                parseError = "无法解析该轨迹文件，请检查文件是否完整或格式是否正确。"
                suggestionStatus = "自动推荐失败，请手动填写路线信息。"
            }

            if requestID == suggestionRequestID {
                isSuggestingMetadata = false
            }
        }
    }

    private func upload() {
        guard let selectedFile, let token = session.token else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        isUploading = true
        errorMessage = nil
        telemetry.record(.routeContribution, phase: .started, source: .contribution)

        Task {
            let access = selectedFile.startAccessingSecurityScopedResource()
            defer { if access { selectedFile.stopAccessingSecurityScopedResource() } }

            do {
                let reason = recommendationReason.trimmingCharacters(in: .whitespacesAndNewlines)
                let track = try await APIClient.shared.uploadTrack(
                    fileURL: selectedFile,
                    name: trimmedName,
                    city: city,
                    tags: normalizedTags,
                    sport: sport,
                    trackKind: "route_contribution",
                    isPublic: true,
                    showContributor: showContributor,
                    recommendationReason: reason.isEmpty ? nil : reason,
                    token: token
                )
                telemetry.record(.routeContribution, phase: .succeeded, source: .contribution)
                didUpload(track)
                dismiss()
            } catch {
                telemetry.record(
                    .routeContribution,
                    phase: .failed,
                    source: .contribution,
                    failureCategory: TelemetryFailureCategory.classify(error)
                )
                errorMessage = error.localizedDescription
            }
            isUploading = false
        }
    }

    private var normalizedTags: String {
        var seen = Set<String>()
        return tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ",")
    }
}
