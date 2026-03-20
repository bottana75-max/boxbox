import Foundation

@MainActor
@Observable
class RaceDetailViewModel {
    let race: Race
    var results: [RaceResult] = []
    var isLoading = false
    var error: String?
    var countdown: String = ""

    @ObservationIgnored private var countdownTask: Task<Void, Never>?

    init(race: Race) {
        self.race = race
    }

    func loadData() async {
        if race.isPast {
            isLoading = true
            error = nil
            do {
                results = try await OpenF1Service.shared.fetchRaceResults(round: race.round)
            } catch {
                self.error = "Results not available yet"
            }
            isLoading = false
        } else {
            startCountdownTimer()
        }
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
        guard let raceDate = race.raceDate else {
            countdown = "Date TBD"
            return
        }
        if let text = countdownString(to: raceDate) {
            countdown = text
        } else {
            countdown = "Race started!"
            countdownTask?.cancel()
        }
    }

    nonisolated deinit {
        countdownTask?.cancel()
    }
}
