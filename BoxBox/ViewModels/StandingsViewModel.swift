import Foundation

@MainActor
@Observable
class StandingsViewModel {
    var driverStandings: [DriverStanding] = []
    var constructorStandings: [Constructor] = []
    var selectedTab = 0
    var isLoading = false
    var error: String?
    var driverHeadshots: [String: String] = [:]

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
                async let rosterTask = service.fetchDrivers()
                let (drivers, constructors, roster) = try await (driversTask, constructorsTask, rosterTask)
                guard !Task.isCancelled else { return }
                driverStandings = drivers
                constructorStandings = constructors
                driverHeadshots = Dictionary(uniqueKeysWithValues: roster.map { ($0.nameAcronym.uppercased(), $0.headshotUrl ?? "") })
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            isLoading = false
        }
        loadTask = task
        await task.value
    }

    func headshotURL(for standing: DriverStanding) -> String? {
        let value = driverHeadshots[standing.driverCode.uppercased()]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    nonisolated deinit {
        loadTask?.cancel()
    }
}
