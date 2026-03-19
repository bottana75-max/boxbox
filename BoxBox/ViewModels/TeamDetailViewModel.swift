import Foundation

@MainActor
@Observable
class TeamDetailViewModel {
    let teamName: String
    let teamColour: String

    var standing: Constructor?
    var teamDrivers: [DriverStanding] = []
    var recentResults: [TeamRaceResult] = []
    var isLoading = false
    var error: String?

    nonisolated(unsafe) var loadTask: Task<Void, Never>?

    var constructorId: String {
        let mapping: [String: String] = [
            "McLaren": "mclaren",
            "Red Bull Racing": "red_bull",
            "Ferrari": "ferrari",
            "Mercedes": "mercedes",
            "Aston Martin": "aston_martin",
            "Alpine": "alpine",
            "Williams": "williams",
            "Haas F1 Team": "haas",
            "Kick Sauber": "sauber",
            "RB": "rb",
        ]
        return mapping[teamName] ?? teamName.lowercased().replacingOccurrences(of: " ", with: "_")
    }

    init(teamName: String, teamColour: String) {
        self.teamName = teamName
        self.teamColour = teamColour
    }

    nonisolated deinit {
        loadTask?.cancel()
    }

    func loadData() async {
        isLoading = true
        error = nil

        let task = Task {
            do {
                async let standingsReq = OpenF1Service.shared.fetchConstructorStandings()
                async let driverStandingsReq = OpenF1Service.shared.fetchDriverStandings()
                async let resultsReq = OpenF1Service.shared.fetchConstructorResults(constructorId: constructorId)

                let (constructors, drivers, results) = try await (standingsReq, driverStandingsReq, resultsReq)

                guard !Task.isCancelled else { return }

                standing = constructors.first { $0.name == teamName }
                teamDrivers = drivers.filter { $0.constructorName == teamName }
                recentResults = Array(results.suffix(10))
            } catch {
                guard !Task.isCancelled else { return }
                self.error = "Could not load team data. Check your connection."
            }
            isLoading = false
        }
        loadTask = task
        await task.value
    }
}
