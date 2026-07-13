import Foundation

struct RecentRoute: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let city: String?
    let distanceM: Double
    let elevationGainM: Double
    let viewedAt: Date

    init(track: Track, viewedAt: Date = Date()) {
        id = track.id
        name = track.name
        city = track.city
        distanceM = track.distanceM
        elevationGainM = track.elevationGainM
        self.viewedAt = viewedAt
    }
}

@MainActor
final class RecentRoutesStore: ObservableObject {
    @Published private(set) var routes: [RecentRoute] = []

    private let defaults: UserDefaults
    private let storageKey = "trailbox.recent-routes"
    private let maximumCount = 8

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([RecentRoute].self, from: data) else { return }
        routes = Array(stored.sorted { $0.viewedAt > $1.viewedAt }.prefix(maximumCount))
    }

    func record(_ track: Track) {
        routes.removeAll { $0.id == track.id }
        routes.insert(RecentRoute(track: track), at: 0)
        routes = Array(routes.prefix(maximumCount))
        persist()
    }

    func clear() {
        routes = []
        defaults.removeObject(forKey: storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(routes) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
