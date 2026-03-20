import Foundation

@MainActor
@Observable
class DriversViewModel {
    var drivers: [Driver] = []
    var selectedDriverIDs: [String] = []
    var isCompareMode = false
    var isLoading = false
    var error: String?

    @ObservationIgnored private var loadTask: Task<Void, Never>?
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
        loadTask?.cancel()
        isLoading = true
        error = nil

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let fetched = try await service.fetchDrivers()
                guard !Task.isCancelled else { return }
                drivers = fetched
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
