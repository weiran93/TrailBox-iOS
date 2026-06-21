import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var selectedTab: Tab = .explore
    @State private var showAuthentication = false

    private enum Tab { case explore, activity }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if selectedTab == .explore { ExploreView(showAuthentication: $showAuthentication) }
                else { MyTracksView(showAuthentication: $showAuthentication) }
            }
            .padding(.bottom, 70)
            bottomBar
        }
        .background(TrailBoxColor.background)
        .sheet(isPresented: $showAuthentication) { AuthenticationView() }
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
