import Foundation

actor OpenF1Service {
    static let shared = OpenF1Service()

    private let openF1Base = "https://api.openf1.org/v1"
    private let jolpicaBase = "https://api.jolpi.ca/ergast/f1"
    private let decoder = JSONDecoder()

    func fetchDrivers(sessionKey: String = "latest") async throws -> [Driver] {
        let url = URL(string: "\(openF1Base)/drivers?session_key=\(sessionKey)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let drivers = try decoder.decode([Driver].self, from: data)
        var seen = Set<Int>()
        return drivers.filter { seen.insert($0.driverNumber).inserted }
    }

    func resolveDriver(for driver: Driver) async throws -> Driver {
        guard driver.driverNumber == 0 || driver.headshotUrl == nil || driver.countryCode.isEmpty else {
            return driver
        }

        let drivers = try await fetchDrivers()
        return drivers.first(where: {
            $0.nameAcronym.uppercased() == driver.nameAcronym.uppercased()
                || $0.matches(code: driver.nameAcronym, fullName: driver.fullName)
                || ($0.teamName == driver.teamName && $0.fullName.lowercased() == driver.fullName.lowercased())
        }) ?? driver
    }

    struct DriverPosition: Codable {
        let position: Int
        let driverNumber: Int
        let date: String

        enum CodingKeys: String, CodingKey {
            case position
            case driverNumber = "driver_number"
            case date
        }
    }

    func fetchDriverPositions(driverNumber: Int) async throws -> [DriverPosition] {
        let url = URL(string: "\(openF1Base)/positions?driver_number=\(driverNumber)&session_key=latest")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try decoder.decode([DriverPosition].self, from: data)
    }

    func fetchRaceResults(round: Int) async throws -> [RaceResult] {
        let url = URL(string: "\(jolpicaBase)/current/\(round)/results.json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try decoder.decode(JolpicaRaceResponse.self, from: data)
        guard let jolpicaRace = response.MRData.RaceTable.Races.first else {
            throw F1Error.noData
        }
        return mapRaceResults(jolpicaRace.Results ?? [])
    }

    func fetchCurrentSchedule() async throws -> [Race] {
        let url = URL(string: "\(jolpicaBase)/current.json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try decoder.decode(JolpicaRaceResponse.self, from: data)
        return response.MRData.RaceTable.Races.map(mapRace)
    }

    func fetchLastRaceResults() async throws -> (Race, [RaceResult]) {
        let url = URL(string: "\(jolpicaBase)/current/last/results.json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try decoder.decode(JolpicaRaceResponse.self, from: data)
        guard let jolpicaRace = response.MRData.RaceTable.Races.first else {
            throw F1Error.noData
        }
        return (mapRace(jolpicaRace), mapRaceResults(jolpicaRace.Results ?? []))
    }

    func fetchRecentCompletedRaces(limit: Int = 3) async throws -> [(Race, [RaceResult])] {
        let schedule = try await fetchCurrentSchedule()
        let completed = schedule.filter { $0.isPast }
            .sorted { $0.round > $1.round }
            .prefix(limit)

        // Fetch all race results concurrently instead of serially.
        return try await withThrowingTaskGroup(of: (Int, Race, [RaceResult]).self) { group in
            for race in completed {
                group.addTask { [race] in
                    let results = try await self.fetchRaceResults(round: race.round)
                    return (race.round, race, results)
                }
            }
            var payload: [(Int, Race, [RaceResult])] = []
            for try await entry in group {
                payload.append(entry)
            }
            // Restore descending-round order after concurrent collection.
            return payload.sorted { $0.0 > $1.0 }.map { ($0.1, $0.2) }
        }
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

    func fetchDriverResults(driverId: String) async throws -> [DriverRaceResult] {
        let url = URL(string: "\(jolpicaBase)/current/drivers/\(driverId)/results.json?limit=10")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try decoder.decode(JolpicaRaceResponse.self, from: data)
        let races = response.MRData.RaceTable.Races
        guard !races.isEmpty else {
            throw F1Error.noData
        }
        return races.compactMap { race -> DriverRaceResult? in
            guard let result = race.Results?.first else { return nil }
            return DriverRaceResult(
                id: "\(race.round)-\(result.Driver.driverId)",
                race: mapRace(race),
                position: Int(result.position) ?? 0,
                points: Double(result.points) ?? 0,
                status: result.status
            )
        }
    }

    func findDriverId(for driver: Driver) async throws -> String? {
        let standings = try await fetchDriverStandings()

        // Primary: exact acronym match (e.g. "VER" == "VER").
        if let match = standings.first(where: { $0.driverCode == driver.nameAcronym }) {
            return match.id
        }

        // Fallback: check whether the driver's full name contains the standing's family name.
        let fullNameLower = driver.fullName.lowercased()
        let fallback = standings.first { standing in
            let familyName = standing.driverName.split(separator: " ").last?.lowercased() ?? ""
            return !familyName.isEmpty && fullNameLower.contains(familyName)
        }
        return fallback?.id
    }

    func fetchConstructorResults(constructorId: String) async throws -> [TeamRaceResult] {
        let url = URL(string: "\(jolpicaBase)/current/constructors/\(constructorId)/results.json?limit=10")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try decoder.decode(JolpicaRaceResponse.self, from: data)
        let races = response.MRData.RaceTable.Races
        guard !races.isEmpty else {
            throw F1Error.noData
        }
        return races.flatMap { race in
            (race.Results ?? []).map { r in
                TeamRaceResult(
                    id: "\(race.round)-\(r.Driver.driverId)",
                    race: mapRace(race),
                    driverCode: r.Driver.code ?? String(r.Driver.familyName.prefix(3)).uppercased(),
                    position: Int(r.position) ?? 0,
                    points: Double(r.points) ?? 0,
                    status: r.status
                )
            }
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

    nonisolated func buildTrends(from standings: [DriverStanding], recentRaces: [(Race, [RaceResult])], limit: Int = 5) -> [DriverTrend] {
        let raceResultSets = recentRaces.map { $0.1 }
        return standings.prefix(limit).map { standing in
            let results = raceResultSets.compactMap { raceResults in
                raceResults.first(where: { $0.driverCode == standing.driverCode || $0.driverName == standing.driverName })
            }

            // Momentum score: weight recent races more heavily (offset 0 = 3×, offset 1 = 2×, offset 2+ = 1×).
            // A finish in position P contributes max(0, 12 - P) so winners score highest.
            // Championship wins are added as a flat bonus for title pedigree.
            let score = results.enumerated().reduce(0) { partial, item in
                let weight = max(1, 4 - item.offset)
                let resultScore = max(0, 12 - item.element.position)
                return partial + weight * resultScore
            } + standing.wins

            return DriverTrend(
                id: standing.id,
                driverName: standing.driverName,
                driverCode: standing.driverCode,
                constructorName: standing.constructorName,
                currentPosition: standing.position,
                currentPoints: standing.points,
                recentResults: results,
                trendScore: score
            )
        }
        .sorted { lhs, rhs in
            if lhs.trendScore == rhs.trendScore {
                return lhs.currentPosition < rhs.currentPosition
            }
            return lhs.trendScore > rhs.trendScore
        }
    }

    private func mapRace(_ jolpicaRace: JolpicaRace) -> Race {
        Race(
            id: jolpicaRace.round,
            raceName: jolpicaRace.raceName,
            circuitName: jolpicaRace.Circuit.circuitName,
            country: jolpicaRace.Circuit.Location.country,
            date: jolpicaRace.date,
            round: Int(jolpicaRace.round) ?? 0
        )
    }

    private func mapRaceResults(_ results: [JolpicaResult]) -> [RaceResult] {
        results.map { r in
            RaceResult(
                id: "\(r.position)-\(r.Driver.driverId)",
                position: Int(r.position) ?? 0,
                driverName: "\(r.Driver.givenName) \(r.Driver.familyName)",
                driverCode: r.Driver.code ?? String(r.Driver.familyName.prefix(3)).uppercased(),
                constructor: r.Constructor.name,
                points: Double(r.points) ?? 0,
                status: r.status
            )
        }
    }
}

struct DriverStanding: Identifiable, Codable, Hashable {
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
