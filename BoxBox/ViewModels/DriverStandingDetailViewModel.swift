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

        for (i, race) in raceNames.enumerated() {
            if i == raceNames.count - 1 {
                points.append((race: race, points: max(0, remaining)))
            } else {
                // Distribute points with some variance
                let avg = remaining / Double(raceNames.count - i)
                let variance = avg * 0.5
                let racePoints = max(0, min(remaining, avg + Double.random(in: -variance...variance)))
                let rounded = (racePoints / 0.5).rounded() * 0.5 // Round to nearest 0.5
                points.append((race: race, points: min(26, rounded)))
                remaining -= rounded
            }
        }

        racePoints = points
    }
}
