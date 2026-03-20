import Foundation

@MainActor
@Observable
class ReplayViewModel {
    let race: Race

    var snapshots: [ReplaySnapshot] = []
    var selectedIndex = 0
    var isPlaying = false
    var isLoading = false
    var error: String?

    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    private let service = ReplayService.shared

    init(race: Race) {
        self.race = race
    }

    var canShowReplay: Bool {
        race.isReplayEligible
    }

    var currentSnapshot: ReplaySnapshot? {
        guard snapshots.indices.contains(selectedIndex) else { return snapshots.last }
        return snapshots[selectedIndex]
    }

    var progress: Double {
        get {
            guard snapshots.count > 1 else { return 0 }
            return Double(selectedIndex) / Double(snapshots.count - 1)
        }
        set {
            guard snapshots.count > 1 else { return }
            let clamped = min(max(newValue, 0), 1)
            selectedIndex = Int(round(clamped * Double(snapshots.count - 1)))
        }
    }

    func loadReplay() async {
        guard canShowReplay else { return }
        isLoading = true
        error = nil
        pause()

        do {
            let payload = try await service.fetchReplay(for: race)
            snapshots = payload.snapshots
            selectedIndex = 0
            if snapshots.isEmpty {
                error = "Replay data is not available for this race yet"
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard !isPlaying, snapshots.count > 1 else { return }
        isPlaying = true
        playbackTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.selectedIndex >= self.snapshots.count - 1 {
                    self.isPlaying = false
                    return
                }
                try? await Task.sleep(for: .milliseconds(900))
                self.selectedIndex += 1
            }
        }
    }

    func pause() {
        isPlaying = false
        playbackTask?.cancel()
        playbackTask = nil
    }

    func step(by amount: Int) {
        pause()
        selectedIndex = min(max(selectedIndex + amount, 0), max(snapshots.count - 1, 0))
    }

    nonisolated deinit {
        playbackTask?.cancel()
    }
}
