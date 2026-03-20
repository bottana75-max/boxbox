import Foundation

@MainActor
@Observable
class RaceDetailViewModel {
    let race: Race
    var results: [RaceResult] = []
    var isLoading = false
    var error: String?
    var countdown: String = ""

    @ObservationIgnored private var loadTask: Task<Void, Never>?
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
            loadTask?.cancel()
            isLoading = true
            error = nil
            let task = Task { [weak self] in
                guard let self else { return }
                do {
                    let fetched = try await OpenF1Service.shared.fetchRaceResults(round: race.round)
                    guard !Task.isCancelled else { return }
                    results = fetched
                } catch {
                    guard !Task.isCancelled else { return }
                    self.error = "Results not available yet"
                }
                isLoading = false
            }
            loadTask = task
            await task.value
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
                while !Task.isCancelled, let self {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { break }
                    self.countdown = self.countdownTimer.text.isEmpty ? "Race started!" : self.countdownTimer.text
                }
            }
        }
    }

    nonisolated deinit {
        loadTask?.cancel()
        countdownSyncTask?.cancel()
    }
}
