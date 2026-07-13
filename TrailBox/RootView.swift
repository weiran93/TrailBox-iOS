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
        .overlay(alignment: .bottom) {
            if let feedback = savedRoutes.feedback {
                SavedRouteFeedbackBanner(
                    feedback: feedback,
                    isWorking: savedRoutes.savingTrackIDs.contains(feedback.trackID),
                    undo: {
                        guard let token = session.token else { return }
                        Task { await savedRoutes.undoRemoval(feedback, token: token) }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 82)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: feedback.id) {
                    try? await Task.sleep(nanoseconds: feedback.allowsUndo ? 4_000_000_000 : 2_400_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        savedRoutes.dismissFeedback(id: feedback.id)
                    }
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: savedRoutes.feedback?.id)
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

private struct SavedRouteFeedbackBanner: View {
    let feedback: SavedRouteFeedback
    let isWorking: Bool
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: feedback.kind == .removed ? "bookmark.slash.fill" : "bookmark.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(feedback.kind == .removed ? TrailBoxColor.warning : TrailBoxColor.primaryDark)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.7), in: Circle())

            Text(feedback.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TrailBoxColor.text)

            Spacer(minLength: 8)

            if feedback.allowsUndo {
                Button(action: undo) {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("撤销")
                            .font(.subheadline.weight(.bold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(TrailBoxColor.primaryDark)
                .frame(minWidth: 44, minHeight: 44)
                .disabled(isWorking)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, feedback.allowsUndo ? 8 : 16)
        .frame(minHeight: 56)
        .trailBoxGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
    }
}
