import SwiftUI

@main
struct TrailBoxApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = SessionStore()
    @StateObject private var deepLinkRouter = DeepLinkRouter()
    @StateObject private var savedRoutes = SavedRoutesStore()
    @StateObject private var departurePlans = DeparturePlanStore()
    @StateObject private var telemetry = TelemetryConsentController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(deepLinkRouter)
                .environmentObject(savedRoutes)
                .environmentObject(departurePlans)
                .environmentObject(telemetry)
                .tint(TrailBoxColor.primary)
                .preferredColorScheme(.light)
                .task(id: session.user?.id) {
                    departurePlans.activate(userID: session.user?.id)
                }
                .onOpenURL { deepLinkRouter.handle($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { deepLinkRouter.handle(url) }
                }
                .onChange(of: scenePhase) { phase in
                    guard phase == .active else { return }
                    Task { await TelemetryManager.shared.flush() }
                }
        }
    }
}
