import Foundation
import simd

@MainActor
final class ReplayService {
    static let shared = ReplayService()

    private let baseURL = "https://api.openf1.org/v1"
    private let decoder = JSONDecoder()
    private var sessionCache: [String: Int] = [:]
    private let freshnessWindow: TimeInterval = 4.5

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

    private struct LocationResponse: Decodable {
        let date: String
        let driverNumber: Int
        let x: Double
        let y: Double
        let z: Double

        enum CodingKeys: String, CodingKey {
            case date, x, y, z
            case driverNumber = "driver_number"
        }
    }

    private struct AxisBasis {
        let center: SIMD2<Double>
        let axis1: SIMD2<Double>
        let axis2: SIMD2<Double>
        let min1: Double
        let max1: Double
        let min2: Double
        let max2: Double

        var span1: Double { max(max1 - min1, 1) }
        var span2: Double { max(max2 - min2, 1) }
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

    nonisolated private func parseDate(_ string: String) -> Date? {
        Self.isoFormatter.date(from: string) ?? Self.isoFormatterNoFrac.date(from: string)
    }

    func fetchAvailableDrivers(for race: Race) async throws -> [ReplayDriver] {
        let sessionKey = try await fetchSessionKey(for: race)
        return try await fetchDrivers(sessionKey: sessionKey)
    }

    func fetchReplay(for race: Race, selectedDriverNumbers: [Int]) async throws -> RaceReplayPayload {
        guard race.isReplayEligible else {
            throw F1Error.apiError("Replay is only available after current-season races finish")
        }
        guard !selectedDriverNumbers.isEmpty else {
            throw F1Error.apiError("Choose at least one driver")
        }
        guard selectedDriverNumbers.count <= 5 else {
            throw F1Error.apiError("Replay can load up to 5 drivers at once")
        }

        let sessionKey = try await fetchSessionKey(for: race)
        async let driversTask = fetchDrivers(sessionKey: sessionKey)
        async let positionsTask = fetchPositionData(sessionKey: sessionKey)
        async let locationsTask = fetchLocationData(sessionKey: sessionKey, driverNumbers: selectedDriverNumbers)

        let drivers = try await driversTask
        let positionData = try await positionsTask
        let locationData = try await locationsTask

        let driversByNumber = Dictionary(uniqueKeysWithValues: drivers.map { ($0.driverNumber, $0) })
        let selectedDrivers = selectedDriverNumbers.compactMap { driversByNumber[$0] }
        guard !selectedDrivers.isEmpty else {
            throw F1Error.apiError("Selected drivers are not available for this race")
        }

        let snapshots = buildSnapshots(
            race: race,
            selectedDrivers: selectedDrivers,
            allDrivers: drivers,
            locationData: locationData,
            positionData: positionData
        )

        guard let last = snapshots.last else {
            throw F1Error.noData
        }

        let sampleCount = locationData.values.reduce(0) { $0 + $1.count }
        return RaceReplayPayload(
            availableDrivers: drivers,
            selectedDrivers: selectedDrivers,
            snapshots: snapshots,
            totalDuration: last.elapsedTime,
            projection: ReplayProjectionMetadata(
                loadedDriverCount: selectedDrivers.count,
                sampleCount: sampleCount,
                usesProjectedTrackFit: true,
                freshnessWindow: freshnessWindow
            )
        )
    }

    private func fetchSessionKey(for race: Race) async throws -> Int {
        if let cached = sessionCache[race.id] { return cached }

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
                let haystack = "\(entry.0.circuitShortName) \(entry.0.countryName) \(entry.0.sessionName)".lowercased()
                return haystack.contains(countryToken) || haystack.contains(raceNameToken) || circuitToken.contains(entry.0.circuitShortName.lowercased())
            }

        guard let sessionKey = bestMatch?.0.sessionKey else {
            throw F1Error.apiError("Replay not available for this race")
        }

        sessionCache[race.id] = sessionKey
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
        .sorted { lhs, rhs in
            if lhs.teamName == rhs.teamName { return lhs.fullName < rhs.fullName }
            return lhs.teamName < rhs.teamName
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

    private func fetchLocationData(sessionKey: Int, driverNumbers: [Int]) async throws -> [Int: [ReplayLocationPoint]] {
        try await withThrowingTaskGroup(of: (Int, [ReplayLocationPoint]).self) { group in
            for driverNumber in driverNumbers {
                group.addTask {
                    let url = URL(string: "\(self.baseURL)/location?session_key=\(sessionKey)&driver_number=\(driverNumber)")!
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let responses = try self.decoder.decode([LocationResponse].self, from: data)
                    let points = responses.compactMap { response -> ReplayLocationPoint? in
                        guard let date = self.parseDate(response.date) else { return nil }
                        return ReplayLocationPoint(date: date, x: response.x, y: response.y, z: response.z)
                    }
                    .sorted { $0.date < $1.date }
                    return (driverNumber, points)
                }
            }

            var result: [Int: [ReplayLocationPoint]] = [:]
            for try await (driverNumber, points) in group {
                result[driverNumber] = points
            }
            return result
        }
    }

    private func buildSnapshots(
        race: Race,
        selectedDrivers: [ReplayDriver],
        allDrivers: [ReplayDriver],
        locationData: [Int: [ReplayLocationPoint]],
        positionData: [Int: [PositionPoint]]
    ) -> [ReplaySnapshot] {
        let selectedNumbers = Set(selectedDrivers.map(\.driverNumber))
        let sourcePoints = selectedNumbers
            .compactMap { locationData[$0] }
            .flatMap { $0 }

        guard !sourcePoints.isEmpty else { return [] }

        let allTimes = sourcePoints.map(\.date).sorted()
        guard let start = allTimes.first, let end = allTimes.last else { return [] }

        let trackPoints = race.circuitInfo?.trackMapPoints ?? fallbackTrack(points: sourcePoints)
        let projector = makeProjector(source: sourcePoints, target: trackPoints)
        let driversByNumber = Dictionary(uniqueKeysWithValues: allDrivers.map { ($0.driverNumber, $0) })

        let totalDuration = end.timeIntervalSince(start)
        let interval: TimeInterval = totalDuration > 7_200 ? 3 : 2
        let snapshotCount = max(2, Int(ceil(totalDuration / interval)) + 1)

        return (0..<snapshotCount).compactMap { index in
            let timestamp = index == snapshotCount - 1 ? end : start.addingTimeInterval(Double(index) * interval)
            let markers = selectedDrivers.compactMap { driver -> ReplayMarker? in
                guard let points = locationData[driver.driverNumber],
                      let location = latestLocation(in: points, at: timestamp),
                      abs(timestamp.timeIntervalSince(location.date)) <= freshnessWindow,
                      let projected = projector(location)
                else { return nil }

                return ReplayMarker(
                    driver: driver,
                    runningPosition: latestPosition(in: positionData[driver.driverNumber] ?? [], at: timestamp),
                    projectedPoint: projected,
                    sourcePoint: location
                )
            }

            let standings = positionData
                .compactMap { driverNumber, points -> ReplayStandingEntry? in
                    guard let driver = driversByNumber[driverNumber],
                          let position = latestPosition(in: points, at: timestamp)
                    else { return nil }
                    return ReplayStandingEntry(driver: driver, position: position, isSelected: selectedNumbers.contains(driverNumber))
                }
                .sorted { lhs, rhs in lhs.position < rhs.position }

            guard !standings.isEmpty else { return nil }

            return ReplaySnapshot(
                index: index,
                timestamp: timestamp,
                elapsedTime: timestamp.timeIntervalSince(start),
                markers: markers,
                standings: Array(standings.prefix(10)),
                headline: headline(for: markers, standings: standings, selectedDrivers: selectedDrivers)
            )
        }
    }

    private func headline(for markers: [ReplayMarker], standings: [ReplayStandingEntry], selectedDrivers: [ReplayDriver]) -> String {
        if let leader = standings.first, selectedDrivers.contains(leader.driver) {
            return "\(leader.driver.fullName) is leading the race"
        }
        let selectedStandings = standings.filter(\.isSelected)
        if let bestSelected = selectedStandings.first {
            return "Tracking \(bestSelected.driver.fullName) in P\(bestSelected.position)"
        }
        if let marker = markers.first, let position = marker.runningPosition {
            return "\(marker.driver.fullName) currently P\(position)"
        }
        return "Selected driver locations shown only when OpenF1 has a fresh sample"
    }

    private func latestPosition(in points: [PositionPoint], at time: Date) -> Int? {
        guard !points.isEmpty, time >= points[0].date else { return nil }
        var low = 0
        var high = points.count - 1

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

    private func latestLocation(in points: [ReplayLocationPoint], at time: Date) -> ReplayLocationPoint? {
        guard !points.isEmpty, time >= points[0].date else { return nil }
        var low = 0
        var high = points.count - 1

        while low < high {
            let mid = (low + high + 1) / 2
            if points[mid].date <= time {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return points[low]
    }

    private func fallbackTrack(points: [ReplayLocationPoint]) -> [TrackMapPoint] {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return [] }
        let spanX = max(maxX - minX, 1)
        let spanY = max(maxY - minY, 1)
        return points.prefix(400).map {
            TrackMapPoint((($0.x - minX) / spanX) * 100, (($0.y - minY) / spanY) * 100)
        }
    }

    private func makeProjector(source: [ReplayLocationPoint], target: [TrackMapPoint]) -> ((ReplayLocationPoint) -> TrackMapPoint?) {
        let sourceVectors = source.map { SIMD2<Double>($0.x, $0.y) }
        let targetVectors = target.map { SIMD2<Double>($0.x, $0.y) }
        guard sourceVectors.count >= 3, targetVectors.count >= 3,
              let sourceBasis = makeBasis(for: sourceVectors),
              let targetBasis = makeBasis(for: targetVectors)
        else {
            return { _ in nil }
        }

        let options: [(swap: Bool, flip1: Bool, flip2: Bool)] = [
            (false, false, false), (false, false, true), (false, true, false), (false, true, true),
            (true, false, false), (true, false, true), (true, true, false), (true, true, true)
        ]

        let best = options.min { lhs, rhs in
            alignmentScore(option: lhs, source: sourceVectors, sourceBasis: sourceBasis, target: targetVectors, targetBasis: targetBasis)
                < alignmentScore(option: rhs, source: sourceVectors, sourceBasis: sourceBasis, target: targetVectors, targetBasis: targetBasis)
        } ?? (false, false, false)

        return { point in
            let vector = SIMD2<Double>(point.x, point.y)
            return self.project(vector: vector, option: best, sourceBasis: sourceBasis, targetBasis: targetBasis)
        }
    }

    private func alignmentScore(
        option: (swap: Bool, flip1: Bool, flip2: Bool),
        source: [SIMD2<Double>],
        sourceBasis: AxisBasis,
        target: [SIMD2<Double>],
        targetBasis: AxisBasis
    ) -> Double {
        let projected = source.compactMap { project(vector: $0, option: option, sourceBasis: sourceBasis, targetBasis: targetBasis) }
        guard !projected.isEmpty else { return .greatestFiniteMagnitude }
        let projectedVectors = projected.map { SIMD2<Double>($0.x, $0.y) }
        return target.reduce(0) { partial, point in
            let bestDistance = projectedVectors.map { simd_distance($0, point) }.min() ?? 1000
            return partial + bestDistance
        }
    }

    private func makeBasis(for points: [SIMD2<Double>]) -> AxisBasis? {
        guard !points.isEmpty else { return nil }
        let center = points.reduce(SIMD2<Double>(repeating: 0), +) / Double(points.count)
        let centered = points.map { $0 - center }

        let xx = centered.reduce(0.0) { $0 + ($1.x * $1.x) }
        let yy = centered.reduce(0.0) { $0 + ($1.y * $1.y) }
        let xy = centered.reduce(0.0) { $0 + ($1.x * $1.y) }
        let trace = xx + yy
        let determinant = xx * yy - xy * xy
        let root = sqrt(max(0, trace * trace / 4 - determinant))
        let lambda1 = trace / 2 + root

        var axis1 = SIMD2<Double>(xy, lambda1 - xx)
        if simd_length(axis1) < 0.0001 {
            axis1 = xx >= yy ? SIMD2<Double>(1, 0) : SIMD2<Double>(0, 1)
        }
        axis1 = simd_normalize(axis1)
        let axis2 = SIMD2<Double>(-axis1.y, axis1.x)

        let p1 = centered.map { simd_dot($0, axis1) }
        let p2 = centered.map { simd_dot($0, axis2) }
        guard let min1 = p1.min(), let max1 = p1.max(), let min2 = p2.min(), let max2 = p2.max() else { return nil }

        return AxisBasis(center: center, axis1: axis1, axis2: axis2, min1: min1, max1: max1, min2: min2, max2: max2)
    }

    private func project(
        vector: SIMD2<Double>,
        option: (swap: Bool, flip1: Bool, flip2: Bool),
        sourceBasis: AxisBasis,
        targetBasis: AxisBasis
    ) -> TrackMapPoint? {
        let centered = vector - sourceBasis.center
        var c1 = simd_dot(centered, sourceBasis.axis1)
        var c2 = simd_dot(centered, sourceBasis.axis2)

        c1 = ((c1 - sourceBasis.min1) / sourceBasis.span1) - 0.5
        c2 = ((c2 - sourceBasis.min2) / sourceBasis.span2) - 0.5

        if option.flip1 { c1 *= -1 }
        if option.flip2 { c2 *= -1 }
        if option.swap { swap(&c1, &c2) }

        let t1 = c1 * targetBasis.span1 + (targetBasis.min1 + targetBasis.max1) / 2
        let t2 = c2 * targetBasis.span2 + (targetBasis.min2 + targetBasis.max2) / 2
        let projected = targetBasis.center + targetBasis.axis1 * t1 + targetBasis.axis2 * t2

        return TrackMapPoint(min(max(projected.x, 0), 100), min(max(projected.y, 0), 100))
    }
}

private struct PositionPoint {
    let date: Date
    let position: Int
}
