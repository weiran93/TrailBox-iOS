import SwiftUI

struct RouteFeedbackView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    let trackID: String
    let didSubmit: () async -> Void

    @State private var difficulty = 3
    @State private var scenery = 4
    @State private var navigation = 3
    @State private var supply = 3
    @State private var signal = 3
    @State private var isRecommended = true
    @State private var comment = ""
    @State private var conditionType = "none"
    @State private var conditionDescription = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("路线体验") {
                    ratingRow("体感难度", value: $difficulty)
                    ratingRow("风景", value: $scenery)
                    ratingRow("导航清晰度", value: $navigation)
                    ratingRow("补给便利度", value: $supply)
                    ratingRow("手机信号", value: $signal)
                    Toggle("推荐这条路线", isOn: $isRecommended)
                }

                Section("体验补充") {
                    TextField("分享路线亮点、难点或注意事项", text: $comment, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("近期路况（选填）") {
                    Picker("路况类型", selection: $conditionType) {
                        Text("没有需要提醒的情况").tag("none")
                        Text("临时封路").tag("closure")
                        Text("施工").tag("construction")
                        Text("积雪").tag("snow")
                        Text("泥泞").tag("mud")
                        Text("补给变化").tag("supply")
                        Text("信号情况").tag("signal")
                    }
                    if conditionType != "none" {
                        TextField("描述具体位置和情况", text: $conditionDescription, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }
            }
            .navigationTitle("路线反馈")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "提交中…" : "提交") { submit() }
                        .disabled(isSaving)
                }
            }
            .alert("提交失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func ratingRow(_ title: String, value: Binding<Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { score in
                    Button {
                        value.wrappedValue = score
                    } label: {
                        Image(systemName: score <= value.wrappedValue ? "star.fill" : "star")
                            .foregroundStyle(score <= value.wrappedValue ? .yellow : TrailBoxColor.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func submit() {
        guard let token = session.token else { return }
        isSaving = true
        Task {
            do {
                let reviewInput = RouteReviewInput(
                    difficultyRating: difficulty,
                    sceneryRating: scenery,
                    navigationRating: navigation,
                    supplyRating: supply,
                    signalRating: signal,
                    isRecommended: isRecommended,
                    comment: comment.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                )
                let _: RouteReview = try await APIClient.shared.request(
                    "/tracks/\(trackID)/reviews",
                    method: "POST",
                    body: reviewInput,
                    token: token
                )
                if conditionType != "none" {
                    let conditionInput = RouteConditionInput(
                        conditionType: conditionType,
                        severity: ["closure", "construction", "snow"].contains(conditionType) ? "warning" : "info",
                        description: conditionDescription.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    )
                    let _: RouteCondition = try await APIClient.shared.request(
                        "/tracks/\(trackID)/conditions",
                        method: "POST",
                        body: conditionInput,
                        token: token
                    )
                }
                await didSubmit()
                dismiss()
            } catch {
                errorMessage = ErrorMessage.display(error)
            }
            isSaving = false
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
