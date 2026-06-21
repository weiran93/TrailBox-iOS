import Foundation

@MainActor
final class DeepLinkRouter: ObservableObject {
    @Published var pendingRoute: RouteLink?

    func handle(_ url: URL) {
        let components = url.pathComponents
        guard components.count >= 3, components[1] == "r", !components[2].isEmpty else { return }
        pendingRoute = RouteLink(id: components[2])
    }
}

struct RouteLink: Identifiable {
    let id: String
}
