import Foundation

@MainActor
@Observable
class DriversViewModel {
    var drivers: [Driver] = []
    var selectedDriverIDs: [String] = []
    var isCompareMode = false
    var isLoading = false
    var error: String?

    private let service = OpenF1Service.shared

    var selectedDrivers: [Driver] {
        drivers.filter { selectedDriverIDs.contains($0.id) }
    }

    var canCompare: Bool {
        selectedDriverIDs.count == 2
    }

    func toggleSelection(for driver: Driver) {
        if let index = selectedDriverIDs.firstIndex(of: driver.id) {
            selectedDriverIDs.remove(at: index)
            return
        }
        guard selectedDriverIDs.count < 2 else {
            selectedDriverIDs.removeFirst()
            selectedDriverIDs.append(driver.id)
            return
        }
        selectedDriverIDs.append(driver.id)
    }

    func resetCompareMode() {
        isCompareMode = false
        selectedDriverIDs.removeAll()
    }

    func loadData() async {
        isLoading = true
        error = nil

        do {
            drivers = try await service.fetchDrivers()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
