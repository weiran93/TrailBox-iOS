import SwiftUI

@main
struct TrailBoxApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var deepLinkRouter = DeepLinkRouter()
    @StateObject private var savedRoutes = SavedRoutesStore()
    @StateObject private var recentRoutes = RecentRoutesStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(deepLinkRouter)
                .environmentObject(savedRoutes)
                .environmentObject(recentRoutes)
                .tint(TrailBoxColor.primary)
                .preferredColorScheme(.light)
                .onOpenURL { deepLinkRouter.handle($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { deepLinkRouter.handle(url) }
                }
        }
    }
}
