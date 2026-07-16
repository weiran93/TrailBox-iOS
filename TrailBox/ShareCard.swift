import CoreImage.CIFilterBuiltins
import MapKit
import Photos
import SwiftUI
import UIKit

enum ShareCardType: String, CaseIterable, Identifiable {
    case activityPure = "activity_pure"
    case activityLightBrand = "activity_light_brand"
    case routeQR = "route_qr"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .activityPure: "纯分享版"
        case .activityLightBrand: "轻引导版"
        case .routeQR: "路线码版"
        }
    }
}

enum ShareSource { case activity, exploreRoute }

struct RouteShareData {
    let routeID: String?
    let activityID: String?
    let title: String
    let locationText: String
    let startTime: Date?
    let distanceKm: Double
    let elevationGainM: Double?
    let elevationLossM: Double?
    let durationText: String?
    let maxElevationM: Double?
    let difficultyScore: Double?
    let difficultyLevel: String?
    let estimatedDurationMin: Int?
    let estimatedDurationMax: Int?
    let routeTypeText: String?
    let routeTagText: String?
    let sportText: String?
    let contributorText: String?
    let trackPoints: [TrackPoint]

    static func defaultType(for source: ShareSource) -> ShareCardType {
        source == .activity ? .activityPure : .routeQR
    }

    var calculatedMaxElevation: Double? {
        maxElevationM ?? trackPoints.compactMap(\.altitude).max().map { $0.rounded() }
    }

    var qrURL: URL? {
        guard let routeID, !routeID.isEmpty else { return nil }
        var components = URLComponents(string: "https://runfast.fun/r/\(routeID)")
        components?.queryItems = [
            URLQueryItem(name: "utm_source", value: "share_card"),
            URLQueryItem(name: "utm_medium", value: "wechat_qr"),
            URLQueryItem(name: "utm_campaign", value: "route_share")
        ]
        return components?.url
    }

    static func make(from track: Track, source: ShareSource, analysis: RouteAnalysis? = nil) -> RouteShareData {
        let duration: String?
        if let seconds = track.durationSec, seconds > 0 {
            duration = String(format: "%dh%02dm", Int(seconds) / 3600, (Int(seconds) % 3600) / 60)
        } else {
            duration = nil
        }
        let fallbackTitle = track.city.map { "\($0)越野跑" } ?? "一次向山而行"
        return RouteShareData(
            routeID: source == .exploreRoute ? track.id : nil,
            activityID: source == .activity ? track.id : nil,
            title: track.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackTitle : track.name,
            locationText: track.city?.isEmpty == false ? track.city! : "山野之间",
            startTime: track.startTime ?? track.createdAt,
            distanceKm: track.distanceM / 1_000,
            elevationGainM: track.elevationGainM > 0 ? track.elevationGainM : nil,
            elevationLossM: track.elevationLossM > 0 ? track.elevationLossM : nil,
            durationText: duration,
            maxElevationM: analysis?.highestElevationM,
            difficultyScore: analysis?.difficultyScore,
            difficultyLevel: analysis?.difficultyLevel,
            estimatedDurationMin: analysis?.estimatedDurationMin,
            estimatedDurationMax: analysis?.estimatedDurationMax,
            routeTypeText: analysis?.routeTypeDisplay,
            routeTagText: track.tagList.first,
            sportText: track.sport,
            contributorText: track.showContributor ? track.contributorName : nil,
            trackPoints: track.points
        )
    }
}

enum ShareRenderStatus { case idle, rendering, success, failed }

struct ShareCard: View {
    let type: ShareCardType
    let data: RouteShareData
    let mapImage: UIImage

    var body: some View {
        Group {
            if type == .activityPure { DarkShareCard(data: data, mapImage: mapImage) }
            else { LightShareCard(type: type, data: data, mapImage: mapImage) }
        }
        .frame(width: 1080, height: 1440)
        .clipped()
    }
}

private struct DarkShareCard: View {
    let data: RouteShareData
    let mapImage: UIImage

    var body: some View {
        ZStack {
            MapBackground(image: mapImage, isDark: true)
            LinearGradient(colors: [.clear, Color(red: 0.0, green: 0.12, blue: 0.08).opacity(0.82)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading) {
                ShareHeader(data: data, foreground: .white, secondary: .white.opacity(0.76), logoBackground: Color(red: 0.34, green: 0.70, blue: 0.20))
                Spacer()
                ShareMetrics(type: .activityPure, data: data, foreground: .white, secondary: .white.opacity(0.72), divider: .white.opacity(0.20))
                Divider().overlay(.white.opacity(0.24)).padding(.top, 44)
                BrandFooter(type: .activityPure, qrURL: data.qrURL, foreground: .white, secondary: .white.opacity(0.76))
                    .padding(.top, 26)
            }
            .padding(40)
        }
    }
}

private struct LightShareCard: View {
    let type: ShareCardType
    let data: RouteShareData
    let mapImage: UIImage

    var body: some View {
        ZStack {
            Color(red: 0.961, green: 0.957, blue: 0.933)
            VStack(alignment: .leading, spacing: 24) {
            ShareHeader(data: data, foreground: Color(red: 0.02, green: 0.18, blue: 0.12), secondary: Color(red: 0.08, green: 0.28, blue: 0.18), logoBackground: Color(red: 0.79, green: 0.84, blue: 0.75))
            ZStack(alignment: .bottom) {
                MapBackground(image: mapImage, isDark: false)
                LinearGradient(colors: [.clear, .white.opacity(0.22)], startPoint: .top, endPoint: .bottom)
                ShareMetrics(type: type, data: data, foreground: Color(red: 0.02, green: 0.18, blue: 0.12), secondary: TrailBoxColor.secondaryText, divider: TrailBoxColor.border)
                    .padding(.horizontal, 28).padding(.vertical, 28).background(.white.opacity(0.82)).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)).shadow(color: Color(red: 0.07, green: 0.23, blue: 0.18).opacity(0.05), radius: 16, y: 6).padding(18)
            }
            .frame(height: 520)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            Spacer(minLength: 0)
            BrandFooter(type: type, qrURL: data.qrURL, foreground: Color(red: 0.02, green: 0.18, blue: 0.12), secondary: TrailBoxColor.secondaryText)
                .padding(.top, 8)
            }
            .padding(40)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(TrailBoxColor.border.opacity(0.7)))
    }
}

private struct ShareHeader: View {
    let data: RouteShareData
    let foreground: Color
    let secondary: Color
    let logoBackground: Color

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text(data.title).font(.system(size: 56, weight: .heavy, design: .rounded)).foregroundStyle(foreground).lineLimit(2).minimumScaleFactor(0.75)
                Label(data.locationText, systemImage: "mappin.and.ellipse").font(.system(size: 27, weight: .semibold)).foregroundStyle(secondary)
                if let startTime = data.startTime { Text(startTime, format: .dateTime.month(.twoDigits).day(.twoDigits).hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits)).font(.system(size: 24, weight: .medium)).foregroundStyle(secondary) }
            }
            Spacer(minLength: 20)
            Image(systemName: "mountain.2.fill").font(.system(size: 42, weight: .bold)).foregroundStyle(.white).frame(width: 78, height: 78).background(logoBackground).clipShape(Circle())
        }
    }
}

private struct ShareMetrics: View {
    let type: ShareCardType
    let data: RouteShareData
    let foreground: Color
    let secondary: Color
    let divider: Color

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            metric("距离", String(format: "%.2f", data.distanceKm), "km")
            verticalDivider
            metric("累计爬升", data.elevationGainM.map { String(format: "%.0f", $0) } ?? "-", "m")
            if type == .routeQR {
                verticalDivider
                metric("累计下降", data.elevationLossM.map { String(format: "%.0f", $0) } ?? "-", "m")
            } else if type != .routeQR {
                verticalDivider
                metric("用时", data.durationText ?? "-", "")
            }
        }
    }

    private var verticalDivider: some View { Rectangle().fill(divider).frame(width: 1, height: 94).padding(.horizontal, 18) }

    private func metric(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 21, weight: .medium)).foregroundStyle(secondary)
            HStack(alignment: .lastTextBaseline, spacing: 4) { Text(value).font(.system(size: 39, weight: .heavy, design: .rounded)).foregroundStyle(foreground).minimumScaleFactor(0.65); if !unit.isEmpty { Text(unit).font(.system(size: 18, weight: .semibold)).foregroundStyle(secondary) } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BrandFooter: View {
    let type: ShareCardType
    let qrURL: URL?
    let foreground: Color
    let secondary: Color

    var body: some View {
        if type == .routeQR {
            HStack(alignment: .bottom, spacing: 18) {
                brandName
                Spacer()
                Text("微信识别查看路线").font(.system(size: 17, weight: .semibold)).foregroundStyle(secondary)
            }
        } else {
            HStack { brandName; Spacer(); Text(type == .activityLightBrand ? "完整路线见「小野box APP」" : "记录每一次向山而行").font(.system(size: 19, weight: .medium)).foregroundStyle(secondary) }
        }
    }

    private var brandName: some View { HStack(spacing: 10) { Image(systemName: "mountain.2.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(foreground).frame(width: 40, height: 40).background(foreground.opacity(0.10)).clipShape(Circle()); Text(type == .activityPure ? "小野box" : "「小野 BOX」APP").font(.system(size: 25, weight: .bold)).foregroundStyle(foreground) } }
}

private struct MapBackground: View {
    let image: UIImage
    let isDark: Bool
    var body: some View {
        Image(uiImage: image).resizable().scaledToFill().overlay(isDark ? Color(red: 0.0, green: 0.16, blue: 0.10).opacity(0.66) : Color.white.opacity(0.10))
    }
}

private enum RouteMapRenderer {
    static func image(for points: [TrackPoint], size: CGSize, dark: Bool) async throws -> UIImage {
        guard points.count > 1 else { return placeholder(size: size) }
        let coordinates = points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        let options = MKMapSnapshotter.Options()
        options.mapType = .mutedStandard
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false
        options.size = size
        options.scale = 1
        options.region = region(for: coordinates)
        let snapshot = try await snapshotter(options).start()
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            snapshot.image.draw(in: CGRect(origin: .zero, size: size))
            let path = UIBezierPath()
            path.move(to: snapshot.point(for: coordinates[0]))
            for coordinate in coordinates.dropFirst() { path.addLine(to: snapshot.point(for: coordinate)) }
            let accent = UIColor(red: 0.56, green: 0.86, blue: 0.39, alpha: 1)
            context.cgContext.setShadow(offset: .zero, blur: dark ? 10 : 4, color: accent.withAlphaComponent(dark ? 0.45 : 0.20).cgColor)
            accent.withAlphaComponent(dark ? 0.20 : 0.14).setStroke()
            path.lineWidth = dark ? 24 : 14; path.lineJoinStyle = .round; path.lineCapStyle = .round; path.stroke()
            context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor(red: 0.33, green: 0.76, blue: 0.10, alpha: 1).setStroke()
            path.lineWidth = dark ? 12 : 8; path.stroke()
            marker(at: snapshot.point(for: coordinates[0]), color: UIColor(red: 0.41, green: 0.73, blue: 0.14, alpha: 1))
            marker(at: snapshot.point(for: coordinates[coordinates.count - 1]), color: UIColor(red: 1.0, green: 0.63, blue: 0.12, alpha: 1))
        }
    }

    private static func snapshotter(_ options: MKMapSnapshotter.Options) -> MKMapSnapshotter { MKMapSnapshotter(options: options) }

    private static func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = coordinates.map(\.latitude), lons = coordinates.map(\.longitude)
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0, minLon = lons.min() ?? 0, maxLon = lons.max() ?? 0
        let latitudeDelta = max((maxLat - minLat) * 1.35, 0.012)
        let longitudeDelta = max((maxLon - minLon) * 1.35, 0.012)
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2), span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta))
    }

    private static func marker(at point: CGPoint, color: UIColor) {
        let outer = UIBezierPath(ovalIn: CGRect(x: point.x - 14, y: point.y - 14, width: 28, height: 28)); UIColor.white.setFill(); outer.fill()
        let inner = UIBezierPath(ovalIn: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18)); color.setFill(); inner.fill()
    }

    private static func placeholder(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in UIColor(red: 0.88, green: 0.92, blue: 0.84, alpha: 1).setFill(); context.fill(CGRect(origin: .zero, size: size)) }
    }
}

// Port of the PWA route-share canvas. These coordinates deliberately match the web
// implementation so exported iOS and PWA route cards share the same composition.
private enum PWAStyleRouteCardRenderer {
    static func render(data: RouteShareData, activityType: ShareCardType? = nil) async -> UIImage {
        if activityType == .activityLightBrand { return renderActivityLight(data: data) }
        if activityType == .activityPure { return renderActivityPure(data: data) }

        let mapSize = CGSize(width: 940, height: 558)
        let mapImage = try? await RouteMapRenderer.image(
            for: data.trackPoints,
            size: mapSize,
            dark: false
        )
        return renderRouteCard(data: data, mapImage: mapImage)
    }

    private static func renderRouteCard(data: RouteShareData, mapImage: UIImage?) -> UIImage {
        let size = CGSize(width: 1080, height: 1440)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let ctx = context.cgContext
            drawAmbientBackground(context: ctx, size: size)
            drawGlassSurface(
                CGRect(x: 42, y: 42, width: 996, height: 1356),
                radius: 68,
                fill: UIColor.white.withAlphaComponent(0.56),
                stroke: UIColor.white.withAlphaComponent(0.80),
                shadow: UIColor(hex: 0x1A372D).withAlphaComponent(0.18),
                shadowBlur: 44,
                shadowOffset: CGSize(width: 0, height: 24),
                context: ctx
            )

            drawBrandHeader(data: data, context: ctx)
            let longTitle = drawRouteTitle(data.title, context: ctx)
            drawRouteSubtitle(data: data, y: longTitle ? 318 : 304, context: ctx)
            drawDifficultySeal(data: data, context: ctx)

            let mapRect = CGRect(x: 70, y: 366, width: 940, height: 558)
            drawMap(mapImage, data: data, in: mapRect, context: ctx)
            drawStats(data: data, context: ctx)
            drawFooter(data: data, context: ctx)
        }
    }

    private static func drawAmbientBackground(context: CGContext, size: CGSize) {
        let base = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [UIColor(hex: 0xE8EEEA).cgColor, UIColor(hex: 0xDBE6E1).cgColor, UIColor(hex: 0xE8E3DC).cgColor] as CFArray,
            locations: [0, 0.52, 1]
        )!
        context.drawLinearGradient(base, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        drawRadialGlow(center: CGPoint(x: 130, y: 420), radius: 330, color: UIColor(hex: 0xDD6530).withAlphaComponent(0.38), context: context)
        drawRadialGlow(center: CGPoint(x: 970, y: 610), radius: 390, color: UIColor(hex: 0x287B6D).withAlphaComponent(0.46), context: context)
        drawRadialGlow(center: CGPoint(x: 500, y: 1400), radius: 410, color: UIColor(hex: 0x9EDBC8).withAlphaComponent(0.58), context: context)
        drawRadialGlow(center: CGPoint(x: 210, y: 120), radius: 290, color: UIColor(hex: 0xDCF5EE).withAlphaComponent(0.72), context: context)
        drawRadialGlow(center: CGPoint(x: 930, y: 80), radius: 280, color: UIColor(hex: 0xF7DEC7).withAlphaComponent(0.72), context: context)
    }

    private static func drawRadialGlow(center: CGPoint, radius: CGFloat, color: UIColor, context: CGContext) {
        let clear = color.withAlphaComponent(0)
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [color.cgColor, clear.cgColor] as CFArray,
            locations: [0, 1]
        ) else { return }
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: radius,
            options: [.drawsAfterEndLocation]
        )
    }

    private static func drawGlassSurface(
        _ rect: CGRect,
        radius: CGFloat,
        fill: UIColor,
        stroke: UIColor,
        shadow: UIColor,
        shadowBlur: CGFloat,
        shadowOffset: CGSize,
        context: CGContext
    ) {
        let path = rounded(rect, radius: radius)
        context.saveGState()
        context.setShadow(offset: shadowOffset, blur: shadowBlur, color: shadow.cgColor)
        fill.setFill()
        path.fill()
        context.restoreGState()
        stroke.setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    private static func drawBrandHeader(data: RouteShareData, context: CGContext) {
        drawAppIcon(in: CGRect(x: 84, y: 82, width: 54, height: 54), context: context)
        drawText("「小野 BOX」APP", in: CGRect(x: 153, y: 81, width: 360, height: 36), font: pingFang(26, weight: .semibold), color: UIColor(hex: 0x12251E), context: context)
        drawText("TRAILBOX", in: CGRect(x: 153, y: 118, width: 220, height: 20), font: avenir(12, weight: .semibold), color: UIColor(hex: 0x66756F), characterSpacing: 2, context: context)

        let year = data.startTime.map { Calendar.current.component(.year, from: $0) } ?? Calendar.current.component(.year, from: Date())
        let issue = "FIELD NOTE 001\n\(data.locationText.uppercased()) / \(year)"
        drawText(issue, in: CGRect(x: 650, y: 84, width: 344, height: 54), font: avenir(14, weight: .semibold), color: UIColor(hex: 0x65726C), alignment: .right, lineSpacing: 4, characterSpacing: 1.2, context: context)
    }

    @discardableResult
    private static func drawRouteTitle(_ title: String, context: CGContext) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let large = songti(112)
        let medium = songti(88)
        let largeWidth = (normalized as NSString).size(withAttributes: [.font: large]).width
        let mediumWidth = (normalized as NSString).size(withAttributes: [.font: medium]).width

        if normalized.count <= 4, largeWidth <= 760 {
            drawText(normalized, in: CGRect(x: 82, y: 166, width: 760, height: 128), font: large, color: UIColor(hex: 0x12251E), characterSpacing: -3, context: context)
            return false
        }
        if normalized.count <= 8, mediumWidth <= 760 {
            drawText(normalized, in: CGRect(x: 82, y: 176, width: 760, height: 108), font: medium, color: UIColor(hex: 0x12251E), characterSpacing: -2, context: context)
            return false
        }

        drawText(
            normalized,
            in: CGRect(x: 82, y: 160, width: 760, height: 140),
            font: songti(64),
            color: UIColor(hex: 0x12251E),
            lineBreakMode: .byTruncatingTail,
            lineSpacing: -2,
            characterSpacing: -1,
            context: context
        )
        return true
    }

    private static func drawRouteSubtitle(data: RouteShareData, y: CGFloat, context: CGContext) {
        var labels = [data.sportText?.isEmpty == false ? data.sportText! : "越野跑"]
        if let tag = data.routeTagText, !tag.isEmpty, !labels.contains(tag) { labels.append(tag) }
        if labels.count < 2 { labels.append("探索路线") }
        let routeType = data.routeTypeText?.isEmpty == false ? data.routeTypeText! : "路线"
        if !labels.contains(routeType) { labels.append(routeType) }

        var x: CGFloat = 88
        for (index, label) in labels.prefix(3).enumerated() {
            if index > 0 {
                UIColor(hex: 0xD85F32).setFill()
                UIBezierPath(ovalIn: CGRect(x: x, y: y + 10, width: 4, height: 4)).fill()
                x += 19
            }
            let font = pingFang(20, weight: .medium)
            let width = (label as NSString).size(withAttributes: [.font: font]).width
            drawText(label, in: CGRect(x: x, y: y, width: width + 4, height: 30), font: font, color: UIColor(hex: 0x51645C), context: context)
            x += width + 15
        }
    }

    private static func drawDifficultySeal(data: RouteShareData, context: CGContext) {
        let rect = CGRect(x: 882, y: 190, width: 112, height: 112)
        let path = rounded(rect, radius: 31)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 13), blur: 22, color: UIColor(hex: 0xB2411B).withAlphaComponent(0.25).cgColor)
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [UIColor(hex: 0xE16D3C).cgColor, UIColor(hex: 0xC94D27).cgColor] as CFArray,
            locations: [0, 1]
        )!
        path.addClip()
        context.drawLinearGradient(gradient, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
        context.restoreGState()
        UIColor.white.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 2
        path.stroke()

        let score = Int(resolvedDifficultyScore(data).rounded())
        let level = resolvedDifficultyLevel(data)
        drawText("难度", in: CGRect(x: rect.minX, y: 202, width: rect.width, height: 19), font: pingFang(13, weight: .semibold), color: UIColor(hex: 0xFFF8EF), alignment: .center, characterSpacing: 1.6, context: context)
        drawText("\(score)", in: CGRect(x: rect.minX, y: 220, width: rect.width, height: 49), font: din(41), color: UIColor(hex: 0xFFF8EF), alignment: .center, context: context)
        drawText(level, in: CGRect(x: rect.minX, y: 271, width: rect.width, height: 19), font: pingFang(13, weight: .semibold), color: UIColor(hex: 0xFFF8EF), alignment: .center, characterSpacing: 1.2, context: context)
    }

    private static func drawMap(_ mapImage: UIImage?, data: RouteShareData, in rect: CGRect, context: CGContext) {
        let path = rounded(rect, radius: 48)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 18), blur: 30, color: UIColor(hex: 0x143E32).withAlphaComponent(0.24).cgColor)
        UIColor(hex: 0x17493E).setFill()
        path.fill()
        context.restoreGState()

        context.saveGState()
        path.addClip()
        if let mapImage {
            mapImage.draw(in: rect)
        } else {
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor(hex: 0x2B7568).cgColor, UIColor(hex: 0x153E35).cgColor] as CFArray,
                locations: [0, 1]
            )!
            context.drawLinearGradient(gradient, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
        }
        UIColor(hex: 0x0D3B31).withAlphaComponent(0.16).setFill()
        context.fill(rect)
        let sheen = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [UIColor.white.withAlphaComponent(0.16).cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray,
            locations: [0, 1]
        )!
        context.drawLinearGradient(sheen, start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        context.restoreGState()
        UIColor.white.withAlphaComponent(0.72).setStroke()
        path.lineWidth = 2
        path.stroke()

        let first = data.trackPoints.first
        let coordinateText: String
        if let first {
            coordinateText = String(format: "%.4f° %@\n%.4f° %@", abs(first.lat), first.lat >= 0 ? "N" : "S", abs(first.lon), first.lon >= 0 ? "E" : "W")
        } else {
            coordinateText = data.locationText
        }
        drawMapLabel(coordinateText, in: CGRect(x: 92, y: 392, width: 174, height: 70), alignment: .left, context: context)

        let altitude = data.calculatedMaxElevation.map { NumberFormatter.localizedString(from: NSNumber(value: Int($0)), number: .decimal) } ?? "—"
        drawMapLabel("最高海拔\n\(altitude) M", in: CGRect(x: 822, y: 392, width: 166, height: 70), alignment: .right, context: context)

        if let contributor = data.contributorText, !contributor.isEmpty {
            drawText("路线贡献 · \(contributor)", in: CGRect(x: 590, y: 880, width: 396, height: 24), font: pingFang(14, weight: .medium), color: UIColor.white.withAlphaComponent(0.72), alignment: .right, characterSpacing: 1.0, context: context)
        }
    }

    private static func drawMapLabel(_ value: String, in rect: CGRect, alignment: NSTextAlignment, context: CGContext) {
        drawGlassSurface(rect, radius: 18, fill: UIColor.white.withAlphaComponent(0.16), stroke: UIColor.white.withAlphaComponent(0.34), shadow: .clear, shadowBlur: 0, shadowOffset: .zero, context: context)
        drawText(value, in: rect.insetBy(dx: 14, dy: 10), font: avenir(14, weight: .semibold), color: UIColor.white.withAlphaComponent(0.94), alignment: alignment, lineSpacing: 2, characterSpacing: 0.6, context: context)
    }

    private static func drawStats(data: RouteShareData, context: CGContext) {
        let rect = CGRect(x: 86, y: 946, width: 908, height: 178)
        drawGlassSurface(rect, radius: 30, fill: UIColor.white.withAlphaComponent(0.60), stroke: UIColor.white.withAlphaComponent(0.78), shadow: UIColor(hex: 0x12372B).withAlphaComponent(0.11), shadowBlur: 20, shadowOffset: CGSize(width: 0, height: 9), context: context)

        let firstDividerX: CGFloat = 446
        let secondDividerX: CGFloat = 702
        UIColor(hex: 0x123026).withAlphaComponent(0.13).setFill()
        context.fill(CGRect(x: firstDividerX, y: 975, width: 1, height: 120))
        context.fill(CGRect(x: secondDividerX, y: 975, width: 1, height: 120))

        let labelColor = UIColor(hex: 0x677770)
        let valueColor = UIColor(hex: 0x12251E)
        drawText("路线距离", in: CGRect(x: 116, y: 978, width: 240, height: 22), font: pingFang(14, weight: .medium), color: labelColor, characterSpacing: 0.5, context: context)
        drawText(String(format: "%.1f", data.distanceKm), in: CGRect(x: 116, y: 1008, width: 230, height: 76), font: din(68), color: valueColor, context: context)
        drawText("KM", in: CGRect(x: 322, y: 1051, width: 72, height: 28), font: avenir(19, weight: .semibold), color: UIColor(hex: 0xD65A30), characterSpacing: 0.8, context: context)

        drawText("累计爬升", in: CGRect(x: 476, y: 978, width: 190, height: 22), font: pingFang(14, weight: .medium), color: labelColor, characterSpacing: 0.5, context: context)
        let gain = data.elevationGainM.map { String(format: "%.0f", $0) } ?? "—"
        drawText(gain, in: CGRect(x: 476, y: 1012, width: 150, height: 45), font: din(35), color: valueColor, context: context)
        drawText("M", in: CGRect(x: 624, y: 1027, width: 34, height: 28), font: avenir(18, weight: .semibold), color: valueColor, context: context)
        let density = data.elevationGainM.map { data.distanceKm > 0 ? String(format: "爬升密度 %.1f m/km", $0 / data.distanceKm) : "爬升密度待计算" } ?? "爬升密度待计算"
        drawText(density, in: CGRect(x: 476, y: 1068, width: 210, height: 22), font: pingFang(14), color: UIColor(hex: 0x718079), context: context)

        drawText("预计用时", in: CGRect(x: 732, y: 978, width: 190, height: 22), font: pingFang(14, weight: .medium), color: labelColor, characterSpacing: 0.5, context: context)
        drawText(resolvedEstimatedHours(data), in: CGRect(x: 732, y: 1013, width: 185, height: 45), font: din(33), color: valueColor, context: context)
        drawText("H", in: CGRect(x: 922, y: 1027, width: 32, height: 28), font: avenir(18, weight: .semibold), color: valueColor, context: context)
        drawText("路线难度 · \(resolvedDifficultyLevel(data))", in: CGRect(x: 732, y: 1068, width: 220, height: 22), font: pingFang(14), color: UIColor(hex: 0x718079), context: context)
    }

    private static func drawFooter(data: RouteShareData, context: CGContext) {
        drawText("READY FOR THE TRAIL", in: CGRect(x: 86, y: 1190, width: 320, height: 24), font: avenir(13, weight: .semibold), color: UIColor(hex: 0xD35B32), characterSpacing: 1.7, context: context)
        drawText("看懂路线，\n再决定下一次出发。", in: CGRect(x: 86, y: 1220, width: 590, height: 108), font: songti(37), color: UIColor(hex: 0x12251E), lineSpacing: 4, characterSpacing: -0.4, context: context)

        var x: CGFloat = 86
        for label in ["困难路段", "天气", "沿途设施", "导航"] {
            let font = pingFang(15)
            let width = (label as NSString).size(withAttributes: [.font: font]).width
            drawText(label, in: CGRect(x: x, y: 1341, width: width + 2, height: 24), font: font, color: UIColor(hex: 0x64746D), context: context)
            x += width + 22
        }

        drawTransparentQR(data.qrURL, in: CGRect(x: 818, y: 1178, width: 176, height: 176), context: context)
        drawText("微信识别查看路线", in: CGRect(x: 780, y: 1344, width: 252, height: 22), font: pingFang(12), color: UIColor(hex: 0x4C6158), alignment: .center, characterSpacing: 0.25, context: context)
    }

    private static func resolvedDifficultyScore(_ data: RouteShareData) -> Double {
        if let score = data.difficultyScore { return min(max(score, 0), 100) }
        let climb = data.elevationGainM ?? 0
        return min(max(data.distanceKm * 1.8 + climb / 33, 10), 100)
    }

    private static func resolvedDifficultyLevel(_ data: RouteShareData) -> String {
        if let level = data.difficultyLevel, !level.isEmpty { return level }
        switch resolvedDifficultyScore(data) {
        case ..<35: return "简单"
        case ..<55: return "中等"
        case ..<75: return "困难"
        default: return "极难"
        }
    }

    private static func resolvedEstimatedHours(_ data: RouteShareData) -> String {
        if let minimum = data.estimatedDurationMin, let maximum = data.estimatedDurationMax {
            return String(format: "%.1f–%.1f", Double(minimum) / 60, Double(maximum) / 60)
        }
        let center = max(data.distanceKm / 5 + (data.elevationGainM ?? 0) / 600, 0.5)
        return String(format: "%.1f–%.1f", center * 0.82, center * 1.28)
    }

    private static func drawTransparentQR(_ url: URL?, in rect: CGRect, context: CGContext) {
        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data((url?.absoluteString ?? "https://runfast.fun").utf8)
        generator.correctionLevel = "M"
        guard let output = generator.outputImage else { return }
        let color = CIFilter.falseColor()
        color.inputImage = output
        color.color0 = CIColor(red: 16 / 255, green: 37 / 255, blue: 30 / 255, alpha: 1)
        color.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 0)
        guard let transparent = color.outputImage else { return }
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        guard let image = ciContext.createCGImage(transparent, from: output.extent) else { return }

        let moduleCount = output.extent.width
        let moduleSize = max(floor(rect.width / (moduleCount + 8)), 1)
        let contentSize = moduleCount * moduleSize
        let target = CGRect(x: rect.midX - contentSize / 2, y: rect.midY - contentSize / 2, width: contentSize, height: contentSize).integral
        context.saveGState()
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.draw(image, in: target)
        context.restoreGState()
    }

    private static func drawAppIcon(in rect: CGRect, context: CGContext) {
        let candidates = ["AppIcon", "AppIcon-180", "AppIcon60x60"]
        var icon = candidates.lazy.compactMap { UIImage(named: $0) }.first
        if icon == nil,
           let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           let name = files.last {
            icon = UIImage(named: name)
        }

        let path = rounded(rect, radius: 16)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 7), blur: 12, color: UIColor(hex: 0x18372C).withAlphaComponent(0.14).cgColor)
        UIColor(hex: 0xDCE9DF).setFill()
        path.fill()
        context.restoreGState()
        context.saveGState()
        path.addClip()
        if let icon {
            icon.draw(in: rect)
        } else {
            UIColor(hex: 0x2F6B52).setFill()
            context.fill(rect)
            UIImage(systemName: "mountain.2.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: rect.insetBy(dx: 10, dy: 13))
        }
        context.restoreGState()
        UIColor.white.withAlphaComponent(0.84).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private static func songti(_ size: CGFloat) -> UIFont {
        UIFont(name: "STSongti-SC-Light", size: size)
            ?? UIFont(name: "STSongti-SC-Regular", size: size)
            ?? UIFont(name: "Songti SC", size: size)
            ?? .systemFont(ofSize: size, weight: .light)
    }

    private static func pingFang(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let name: String
        switch weight {
        case .semibold, .bold, .heavy, .black: name = "PingFangSC-Semibold"
        case .medium: name = "PingFangSC-Medium"
        case .light, .thin, .ultraLight: name = "PingFangSC-Light"
        default: name = "PingFangSC-Regular"
        }
        return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    private static func din(_ size: CGFloat) -> UIFont {
        UIFont(name: "DINAlternate-Bold", size: size)
            ?? UIFont(name: "AvenirNextCondensed-Bold", size: size)
            ?? .monospacedDigitSystemFont(ofSize: size, weight: .bold)
    }

    private static func avenir(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "AvenirNext-Bold"
        case .semibold: name = "AvenirNext-DemiBold"
        case .medium: name = "AvenirNext-Medium"
        default: name = "AvenirNext-Regular"
        }
        return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    private static func drawText(
        _ value: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left,
        lineBreakMode: NSLineBreakMode = .byWordWrapping,
        lineSpacing: CGFloat = 0,
        characterSpacing: CGFloat = 0,
        context: CGContext
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = lineBreakMode
        style.lineSpacing = lineSpacing
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
            .kern: characterSpacing
        ]
        (value as NSString).draw(in: rect, withAttributes: attributes)
    }

    private static func renderActivityPure(data: RouteShareData) -> UIImage {
        let size = CGSize(width: 1080, height: 1440); let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let ctx = context.cgContext
            drawRoute(data.trackPoints, in: CGRect(origin: .zero, size: size), context: ctx, dark: true)
            let shade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [UIColor.black.withAlphaComponent(0).cgColor, UIColor.black.withAlphaComponent(0.12).cgColor, UIColor.black.withAlphaComponent(0.58).cgColor] as CFArray, locations: [0, 0.50, 1])!
            ctx.drawLinearGradient(shade, start: .zero, end: CGPoint(x: 0, y: 1440), options: [])
            text(fit(data.title, maxWidth: 760, font: .systemFont(ofSize: 58, weight: .heavy)), at: CGPoint(x: 40, y: 64), font: .systemFont(ofSize: 58, weight: .heavy), color: .white, context: ctx)
            text("●  \(data.locationText)", at: CGPoint(x: 40, y: 146), font: .systemFont(ofSize: 25, weight: .semibold), color: UIColor.white.withAlphaComponent(0.90), context: ctx)
            if let date = data.startTime { text(date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits)), at: CGPoint(x: 40, y: 188), font: .systemFont(ofSize: 22, weight: .medium), color: UIColor.white.withAlphaComponent(0.82), context: ctx) }
            UIColor(hex: 0x8EDB63).withAlphaComponent(0.30).setFill(); UIBezierPath(ovalIn: CGRect(x: 950, y: 54, width: 64, height: 64)).fill()
            drawMetrics([("距离", String(format: "%.2f", data.distanceKm), "km"), ("累计爬升", data.elevationGainM.map { String(format: "%.0f", $0) } ?? "-", "m"), ("用时", data.durationText ?? "-", "")], y: 1085, dark: true, context: ctx)
            ctx.setFillColor(UIColor.white.withAlphaComponent(0.20).cgColor); ctx.fill(CGRect(x: 40, y: 1264, width: 1000, height: 1))
            text("●  小野box", at: CGPoint(x: 40, y: 1302), font: .systemFont(ofSize: 28, weight: .bold), color: .white, context: ctx)
            text("记录每一次向山而行", at: CGPoint(x: 1040, y: 1306), font: .systemFont(ofSize: 20, weight: .semibold), color: UIColor.white.withAlphaComponent(0.88), context: ctx, alignment: .right)
        }
    }

    private static func renderActivityLight(data: RouteShareData) -> UIImage {
        let size = CGSize(width: 1080, height: 1440); let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let ctx = context.cgContext; ctx.setFillColor(UIColor(hex: 0xF5F4EE).cgColor); ctx.fill(CGRect(origin: .zero, size: size))
            text(fit(data.title, maxWidth: 800, font: .systemFont(ofSize: 54, weight: .heavy)), at: CGPoint(x: 40, y: 52), font: .systemFont(ofSize: 54, weight: .heavy), color: UIColor(hex: 0x123B2F), context: ctx)
            text("●  \(data.locationText)", at: CGPoint(x: 40, y: 132), font: .systemFont(ofSize: 22, weight: .semibold), color: UIColor(hex: 0x123B2F), context: ctx)
            if let date = data.startTime { text(date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits)), at: CGPoint(x: 40, y: 166), font: .systemFont(ofSize: 21, weight: .medium), color: UIColor(hex: 0x5F7568), context: ctx) }
            UIColor(hex: 0x123B2F).withAlphaComponent(0.12).setFill(); UIBezierPath(ovalIn: CGRect(x: 950, y: 52, width: 58, height: 58)).fill()
            drawRoute(data.trackPoints, in: CGRect(x: 40, y: 240, width: 1000, height: 520), context: ctx, dark: false)
            UIColor.white.withAlphaComponent(0.88).setFill(); rounded(CGRect(x: 58, y: 790, width: 964, height: 180), radius: 24).fill()
            drawMetrics([("距离", String(format: "%.2f", data.distanceKm), "km"), ("累计爬升", data.elevationGainM.map { String(format: "%.0f", $0) } ?? "-", "m"), ("用时", data.durationText ?? "-", "")], y: 830, dark: false, context: ctx)
            text("●  小野box APP", at: CGPoint(x: 40, y: 1190), font: .systemFont(ofSize: 28, weight: .bold), color: UIColor(hex: 0x123B2F), context: ctx)
            text("完整路线见「小野box APP」", at: CGPoint(x: 1040, y: 1194), font: .systemFont(ofSize: 20, weight: .semibold), color: UIColor(hex: 0x385746), context: ctx, alignment: .right)
            ctx.setStrokeColor(UIColor(hex: 0xD8DDD2).cgColor); ctx.stroke(CGRect(x: 0.5, y: 0.5, width: 1079, height: 1439))
        }
    }

    private static func drawMetrics(_ values: [(String, String, String)], y: CGFloat, dark: Bool, context: CGContext) {
        for (index, value) in values.enumerated() {
            let x = CGFloat(40 + index * 340)
            if index > 0 { context.setFillColor((dark ? UIColor.white.withAlphaComponent(0.18) : UIColor(hex: 0xD8DDD2)).cgColor); context.fill(CGRect(x: x - 28, y: y, width: 1, height: 96)) }
            let labelColor = dark ? UIColor.white.withAlphaComponent(0.82) : UIColor(hex: 0x5F7568); let numberColor = dark ? UIColor.white : UIColor(hex: 0x123B2F)
            text(value.0, at: CGPoint(x: x, y: y), font: .systemFont(ofSize: 20, weight: .semibold), color: labelColor, context: context)
            text(value.1, at: CGPoint(x: x, y: y + 34), font: .systemFont(ofSize: 42, weight: .heavy), color: numberColor, context: context)
            if !value.2.isEmpty { text(value.2, at: CGPoint(x: x, y: y + 84), font: .systemFont(ofSize: 18, weight: .bold), color: labelColor, context: context) }
        }
    }

    private static func drawRoute(_ points: [TrackPoint], in rect: CGRect, context: CGContext, dark: Bool = true, pwaRouteStyle: Bool = false) {
        let colors = dark ? [UIColor(hex: 0x1D3C39).cgColor, UIColor(hex: 0x102722).cgColor] : [UIColor(hex: 0xEEF4E4).cgColor, UIColor(hex: 0xE1EBD6).cgColor]
        let background = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
        context.saveGState(); rounded(rect, radius: 36).addClip(); context.drawLinearGradient(background, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
        context.setStrokeColor((dark ? UIColor(red: 190/255, green: 222/255, blue: 190/255, alpha: 0.12) : UIColor(hex: 0x123B2F).withAlphaComponent(0.12)).cgColor); context.setLineWidth(2)
        for i in 0..<9 {
            let lineY = rect.minY + 20 + CGFloat(i * 42)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.minX - 30, y: lineY + (i.isMultiple(of: 2) ? -10 : 14)))
            path.addCurve(to: CGPoint(x: rect.minX + rect.width * 0.62, y: lineY - 10), controlPoint1: CGPoint(x: rect.minX + rect.width * 0.2, y: lineY - 30), controlPoint2: CGPoint(x: rect.minX + rect.width * 0.42, y: lineY + 38))
            path.addCurve(to: CGPoint(x: rect.maxX + 35, y: lineY - 6), controlPoint1: CGPoint(x: rect.minX + rect.width * 0.82, y: lineY - 45), controlPoint2: CGPoint(x: rect.maxX + 10, y: lineY + 24))
            path.stroke()
        }
        guard points.count > 1 else { context.restoreGState(); return }
        let lats = points.map(\.lat), lons = points.map(\.lon); guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else { context.restoreGState(); return }
        let scale = min((rect.width - 124) / max(maxLon - minLon, 0.001), (rect.height - 124) / max(maxLat - minLat, 0.001)); let centerLat = (minLat + maxLat) / 2; let centerLon = (minLon + maxLon) / 2
        func project(_ point: TrackPoint) -> CGPoint { CGPoint(x: rect.midX + (point.lon - centerLon) * scale, y: rect.midY - (point.lat - centerLat) * scale) }
        let path = UIBezierPath(); path.move(to: project(points[0])); for point in points.dropFirst() { path.addLine(to: project(point)) }; path.lineCapStyle = .round; path.lineJoinStyle = .round
        if pwaRouteStyle {
            UIColor.black.withAlphaComponent(0.30).setStroke(); path.lineWidth = 18; path.stroke()
            UIColor(hex: 0xA8EB77).setStroke(); path.lineWidth = 9; path.stroke()
        } else {
            context.setShadow(offset: .zero, blur: dark ? 10 : 4, color: UIColor(hex: 0xA8EB77).withAlphaComponent(dark ? 0.35 : 0.20).cgColor)
            UIColor(hex: 0xA8EB77).withAlphaComponent(dark ? 0.20 : 0.14).setStroke(); path.lineWidth = dark ? 18 : 14; path.stroke()
            context.setShadow(offset: .zero, blur: 0, color: nil); UIColor(hex: 0xA8EB77).setStroke(); path.lineWidth = dark ? 9 : 8; path.stroke()
        }
        marker(project(points[0]), color: UIColor(hex: 0x91DF62)); marker(project(points[points.count - 1]), color: UIColor(hex: 0xF5B562)); context.restoreGState()
    }

    private static func marker(_ point: CGPoint, color: UIColor) { UIColor(hex: 0xF5F8ED).setFill(); UIBezierPath(ovalIn: CGRect(x: point.x - 16, y: point.y - 16, width: 32, height: 32)).fill(); color.setFill(); UIBezierPath(ovalIn: CGRect(x: point.x - 11, y: point.y - 11, width: 22, height: 22)).fill() }
    private static func drawQR(_ url: URL?, in rect: CGRect, context: CGContext) { UIColor.white.setFill(); rounded(rect, radius: 18).fill(); let filter = CIFilter.qrCodeGenerator(); filter.message = Data((url?.absoluteString ?? "https://runfast.fun").utf8); filter.correctionLevel = "M"; let ci = CIContext(); if let output = filter.outputImage, let image = ci.createCGImage(output, from: output.extent) { context.interpolationQuality = .none; context.draw(image, in: rect.insetBy(dx: 12, dy: 12)) } }
    private static func text(_ value: String, at point: CGPoint, font: UIFont, color: UIColor, context: CGContext, alignment: NSTextAlignment = .left) { let style = NSMutableParagraphStyle(); style.alignment = alignment; (value as NSString).draw(in: CGRect(x: point.x + (alignment == .right ? -936 : alignment == .center ? -180 : 0), y: point.y, width: alignment == .left ? 936 : alignment == .center ? 360 : 936, height: 80), withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style]) }
    private static func fit(_ value: String, maxWidth: CGFloat, font: UIFont) -> String { guard (value as NSString).size(withAttributes: [.font: font]).width > maxWidth else { return value }; var text = value; while text.count > 1 && ((text + "…") as NSString).size(withAttributes: [.font: font]).width > maxWidth { text.removeLast() }; return text + "…" }
    private static func rounded(_ rect: CGRect, radius: CGFloat) -> UIBezierPath { UIBezierPath(roundedRect: rect, cornerRadius: radius) }
}

private extension UIColor { convenience init(hex: UInt32) { self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1) } }

private struct QRCodeView: View {
    let url: URL?
    private let context = CIContext()
    var body: some View {
        Group {
            if let image { Image(uiImage: image).interpolation(.none).resizable() }
            else { Image(systemName: "qrcode").resizable().padding(10) }
        }
    }
    private var image: UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data((url?.absoluteString ?? "https://runfast.fun").utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)), let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

@MainActor
final class ShareCardRenderer: ObservableObject {
    @Published private(set) var status: ShareRenderStatus = .idle
    @Published private(set) var image: UIImage?
    @Published private(set) var images: [ShareCardType: UIImage] = [:]
    private var renderIDs: [ShareCardType: UUID] = [:]

    func render(type: ShareCardType, data: RouteShareData) {
        let requestID = UUID()
        renderIDs[type] = requestID
        status = .rendering
        image = nil
        Task {
            let rendered = await Task.detached(priority: .userInitiated) {
                await PWAStyleRouteCardRenderer.render(data: data, activityType: type == .routeQR ? nil : type)
            }.value
            guard renderIDs[type] == requestID else { return }
            images[type] = rendered
            image = rendered
            status = .success
        }
    }

    func image(for type: ShareCardType) -> UIImage? { images[type] }
}

enum ImageSaveService {
    static func save(_ image: UIImage, completion: @escaping (Result<Void, Error>) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(.failure(ImageSaveError.noPermission)) }
                return
            }
            PHPhotoLibrary.shared().performChanges({ PHAssetChangeRequest.creationRequestForAsset(from: image) }) { success, error in
                DispatchQueue.main.async { success ? completion(.success(())) : completion(.failure(error ?? ImageSaveError.writeFailed)) }
            }
        }
    }
}

enum ImageSaveError: Error { case noPermission, writeFailed }

struct ShareSheet: UIViewControllerRepresentable {
    let image: UIImage
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [image], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
