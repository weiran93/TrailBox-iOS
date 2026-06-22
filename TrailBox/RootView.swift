import SwiftUI

@MainActor
final class BottomBarVisibilityStore: ObservableObject {
    @Published var isVisible = true
}

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var deepLinkRouter: DeepLinkRouter
    @EnvironmentObject private var bottomBarVisibility: BottomBarVisibilityStore
    @State private var selectedTab: Tab = .explore
    @State private var showAuthentication = false

    private enum Tab { case explore, activity }

    // Total height of the custom bottom bar including the safe-area filler.
    static let bottomBarHeight: CGFloat = 83

    var body: some View {
        ZStack(alignment: .bottom) {
            // Both tabs stay in the view hierarchy so their @StateObject view models
            // and scroll positions survive tab switches. Visibility is toggled via opacity.
            // The tab content extends underneath the bottom bar; each tab insets its own
            // scrollable content so the bar never compresses the layout when it hides.
            ExploreView(showAuthentication: $showAuthentication)
                .opacity(selectedTab == .explore ? 1 : 0)
                .allowsHitTesting(selectedTab == .explore)
                .zIndex(selectedTab == .explore ? 1 : 0)

            MyTracksView(showAuthentication: $showAuthentication)
                .opacity(selectedTab == .activity ? 1 : 0)
                .allowsHitTesting(selectedTab == .activity)
                .zIndex(selectedTab == .activity ? 1 : 0)

            bottomBarContainer
                .zIndex(2)
        }
        .background(TrailBoxColor.background)
        .ignoresSafeArea(.container, edges: .bottom)
        .sheet(isPresented: Binding(
            get: { showAuthentication || session.shouldPresentAuthentication },
            set: { presented in
                showAuthentication = presented
                if !presented { session.shouldPresentAuthentication = false }
            }
        )) { AuthenticationView() }
        .sheet(item: $deepLinkRouter.pendingRoute) { route in
            NavigationStack { TrackDetailView(trackID: route.id, isPublicSource: true) }
        }
    }

    private var bottomBarContainer: some View {
        VStack(spacing: 0) {
            bottomBar
            Color.white.frame(height: bottomBarVisibility.isVisible ? 34 : 0)
        }
        .frame(height: bottomBarVisibility.isVisible ? RootView.bottomBarHeight : 0)
        .opacity(bottomBarVisibility.isVisible ? 1 : 0)
        .clipped()
        .animation(.easeInOut(duration: 0.25), value: bottomBarVisibility.isVisible)
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            tabButton(.explore, title: "探索路线", icon: "magnifyingglass")
            tabButton(.activity, title: "我的记录", icon: "figure.run")
        }
        .frame(height: 49)
        .background(.white)
        .overlay(alignment: .top) { Divider().overlay(TrailBoxColor.border) }
    }

    private func tabButton(_ tab: Tab, title: String, icon: String) -> some View {
        Button {
            if tab == .activity && !session.isAuthenticated {
                selectedTab = .explore
                showAuthentication = true
            } else {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 19, weight: .semibold))
                Text(title).font(.caption2.weight(.medium))
            }.foregroundStyle(selectedTab == tab ? TrailBoxColor.primary : TrailBoxColor.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
