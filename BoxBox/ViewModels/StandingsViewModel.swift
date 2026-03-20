import Foundation

@MainActor
@Observable
class StandingsViewModel {
    var driverStandings: [DriverStanding] = []
    var constructorStandings: [Constructor] = []
    var selectedTab = 0
    var isLoading = false
    var error: String?

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    private let service = OpenF1Service.shared

    func loadData() async {
        loadTask?.cancel()
        isLoading = true
        error = nil

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                async let driversTask = service.fetchDriverStandings()
                async let constructorsTask = service.fetchConstructorStandings()
                let (drivers, constructors) = try await (driversTask, constructorsTask)
                guard !Task.isCancelled else { return }
                driverStandings = drivers
                constructorStandings = constructors
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
