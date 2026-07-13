import SwiftUI

struct SavedRouteFeedback: Identifiable, Equatable {
    enum Kind: Equatable {
        case saved
        case removed
        case restored
    }

    let id = UUID()
    let trackID: String
    let kind: Kind

    var message: String {
        switch kind {
        case .saved: return "已加入收藏路线"
        case .removed: return "已取消收藏"
        case .restored: return "已恢复收藏"
        }
    }

    var allowsUndo: Bool { kind == .removed }
}

@MainActor
final class SavedRoutesStore: ObservableObject {
    @Published private(set) var box: TrackBox?
    @Published private(set) var savingTrackIDs: Set<String> = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var feedback: SavedRouteFeedback?
    private var optimisticStates: [String: Bool] = [:]

    var tracks: [Track] { box?.tracks ?? [] }
    var savedTrackIDs: Set<String> { Set(tracks.map(\.id)) }

    func isSaved(_ trackID: String) -> Bool {
        optimisticStates[trackID] ?? savedTrackIDs.contains(trackID)
    }

    func dismissError() {
        errorMessage = nil
    }

    func dismissFeedback(id: UUID? = nil) {
        guard id == nil || feedback?.id == id else { return }
        feedback = nil
    }

    func load(token: String?) async {
        guard let token else {
            box = nil
            feedback = nil
            errorMessage = nil
            return
        }
        do {
            box = try await APIClient.shared.request("/boxes/want-to-run", token: token)
            errorMessage = nil
        } catch {
            errorMessage = "收藏路线加载失败：\(ErrorMessage.display(error))"
        }
    }

    func toggle(trackID: String, token: String) async {
        guard !savingTrackIDs.contains(trackID) else { return }
        let wasSaved = isSaved(trackID)
        await update(
            trackID: trackID,
            shouldSave: !wasSaved,
            successKind: wasSaved ? .removed : .saved,
            token: token
        )
    }

    func undoRemoval(_ feedback: SavedRouteFeedback, token: String) async {
        guard feedback.kind == .removed,
              self.feedback?.id == feedback.id,
              !isSaved(feedback.trackID),
              !savingTrackIDs.contains(feedback.trackID) else { return }
        await update(trackID: feedback.trackID, shouldSave: true, successKind: .restored, token: token)
    }

    private func update(
        trackID: String,
        shouldSave: Bool,
        successKind: SavedRouteFeedback.Kind,
        token: String
    ) async {
        feedback = nil
        errorMessage = nil
        optimisticStates[trackID] = shouldSave
        savingTrackIDs.insert(trackID)
        defer {
            optimisticStates[trackID] = nil
            savingTrackIDs.remove(trackID)
        }

        do {
            let method = shouldSave ? "PUT" : "DELETE"
            box = try await APIClient.shared.request(
                "/boxes/want-to-run/tracks/\(trackID)",
                method: method,
                token: token
            )
            errorMessage = nil
            feedback = SavedRouteFeedback(trackID: trackID, kind: successKind)
        } catch {
            errorMessage = "收藏操作失败：\(ErrorMessage.display(error))"
        }
    }
}
