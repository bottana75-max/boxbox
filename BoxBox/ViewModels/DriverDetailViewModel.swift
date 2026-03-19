import Foundation

@MainActor
@Observable
class DriverDetailViewModel {
    let driver: Driver
    var recentResults: [DriverRaceResult] = []
    var isLoading = false
    var error: String?

    init(driver: Driver) {
        self.driver = driver
    }

    func loadResults() async {
        isLoading = true
        error = nil
        do {
            // Try to find the Jolpica driverId for this driver
            guard let driverId = try await OpenF1Service.shared.findDriverId(for: driver) else {
                error = "Driver not found in standings"
                isLoading = false
                return
            }
            let results = try await OpenF1Service.shared.fetchDriverResults(driverId: driverId)
            recentResults = Array(results.suffix(5))
        } catch {
            self.error = "Recent results not available"
        }
        isLoading = false
    }
}
