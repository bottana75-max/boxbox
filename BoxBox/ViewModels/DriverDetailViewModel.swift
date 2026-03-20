import Foundation

@MainActor
@Observable
class DriverDetailViewModel {
    var driver: Driver
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

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    private let service = OpenF1Service.shared

    init(driver: Driver) {
        self.driver = driver
    }

    func loadResults() async {
        loadTask?.cancel()
        isLoading = true
        error = nil

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                // Resolve full driver profile (headshot, country) before fetching results.
                let resolved = try await service.resolveDriver(for: driver)
                guard !Task.isCancelled else { return }
                driver = resolved

                guard let driverId = try await service.findDriverId(for: resolved) else {
                    error = "Driver data is not available right now"
                    isLoading = false
                    return
                }
                guard !Task.isCancelled else { return }

                let results = try await service.fetchDriverResults(driverId: driverId)
                guard !Task.isCancelled else { return }
                recentResults = Array(results.suffix(5))
            } catch {
                guard !Task.isCancelled else { return }
                self.error = "Recent results not available"
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
