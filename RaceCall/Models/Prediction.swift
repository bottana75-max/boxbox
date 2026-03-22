import Foundation

// MARK: - Weekend Phase

enum WeekendPhase: String, Codable, CaseIterable {
    case baseline = "Baseline"
    case postPractice = "Post-Practice"
    case postQualifying = "Post-Qualifying"
    case raceReady = "Race Ready"

    var shortLabel: String { rawValue }

    var description: String {
        switch self {
        case .baseline: return "Pre-weekend — using championship form and historical data only."
        case .postPractice: return "Practice data available — long-run pace and tyre behaviour visible."
        case .postQualifying: return "Grid is set — qualifying pace and grid positions confirmed."
        case .raceReady: return "All weekend data in — final conditions and grid locked."
        }
    }

    var icon: String {
        switch self {
        case .baseline: return "chart.bar"
        case .postPractice: return "gauge.with.dots.needle.33percent"
        case .postQualifying: return "flag.checkered"
        case .raceReady: return "light.beacon.max"
        }
    }
}

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
    let weekendPaceScore: Int   // 0–100 based on practice/qualifying when available
    let overallRating: Int      // combined ranking 0–100
    let momentumLabel: String   // "White hot", "Charging", "Stable", "Needs a reset"
    let recentForm: String      // "P1 · P3 · P5"
    let averageFinish: Double
    let gridPosition: Int?      // nil if qualifying hasn't happened
    let edgeNarrative: String   // V2.3: one-line explanation of why this contender is ranked here
}

struct RaceCallContext: Codable {
    let raceName: String
    let circuitName: String
    let country: String
    let date: String
    let round: Int
    let weekendPhase: String
    let phaseDescription: String
    let circuitProfile: CircuitProfileContext
    let weatherProfile: WeatherProfileContext
    let liveWeather: LiveWeatherContext?
    let sessionContext: SessionContext
    let weekendPace: WeekendPaceContext
    let contenders: [ContenderProfile]
    let comparisonBoard: [ContenderComparisonContext]
    let weekendScenarios: WeekendScenarioContext
    let recentRaces: [RecentRaceContext]
    let confidenceLabel: String   // "High", "Medium", "Low"
    let chaosLabel: String        // "Low", "Medium", "High", "Extreme"
    let confidenceScore: Int      // 0–10 numeric
    let chaosScore: Int           // 0–10 numeric
}

struct ContenderComparisonContext: Codable {
    let leader: String
    let challenger: String
    let overallGap: Int
    let leaderEdge: String
    let challengerPath: String
    let verdict: String
}

struct WeekendScenarioContext: Codable {
    let poleConversion: String
    let frontRowMiss: String
    let tyreStressSwing: String
    let weatherSwing: String
    let strategyVolatility: String
    let safetyCarWindow: String
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

struct LiveWeatherContext: Codable {
    let airTemp: Double?
    let trackTemp: Double?
    let humidity: Double?
    let rainfall: Bool?
    let windSpeed: Double?
    let windDirection: Int?
    let source: String  // "OpenF1 live" or "seasonal estimate"
}

struct SessionContext: Codable {
    let availableSessions: [String]
    let lastCompletedSession: String?
    let sessionCount: Int
    let source: String
}

struct WeekendPaceContext: Codable {
    let headline: String
    let longRunBias: String
    let firstStintShape: String
    let gridPressure: String
    let tyreStrategy: TyreStrategyContext
}

struct TyreStrategyContext: Codable {
    let expectedStints: Int          // 1-stop, 2-stop, 3-stop baseline
    let degradationSeverity: String  // "Low", "Medium", "High", "Extreme"
    let likelyCompounds: String      // e.g. "Medium → Hard" or "Soft → Medium → Hard"
    let undercutPotency: String      // "Strong", "Moderate", "Weak"
    let overcutViable: Bool
    let safetyCarLikelihood: String  // "Low", "Medium", "High" based on circuit history
    let pitWindowNarrative: String   // one-line about when pit action peaks
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
    let keyBattle: KeyBattle
    let strategyAngle: String
    let tyreCall: String
    let pitWallNote: String
    let reasoning: String
    let flipScenario: String
    let winnerEdge: String                         // V2.3: why P1 beats P2 — specific, concrete
    let weekendScenarios: [WeekendScenarioResult]  // V2.3: 2-3 conditional outcomes

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

    struct KeyBattle: Codable {
        let drivers: [String]  // 2 driver names
        let narrative: String
    }
}

// V2.3: Weekend Scenario — conditional outcome based on a specific trigger
struct WeekendScenarioResult: Codable {
    let trigger: String      // e.g. "Rain in stint 2", "Safety car before lap 15", "Clean qualifying for VER"
    let outcome: String      // e.g. "Verstappen wins by 8+ seconds — tyre advantage compounds in the wet"
    let likelihood: String   // "Low", "Medium", "High"
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
    let keyBattleDrivers: [String]
    let keyBattleNarrative: String
    let strategyAngle: String
    let tyreCall: String
    let pitWallNote: String
    let reasoning: String
    let flipScenario: String
    let winnerEdge: String                          // V2.3: why P1 beats P2
    let weekendScenarios: [WeekendScenarioResult]   // V2.3: conditional outcomes
    let confidenceLabel: String
    let chaosLabel: String
    let confidenceScore: Int     // 0–10 numeric for granularity
    let chaosScore: Int          // 0–10 numeric for granularity
    let weekendPhase: String
    let createdAt: Date
}

// Legacy compat — keep old type alias so nothing breaks elsewhere
typealias Prediction = RaceCall
