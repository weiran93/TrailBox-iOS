import SwiftUI

@MainActor
final class SavedRoutesStore: ObservableObject {
    @Published private(set) var box: TrackBox?
    @Published private(set) var savingTrackIDs: Set<String> = []
    @Published private(set) var errorMessage: String?
    private var optimisticStates: [String: Bool] = [:]

    var tracks: [Track] { box?.tracks ?? [] }
    var savedTrackIDs: Set<String> { Set(tracks.map(\.id)) }

    func isSaved(_ trackID: String) -> Bool {
        optimisticStates[trackID] ?? savedTrackIDs.contains(trackID)
    }

    func dismissError() {
        errorMessage = nil
    }

    func load(token: String?) async {
        guard let token else {
            box = nil
            return
        }
        do {
            box = try await APIClient.shared.request("/boxes/want-to-run", token: token)
        } catch {
            errorMessage = "收藏路线加载失败：\(ErrorMessage.display(error))"
        }
    }

    func toggle(trackID: String, token: String) async {
        guard !savingTrackIDs.contains(trackID) else { return }
        let wasSaved = isSaved(trackID)
        optimisticStates[trackID] = !wasSaved
        savingTrackIDs.insert(trackID)
        defer {
            optimisticStates[trackID] = nil
            savingTrackIDs.remove(trackID)
        }

        do {
            let method = wasSaved ? "DELETE" : "PUT"
            box = try await APIClient.shared.request(
                "/boxes/want-to-run/tracks/\(trackID)",
                method: method,
                token: token
            )
        } catch {
            errorMessage = "收藏操作失败：\(ErrorMessage.display(error))"
        }
    }
}
