import Foundation

@MainActor
@Observable
class StandingsViewModel {
    var driverStandings: [DriverStanding] = []
    var constructorStandings: [Constructor] = []
    var selectedTab = 0
    var isLoading = false
    var error: String?

    private let service = OpenF1Service.shared

    func loadData() async {
        isLoading = true
        error = nil

        do {
            async let driversTask = service.fetchDriverStandings()
            async let constructorsTask = service.fetchConstructorStandings()

            driverStandings = try await driversTask
            constructorStandings = try await constructorsTask
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
