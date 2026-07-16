import SwiftUI

struct SharePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var telemetry: TelemetryConsentController
    @StateObject private var renderer = ShareCardRenderer()
    @State private var type: ShareCardType
    @State private var shareImage: ShareImage?
    @State private var message: String?
    let source: ShareSource
    let data: RouteShareData

    init(source: ShareSource, data: RouteShareData) {
        self.source = source
        self.data = data
        _type = State(initialValue: RouteShareData.defaultType(for: source))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                preview
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(TrailBoxColor.background)
            .navigationTitle(source == .activity ? "分享运动" : "分享路线")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("返回") { dismiss() } } }
            .task { renderer.render(type: activeType, data: data) }
            .sheet(item: $shareImage) { item in
                ShareSheet(image: item.image) { completed, error in
                    Task { @MainActor in
                        if let error {
                            telemetry.record(.share, phase: .failed, source: .shareSheet, failureCategory: TelemetryFailureCategory.classify(error))
                        } else {
                            telemetry.record(.share, phase: completed ? .succeeded : .cancelled, source: .shareSheet, failureCategory: completed ? nil : .cancelled)
                        }
                    }
                }
            }
            .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("确定", role: .cancel) {} } message: { Text(message ?? "") }
            .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        }
    }

    @ViewBuilder private var preview: some View {
        if source == .activity {
            cardPreview(.activityPure)
        } else {
            cardPreview(.routeQR)
        }
    }

    private var activeType: ShareCardType { source == .activity ? .activityPure : .routeQR }

    @ViewBuilder private func cardPreview(_ cardType: ShareCardType) -> some View {
        if let image = renderer.image(for: cardType) {
            Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 16)).shadow(color: .black.opacity(0.16), radius: 12, y: 6).padding(.horizontal, 2)
        } else if renderer.status == .failed && type == cardType {
            Button("重新生成") { renderer.render(type: cardType, data: data) }.buttonStyle(.borderedProminent)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(TrailBoxColor.border.opacity(0.65), lineWidth: 1)
                    }

                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                    Text("正在生成分享卡")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(TrailBoxColor.secondaryText)
                }
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 2)
        }
    }

    private var actions: some View {
        let isDisabled = renderer.image(for: activeType) == nil
        return FloatingActionBar {
            HStack(spacing: 12) {
                Button {
                    if let image = renderer.image(for: activeType) {
                        telemetry.record(.share, phase: .started, source: .shareSheet)
                        shareImage = ShareImage(image: image)
                    }
                } label: {
                    Label("分享", systemImage: "square.and.arrow.up")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .foregroundStyle(TrailBoxColor.text)
                .buttonStyle(.plain)
                .trailBoxGlass(interactive: !isDisabled, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .disabled(isDisabled)

                Button { save() } label: {
                    Label("保存图片", systemImage: "photo.on.rectangle")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .foregroundStyle(.white)
                .buttonStyle(.plain)
                .trailBoxGlass(
                    tint: isDisabled ? TrailBoxColor.secondaryText.opacity(0.45) : TrailBoxColor.primary,
                    interactive: !isDisabled,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .disabled(isDisabled)
            }
        }
    }

    private func save() {
        guard let image = renderer.image(for: activeType) else { return }
        telemetry.record(.share, phase: .started, source: .photoLibrary)
        ImageSaveService.save(image) { result in
            switch result {
            case .success:
                telemetry.record(.share, phase: .succeeded, source: .photoLibrary)
                message = "已保存到相册"
            case .failure:
                telemetry.record(.share, phase: .failed, source: .photoLibrary, failureCategory: .permission)
                message = "保存失败，请检查相册权限"
            }
        }
    }
}

private struct ShareImage: Identifiable { let image: UIImage; let id = UUID() }
