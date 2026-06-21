import MapKit
import SwiftUI
import Charts

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
    @StateObject private var viewModel = TrackDetailViewModel()
    @State private var showEdit = false
    @State private var showDeleteConfirmation = false
    @State private var shareFile: ActivityFile?
    @State private var actionError: String?
    @State private var aiAnalysis: String?
    @State private var isAnalyzing = false
    @State private var showFullscreenMap = false
    let trackID: String
    let isPublicSource: Bool

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
        .task { await viewModel.load(id: trackID, isPublic: isPublicSource, token: session.token) }
    }

    private func details(_ track: Track) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isPublicSource {
                    VStack(alignment: .leading, spacing: 5) { Text(track.name).font(.title2.bold()).foregroundStyle(TrailBoxColor.text); if let description = track.description { Text(description).font(.subheadline).foregroundStyle(TrailBoxColor.secondaryText) } }.padding(.horizontal, 16).padding(.top, 8)
                } else { activityHero(track).padding(.horizontal, 16).padding(.top, 8) }
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
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: URL(string: "https://runfast.fun/#track-detail?id=\(track.id)&source=explore")!) { Image(systemName: "square.and.arrow.up") }
                if !isPublicSource {
                    Menu {
                        Button("编辑记录") { showEdit = true }
                        Button("下载 GPX") { download(track) }
                        Button("删除记录", role: .destructive) { showDeleteConfirmation = true }
                    } label: { Image(systemName: "ellipsis") }
                } else {
                    Button { download(track) } label: { Image(systemName: "arrow.down.circle") }
                }
            }
        }
        .sheet(isPresented: $showEdit) { EditTrackView(track: track) { Task { await viewModel.load(id: trackID, isPublic: isPublicSource, token: session.token) } } }
        .sheet(item: $shareFile) { ActivityFileView(url: $0.url) }
        .confirmationDialog("删除这条记录？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) { delete(track) }
        } message: { Text("删除后不可恢复。") }
        .alert("操作失败", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) { Button("确定", role: .cancel) {} } message: { Text(actionError ?? "") }
        .onAppear { if aiAnalysis == nil { aiAnalysis = track.aiAnalysisText } }
        .sheet(isPresented: $showFullscreenMap) { NavigationStack { TrackMap(points: track.points).ignoresSafeArea(edges: .bottom).navigationTitle(track.name).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { showFullscreenMap = false } } } } }
    }

    private func metric(_ value: String, _ label: String) -> some View { VStack(alignment: .leading, spacing: 3) { Text(value).font(.headline).foregroundStyle(TrailBoxColor.text); Text(label).font(.caption).foregroundStyle(TrailBoxColor.secondaryText) } }
    private func activityHero(_ track: Track) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(DisplayFormat.date(track.startTime ?? track.createdAt) + (track.sport.map { " · \($0)" } ?? "")).font(.subheadline).foregroundStyle(TrailBoxColor.secondaryText)
                Text(track.name).font(.system(.title2, design: .rounded, weight: .heavy))
                HStack { Text("基础耐力").font(.caption.weight(.bold)).foregroundStyle(TrailBoxColor.primaryDark).padding(.horizontal, 10).padding(.vertical, 6).background(TrailBoxColor.primary.opacity(0.12)).clipShape(Capsule()); Text(track.isPublic ? "公开路线" : "私有记录").font(.caption.weight(.bold)).foregroundStyle(track.isPublic ? TrailBoxColor.primaryDark : TrailBoxColor.secondaryText).padding(.horizontal, 10).padding(.vertical, 6).background((track.isPublic ? TrailBoxColor.primary : TrailBoxColor.secondaryText).opacity(0.12)).clipShape(Capsule()) }
                if let aiAnalysis {
                    Text("AI 分析已生成").font(.headline.weight(.bold)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 16).background(TrailBoxColor.primary).clipShape(RoundedRectangle(cornerRadius: 12))
                    Divider()
                    markdownText(aiAnalysis).font(.body).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                } else {
                    Button(isAnalyzing ? "分析中…" : "AI 运动分析") { analyze(track) }.font(.headline.weight(.bold)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 16).background(TrailBoxColor.primary).clipShape(RoundedRectangle(cornerRadius: 12)).disabled(isAnalyzing)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity)
    }
    private func coreAnalysis(_ text: String) -> String { let parts = text.components(separatedBy: "【核心判断】"); let value = parts.count > 1 ? (parts[1].components(separatedBy: "【").first ?? text) : text; return value.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
    private func markdownText(_ text: String) -> Text {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .full)) {
            return Text(attributed)
        }
        return Text(text.replacingOccurrences(of: "**", with: ""))
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
        Task { do { try await APIClient.shared.requestVoid("/tracks/\(track.id)", method: "DELETE", token: token); await MainActor.run { } } catch { actionError = error.localizedDescription } }
    }

    private func analyze(_ track: Track) {
        guard let token = session.token else { return }; isAnalyzing = true
        Task { do { let result: AIAnalysisResponse = try await APIClient.shared.request("/tracks/\(track.id)/ai-analysis", method: "POST", token: token); aiAnalysis = result.analysis } catch { actionError = error.localizedDescription }; isAnalyzing = false }
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
