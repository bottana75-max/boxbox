import Foundation

@MainActor
@Observable
class DriverDetailViewModel {
    let driver: Driver
    var recentResults: [DriverRaceResult] = []
    var isLoading = false
    var error: String?

    var profile: DriverProfile? {
        driver.profile
    }

    var podiumFinishes: Int {
        recentResults.filter { (1...3).contains($0.position) }.count
    }

    var winsInRecentForm: Int {
        recentResults.filter { $0.position == 1 }.count
    }

    var pointsFinishes: Int {
        recentResults.filter { $0.points > 0 }.count
    }

    var averageFinishText: String {
        let validPositions = recentResults.map(\.position).filter { $0 > 0 }
        guard !validPositions.isEmpty else { return "—" }
        let average = Double(validPositions.reduce(0, +)) / Double(validPositions.count)
        return String(format: "%.1f", average)
    }

    var recentFormLabel: String {
        guard !recentResults.isEmpty else { return "No race sample" }
        if winsInRecentForm >= 2 || podiumFinishes >= 4 { return "Hot streak" }
        if averageFinishText != "—", let avg = Double(averageFinishText), avg <= 8 { return "Strong form" }
        if recentResults.contains(where: { $0.isDNF }) { return "Volatile" }
        return "Steady"
    }

    init(driver: Driver) {
        self.driver = driver
    }

    func loadResults() async {
        isLoading = true
        error = nil
        do {
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
