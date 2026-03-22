import Foundation

@MainActor
@Observable
class DriverStandingDetailViewModel {
    let standing: DriverStanding

    // Mock points per race (API doesn't provide per-race breakdown)
    var racePoints: [(race: String, points: Double)] = []

    init(standing: DriverStanding) {
        self.standing = standing
        generateMockRacePoints()
    }

    private func generateMockRacePoints() {
        let raceNames = ["BAH", "SAU", "AUS", "JPN", "CHN", "MIA", "EMI", "MON", "ESP", "CAN"]
        let totalPoints = standing.points
        var remaining = totalPoints
        var points: [(race: String, points: Double)] = []
        let lastIndex = raceNames.count - 1

        for (i, race) in raceNames.enumerated() {
            if i == lastIndex {
                // Assign whatever is left to the final race, clamped to 0.
                points.append((race: race, points: max(0, remaining)))
            } else {
                // Distribute points proportionally with ±50% variance, then round to nearest 0.5.
                let avg = remaining / Double(raceNames.count - i)
                let variance = avg * 0.5
                let rawPoints = max(0, min(remaining, avg + Double.random(in: -variance...variance)))
                // Round to nearest 0.5 (valid F1 sprint/race point step) and cap at max race award (26).
                let rounded = (rawPoints * 2).rounded() / 2
                let capped = min(26, rounded)
                points.append((race: race, points: capped))
                remaining -= capped
            }
        }

        racePoints = points
    }
}
