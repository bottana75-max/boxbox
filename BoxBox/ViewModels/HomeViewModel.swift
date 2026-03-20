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

    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    private let service = OpenF1Service.shared

    var titleFightGapText: String {
        guard let leader = titleChasers.first, titleChasers.count > 1 else { return "No pressure yet" }
        let gap = leader.points - titleChasers[1].points
        return "P1 leads by \(gap.cleanNumber) pts"
    }

    func loadData() async {
        isLoading = true
        error = nil

        do {
            async let scheduleTask = service.fetchCurrentSchedule()
            async let lastResultsTask = service.fetchLastRaceResults()
            async let standingsTask = service.fetchDriverStandings()
            async let recentTask = service.fetchRecentCompletedRaces(limit: 3)

            let schedule = try await scheduleTask
            let (race, results) = try await lastResultsTask
            let standings = try await standingsTask
            let recent = try await recentTask

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

            startCountdownTimer()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func startCountdownTimer() {
        countdownTask?.cancel()
        updateCountdown() // Populate immediately so the UI never shows an empty string on first render.
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.updateCountdown()
            }
        }
    }

    private func updateCountdown() {
        guard let raceDate = nextRace?.raceDate else {
            countdown = ""
            return
        }

        let now = Date()
        let diff = Calendar.current.dateComponents([.day, .hour, .minute, .second], from: now, to: raceDate)

        guard let d = diff.day, let h = diff.hour, let m = diff.minute, let s = diff.second else { return }
        countdown = "\(d)d \(h)h \(m)m \(s)s"
    }

    nonisolated deinit {
        countdownTask?.cancel()
    }
}
