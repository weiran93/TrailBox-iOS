import SwiftUI

enum TrailBoxColor {
    static let primary = Color(red: 46 / 255, green: 139 / 255, blue: 78 / 255)
    static let primaryDark = Color(red: 18 / 255, green: 82 / 255, blue: 52 / 255)
    static let moss = Color(red: 102 / 255, green: 132 / 255, blue: 73 / 255)
    static let sand = Color(red: 239 / 255, green: 230 / 255, blue: 203 / 255)
    static let stone = Color(red: 105 / 255, green: 103 / 255, blue: 91 / 255)
    static let sky = Color(red: 67 / 255, green: 132 / 255, blue: 168 / 255)
    static let warning = Color(red: 196 / 255, green: 102 / 255, blue: 48 / 255)
    static let background = Color(red: 245 / 255, green: 242 / 255, blue: 230 / 255)
    static let surface = Color(red: 253 / 255, green: 252 / 255, blue: 247 / 255)
    static let surfaceMuted = Color(red: 237 / 255, green: 238 / 255, blue: 226 / 255)
    static let text = Color.primary
    static let secondaryText = Color.secondary
    static let border = primaryDark.opacity(0.14)
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
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(TrailBoxColor.border, lineWidth: 0.75))
            .shadow(color: TrailBoxColor.primaryDark.opacity(0.055), radius: 12, y: 5)
    }
}

struct TrailPageBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [TrailBoxColor.background, TrailBoxColor.sand.opacity(0.42), TrailBoxColor.background],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Canvas { context, size in
                for index in 0..<8 {
                    let baseY = size.height * CGFloat(0.08 + Double(index) * 0.135)
                    var contour = Path()
                    contour.move(to: CGPoint(x: -20, y: baseY))
                    stride(from: CGFloat(0), through: size.width + 24, by: 18).forEach { x in
                        let phase = Double(x / max(size.width, 1)) * .pi * 2.2 + Double(index) * 0.7
                        let y = baseY + CGFloat(sin(phase)) * CGFloat(7 + (index % 3) * 2)
                        contour.addLine(to: CGPoint(x: x, y: y))
                    }
                    context.stroke(contour, with: .color(TrailBoxColor.primaryDark.opacity(0.035)), lineWidth: 0.8)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
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
