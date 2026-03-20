import Foundation

@MainActor
class ReplayService {
    static let shared = ReplayService()

    private let baseURL = "https://api.openf1.org/v1"
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    // MARK: - API Response Types

    private struct LocationResponse: Decodable {
        let date: String
        let x: Double
        let y: Double
        let driverNumber: Int

        enum CodingKeys: String, CodingKey {
            case date, x, y
            case driverNumber = "driver_number"
        }
    }

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

    // MARK: - Date Parsing

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func parseDate(_ string: String) -> Date? {
        Self.isoFormatter.date(from: string) ?? Self.isoFormatterNoFrac.date(from: string)
    }

    // MARK: - Public API

    func fetchAvailableSessions() async throws -> [ReplaySession] {
        let url = URL(string: "\(baseURL)/sessions?year=2025&session_name=Race")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let sessions = try decoder.decode([SessionResponse].self, from: data)

        let now = Date()
        return sessions.compactMap { s in
            guard let date = parseDate(s.dateStart), date < now else { return nil }
            return ReplaySession(
                sessionKey: s.sessionKey,
                raceName: "\(s.countryName) Grand Prix",
                circuitName: s.circuitShortName,
                date: date
            )
        }
    }

    func fetchDrivers(sessionKey: Int) async throws -> [ReplayDriver] {
        let url = URL(string: "\(baseURL)/drivers?session_key=\(sessionKey)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let responses = try decoder.decode([DriverResponse].self, from: data)

        var seen = Set<Int>()
        return responses.compactMap { d in
            guard seen.insert(d.driverNumber).inserted else { return nil }
            return ReplayDriver(
                driverNumber: d.driverNumber,
                fullName: d.fullName,
                nameAcronym: d.nameAcronym,
                teamName: d.teamName,
                teamColour: d.teamColour ?? "FFFFFF"
            )
        }
    }

    func fetchLocationData(sessionKey: Int, driverNumbers: [Int]) async throws -> [Int: [LocationPoint]] {
        var result: [Int: [LocationPoint]] = [:]
        let maxPoints = 5000

        for num in driverNumbers {
            let url = URL(string: "\(baseURL)/location?session_key=\(sessionKey)&driver_number=\(num)")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let responses = try decoder.decode([LocationResponse].self, from: data)

            var points = responses.compactMap { r -> LocationPoint? in
                guard let date = parseDate(r.date) else { return nil }
                return LocationPoint(date: date, x: r.x, y: r.y)
            }

            // Subsample if too many points
            if points.count > maxPoints {
                let step = points.count / maxPoints
                points = stride(from: 0, to: points.count, by: step).map { points[$0] }
            }

            result[num] = points
        }

        return result
    }

    func fetchPositionData(sessionKey: Int) async throws -> [Int: [PositionPoint]] {
        let url = URL(string: "\(baseURL)/position?session_key=\(sessionKey)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let responses = try decoder.decode([PositionResponse].self, from: data)

        var result: [Int: [PositionPoint]] = [:]
        for r in responses {
            guard let date = parseDate(r.date) else { continue }
            let point = PositionPoint(date: date, position: r.position)
            result[r.driverNumber, default: []].append(point)
        }

        return result
    }
}
