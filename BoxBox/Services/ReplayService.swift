import Foundation

@MainActor
class ReplayService {
    static let shared = ReplayService()

    private let baseURL = "https://api.openf1.org/v1"
    private let decoder = JSONDecoder()

    private struct PositionResponse: Decodable {
        let date: String
        let position: Int
        let driverNumber: Int

        enum CodingKeys: String, CodingKey {
            case date, position
            case driverNumber = "driver_number"
        }
    }

    private struct DriverResponse: Decodable {
        let driverNumber: Int
        let fullName: String
        let nameAcronym: String
        let teamName: String
        let teamColour: String?

        enum CodingKeys: String, CodingKey {
            case driverNumber = "driver_number"
            case fullName = "full_name"
            case nameAcronym = "name_acronym"
            case teamName = "team_name"
            case teamColour = "team_colour"
        }
    }

    private struct SessionResponse: Decodable {
        let sessionKey: Int
        let sessionName: String
        let circuitShortName: String
        let countryName: String
        let dateStart: String

        enum CodingKeys: String, CodingKey {
            case sessionKey = "session_key"
            case sessionName = "session_name"
            case circuitShortName = "circuit_short_name"
            case countryName = "country_name"
            case dateStart = "date_start"
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private func parseDate(_ string: String) -> Date? {
        Self.isoFormatter.date(from: string) ?? Self.isoFormatterNoFrac.date(from: string)
    }

    func fetchReplay(for race: Race) async throws -> RaceReplayPayload {
        let sessionKey = try await fetchSessionKey(for: race)
        async let driversTask = fetchDrivers(sessionKey: sessionKey)
        async let positionsTask = fetchPositionData(sessionKey: sessionKey)

        let drivers = try await driversTask
        let positions = try await positionsTask
        let snapshots = buildSnapshots(drivers: drivers, positionData: positions)

        guard let last = snapshots.last else {
            throw F1Error.noData
        }

        return RaceReplayPayload(
            drivers: drivers,
            snapshots: snapshots,
            totalDuration: last.elapsedTime
        )
    }

    private func fetchSessionKey(for race: Race) async throws -> Int {
        let year = race.seasonYear
        let url = URL(string: "\(baseURL)/sessions?year=\(year)&session_name=Race")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let sessions = try decoder.decode([SessionResponse].self, from: data)

        let targetDate = race.raceDate ?? .distantPast
        let raceNameToken = race.raceWeekendTitle.lowercased()
        let countryToken = race.country.lowercased()
        let circuitToken = race.circuitName.lowercased()

        let bestMatch = sessions
            .compactMap { session -> (SessionResponse, Date)? in
                guard let date = parseDate(session.dateStart) else { return nil }
                return (session, date)
            }
            .sorted { abs($0.1.timeIntervalSince(targetDate)) < abs($1.1.timeIntervalSince(targetDate)) }
            .first { entry in
                let session = entry.0
                let haystack = "\(session.circuitShortName) \(session.countryName)".lowercased()
                return haystack.contains(countryToken) || haystack.contains(raceNameToken) || circuitToken.contains(session.circuitShortName.lowercased())
            }

        guard let sessionKey = bestMatch?.0.sessionKey else {
            throw F1Error.apiError("Replay not available for this race")
        }

        return sessionKey
    }

    private func fetchDrivers(sessionKey: Int) async throws -> [ReplayDriver] {
        let url = URL(string: "\(baseURL)/drivers?session_key=\(sessionKey)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let responses = try decoder.decode([DriverResponse].self, from: data)

        var seen = Set<Int>()
        return responses.compactMap { driver in
            guard seen.insert(driver.driverNumber).inserted else { return nil }
            return ReplayDriver(
                driverNumber: driver.driverNumber,
                fullName: driver.fullName,
                nameAcronym: driver.nameAcronym,
                teamName: driver.teamName,
                teamColour: driver.teamColour ?? F1Design.teamHex(for: driver.teamName)
            )
        }
    }

    private func fetchPositionData(sessionKey: Int) async throws -> [Int: [PositionPoint]] {
        let url = URL(string: "\(baseURL)/position?session_key=\(sessionKey)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let responses = try decoder.decode([PositionResponse].self, from: data)

        var result: [Int: [PositionPoint]] = [:]
        for response in responses {
            guard let date = parseDate(response.date) else { continue }
            result[response.driverNumber, default: []].append(PositionPoint(date: date, position: response.position))
        }

        for key in result.keys {
            result[key]?.sort { $0.date < $1.date }
        }

        return result
    }

    private func buildSnapshots(drivers: [ReplayDriver], positionData: [Int: [PositionPoint]]) -> [ReplaySnapshot] {
        let allTimestamps = positionData.values
            .flatMap { $0.map(\.date) }
            .sorted()

        guard let start = allTimestamps.first, !allTimestamps.isEmpty else { return [] }

        let step = max(1, allTimestamps.count / 90)
        let sampledTimes = stride(from: 0, to: allTimestamps.count, by: step).map { allTimestamps[$0] }
        let finalTimes = sampledTimes.last == allTimestamps.last ? sampledTimes : sampledTimes + [allTimestamps.last!]

        let driversByNumber = Dictionary(uniqueKeysWithValues: drivers.map { ($0.driverNumber, $0) })
        var previousRanks: [Int: Int] = [:]

        return finalTimes.enumerated().compactMap { index, timestamp in
            var currentRanks: [Int: Int] = [:]

            for (driverNumber, points) in positionData {
                if let rank = latestPosition(in: points, at: timestamp) {
                    currentRanks[driverNumber] = rank
                }
            }

            let standings = currentRanks
                .sorted { lhs, rhs in lhs.value < rhs.value }
                .compactMap { driverNumber, rank -> ReplayStandingEntry? in
                    guard let driver = driversByNumber[driverNumber] else { return nil }
                    let previous = previousRanks[driverNumber] ?? rank
                    return ReplayStandingEntry(driver: driver, position: rank, delta: previous - rank)
                }

            guard !standings.isEmpty else { return nil }

            let headline = headlineForSnapshot(index: index, standings: standings, previousRanks: previousRanks)
            previousRanks = currentRanks

            return ReplaySnapshot(
                index: index,
                timestamp: timestamp,
                elapsedTime: timestamp.timeIntervalSince(start),
                standings: Array(standings.prefix(10)),
                headline: headline
            )
        }
    }

    private func latestPosition(in points: [PositionPoint], at time: Date) -> Int? {
        guard !points.isEmpty else { return nil }

        var low = 0
        var high = points.count - 1

        if time < points[0].date {
            return nil
        }

        while low < high {
            let mid = (low + high + 1) / 2
            if points[mid].date <= time {
                low = mid
            } else {
                high = mid - 1
            }
        }

        return points[low].position
    }

    private func headlineForSnapshot(index: Int, standings: [ReplayStandingEntry], previousRanks: [Int: Int]) -> String {
        guard let leader = standings.first else { return "Race settles into formation" }
        if index == 0 { return "Lights out: \(leader.driver.fullName) opens at the front" }

        if let previousLeaderNumber = previousRanks.min(by: { $0.value < $1.value })?.key,
           previousLeaderNumber != leader.driver.driverNumber,
           let previousLeaderRank = previousRanks[leader.driver.driverNumber],
           previousLeaderRank > 1 {
            return "Lead change: \(leader.driver.fullName) moves into P1"
        }

        if let biggestMover = standings.max(by: { abs($0.delta) < abs($1.delta) }), abs(biggestMover.delta) >= 2 {
            let direction = biggestMover.delta > 0 ? "up" : "back"
            return "\(biggestMover.driver.fullName) jumps \(abs(biggestMover.delta)) place\(abs(biggestMover.delta) == 1 ? "" : "s") \(direction) to P\(biggestMover.position)"
        }

        return "\(leader.driver.fullName) leads with the top 10 settling in"
    }
}
