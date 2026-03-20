import Foundation

@MainActor
@Observable
final class ReplayViewModel {
    let race: Race

    var availableDrivers: [ReplayDriver] = []
    var selectedDriverNumbers: Set<Int> = []
    var snapshots: [ReplaySnapshot] = []
    var projection: ReplayProjectionMetadata?
    var selectedIndex = 0
    var isPlaying = false
    var isLoadingDrivers = false
    var isLoadingReplay = false
    var error: String?
    var hasLoadedDriverList = false

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    private let service = ReplayService.shared
    private let maxDriverSelection = 5

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

    var selectedDrivers: [ReplayDriver] {
        availableDrivers.filter { selectedDriverNumbers.contains($0.driverNumber) }
    }

    var selectionSummary: String {
        if selectedDriverNumbers.isEmpty { return "Choose 1 to 5 drivers before loading full location data." }
        return "\(selectedDriverNumbers.count)/\(maxDriverSelection) drivers selected"
    }

    func prepare() async {
        guard canShowReplay, !hasLoadedDriverList else { return }
        loadTask?.cancel()
        isLoadingDrivers = true
        error = nil

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let drivers = try await service.fetchAvailableDrivers(for: race)
                guard !Task.isCancelled else { return }
                availableDrivers = drivers
                hasLoadedDriverList = true
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            isLoadingDrivers = false
        }
        loadTask = task
        await task.value
    }

    func toggleDriver(_ driver: ReplayDriver) {
        if selectedDriverNumbers.contains(driver.driverNumber) {
            selectedDriverNumbers.remove(driver.driverNumber)
            return
        }

        guard selectedDriverNumbers.count < maxDriverSelection else {
            error = "Load up to 5 drivers at a time so the replay stays fast and readable."
            return
        }

        error = nil
        selectedDriverNumbers.insert(driver.driverNumber)
    }

    func loadReplay() async {
        guard canShowReplay else { return }
        guard !selectedDriverNumbers.isEmpty else {
            error = "Choose at least one driver first."
            return
        }

        loadTask?.cancel()
        isLoadingReplay = true
        error = nil
        pause()

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let payload = try await service.fetchReplay(for: race, selectedDriverNumbers: Array(selectedDriverNumbers).sorted())
                guard !Task.isCancelled else { return }
                availableDrivers = payload.availableDrivers
                snapshots = payload.snapshots
                projection = payload.projection
                selectedIndex = 0
                if snapshots.isEmpty {
                    error = "Replay data is not available for this race yet."
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            isLoadingReplay = false
        }
        loadTask = task
        await task.value
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard !isPlaying, snapshots.count > 1 else { return }
        isPlaying = true
        playbackTask = Task { [weak self] in
            while !Task.isCancelled, let self {
                if self.selectedIndex >= self.snapshots.count - 1 {
                    self.isPlaying = false
                    return
                }
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { break }
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
        loadTask?.cancel()
        playbackTask?.cancel()
    }
}
