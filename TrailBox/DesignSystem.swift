import SwiftUI

enum TrailBoxColor {
    static let primary = Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)
    static let primaryDark = Color(red: 22 / 255, green: 163 / 255, blue: 74 / 255)
    static let background = Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255)
    static let text = Color(red: 31 / 255, green: 41 / 255, blue: 55 / 255)
    static let secondaryText = Color(red: 107 / 255, green: 114 / 255, blue: 128 / 255)
    static let border = Color(red: 229 / 255, green: 231 / 255, blue: 235 / 255)
    static let danger = Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255)
}

struct SectionCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(TrailBoxColor.border, lineWidth: 1))
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

    static func date(_ value: Date?) -> String {
        guard let value else { return "" }
        return value.formatted(.dateTime.year().month().day())
    }
}
