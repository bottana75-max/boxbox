import Foundation

@MainActor
@Observable
class HomeViewModel {
    var nextRace: Race?
    var lastRace: Race?
    var lastRaceResults: [RaceResult] = []
    var recentRaces: [(Race, [RaceResult])] = []
    var championshipLeader: DriverStanding?
    var titleChasers: [DriverStanding] = []
    var driverTrends: [DriverTrend] = []
    var pressureProfile = CircuitPressureProfile.from(info: nil)
    var isLoading = false
    var error: String?
    var countdown: String = ""

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var countdownSyncTask: Task<Void, Never>?
    @ObservationIgnored private lazy var countdownTimer = CountdownTimer(
        targetDateProvider: { [weak self] in self?.nextRace?.raceDate }
    )
    private let service = OpenF1Service.shared

    var titleFightGapText: String {
        guard let leader = titleChasers.first, titleChasers.count > 1 else { return "No pressure yet" }
        let gap = leader.points - titleChasers[1].points
        return "P1 leads by \(gap.cleanNumber) pts"
    }

    func loadData() async {
        loadTask?.cancel()
        isLoading = true
        error = nil

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                async let scheduleTask = service.fetchCurrentSchedule()
                async let lastResultsTask = service.fetchLastRaceResults()
                async let standingsTask = service.fetchDriverStandings()
                async let recentTask = service.fetchRecentCompletedRaces(limit: 3)

                let schedule = try await scheduleTask
                let (race, results) = try await lastResultsTask
                let standings = try await standingsTask
                let recent = try await recentTask

                guard !Task.isCancelled else { return }

                lastRace = race
                lastRaceResults = Array(results.prefix(5))
                recentRaces = recent
                championshipLeader = standings.first
                titleChasers = Array(standings.prefix(3))

                let now = Date()
                nextRace = schedule.first { race in
                    guard let raceDate = race.raceDate else { return false }
                    return raceDate > now
                }

                pressureProfile = CircuitPressureProfile.from(info: nextRace?.circuitInfo)
                driverTrends = service.buildTrends(from: standings, recentRaces: recent, limit: 5)

                countdownTimer.start()
                // Sync timer text into the observable property.
                countdown = countdownTimer.text
                startCountdownSync()
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            isLoading = false
        }
        loadTask = task
        await task.value
    }

    /// Bridges the CountdownTimer text into our @Observable countdown property.
    private func startCountdownSync() {
        countdownSyncTask?.cancel()
        countdownSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.countdown = self.countdownTimer.text
            }
        }
    }

    nonisolated deinit {
        loadTask?.cancel()
        countdownSyncTask?.cancel()
    }
}
