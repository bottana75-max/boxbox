import Foundation

actor OpenF1Service {
    static let shared = OpenF1Service()

    private let openF1Base = "https://api.openf1.org/v1"
    private let jolpicaBase = "https://api.jolpi.ca/ergast/f1"
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    // MARK: - OpenF1 Endpoints

    func fetchDrivers(sessionKey: String = "latest") async throws -> [Driver] {
        let url = URL(string: "\(openF1Base)/drivers?session_key=\(sessionKey)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let drivers = try decoder.decode([Driver].self, from: data)
        // Deduplicate by driver number, keeping first occurrence
        var seen = Set<Int>()
        return drivers.filter { seen.insert($0.driverNumber).inserted }
    }

    // MARK: - Jolpica Endpoints

    func fetchCurrentSchedule() async throws -> [Race] {
        let url = URL(string: "\(jolpicaBase)/current.json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try decoder.decode(JolpicaRaceResponse.self, from: data)
        return response.MRData.RaceTable.Races.map { jolpicaRace in
            Race(
                id: jolpicaRace.round,
                raceName: jolpicaRace.raceName,
                circuitName: jolpicaRace.Circuit.circuitName,
                country: jolpicaRace.Circuit.Location.country,
                date: jolpicaRace.date,
                round: Int(jolpicaRace.round) ?? 0
            )
        }
    }

    func fetchLastRaceResults() async throws -> (Race, [RaceResult]) {
        let url = URL(string: "\(jolpicaBase)/current/last/results.json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try decoder.decode(JolpicaRaceResponse.self, from: data)
        guard let jolpicaRace = response.MRData.RaceTable.Races.first else {
            throw F1Error.noData
        }
        let race = Race(
            id: jolpicaRace.round,
            raceName: jolpicaRace.raceName,
            circuitName: jolpicaRace.Circuit.circuitName,
            country: jolpicaRace.Circuit.Location.country,
            date: jolpicaRace.date,
            round: Int(jolpicaRace.round) ?? 0
        )
        let results = (jolpicaRace.Results ?? []).map { r in
            RaceResult(
                id: "\(r.position)-\(r.Driver.driverId)",
                position: Int(r.position) ?? 0,
                driverName: "\(r.Driver.givenName) \(r.Driver.familyName)",
                driverCode: r.Driver.code ?? r.Driver.familyName.prefix(3).uppercased(),
                constructor: r.Constructor.name,
                points: Double(r.points) ?? 0,
                status: r.status
            )
        }
        return (race, results)
    }

    func fetchDriverStandings() async throws -> [DriverStanding] {
        let url = URL(string: "\(jolpicaBase)/current/driverStandings.json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try decoder.decode(StandingsResponse.self, from: data)
        guard let list = response.MRData.StandingsTable.StandingsLists.first,
              let standings = list.DriverStandings else {
            throw F1Error.noData
        }
        return standings.map { s in
            DriverStanding(
                id: s.Driver.driverId,
                position: Int(s.position) ?? 0,
                driverName: "\(s.Driver.givenName) \(s.Driver.familyName)",
                driverCode: s.Driver.code ?? s.Driver.familyName.prefix(3).uppercased(),
                constructorName: s.Constructors.first?.name ?? "Unknown",
                points: Double(s.points) ?? 0,
                wins: Int(s.wins) ?? 0
            )
        }
    }

    func fetchConstructorStandings() async throws -> [Constructor] {
        let url = URL(string: "\(jolpicaBase)/current/constructorStandings.json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try decoder.decode(StandingsResponse.self, from: data)
        guard let list = response.MRData.StandingsTable.StandingsLists.first,
              let standings = list.ConstructorStandings else {
            throw F1Error.noData
        }
        return standings.map { s in
            Constructor(
                id: s.Constructor.name.lowercased().replacingOccurrences(of: " ", with: "-"),
                name: s.Constructor.name,
                points: Double(s.points) ?? 0,
                position: Int(s.position) ?? 0,
                wins: Int(s.wins) ?? 0
            )
        }
    }
}

struct DriverStanding: Identifiable, Codable {
    let id: String
    let position: Int
    let driverName: String
    let driverCode: String
    let constructorName: String
    let points: Double
    let wins: Int
}

enum F1Error: LocalizedError {
    case noData
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noData: return "No data available"
        case .apiError(let msg): return msg
        }
    }
}
