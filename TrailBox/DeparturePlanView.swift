import SwiftUI

struct DeparturePlanView: View {
    @EnvironmentObject private var departurePlans: DeparturePlanStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DeparturePlan
    @State private var showDeleteConfirmation = false
    @State private var didSave = false

    let dismissOnSave: Bool
    let onOpenRoute: (() -> Void)?

    init(plan: DeparturePlan, dismissOnSave: Bool, onOpenRoute: (() -> Void)? = nil) {
        _draft = State(initialValue: plan)
        self.dismissOnSave = dismissOnSave
        self.onOpenRoute = onOpenRoute
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                planHero
                scheduleCard
                intelligenceCard
                checklistCard
                sourceCard

                if departurePlans.plan(id: draft.id) != nil {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("删除出发计划", systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TrailBoxColor.danger)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .background(TrailPageBackground())
        .navigationTitle("出发计划")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingActionBar {
                Button(action: save) {
                    Label(didSave ? "已保存" : "保存计划", systemImage: didSave ? "checkmark.circle.fill" : "calendar.badge.checkmark")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.plain)
                .trailBoxGlass(tint: TrailBoxColor.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .toolbar {
            if dismissOnSave {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .alert("删除这份出发计划？", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                departurePlans.delete(id: draft.id)
                dismiss()
            }
        } message: {
            Text("准备清单和计划时间会一并删除。")
        }
        .onChange(of: draft.plannedStart) { _ in
            didSave = false
            persistIfExisting()
        }
        .onAppear {
            didSave = departurePlans.plan(id: draft.id) != nil
        }
    }

    private var planHero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [TrailBoxColor.primaryDark, TrailBoxColor.primary, TrailBoxColor.moss],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Canvas { context, size in
                for index in 0..<5 {
                    let y = CGFloat(18 + index * 34)
                    var contour = Path()
                    contour.move(to: CGPoint(x: -20, y: y))
                    contour.addCurve(
                        to: CGPoint(x: size.width + 20, y: y + 8),
                        control1: CGPoint(x: size.width * 0.28, y: y - 25),
                        control2: CGPoint(x: size.width * 0.72, y: y + 28)
                    )
                    context.stroke(contour, with: .color(.white.opacity(0.08)), lineWidth: 1)
                }
            }
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(draft.city ?? "路线计划", systemImage: "mappin.and.ellipse")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.78))
                    Spacer()
                    Text(draft.riskLevel.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.18), in: Capsule())
                }

                Text(draft.routeName)
                    .font(.system(size: 25, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(3)

                HStack(spacing: 0) {
                    heroMetric(DisplayFormat.distance(draft.distanceM), "距离")
                    heroMetric(DisplayFormat.elevation(draft.elevationGainM), "累计爬升")
                    heroMetric(DeparturePlanFormat.duration(minimum: draft.estimatedDurationMin, maximum: draft.estimatedDurationMax), "预计用时")
                }
                .padding(.vertical, 11)
                .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.3), lineWidth: 0.8))
        .shadow(color: TrailBoxColor.primaryDark.opacity(0.16), radius: 18, y: 9)
    }

    private var scheduleCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                Label("计划时间", systemImage: "calendar.badge.clock")
                    .font(.headline)

                DatePicker(
                    "计划出发",
                    selection: $draft.plannedStart,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .font(.subheadline.weight(.semibold))

                Divider()

                HStack(spacing: 0) {
                    scheduleMetric(DeparturePlanFormat.time(draft.plannedStart), "计划出发", TrailBoxColor.primaryDark)
                    scheduleMetric(DeparturePlanFormat.finishRange(draft), "预计完成", TrailBoxColor.sky)
                    scheduleMetric(DeparturePlanFormat.time(draft.latestSafeStart), "最晚出发", draft.startsAfterSafeTime ? TrailBoxColor.danger : TrailBoxColor.warning)
                }

                if draft.startsAfterSafeTime {
                    Label("当前计划可能晚于安全出发时间，建议提前出发或缩短行程。", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(TrailBoxColor.danger)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let sunset = draft.sunsetOnPlannedDay {
                    Label("按日落 \(DeparturePlanFormat.time(sunset)) 并预留 1 小时安全余量计算", systemImage: "sunset.fill")
                        .font(.caption)
                        .foregroundStyle(TrailBoxColor.secondaryText)
                } else {
                    Label("暂无可靠日落或用时数据，最晚出发时间需要自行确认", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(TrailBoxColor.secondaryText)
                }
            }
        }
    }

    private var intelligenceCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("出发情报", systemImage: "sparkles")
                        .font(.headline)
                    Spacer()
                    Text(draft.riskLevel.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(riskColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(riskColor.opacity(0.11), in: Capsule())
                }

                intelligenceRow("exclamationmark.triangle.fill", draft.riskSummary, riskColor)
                intelligenceRow("cloud.sun.fill", draft.weatherSummary, TrailBoxColor.sky)
                intelligenceRow("mappin.and.ellipse", draft.facilitySummary, TrailBoxColor.moss)

                if let weatherDate = draft.weatherDate,
                   !Calendar.current.isDate(weatherDate, inSameDayAs: draft.plannedStart) {
                    Label("天气参考日期与计划日期不同，出发前请回到路线详情刷新计划。", systemImage: "arrow.clockwise.circle")
                        .font(.caption)
                        .foregroundStyle(TrailBoxColor.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var checklistCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Label("出发清单", systemImage: "checklist")
                        .font(.headline)
                    Spacer()
                    Text("\(draft.completedItemCount)/\(draft.checklist.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TrailBoxColor.primaryDark)
                }

                ProgressView(value: draft.progress)
                    .tint(TrailBoxColor.primary)

                ForEach(draft.checklist.indices, id: \.self) { index in
                    Button {
                        draft.checklist[index].isCompleted.toggle()
                        didSave = false
                        persistIfExisting()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: draft.checklist[index].isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(draft.checklist[index].isCompleted ? TrailBoxColor.primary : TrailBoxColor.secondaryText)
                                .frame(width: 26, height: 26)

                            Image(systemName: draft.checklist[index].systemImage)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(TrailBoxColor.primaryDark)
                                .frame(width: 30, height: 30)
                                .background(TrailBoxColor.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(draft.checklist[index].title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(TrailBoxColor.text)
                                    .strikethrough(draft.checklist[index].isCompleted, color: TrailBoxColor.secondaryText)
                                if let detail = draft.checklist[index].detail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(TrailBoxColor.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(draft.checklist[index].title)，\(draft.checklist[index].isCompleted ? "已完成" : "未完成")")

                    if index < (draft.checklist.indices.last ?? 0) {
                        Divider().padding(.leading, 68)
                    }
                }
            }
        }
    }

    private var sourceCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("计划依据", systemImage: "checkmark.seal")
                    .font(.subheadline.weight(.semibold))
                Text(draft.sourceSummary)
                    .font(.caption)
                    .foregroundStyle(TrailBoxColor.secondaryText)
                if let updatedAt = draft.weatherUpdatedAt {
                    Text("天气更新于 \(DeparturePlanFormat.updated(updatedAt))")
                        .font(.caption2)
                        .foregroundStyle(TrailBoxColor.secondaryText)
                }
                Text("出发计划是辅助建议，不能替代现场判断、官方预警和专业救援信息。")
                    .font(.caption2)
                    .foregroundStyle(TrailBoxColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let onOpenRoute {
                    Divider()
                    Button(action: onOpenRoute) {
                        Label("查看路线最新信息", systemImage: "map.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TrailBoxColor.primaryDark)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var riskColor: Color {
        switch draft.riskLevel {
        case .regular: return TrailBoxColor.primaryDark
        case .attention: return TrailBoxColor.warning
        case .high: return TrailBoxColor.danger
        }
    }

    private func heroMetric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.66))
        }
        .frame(maxWidth: .infinity)
    }

    private func scheduleMetric(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.caption2)
                .foregroundStyle(TrailBoxColor.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func intelligenceRow(_ image: String, _ text: String, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: image)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(TrailBoxColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func save() {
        departurePlans.upsert(draft)
        didSave = true
        if dismissOnSave { dismiss() }
    }

    private func persistIfExisting() {
        guard departurePlans.plan(id: draft.id) != nil else { return }
        departurePlans.upsert(draft)
        didSave = true
    }
}

struct DeparturePlansView: View {
    @EnvironmentObject private var departurePlans: DeparturePlanStore
    let onSelect: (UUID) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if departurePlans.plans.isEmpty {
                    EmptyStateView(
                        title: "还没有出发计划",
                        systemImage: "calendar.badge.plus",
                        message: "在公开路线详情中生成计划，系统会整理时间、天气和准备清单。"
                    )
                    .frame(minHeight: 420)
                } else {
                    ForEach(orderedPlans) { plan in
                        Button { onSelect(plan.id) } label: {
                            DeparturePlanCard(plan: plan)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("删除计划", role: .destructive) {
                                departurePlans.delete(id: plan.id)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(TrailPageBackground())
        .navigationTitle("出发计划")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var orderedPlans: [DeparturePlan] {
        let now = Date()
        let upcoming = departurePlans.plans
            .filter { ($0.expectedFinishEnd ?? $0.plannedStart) >= now }
            .sorted { $0.plannedStart < $1.plannedStart }
        let past = departurePlans.plans
            .filter { ($0.expectedFinishEnd ?? $0.plannedStart) < now }
            .sorted { $0.plannedStart > $1.plannedStart }
        return upcoming + past
    }
}

struct DeparturePlanCard: View {
    let plan: DeparturePlan

    var body: some View {
        SectionCard {
            HStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text(plan.plannedStart.formatted(.dateTime.month(.abbreviated)))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TrailBoxColor.primaryDark)
                    Text(plan.plannedStart.formatted(.dateTime.day()))
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(TrailBoxColor.text)
                    Text(plan.plannedStart.formatted(.dateTime.hour().minute()))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(TrailBoxColor.secondaryText)
                }
                .frame(width: 58, height: 72)
                .background(TrailBoxColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Text(plan.riskLevel.title)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(riskColor)
                        if plan.startsAfterSafeTime {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(TrailBoxColor.danger)
                        }
                    }
                    Text(plan.routeName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TrailBoxColor.text)
                        .lineLimit(2)
                    Text("\(DisplayFormat.distance(plan.distanceM)) · \(DisplayFormat.elevation(plan.elevationGainM))爬升")
                        .font(.caption)
                        .foregroundStyle(TrailBoxColor.secondaryText)
                    ProgressView(value: plan.progress)
                        .tint(TrailBoxColor.primary)
                }

                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(plan.completedItemCount)/\(plan.checklist.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TrailBoxColor.primaryDark)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TrailBoxColor.secondaryText)
                }
            }
        }
    }

    private var riskColor: Color {
        switch plan.riskLevel {
        case .regular: return TrailBoxColor.primaryDark
        case .attention: return TrailBoxColor.warning
        case .high: return TrailBoxColor.danger
        }
    }
}
