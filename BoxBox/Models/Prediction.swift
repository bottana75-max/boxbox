import Foundation

// MARK: - Structured Race Call Context (sent to AI)

struct ContenderProfile: Codable {
    let driverName: String
    let driverCode: String
    let team: String
    let championshipPosition: Int
    let points: Double
    let wins: Int
    let formScore: Int          // 0–100 based on recent results weighted
    let trackFitScore: Int      // 0–100 based on circuit characteristics vs driver traits
    let overallRating: Int      // combined ranking 0–100
    let momentumLabel: String   // "White hot", "Charging", "Stable", "Needs a reset"
    let recentForm: String      // "P1 · P3 · P5"
    let averageFinish: Double
}

struct RaceCallContext: Codable {
    let raceName: String
    let circuitName: String
    let country: String
    let date: String
    let round: Int
    let circuitProfile: CircuitProfileContext
    let weatherProfile: WeatherProfileContext
    let contenders: [ContenderProfile]
    let recentRaces: [RecentRaceContext]
    let confidenceLabel: String   // "High", "Medium", "Low"
    let chaosLabel: String        // "Low", "Medium", "High", "Extreme"
}

struct CircuitProfileContext: Codable {
    let speedClass: String
    let laps: Int
    let lengthKm: Double
    let turns: Int
    let drsZones: Int
    let overtaking: String
    let tyreStress: String
    let qualifyingImportance: String
    let reliabilityRisk: String
}

struct WeatherProfileContext: Codable {
    let headline: String
    let riskLabel: String
    let ambientTemperature: String
    let trackTemperature: String
    let rainChance: String
}

struct RecentRaceContext: Codable {
    let raceName: String
    let podium: [String]  // driver codes P1, P2, P3
}

// MARK: - Structured AI Output

struct RaceCallAPIResponse: Codable {
    let podium: PodiumPick
    let darkHorse: DarkHorsePick
    let biggestRisk: BiggestRisk
    let reasoning: String
    let flipScenario: String

    struct PodiumPick: Codable {
        let first: String
        let second: String
        let third: String
    }

    struct DarkHorsePick: Codable {
        let driver: String
        let why: String
    }

    struct BiggestRisk: Codable {
        let driver: String
        let why: String
    }
}

// MARK: - Race Call Result (stored locally)

struct RaceCall: Identifiable, Codable {
    let id: UUID
    let raceId: String
    let raceName: String
    let first: String
    let second: String
    let third: String
    let darkHorse: String
    let darkHorseWhy: String
    let biggestRisk: String
    let biggestRiskWhy: String
    let reasoning: String
    let flipScenario: String
    let confidenceLabel: String
    let chaosLabel: String
    let createdAt: Date
}

// Legacy compat — keep old type alias so nothing breaks elsewhere
typealias Prediction = RaceCall
