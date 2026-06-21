import SwiftUI

@main
struct TrailBoxApp: App {
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .tint(TrailBoxColor.primary)
                .preferredColorScheme(.light)
        }
    }
}
