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
    private var previewCache: [String: Track] = [:]

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
            let loadedBox: TrackBox = try await APIClient.shared.request("/boxes/want-to-run", token: token)
            box = boxUsingCachedPreviews(loadedBox)
            box = await hydratedPreviews(in: loadedBox, token: token)
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
            let loadedBox: TrackBox = try await APIClient.shared.request(
                "/boxes/want-to-run/tracks/\(trackID)",
                method: method,
                token: token
            )
            box = boxUsingCachedPreviews(loadedBox)
            box = await hydratedPreviews(in: loadedBox, token: token)
            errorMessage = nil
            feedback = SavedRouteFeedback(trackID: trackID, kind: successKind)
        } catch {
            errorMessage = "收藏操作失败：\(ErrorMessage.display(error))"
        }
    }

    private func boxUsingCachedPreviews(_ loadedBox: TrackBox) -> TrackBox {
        replacingTracks(in: loadedBox) { track in
            track.points.count > 1 ? track : (previewCache[track.id] ?? track)
        }
    }

    private func hydratedPreviews(in loadedBox: TrackBox, token: String) async -> TrackBox {
        var resolvedTracks = Dictionary(uniqueKeysWithValues: loadedBox.tracks.map { track in
            (track.id, track.points.count > 1 ? track : (previewCache[track.id] ?? track))
        })
        let missingTracks = loadedBox.tracks.filter { (resolvedTracks[$0.id]?.points.count ?? 0) < 2 }

        await withTaskGroup(of: Track?.self) { group in
            var iterator = missingTracks.makeIterator()
            for _ in 0..<min(6, missingTracks.count) {
                guard let track = iterator.next() else { break }
                group.addTask {
                    try? await APIClient.shared.request("/tracks/\(track.id)/public", token: token)
                }
            }
            while let track = await group.next() {
                if let track, track.points.count > 1 {
                    resolvedTracks[track.id] = track
                    previewCache[track.id] = track
                }
                if let nextTrack = iterator.next() {
                    group.addTask {
                        try? await APIClient.shared.request("/tracks/\(nextTrack.id)/public", token: token)
                    }
                }
            }
        }

        let activeTrackIDs = Set(loadedBox.tracks.map(\.id))
        previewCache = previewCache.filter { activeTrackIDs.contains($0.key) }
        return replacingTracks(in: loadedBox) { resolvedTracks[$0.id] ?? $0 }
    }

    private func replacingTracks(
        in box: TrackBox,
        transform: (Track) -> Track
    ) -> TrackBox {
        TrackBox(
            id: box.id,
            name: box.name,
            description: box.description,
            isPublic: box.isPublic,
            createdAt: box.createdAt,
            tracks: box.tracks.map(transform)
        )
    }
}
