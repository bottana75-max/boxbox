import Foundation

@MainActor
@Observable
class ScheduleViewModel {
    var races: [Race] = []
    var isLoading = false
    var error: String?

    private let service = OpenF1Service.shared

    var nextRaceRound: Int? {
        let now = Date()
        return races.first { race in
            guard let raceDate = race.raceDate else { return false }
            return raceDate > now
        }?.round
    }

    func loadData() async {
        isLoading = true
        error = nil

        do {
            races = try await service.fetchCurrentSchedule()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
