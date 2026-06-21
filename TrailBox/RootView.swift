import SwiftUI

struct BottomBarVisibilityPreferenceKey: PreferenceKey {
    static let defaultValue = true

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value && nextValue()
    }
}

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var deepLinkRouter: DeepLinkRouter
    @State private var selectedTab: Tab = .explore
    @State private var showAuthentication = false
    @State private var showsBottomBar = true

    private enum Tab { case explore, activity }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if selectedTab == .explore { ExploreView(showAuthentication: $showAuthentication) }
                else { MyTracksView(showAuthentication: $showAuthentication) }
            }
            .padding(.bottom, showsBottomBar ? 70 : 0)
            if showsBottomBar {
                bottomBar
            }
        }
        .background(TrailBoxColor.background)
        .onPreferenceChange(BottomBarVisibilityPreferenceKey.self) { showsBottomBar = $0 }
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

    private var bottomBar: some View {
        HStack(spacing: 0) {
            tabButton(.explore, title: "探索路线", icon: "magnifyingglass")
            tabButton(.activity, title: "我的记录", icon: "figure.run")
        }
        .frame(height: 62)
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
