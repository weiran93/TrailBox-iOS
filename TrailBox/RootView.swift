import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var deepLinkRouter: DeepLinkRouter
    @EnvironmentObject private var savedRoutes: SavedRoutesStore
    @State private var selectedTab: Tab = .explore
    @State private var showAuthentication = false
    @State private var pendingTabAfterAuthentication: Tab?

    private enum Tab { case explore, activity, profile }

    var body: some View {
        TabView(selection: tabSelection) {
            ExploreView(showAuthentication: $showAuthentication)
                .tabItem { Label("探索路线", systemImage: "map") }
                .tag(Tab.explore)

            MyTracksView(showAuthentication: $showAuthentication)
                .tabItem { Label("运动记录", systemImage: "figure.run") }
                .tag(Tab.activity)

            ProfileView(showAuthentication: $showAuthentication)
                .tabItem { Label("我的", systemImage: "person") }
                .tag(Tab.profile)
        }
        .tint(TrailBoxColor.primary)
        .trailBoxTabBarMinimizeOnScroll()
        .sheet(isPresented: Binding(
            get: { showAuthentication || session.shouldPresentAuthentication },
            set: { presented in
                showAuthentication = presented
                if !presented {
                    session.shouldPresentAuthentication = false
                    if !session.isAuthenticated { pendingTabAfterAuthentication = nil }
                }
            }
        )) { AuthenticationView() }
        .sheet(item: $deepLinkRouter.pendingRoute) { route in
            NavigationStack { TrackDetailView(trackID: route.id, isPublicSource: true) }
        }
        .onChange(of: session.isAuthenticated) { isAuthenticated in
            guard isAuthenticated, let pendingTab = pendingTabAfterAuthentication else { return }
            selectedTab = pendingTab
            pendingTabAfterAuthentication = nil
        }
        .task(id: session.token) {
            await savedRoutes.load(token: session.token)
        }
        .alert("收藏路线", isPresented: Binding(
            get: { savedRoutes.errorMessage != nil },
            set: { if !$0 { savedRoutes.dismissError() } }
        )) {
            Button("知道了", role: .cancel) { savedRoutes.dismissError() }
        } message: {
            Text(savedRoutes.errorMessage ?? "")
        }
    }

    private var tabSelection: Binding<Tab> {
        Binding(
            get: { selectedTab },
            set: { tab in
                if tab == .profile && !session.isAuthenticated {
                    pendingTabAfterAuthentication = .profile
                    showAuthentication = true
                    return
                }
                selectedTab = tab
                pendingTabAfterAuthentication = nil
            }
        )
    }
}
