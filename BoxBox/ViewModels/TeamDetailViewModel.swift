import Foundation

@MainActor
@Observable
class TeamDetailViewModel {
    let teamName: String
    let teamColour: String

    var standing: Constructor?
    var teamDrivers: [DriverStanding] = []
    var recentResults: [TeamRaceResult] = []
    var allConstructors: [Constructor] = []
    var isLoading = false
    var error: String?

    @ObservationIgnored private var loadTask: Task<Void, Never>?

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

    var totalDriverPoints: Double {
        teamDrivers.reduce(0) { $0 + $1.points }
    }

    var averageGridRank: String {
        guard !teamDrivers.isEmpty else { return "—" }
        let value = teamDrivers.map(\.position).reduce(0, +) / teamDrivers.count
        return String(format: "P%.1f", Double(value))
    }

    var formAverage: String {
        let finishes = recentResults.filter { !$0.isDNF && $0.position > 0 }.map(\.position)
        guard !finishes.isEmpty else { return "DNF heavy" }
        let avg = finishes.map(Double.init).reduce(0, +) / Double(finishes.count)
        return String(format: "P%.1f", avg)
    }

    var podiumCount: Int {
        recentResults.filter { $0.position <= 3 && !$0.isDNF }.count
    }

    var dnfCount: Int {
        recentResults.filter(\.isDNF).count
    }

    var strongestFinisher: DriverStanding? {
        teamDrivers.min(by: { $0.position < $1.position })
    }

    var nearestRival: Constructor? {
        guard let standing else { return nil }
        return allConstructors
            .filter { $0.name != teamName }
            .min(by: { abs($0.points - standing.points) < abs($1.points - standing.points) })
    }

    var pointsGapSummary: String {
        guard let standing else { return "Standings still loading." }
        if let rival = nearestRival {
            let gap = abs(standing.points - rival.points)
            let direction = rival.position < standing.position ? "behind \(rival.name)" : "clear of \(rival.name)"
            return "P\(standing.position) with \(standing.points.cleanNumber) points, \(gap.cleanNumber) points \(direction)."
        }
        return "P\(standing.position) with \(standing.points.cleanNumber) points."
    }

    var momentumHeadline: String {
        if podiumCount >= 3 { return "Sharp front-running trend" }
        if dnfCount >= 2 { return "Fragile conversion lately" }
        if formAverage.contains("P") { return "Reliable points-scoring window" }
        return "Recent read still thin"
    }

    var teamNarrative: String {
        let leadDriver = strongestFinisher?.driverName ?? teamName
        return "\(teamName) comes in with \(pointsGapSummary) The current read: \(momentumHeadline.lowercased()), led by \(leadDriver). This page is supposed to feel like a premium team sheet, not just a standings dump."
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

                allConstructors = constructors.sorted { $0.position < $1.position }
                standing = constructors.first { $0.name == teamName }
                teamDrivers = drivers.filter { $0.constructorName == teamName }.sorted { $0.position < $1.position }
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
