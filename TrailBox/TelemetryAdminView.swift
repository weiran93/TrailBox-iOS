import SwiftUI

@MainActor
final class TelemetryAdminViewModel: ObservableObject {
    @Published private(set) var summary: TelemetrySummary?
    @Published private(set) var reports: [TelemetryReportSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func load(days: Int, token: String) async {
        isLoading = true
        errorMessage = nil
        do {
            async let loadedSummary: TelemetrySummary = APIClient.shared.request("/admin/telemetry/summary?days=\(days)", token: token)
            async let loadedReports: [TelemetryReportSummary] = APIClient.shared.request("/admin/telemetry/reports?limit=50", token: token)
            summary = try await loadedSummary
            reports = try await loadedReports
        } catch {
            errorMessage = ErrorMessage.display(error)
        }
        isLoading = false
    }
}

struct TelemetryAdminView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var viewModel = TelemetryAdminViewModel()
    @State private var days = 7

    var body: some View {
        Group {
            if let summary = viewModel.summary {
                List {
                    Section {
                        Text(summary.sampleNote)
                            .font(.footnote)
                            .foregroundStyle(TrailBoxColor.secondaryText)
                    }

                    Section("样本") {
                        metric("匿名安装", summary.anonymousInstallations)
                        metric("会话", summary.sessions)
                    }

                    Section("核心漏斗") {
                        ForEach(summary.funnels) { funnel in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("\(eventTitle(funnel.from)) → \(eventTitle(funnel.to))")
                                    Spacer()
                                    Text(funnel.conversionRate, format: .percent.precision(.fractionLength(1)))
                                        .font(.headline)
                                        .foregroundStyle(TrailBoxColor.primaryDark)
                                }
                                Text("\(funnel.convertedSessions) / \(funnel.eligibleSessions) 个会话")
                                    .font(.caption)
                                    .foregroundStyle(TrailBoxColor.secondaryText)
                            }
                            .padding(.vertical, 3)
                        }
                    }

                    Section("动作结果") {
                        ForEach(summary.actions.filter { $0.attempts > 0 }) { action in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(eventTitle(action.name))
                                    Spacer()
                                    Text(action.successRate, format: .percent.precision(.fractionLength(1)))
                                        .font(.subheadline.bold())
                                }
                                Text("尝试 \(action.attempts) · 成功 \(action.succeeded) · 失败 \(action.failed) · 取消 \(action.cancelled)")
                                    .font(.caption)
                                    .foregroundStyle(TrailBoxColor.secondaryText)
                            }
                        }
                    }

                    Section("诊断") {
                        metric("报告", summary.diagnostics.reports)
                        metric("崩溃", summary.diagnostics.crashes)
                        metric("卡死", summary.diagnostics.hangs)
                        metric("CPU 异常", summary.diagnostics.cpuExceptions)
                        metric("磁盘写入异常", summary.diagnostics.diskWriteExceptions)
                    }

                    if !summary.failures.isEmpty {
                        Section("失败分类") {
                            ForEach(summary.failures) { failure in
                                metric(failureTitle(failure.category), failure.count)
                            }
                        }
                    }

                    if !summary.versions.isEmpty {
                        Section("版本分布") {
                            ForEach(summary.versions) { version in
                                metric(version.version, version.sessions)
                            }
                        }
                    }

                    if !viewModel.reports.isEmpty {
                        Section("最近 MetricKit 报告") {
                            ForEach(viewModel.reports) { report in
                                NavigationLink {
                                    TelemetryReportDetailView(report: report)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(report.reportType == "diagnostic" ? "诊断报告" : "性能报告")
                                            .font(.subheadline.weight(.semibold))
                                        Text("v\(report.appVersion) (\(report.build)) · \(report.osVersion)")
                                            .font(.caption)
                                            .foregroundStyle(TrailBoxColor.secondaryText)
                                    }
                                }
                            }
                        }
                    }
                }
                .refreshable { await reload() }
            } else if viewModel.isLoading {
                ProgressView("正在加载匿名观测")
            } else {
                EmptyStateView(
                    title: "观测数据加载失败",
                    systemImage: "waveform.path.ecg.rectangle",
                    message: viewModel.errorMessage ?? "请稍后重试"
                )
            }
        }
        .navigationTitle("匿名观测")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker("统计范围", selection: $days) {
                    Text("7 天").tag(7)
                    Text("30 天").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(width: 132)
            }
        }
        .task { await reload() }
        .onChange(of: days) { _ in Task { await reload() } }
    }

    private func reload() async {
        guard let token = session.token else { return }
        await viewModel.load(days: days, token: token)
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        HStack { Text(title); Spacer(); Text("\(value)").fontWeight(.semibold) }
    }

    private func eventTitle(_ value: String) -> String {
        [
            "app_session": "启动会话", "route_open": "打开路线", "favorite": "收藏",
            "departure": "一键出发", "navigation": "导航", "gpx_export": "GPX 导出",
            "share": "分享", "activity_upload": "上传记录", "route_contribution": "贡献路线",
            "api_failure": "接口失败"
        ][value] ?? value
    }

    private func failureTitle(_ value: String) -> String {
        [
            "network_offline": "网络离线", "timeout": "超时", "connection": "连接失败",
            "unauthorized": "登录过期", "http_4xx": "HTTP 4xx", "http_5xx": "HTTP 5xx",
            "decoding": "数据解码", "file": "文件", "permission": "权限",
            "cancelled": "已取消", "unknown": "未知"
        ][value] ?? value
    }
}

private struct TelemetryReportDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var detail: TelemetryReportDetail?
    @State private var errorMessage: String?
    let report: TelemetryReportSummary

    var body: some View {
        ScrollView {
            if let detail {
                VStack(alignment: .leading, spacing: 14) {
                    Text("v\(detail.appVersion) (\(detail.build)) · \(detail.osVersion)")
                        .font(.subheadline)
                        .foregroundStyle(TrailBoxColor.secondaryText)
                    Text(prettyPayload(detail.payload))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(TrailBoxColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(16)
            } else if let errorMessage {
                EmptyStateView(title: "报告加载失败", systemImage: "exclamationmark.triangle", message: errorMessage)
                    .padding(24)
            } else {
                ProgressView().padding(40)
            }
        }
        .navigationTitle(report.reportType == "diagnostic" ? "诊断报告" : "性能报告")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let token = session.token else { return }
            do {
                detail = try await APIClient.shared.request("/admin/telemetry/reports/\(report.id)", token: token)
            } catch {
                errorMessage = ErrorMessage.display(error)
            }
        }
    }

    private func prettyPayload(_ payload: TelemetryJSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
