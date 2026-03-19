import Foundation

@MainActor
@Observable
class DriversViewModel {
    var drivers: [Driver] = []
    var isLoading = false
    var error: String?

    private let service = OpenF1Service.shared

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
