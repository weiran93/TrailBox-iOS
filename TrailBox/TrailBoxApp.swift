import SwiftUI

@main
struct TrailBoxApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var deepLinkRouter = DeepLinkRouter()
    @StateObject private var bottomBarVisibility = BottomBarVisibilityStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(deepLinkRouter)
                .environmentObject(bottomBarVisibility)
                .tint(TrailBoxColor.primary)
                .preferredColorScheme(.light)
                .onOpenURL { deepLinkRouter.handle($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { deepLinkRouter.handle(url) }
                }
        }
    }
}
