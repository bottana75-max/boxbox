import Foundation

@MainActor
@Observable
class RaceDetailViewModel {
    let race: Race
    var results: [RaceResult] = []
    var isLoading = false
    var error: String?
    var countdown: String = ""

    @ObservationIgnored private var countdownSyncTask: Task<Void, Never>?
    @ObservationIgnored private lazy var countdownTimer = CountdownTimer(
        targetDateProvider: { [weak self] in self?.race.raceDate },
        onExpired: { [weak self] in self?.countdown = "Race started!" }
    )

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
            if race.raceDate == nil {
                countdown = "Date TBD"
                return
            }
            countdownTimer.start()
            countdown = countdownTimer.text
            // Sync timer text into the observable property each second.
            countdownSyncTask?.cancel()
            countdownSyncTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self else { return }
                    self.countdown = self.countdownTimer.text.isEmpty ? "Race started!" : self.countdownTimer.text
                }
            }
        }
    }

    nonisolated deinit {
        countdownSyncTask?.cancel()
    }
}
