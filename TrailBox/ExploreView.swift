import SwiftUI

@MainActor
final class ExploreViewModel: ObservableObject {
    enum State { case loading, content, empty, failed(String) }
    @Published var state: State = .loading
    @Published var tracks: [Track] = []
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

    func load(token: String? = nil) async {
        let isInitialLoad = tracks.isEmpty
        if isInitialLoad { state = .loading }
        do {
            async let fetchedTracks: [Track] = APIClient.shared.request("/tracks/public?include_points=true", token: token)
            async let fetchedTags: [ConfiguredTag] = APIClient.shared.request("/tags")
            tracks = try await fetchedTracks
            tags = (try? await fetchedTags) ?? []
            state = tracks.isEmpty ? .empty : .content
        } catch {
            if isInitialLoad { state = .failed(error.localizedDescription) }
        }
    }
}

struct ExploreView: View {
    @EnvironmentObject private var session: SessionStore
    @Binding var showAuthentication: Bool
    @StateObject private var viewModel = ExploreViewModel()
    @State private var showFilters = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("探索路线").font(.title2.bold()).foregroundStyle(TrailBoxColor.text)
                    Spacer()
                    Text("v1.6.1").font(.caption).foregroundStyle(TrailBoxColor.secondaryText)
                }.padding(.horizontal, 16).frame(height: 56).background(.white)
                switch viewModel.state {
                case .loading: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty: EmptyStateView(title: "暂无公开轨迹", systemImage: "map", message: "成为第一个上传公开路线的人吧")
                case .failed(let message): EmptyStateView(title: "加载失败", systemImage: "exclamationmark.triangle", message: message).overlay(alignment: .bottom) { Button("重试") { Task { await viewModel.load() } }.padding() }
                case .content: content
                }
            }
            .background(TrailBoxColor.background)
            .toolbar(.hidden, for: .navigationBar)
            .task { await viewModel.load(token: session.token) }
            .refreshable { await viewModel.load(token: session.token) }
            .sheet(isPresented: $showFilters) { ExploreFilterSheet(viewModel: viewModel) }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    HStack { Image(systemName: "magnifyingglass").foregroundStyle(TrailBoxColor.secondaryText); TextField("搜索路线、城市、标签", text: $viewModel.keyword).font(.subheadline) }.padding(.horizontal, 12).frame(height: 40).background(.white).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(TrailBoxColor.border))
                    Button { showFilters = true } label: { Image(systemName: "line.3.horizontal.decrease.circle").font(.title3).frame(width: 40, height: 40).background(.white).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(TrailBoxColor.border)) }
                }.padding(.horizontal, 16)
                if !viewModel.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            tagButton("全部", tag: nil)
                            ForEach(viewModel.tags) { tag in tagButton(tag.name, tag: tag.name) }
                        }.padding(.horizontal, 16)
                    }
                }
                if viewModel.filteredTracks.isEmpty {
                    VStack(spacing: 8) { Image(systemName: "line.3.horizontal.decrease.circle").font(.title2).foregroundStyle(TrailBoxColor.secondaryText); Text("暂无匹配路线").font(.headline); Text("试试调整筛选条件").font(.subheadline).foregroundStyle(TrailBoxColor.secondaryText) }
                        .frame(maxWidth: .infinity).padding(.top, 48)
                } else {
                    LazyVStack(spacing: 12) { ForEach(viewModel.filteredTracks) { track in NavigationLink { TrackDetailView(trackID: track.id, isPublicSource: true) } label: { TrackCard(track: track, isActivity: false) }.buttonStyle(.plain) } }
                        .padding(.horizontal, 16)
                }
            }.padding(.vertical, 12)
        }
    }

    private func tagButton(_ title: String, tag: String?) -> some View {
        Button(title) { viewModel.selectedTag = tag }
            .font(.subheadline.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 7)
            .background(viewModel.selectedTag == tag ? TrailBoxColor.primary : .white)
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
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                LinearGradient(colors: [.black.opacity(0.18), .clear, .black.opacity(0.64)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading) {
                    HStack { Text("ROUTE").font(.caption2.bold()).tracking(2).foregroundStyle(.white.opacity(0.9)); Spacer(); if let city = track.city, !city.isEmpty { Text(city).font(.caption.weight(.medium)).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 4).background(.black.opacity(0.32)).clipShape(Capsule()).overlay(Capsule().stroke(.white.opacity(0.28))) } }
                    Spacer()
                    Text(track.name).font(.headline.bold()).foregroundStyle(.white).lineLimit(2).shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                }.padding(14)
            }
            VStack(alignment: .leading, spacing: 9) {
                Text(subtitle).font(.caption).foregroundStyle(TrailBoxColor.secondaryText)
                if !track.tagList.isEmpty { HStack(spacing: 5) { ForEach(track.tagList.prefix(3), id: \.self) { Text($0).font(.caption.weight(.medium)).foregroundStyle(TrailBoxColor.primaryDark).padding(.horizontal, 8).padding(.vertical, 4).background(TrailBoxColor.primary.opacity(0.12)).clipShape(Capsule()) } } }
                Divider().overlay(TrailBoxColor.border)
                HStack(spacing: 0) { exploreStat(DisplayFormat.distance(track.distanceM), "距离", TrailBoxColor.text); exploreStat(compactElevation(track.elevationGainM), "爬升", TrailBoxColor.primary); exploreStat(compactElevation(track.elevationLossM), "下降", .orange) }
            }.padding(16)
        }
        .background(.white).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                HStack(spacing: 14) { Text("平均配速 \(paceText)"); Text("均心 \(averageHeartRate.map { "\($0) bpm" } ?? "-")"); Text("步频 \(averageCadence.map { "\($0) spm" } ?? "-")") }.font(.caption).foregroundStyle(TrailBoxColor.secondaryText).padding(.top, 12)
                if let analysis = track.aiAnalysisText, !analysis.isEmpty { Button { aiExpanded.toggle() } label: { VStack(alignment: .leading, spacing: 6) { HStack { Text("AI 分析结论").font(.caption.weight(.bold)).foregroundStyle(TrailBoxColor.primaryDark); Spacer(); Text(aiExpanded ? "收起" : "展开").font(.caption).foregroundStyle(TrailBoxColor.secondaryText) }; if aiExpanded { Text(coreAnalysis(analysis)).font(.caption).foregroundStyle(TrailBoxColor.text).fixedSize(horizontal: false, vertical: true) } }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(TrailBoxColor.primary.opacity(0.06)).overlay(RoundedRectangle(cornerRadius: 10).stroke(TrailBoxColor.primary.opacity(0.16))).clipShape(RoundedRectangle(cornerRadius: 10)).padding(.top, 10) }.buttonStyle(.plain) } else { Text("AI 分析").font(.caption.weight(.semibold)).foregroundStyle(TrailBoxColor.secondaryText).padding(.horizontal, 12).padding(.vertical, 7).overlay(RoundedRectangle(cornerRadius: 9).stroke(TrailBoxColor.border)).padding(.top, 10) }
            }
        }
    }

    private func activityStat(_ value: String, _ label: String) -> some View { VStack(spacing: 4) { Text(value).font(.title3).foregroundStyle(TrailBoxColor.text); Text(label).font(.caption).foregroundStyle(TrailBoxColor.secondaryText) }.frame(maxWidth: .infinity) }

    private func exploreStat(_ value: String, _ label: String, _ color: Color) -> some View { VStack(spacing: 3) { Text(value).font(.title3.bold()).foregroundStyle(color); Text(label).font(.caption).foregroundStyle(TrailBoxColor.secondaryText) }.frame(maxWidth: .infinity) }
    private func compactElevation(_ value: Double) -> String { value >= 1000 ? String(format: "%.2fk", value / 1000) : String(format: "%.0f", value) }

    private func stat(_ value: String, label: String) -> some View { VStack(alignment: .leading, spacing: 2) { Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(TrailBoxColor.text); Text(label).font(.caption2).foregroundStyle(TrailBoxColor.secondaryText) } }

    private var subtitle: String {
        if isActivity { return DisplayFormat.date(track.startTime ?? track.createdAt) }
        return "贡献者 " + (track.contributorName ?? track.contributorPublicID ?? "小野box 用户")
    }
    private var activityDateAndSport: String { subtitle + (track.sport.map { " · \($0)" } ?? "") }
    private var durationText: String { guard let seconds = track.durationSec, seconds > 0 else { return "-" }; return String(format: "%d:%02d", Int(seconds) / 3600, (Int(seconds) % 3600) / 60) }
    private var paceText: String { guard let seconds = track.durationSec, seconds > 0, track.distanceM > 0 else { return "-" }; let pace = Int(seconds / (track.distanceM / 1000)); return String(format: "%d:%02d/km", pace / 60, pace % 60) }
    private var averageHeartRate: Int? { let values = track.points.compactMap(\.heartRate); guard !values.isEmpty else { return nil }; return values.reduce(0, +) / values.count }
    private var averageCadence: Int? { let values = track.points.compactMap(\.cadence); guard !values.isEmpty else { return nil }; return values.reduce(0, +) / values.count }
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
        let lats = points.map(\.lat), lons = points.map(\.lon)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else { return }
        // Reserve space for the route title overlaid at the bottom of the card.
        let horizontalPadding: CGFloat = 20
        let topPadding: CGFloat = 20
        let bottomPadding: CGFloat = 54
        func position(_ point: TrackPoint) -> CGPoint {
            CGPoint(
                x: horizontalPadding + CGFloat((point.lon - minLon) / max(maxLon - minLon, 0.00001)) * (size.width - 2 * horizontalPadding),
                y: size.height - bottomPadding - CGFloat((point.lat - minLat) / max(maxLat - minLat, 0.00001)) * (size.height - topPadding - bottomPadding)
            )
        }
        var path = Path(); path.move(to: position(points[0])); for point in points.dropFirst() { path.addLine(to: position(point)) }
        context.stroke(path, with: .color(Color(red: 0.09, green: 0.42, blue: 0.23)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
        for (point, color) in [(points.first!, Color.green), (points.last!, Color.red)] { context.fill(Path(ellipseIn: CGRect(x: position(point).x - 5, y: position(point).y - 5, width: 10, height: 10)), with: .color(color)) }
    } }
}
