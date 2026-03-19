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

    /// Circuit info from hardcoded data (laps, length in km)
    var circuitInfo: CircuitInfo? {
        CircuitInfo.lookup(circuitName: circuitName, country: country)
    }
}

struct CircuitInfo {
    let laps: Int
    let lengthKm: Double
    let city: String

    var formattedLength: String {
        String(format: "%.3f km", lengthKm)
    }

    private static let data: [(keywords: [String], city: String, laps: Int, lengthKm: Double)] = [
        (["Albert Park", "Australia"], "Melbourne", 58, 5.278),
        (["Shanghai", "China"], "Shanghai", 56, 5.451),
        (["Suzuka", "Japan"], "Suzuka", 53, 5.807),
        (["Bahrain", "Sakhir"], "Sakhir", 57, 5.412),
        (["Jeddah", "Saudi Arabia"], "Jeddah", 50, 6.174),
        (["Miami"], "Miami", 57, 5.412),
        (["Imola", "Emilia Romagna"], "Imola", 63, 4.909),
        (["Monaco"], "Monte Carlo", 78, 3.337),
        (["Catalunya", "Spain", "Barcelona"], "Barcelona", 66, 4.657),
        (["Montreal", "Canada", "Gilles Villeneuve"], "Montreal", 70, 4.361),
        (["Spielberg", "Austria", "Red Bull Ring"], "Spielberg", 71, 4.318),
        (["Silverstone", "Britain", "British"], "Silverstone", 52, 5.891),
        (["Budapest", "Hungary", "Hungaroring"], "Budapest", 70, 4.381),
        (["Spa", "Belgium"], "Stavelot", 44, 7.004),
        (["Zandvoort", "Netherlands", "Dutch"], "Zandvoort", 72, 4.259),
        (["Monza", "Italy", "Italian"], "Monza", 53, 5.793),
        (["Baku", "Azerbaijan"], "Baku", 51, 6.003),
        (["Marina Bay", "Singapore"], "Singapore", 62, 4.940),
        (["Austin", "COTA", "Americas"], "Austin", 56, 5.513),
        (["Mexico", "Hermanos"], "Mexico City", 71, 4.304),
        (["Interlagos", "Brazil", "São Paulo"], "São Paulo", 71, 4.309),
        (["Las Vegas"], "Las Vegas", 50, 6.201),
        (["Lusail", "Qatar"], "Lusail", 57, 5.380),
        (["Yas Marina", "Abu Dhabi"], "Abu Dhabi", 58, 5.281),
    ]

    static func lookup(circuitName: String, country: String) -> CircuitInfo? {
        let search = "\(circuitName) \(country)".lowercased()
        for entry in data {
            if entry.keywords.contains(where: { search.contains($0.lowercased()) }) {
                return CircuitInfo(laps: entry.laps, lengthKm: entry.lengthKm, city: entry.city)
            }
        }
        return nil
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

// MARK: - Driver Race Result (for DriverDetailView)

struct DriverRaceResult: Identifiable {
    let id: String
    let raceName: String
    let position: Int
    let points: Double
    let status: String

    var isDNF: Bool {
        status != "Finished" && !status.starts(with: "+")
    }

    /// Short race name (e.g. "Australian Grand Prix" → "Australia")
    var shortName: String {
        raceName
            .replacingOccurrences(of: " Grand Prix", with: "")
    }
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
