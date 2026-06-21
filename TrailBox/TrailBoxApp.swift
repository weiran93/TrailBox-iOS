import SwiftUI

@main
struct TrailBoxApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var deepLinkRouter = DeepLinkRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(deepLinkRouter)
                .tint(TrailBoxColor.primary)
                .preferredColorScheme(.light)
                .onOpenURL { deepLinkRouter.handle($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { deepLinkRouter.handle(url) }
                }
        }
    }
}
