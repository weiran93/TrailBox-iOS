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
    let trackPoints: [TrackPoint]

    static func defaultType(for source: ShareSource) -> ShareCardType {
        source == .activity ? .activityPure : .routeQR
    }

    var calculatedMaxElevation: Double? {
        maxElevationM ?? trackPoints.compactMap(\.altitude).max().map { $0.rounded() }
    }

    var qrURL: URL? {
        guard let routeID, !routeID.isEmpty else { return nil }
        var components = URLComponents(string: "https://xiaoyebox.com/r/\(routeID)")
        components?.queryItems = [
            URLQueryItem(name: "utm_source", value: "share_card"),
            URLQueryItem(name: "utm_medium", value: "wechat_qr"),
            URLQueryItem(name: "utm_campaign", value: "route_share")
        ]
        return components?.url
    }

    static func make(from track: Track, source: ShareSource) -> RouteShareData {
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
            maxElevationM: nil,
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
                QRCodeView(url: qrURL).frame(width: 112, height: 112).background(.white).padding(7).overlay(RoundedRectangle(cornerRadius: 8).stroke(TrailBoxColor.border)).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 6) { Text("微信扫码查看路线").font(.system(size: 17, weight: .semibold)).foregroundStyle(foreground); Text("来自小野box APP").font(.system(size: 15)).foregroundStyle(secondary) }
            }
        } else {
            HStack { brandName; Spacer(); Text(type == .activityLightBrand ? "完整路线见「小野box APP」" : "记录每一次向山而行").font(.system(size: 19, weight: .medium)).foregroundStyle(secondary) }
        }
    }

    private var brandName: some View { HStack(spacing: 10) { Image(systemName: "mountain.2.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(foreground).frame(width: 40, height: 40).background(foreground.opacity(0.10)).clipShape(Circle()); Text(type == .activityPure ? "小野box" : "小野box APP").font(.system(size: 25, weight: .bold)).foregroundStyle(foreground) } }
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
    static func render(data: RouteShareData, activityType: ShareCardType? = nil) -> UIImage {
        if activityType == .activityLightBrand { return renderActivityLight(data: data) }
        let size = CGSize(width: 1080, height: 1440)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let ctx = context.cgContext
            let background = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [UIColor(hex: 0xF6F5ED).cgColor, UIColor(hex: 0xE8EEE5).cgColor] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(background, start: .zero, end: CGPoint(x: 1080, y: 1440), options: [])

            text("小野BOX  ·  TRAIL NOTE", at: CGPoint(x: 72, y: 62), font: .systemFont(ofSize: 28, weight: .bold), color: UIColor(hex: 0x1B332A), context: ctx)
            if let date = data.startTime { text(date.formatted(.dateTime.year().month().day()), at: CGPoint(x: 1008, y: 62), font: .systemFont(ofSize: 25, weight: .medium), color: UIColor(hex: 0x6C7C70), context: ctx, alignment: .right) }
            text(fit(data.title, maxWidth: 936, font: .systemFont(ofSize: 61, weight: .bold)), at: CGPoint(x: 72, y: 130), font: .systemFont(ofSize: 61, weight: .bold), color: UIColor(hex: 0x102D23), context: ctx)
            let isActivity = activityType != nil
            text(fit("\(data.locationText)  ·  \(isActivity ? "运动记录" : "探索路线")", maxWidth: 936, font: .systemFont(ofSize: 28, weight: .semibold)), at: CGPoint(x: 72, y: 198), font: .systemFont(ofSize: 28, weight: .semibold), color: UIColor(hex: 0x51715F), context: ctx)

            drawRoute(data.trackPoints, in: CGRect(x: 72, y: 280, width: 936, height: 530), context: ctx, pwaRouteStyle: true)

            let metrics = isActivity
                ? [("距离", String(format: "%.2f km", data.distanceKm)), ("累计爬升", data.elevationGainM.map { String(format: "%.0f m", $0) } ?? "-"), ("用时", data.durationText ?? "-")]
                : [("距离", String(format: "%.2f km", data.distanceKm)), ("累计爬升", data.elevationGainM.map { String(format: "%.0f m", $0) } ?? "-"), ("累计下降", data.elevationLossM.map { String(format: "%.0f m", $0) } ?? "-")]
            for (index, metric) in metrics.enumerated() {
                let x = CGFloat(72 + index * 312)
                if index > 0 { ctx.setFillColor(UIColor(hex: 0xCAD4CA).cgColor); ctx.fill(CGRect(x: x - 24, y: 868, width: 1, height: 136)) }
                text(metric.0, at: CGPoint(x: x, y: 868), font: .systemFont(ofSize: 25, weight: .semibold), color: UIColor(hex: 0x66796B), context: ctx)
                text(fit(metric.1, maxWidth: 280, font: .systemFont(ofSize: 48, weight: .bold)), at: CGPoint(x: x, y: 920), font: .systemFont(ofSize: 48, weight: .bold), color: UIColor(hex: 0x14362A), context: ctx)
            }

            ctx.setFillColor(UIColor(hex: 0xC4D1C6).cgColor); ctx.fill(CGRect(x: 72, y: 1074, width: 936, height: 1))
            if !isActivity {
                text("把每一段山野，收藏成下一次出发的理由。", at: CGPoint(x: 72, y: 1110), font: .systemFont(ofSize: 29, weight: .semibold), color: UIColor(hex: 0x385746), context: ctx)
                drawQR(data.qrURL, in: CGRect(x: 796, y: 1100, width: 184, height: 184), context: ctx)
                text("微信扫码查看路线", at: CGPoint(x: 888, y: 1300), font: .systemFont(ofSize: 22, weight: .semibold), color: UIColor(hex: 0x587164), context: ctx, alignment: .center)
                UIColor(hex: 0x173A2D).setFill(); rounded(CGRect(x: 72, y: 1328, width: 936, height: 64), radius: 20).fill()
                text("TRAILBOX", at: CGPoint(x: 102, y: 1344), font: .systemFont(ofSize: 25, weight: .bold), color: UIColor(hex: 0xD9F3C0), context: ctx)
                text("记录每一次向山而行", at: CGPoint(x: 978, y: 1344), font: .systemFont(ofSize: 23, weight: .medium), color: UIColor(hex: 0xF1F5E9), context: ctx, alignment: .right)
            } else {
                UIColor(hex: 0x173A2D).setFill(); rounded(CGRect(x: 72, y: 1114, width: 936, height: 218), radius: 28).fill()
                text("●  小野box", at: CGPoint(x: 116, y: 1172), font: .systemFont(ofSize: 36, weight: .bold), color: .white, context: ctx)
                text("记录每一次向山而行", at: CGPoint(x: 964, y: 1178), font: .systemFont(ofSize: 25, weight: .semibold), color: UIColor(hex: 0xD9F3C0), context: ctx, alignment: .right)
                text("把每一次出发，都留在山野之间。", at: CGPoint(x: 116, y: 1236), font: .systemFont(ofSize: 23, weight: .medium), color: UIColor.white.withAlphaComponent(0.72), context: ctx)
            }
        }
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
    private static func drawQR(_ url: URL?, in rect: CGRect, context: CGContext) { UIColor.white.setFill(); rounded(rect, radius: 18).fill(); let filter = CIFilter.qrCodeGenerator(); filter.message = Data((url?.absoluteString ?? "https://xiaoyebox.com").utf8); filter.correctionLevel = "M"; let ci = CIContext(); if let output = filter.outputImage, let image = ci.createCGImage(output, from: output.extent) { context.interpolationQuality = .none; context.draw(image, in: rect.insetBy(dx: 12, dy: 12)) } }
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
        filter.message = Data((url?.absoluteString ?? "https://xiaoyebox.com").utf8)
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
            let rendered = PWAStyleRouteCardRenderer.render(data: data, activityType: type == .routeQR ? nil : type)
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
