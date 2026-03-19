import Foundation

struct Race: Identifiable, Codable, Hashable {
    let id: String
    let raceName: String
    let circuitName: String
    let country: String
    let date: String
    let round: Int

    var raceDate: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: date)
    }

    var isPast: Bool {
        guard let raceDate else { return false }
        return raceDate < Date()
    }

    var formattedDate: String {
        guard let raceDate else { return date }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: raceDate)
    }
}

struct RaceResult: Identifiable, Codable {
    let id: String
    let position: Int
    let driverName: String
    let driverCode: String
    let constructor: String
    let points: Double
    let status: String
}

// MARK: - Jolpica API Response Models

struct JolpicaRaceResponse: Codable {
    let MRData: MRData
}

struct MRData: Codable {
    let RaceTable: RaceTable
}

struct RaceTable: Codable {
    let Races: [JolpicaRace]
}

struct JolpicaRace: Codable {
    let round: String
    let raceName: String
    let Circuit: JolpicaCircuit
    let date: String
    let Results: [JolpicaResult]?
}

struct JolpicaCircuit: Codable {
    let circuitName: String
    let Location: JolpicaLocation
}

struct JolpicaLocation: Codable {
    let country: String
}

struct JolpicaResult: Codable {
    let position: String
    let Driver: JolpicaDriver
    let Constructor: JolpicaConstructor
    let points: String
    let status: String
}

struct JolpicaDriver: Codable {
    let driverId: String
    let code: String?
    let givenName: String
    let familyName: String
}

struct JolpicaConstructor: Codable {
    let name: String
}

// MARK: - Standings Response Models

struct StandingsResponse: Codable {
    let MRData: StandingsMRData
}

struct StandingsMRData: Codable {
    let StandingsTable: StandingsTable
}

struct StandingsTable: Codable {
    let StandingsLists: [StandingsList]
}

struct StandingsList: Codable {
    let DriverStandings: [JolpicaDriverStanding]?
    let ConstructorStandings: [JolpicaConstructorStanding]?
}

struct JolpicaDriverStanding: Codable {
    let position: String
    let points: String
    let wins: String
    let Driver: JolpicaDriver
    let Constructors: [JolpicaConstructor]
}

struct JolpicaConstructorStanding: Codable {
    let position: String
    let points: String
    let wins: String
    let Constructor: JolpicaConstructor
}
