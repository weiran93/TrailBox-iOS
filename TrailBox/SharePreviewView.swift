import SwiftUI

struct SharePreviewView: View {
    @Environment(\.dismiss) private var dismiss
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
                actions
            }
            .padding(16)
            .background(TrailBoxColor.background)
            .navigationTitle(source == .activity ? "分享运动" : "分享路线")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("返回") { dismiss() } } }
            .task { renderer.render(type: activeType, data: data) }
            .sheet(item: $shareImage) { ShareSheet(image: $0.image) }
            .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("确定", role: .cancel) {} } message: { Text(message ?? "") }
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
            ProgressView("正在生成分享卡").task { if renderer.image(for: cardType) == nil { renderer.render(type: cardType, data: data) } }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button { if let image = renderer.image(for: activeType) { shareImage = ShareImage(image: image) } } label: { Label("分享", systemImage: "square.and.arrow.up").font(.headline.weight(.bold)).frame(maxWidth: .infinity, minHeight: 62) }
                .foregroundStyle(TrailBoxColor.text).background(.white).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(TrailBoxColor.border)).disabled(renderer.image(for: activeType) == nil)
            Button { save() } label: { Label("保存图片", systemImage: "photo.on.rectangle").font(.headline.weight(.bold)).frame(maxWidth: .infinity, minHeight: 62) }
                .foregroundStyle(.white).background(TrailBoxColor.primary).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)).shadow(color: TrailBoxColor.primary.opacity(0.25), radius: 8, y: 4).disabled(renderer.image(for: activeType) == nil)
        }
    }

    private func save() {
        guard let image = renderer.image(for: activeType) else { return }
        ImageSaveService.save(image) { result in message = (try? result.get()) != nil ? "已保存到相册" : "保存失败，请检查相册权限" }
    }
}

private struct ShareImage: Identifiable { let image: UIImage; let id = UUID() }
