import Foundation

@MainActor
@Observable
class DriverDetailViewModel {
    let driver: Driver
    var finalPosition: Int?
    var positionChanges: [(position: Int, date: String)] = []
    var isLoading = false
    var error: String?

    init(driver: Driver) {
        self.driver = driver
    }

    func loadPositions() async {
        isLoading = true
        error = nil
        do {
            let positions = try await OpenF1Service.shared.fetchDriverPositions(driverNumber: driver.driverNumber)
            if positions.isEmpty {
                finalPosition = nil
            } else {
                finalPosition = positions.last?.position
                // Keep unique position changes for display
                var seen = Set<Int>()
                var changes: [(position: Int, date: String)] = []
                for p in positions {
                    if seen.insert(p.position).inserted {
                        changes.append((position: p.position, date: p.date))
                    }
                }
                positionChanges = changes
            }
        } catch {
            self.error = "Position data not available"
        }
        isLoading = false
    }
}
