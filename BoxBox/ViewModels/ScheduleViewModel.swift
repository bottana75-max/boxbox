import Foundation

@MainActor
@Observable
class ScheduleViewModel {
    var races: [Race] = []
    var isLoading = false
    var error: String?

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    private let service = OpenF1Service.shared

    var completedCount: Int {
        races.filter(\.isPast).count
    }

    var nextRace: Race? {
        let now = Date()
        return races.first { race in
            guard let raceDate = race.raceDate else { return false }
            return raceDate > now
        }
    }

    var nextRaceRound: Int? {
        nextRace?.round
    }

    func loadData() async {
        loadTask?.cancel()
        isLoading = true
        error = nil

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let fetched = try await service.fetchCurrentSchedule()
                guard !Task.isCancelled else { return }
                races = fetched
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            isLoading = false
        }
        loadTask = task
        await task.value
    }

    nonisolated deinit {
        loadTask?.cancel()
    }
}
