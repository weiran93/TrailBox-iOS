import SwiftUI

enum TrailBoxColor {
    static let primary = Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)
    static let primaryDark = Color(red: 22 / 255, green: 163 / 255, blue: 74 / 255)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let text = Color.primary
    static let secondaryText = Color.secondary
    static let border = Color(uiColor: .separator)
    static let danger = Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255)
}

extension View {
    /// Uses native Liquid Glass on iOS 26 and a material fallback on older systems.
    @ViewBuilder
    func trailBoxGlass<S: Shape>(
        tint: Color? = nil,
        interactive: Bool = true,
        in shape: S
    ) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.55), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
        }
    }

    /// Lets the native iOS 26 tab bar minimize while scrolling down.
    @ViewBuilder
    func trailBoxTabBarMinimizeOnScroll() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}

struct SectionCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TrailBoxColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(TrailBoxColor.border.opacity(0.55), lineWidth: 0.5))
    }
}

struct FloatingActionBar<Content: View>: View {
    let bottomPadding: CGFloat
    @ViewBuilder var content: Content

    init(bottomPadding: CGFloat = 10, @ViewBuilder content: () -> Content) {
        self.bottomPadding = bottomPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, bottomPadding)
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.system(size: 34)).foregroundStyle(TrailBoxColor.secondaryText)
            Text(title).font(.headline).foregroundStyle(TrailBoxColor.text)
            Text(message).font(.subheadline).foregroundStyle(TrailBoxColor.secondaryText).multilineTextAlignment(.center)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum DisplayFormat {
    static func distance(_ meters: Double) -> String {
        meters >= 1_000 ? String(format: "%.2f km", meters / 1_000) : String(format: "%.0f m", meters)
    }

    static func elevation(_ meters: Double) -> String { String(format: "%.0f m", meters) }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, total % 60)
        } else {
            return String(format: "%d:%02d", minutes, total % 60)
        }
    }

    static func date(_ value: Date?) -> String {
        guard let value else { return "" }
        return value.formatted(.dateTime.year().month().day())
    }
}
