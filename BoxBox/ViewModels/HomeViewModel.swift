import Foundation

@MainActor
@Observable
class HomeViewModel {
    var nextRace: Race?
    var lastRace: Race?
    var lastRaceResults: [RaceResult] = []
    var championshipLeader: DriverStanding?
    var isLoading = false
    var error: String?
    var countdown: String = ""

    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    private let service = OpenF1Service.shared

    func loadData() async {
        isLoading = true
        error = nil

        do {
            async let scheduleTask = service.fetchCurrentSchedule()
            async let lastResultsTask = service.fetchLastRaceResults()
            async let standingsTask = service.fetchDriverStandings()

            let schedule = try await scheduleTask
            let (race, results) = try await lastResultsTask
            let standings = try await standingsTask

            lastRace = race
            lastRaceResults = Array(results.prefix(3))
            championshipLeader = standings.first

            // Find next race
            let now = Date()
            nextRace = schedule.first { race in
                guard let raceDate = race.raceDate else { return false }
                return raceDate > now
            }

            startCountdownTimer()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func startCountdownTimer() {
        countdownTask?.cancel()
        updateCountdown()
        countdownTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                updateCountdown()
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

        if let d = diff.day, let h = diff.hour, let m = diff.minute, let s = diff.second {
            countdown = "\(d)d \(h)h \(m)m \(s)s"
        }
    }

    nonisolated deinit {
        countdownTask?.cancel()
    }
}
