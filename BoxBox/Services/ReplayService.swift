import Foundation
import simd

actor ReplayService {
    static let shared = ReplayService()

    private let baseURL = "https://api.openf1.org/v1"
    private let decoder = JSONDecoder()
    private var sessionCache: [String: Int] = [:]
    private var driversCache: [Int: [ReplayDriver]] = [:]
    private var positionCache: [Int: [Int: [PositionPoint]]] = [:]
    private var lapCache: [Int: [Int: [LapPoint]]] = [:]
    private var locationCache: [ReplayLocationCacheKey: [ReplayLocationPoint]] = [:]
    private var replayPayloadCache: [ReplayRequestKey: RaceReplayPayload] = [:]
    private var inFlightReplays: [ReplayRequestKey: Task<RaceReplayPayload, Error>] = [:]
    private var inFlightDrivers: [Int: Task<[ReplayDriver], Error>] = [:]
    private var inFlightPositions: [Int: Task<[Int: [PositionPoint]], Error>] = [:]
    private var inFlightLaps: [Int: Task<[Int: [LapPoint]], Error>] = [:]
    private var inFlightLocations: [ReplayLocationCacheKey: Task<[ReplayLocationPoint], Error>] = [:]
    private let freshnessWindow: TimeInterval = 4.5
    private let retryBaseDelay: TimeInterval = 1.5
    private let maxRetryAttempts = 4
    private let interRequestSpacingNs: UInt64 = 250_000_000

    private struct APIErrorEnvelope: Decodable {
        let message: String?
        let error: String?
        let detail: String?
    }

    private struct ReplayRequestKey: Hashable {
        let raceID: String
        let sessionKey: Int
        let driverNumbers: [Int]
    }

    private struct ReplayLocationCacheKey: Hashable {
        let sessionKey: Int
        let driverNumber: Int
    }

    private struct ReplayRateLimitError: Error {
        let label: String
        let retryAfter: TimeInterval?
        let message: String
    }

    private struct PositionResponse: Decodable {
        let date: String
        let position: Int
        let driverNumber: Int

        enum CodingKeys: String, CodingKey {
            case date, position
            case driverNumber = "driver_number"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            date = try container.decode(String.self, forKey: .date)
            position = try Self.decodeInt(container, forKey: .position)
            driverNumber = try Self.decodeInt(container, forKey: .driverNumber)
        }

        private static func decodeInt(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Int {
            if let intValue = try? container.decode(Int.self, forKey: key) { return intValue }
            if let stringValue = try? container.decode(String.self, forKey: key), let intValue = Int(stringValue) { return intValue }
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Expected Int-compatible value")
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
        let x: Double?
        let y: Double?
        let z: Double?

        enum CodingKeys: String, CodingKey {
            case date, x, y, z
            case driverNumber = "driver_number"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            date = try container.decode(String.self, forKey: .date)
            driverNumber = try Self.decodeInt(container, forKey: .driverNumber)
            x = Self.decodeDoubleIfPresent(container, forKey: .x)
            y = Self.decodeDoubleIfPresent(container, forKey: .y)
            z = Self.decodeDoubleIfPresent(container, forKey: .z)
        }

        private static func decodeInt(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Int {
            if let intValue = try? container.decode(Int.self, forKey: key) { return intValue }
            if let stringValue = try? container.decode(String.self, forKey: key), let intValue = Int(stringValue) { return intValue }
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Expected Int-compatible value")
        }

        private static func decodeDoubleIfPresent(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Double? {
            if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
                return value
            }

            let intValue: Int?
            do {
                intValue = try container.decodeIfPresent(Int.self, forKey: key)
            } catch {
                intValue = nil
            }
            if let intValue {
                return Double(intValue)
            }

            let stringValue: String?
            do {
                stringValue = try container.decodeIfPresent(String.self, forKey: key)
            } catch {
                stringValue = nil
            }
            if let stringValue {
                return Double(stringValue)
            }

            return nil
        }
    }

    private struct LapResponse: Decodable {
        let dateStart: String?
        let driverNumber: Int
        let lapNumber: Int

        enum CodingKeys: String, CodingKey {
            case dateStart = "date_start"
            case driverNumber = "driver_number"
            case lapNumber = "lap_number"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            dateStart = try? container.decodeIfPresent(String.self, forKey: .dateStart)
            driverNumber = try Self.decodeInt(container, forKey: .driverNumber)
            lapNumber = try Self.decodeInt(container, forKey: .lapNumber)
        }

        private static func decodeInt(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Int {
            if let intValue = try? container.decode(Int.self, forKey: key) { return intValue }
            if let stringValue = try? container.decode(String.self, forKey: key), let intValue = Int(stringValue) { return intValue }
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Expected Int-compatible value")
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

    private struct AffineTransform2D {
        let a: Double, b: Double
        let c: Double, d: Double
        let tx: Double, ty: Double

        static let identity = AffineTransform2D(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

        func apply(_ p: SIMD2<Double>) -> SIMD2<Double> {
            SIMD2<Double>(a * p.x + b * p.y + tx, c * p.x + d * p.y + ty)
        }

        func compose(with other: AffineTransform2D) -> AffineTransform2D {
            AffineTransform2D(
                a: a * other.a + b * other.c,
                b: a * other.b + b * other.d,
                c: c * other.a + d * other.c,
                d: c * other.b + d * other.d,
                tx: a * other.tx + b * other.ty + tx,
                ty: c * other.tx + d * other.ty + ty
            )
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

    private func retryAfterInterval(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if let seconds = TimeInterval(value) {
            return max(0, seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        if let date = formatter.date(from: value) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }

    private func fetchData(from url: URL, label: String) async throws -> Data {
        var attempt = 0

        while true {
            try Task.checkCancellation()
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse else {
                    throw F1Error.apiError("Replay \(label) failed: invalid server response")
                }

                if http.statusCode == 429 {
                    let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data)
                    let message = envelope?.message ?? envelope?.error ?? envelope?.detail ?? "Too many requests from OpenF1"
                    throw ReplayRateLimitError(label: label, retryAfter: retryAfterInterval(from: http), message: message)
                }

                guard (200...299).contains(http.statusCode) else {
                    let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data)
                    let message = envelope?.message ?? envelope?.error ?? envelope?.detail ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                    throw F1Error.apiError("Replay \(label) failed (\(http.statusCode)): \(message)")
                }

                return data
            } catch let error as ReplayRateLimitError {
                guard attempt < maxRetryAttempts else {
                    let waitText = error.retryAfter.map { String(format: "%.1f", $0) } ?? "a few"
                    throw F1Error.apiError("Replay \(error.label) is being rate-limited by OpenF1. Retried \(maxRetryAttempts + 1)x, last wait \(waitText)s.")
                }

                let retryDelay = max(error.retryAfter ?? 0, retryBaseDelay * pow(2, Double(attempt)))
                let cappedDelay = min(retryDelay, 20)
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(cappedDelay * 1_000_000_000))
            } catch {
                throw error
            }
        }
    }

    func fetchAvailableDrivers(for race: Race) async throws -> [ReplayDriver] {
        let sessionKey = try await fetchSessionKey(for: race)
        return try await fetchDrivers(sessionKey: sessionKey)
    }

    func fetchReplay(
        for race: Race,
        selectedDriverNumbers: [Int],
        statusUpdate: ((String) -> Void)? = nil
    ) async throws -> RaceReplayPayload {
        guard race.isReplayEligible else {
            throw F1Error.apiError("Replay is only available after current-season races finish")
        }
        guard !selectedDriverNumbers.isEmpty else {
            throw F1Error.apiError("Choose at least one driver")
        }
        guard selectedDriverNumbers.count <= 5 else {
            throw F1Error.apiError("Replay can load up to 5 drivers at once")
        }

        let orderedDrivers = selectedDriverNumbers.sorted()
        statusUpdate?("Matching this race to the correct OpenF1 session")
        let sessionKey = try await fetchSessionKey(for: race)
        let requestKey = ReplayRequestKey(raceID: race.id, sessionKey: sessionKey, driverNumbers: orderedDrivers)

        if let cached = replayPayloadCache[requestKey] {
            statusUpdate?("Using cached replay data")
            return cachedPayload(from: cached)
        }

        if let task = inFlightReplays[requestKey] {
            statusUpdate?("Replay already downloading — reusing the active request")
            return try await task.value
        }

        let task = Task<RaceReplayPayload, Error> {
            try await self.makeReplayPayload(
                race: race,
                sessionKey: sessionKey,
                orderedDrivers: orderedDrivers,
                statusUpdate: statusUpdate
            )
        }

        inFlightReplays[requestKey] = task
        do {
            let payload = try await task.value
            replayPayloadCache[requestKey] = payload
            inFlightReplays[requestKey] = nil
            return payload
        } catch {
            inFlightReplays[requestKey] = nil
            throw error
        }
    }

    private func cachedPayload(from payload: RaceReplayPayload) -> RaceReplayPayload {
        RaceReplayPayload(
            availableDrivers: payload.availableDrivers,
            selectedDrivers: payload.selectedDrivers,
            snapshots: payload.snapshots,
            lapAnchors: payload.lapAnchors,
            raceStartSnapshotIndex: payload.raceStartSnapshotIndex,
            totalDuration: payload.totalDuration,
            projection: ReplayProjectionMetadata(
                loadedDriverCount: payload.projection.loadedDriverCount,
                sampleCount: payload.projection.sampleCount,
                usesProjectedTrackFit: payload.projection.usesProjectedTrackFit,
                freshnessWindow: payload.projection.freshnessWindow,
                isCached: true
            )
        )
    }

    private func makeReplayPayload(
        race: Race,
        sessionKey: Int,
        orderedDrivers: [Int],
        statusUpdate: ((String) -> Void)?
    ) async throws -> RaceReplayPayload {
        statusUpdate?("Loading driver list and race timing")
        let drivers = try await fetchDrivers(sessionKey: sessionKey)
        let positionData = try await fetchPositionData(sessionKey: sessionKey)
        let lapData = try await fetchLapData(sessionKey: sessionKey)

        statusUpdate?(orderedDrivers.count == 1 ? "Downloading telemetry for 1 selected driver" : "Downloading telemetry for \(orderedDrivers.count) selected drivers with rate-limit protection")
        let locationData = try await fetchLocationData(sessionKey: sessionKey, driverNumbers: orderedDrivers)

        let driversByNumber = Dictionary(uniqueKeysWithValues: drivers.map { ($0.driverNumber, $0) })
        let selectedDrivers = orderedDrivers.compactMap { driversByNumber[$0] }
        guard !selectedDrivers.isEmpty else {
            throw F1Error.apiError("Selected drivers are not available for this race")
        }

        statusUpdate?("Building replay timeline")
        let timeline = buildSnapshots(
            race: race,
            selectedDrivers: selectedDrivers,
            allDrivers: drivers,
            locationData: locationData,
            positionData: positionData,
            lapData: lapData
        )

        guard let last = timeline.snapshots.last else {
            throw F1Error.noData
        }

        let sampleCount = locationData.values.reduce(0) { $0 + $1.count }
        return RaceReplayPayload(
            availableDrivers: drivers,
            selectedDrivers: selectedDrivers,
            snapshots: timeline.snapshots,
            lapAnchors: timeline.lapAnchors,
            raceStartSnapshotIndex: timeline.raceStartSnapshotIndex,
            totalDuration: last.elapsedTime,
            projection: ReplayProjectionMetadata(
                loadedDriverCount: selectedDrivers.count,
                sampleCount: sampleCount,
                usesProjectedTrackFit: true,
                freshnessWindow: freshnessWindow,
                isCached: false
            )
        )
    }

    private func fetchSessionKey(for race: Race) async throws -> Int {
        if let cached = sessionCache[race.id] { return cached }

        let year = race.seasonYear
        let url = URL(string: "\(baseURL)/sessions?year=\(year)&session_name=Race")!
        let data = try await fetchData(from: url, label: "sessions")
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
        if let cached = driversCache[sessionKey] { return cached }
        if let task = inFlightDrivers[sessionKey] { return try await task.value }

        let task = Task<[ReplayDriver], Error> {
            let url = URL(string: "\(baseURL)/drivers?session_key=\(sessionKey)")!
            let data = try await self.fetchData(from: url, label: "drivers")
            let responses = try self.decoder.decode([DriverResponse].self, from: data)

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

        inFlightDrivers[sessionKey] = task
        do {
            let drivers = try await task.value
            driversCache[sessionKey] = drivers
            inFlightDrivers[sessionKey] = nil
            return drivers
        } catch {
            inFlightDrivers[sessionKey] = nil
            throw error
        }
    }

    private func fetchPositionData(sessionKey: Int) async throws -> [Int: [PositionPoint]] {
        if let cached = positionCache[sessionKey] { return cached }
        if let task = inFlightPositions[sessionKey] { return try await task.value }

        let task = Task<[Int: [PositionPoint]], Error> {
            let url = URL(string: "\(baseURL)/position?session_key=\(sessionKey)")!
            let data = try await self.fetchData(from: url, label: "positions")
            let responses = try self.decoder.decode([PositionResponse].self, from: data)

            var result: [Int: [PositionPoint]] = [:]
            for response in responses {
                guard let date = self.parseDate(response.date) else { continue }
                result[response.driverNumber, default: []].append(PositionPoint(date: date, position: response.position))
            }

            for key in result.keys {
                result[key]?.sort { $0.date < $1.date }
            }
            return result
        }

        inFlightPositions[sessionKey] = task
        do {
            let positions = try await task.value
            positionCache[sessionKey] = positions
            inFlightPositions[sessionKey] = nil
            return positions
        } catch {
            inFlightPositions[sessionKey] = nil
            throw error
        }
    }

    private func fetchLocationData(sessionKey: Int, driverNumbers: [Int]) async throws -> [Int: [ReplayLocationPoint]] {
        var result: [Int: [ReplayLocationPoint]] = [:]
        for (index, driverNumber) in driverNumbers.enumerated() {
            if index > 0 {
                try await Task.sleep(nanoseconds: interRequestSpacingNs)
            }
            result[driverNumber] = try await fetchLocationData(sessionKey: sessionKey, driverNumber: driverNumber)
        }
        return result
    }

    private func fetchLocationData(sessionKey: Int, driverNumber: Int) async throws -> [ReplayLocationPoint] {
        let cacheKey = ReplayLocationCacheKey(sessionKey: sessionKey, driverNumber: driverNumber)
        if let cached = locationCache[cacheKey] { return cached }
        if let task = inFlightLocations[cacheKey] { return try await task.value }

        let task = Task<[ReplayLocationPoint], Error> {
            let url = URL(string: "\(baseURL)/location?session_key=\(sessionKey)&driver_number=\(driverNumber)")!
            let data = try await self.fetchData(from: url, label: "location for #\(driverNumber)")
            let responses = try self.decoder.decode([LocationResponse].self, from: data)
            return responses.compactMap { response -> ReplayLocationPoint? in
                guard let date = self.parseDate(response.date),
                      let x = response.x,
                      let y = response.y
                else { return nil }
                return ReplayLocationPoint(date: date, x: x, y: y, z: response.z ?? 0)
            }
            .sorted { $0.date < $1.date }
        }

        inFlightLocations[cacheKey] = task
        do {
            let points = try await task.value
            locationCache[cacheKey] = points
            inFlightLocations[cacheKey] = nil
            return points
        } catch {
            inFlightLocations[cacheKey] = nil
            throw error
        }
    }

    private func fetchLapData(sessionKey: Int) async throws -> [Int: [LapPoint]] {
        if let cached = lapCache[sessionKey] { return cached }
        if let task = inFlightLaps[sessionKey] { return try await task.value }

        let task = Task<[Int: [LapPoint]], Error> {
            let url = URL(string: "\(baseURL)/laps?session_key=\(sessionKey)")!
            let data = try await self.fetchData(from: url, label: "laps")
            let responses = try self.decoder.decode([LapResponse].self, from: data)

            var result: [Int: [LapPoint]] = [:]
            for response in responses {
                guard let dateString = response.dateStart,
                      let date = self.parseDate(dateString),
                      response.lapNumber > 0
                else { continue }
                result[response.driverNumber, default: []].append(LapPoint(date: date, lapNumber: response.lapNumber))
            }

            for key in result.keys {
                result[key]?.sort { lhs, rhs in
                    if lhs.date == rhs.date { return lhs.lapNumber < rhs.lapNumber }
                    return lhs.date < rhs.date
                }
            }
            return result
        }

        inFlightLaps[sessionKey] = task
        do {
            let laps = try await task.value
            lapCache[sessionKey] = laps
            inFlightLaps[sessionKey] = nil
            return laps
        } catch {
            inFlightLaps[sessionKey] = nil
            throw error
        }
    }

    private func buildSnapshots(
        race: Race,
        selectedDrivers: [ReplayDriver],
        allDrivers: [ReplayDriver],
        locationData: [Int: [ReplayLocationPoint]],
        positionData: [Int: [PositionPoint]],
        lapData: [Int: [LapPoint]]
    ) -> ReplayTimeline {
        let selectedNumbers = Set(selectedDrivers.map(\.driverNumber))
        let sourcePoints = selectedNumbers
            .compactMap { locationData[$0] }
            .flatMap { $0 }

        guard !sourcePoints.isEmpty else {
            return ReplayTimeline(snapshots: [], lapAnchors: [], raceStartSnapshotIndex: 0)
        }

        let allTimes = sourcePoints.map(\.date).sorted()
        guard let rawStart = allTimes.first, let end = allTimes.last else {
            return ReplayTimeline(snapshots: [], lapAnchors: [], raceStartSnapshotIndex: 0)
        }

        let trackPoints = race.circuitInfo?.trackMapPoints ?? fallbackTrack(points: sourcePoints)
        let projector = makeProjector(source: sourcePoints, target: trackPoints)
        let driversByNumber = Dictionary(uniqueKeysWithValues: allDrivers.map { ($0.driverNumber, $0) })
        let rawLapTimeline = makeLapTimeline(from: lapData)
        let officialTotalLaps = race.circuitInfo?.laps
        let lapTimeline = remapLapTimeline(rawLapTimeline, officialTotalLaps: officialTotalLaps)
        let raceStart = inferredRaceStart(from: positionData, lapTimeline: lapTimeline) ?? rawStart
        let start = min(rawStart, raceStart)

        let totalDuration = end.timeIntervalSince(start)
        let interval: TimeInterval = totalDuration > 7_200 ? 3 : 2
        let snapshotCount = max(2, Int(ceil(totalDuration / interval)) + 1)

        let snapshots: [ReplaySnapshot] = (0..<snapshotCount).compactMap { index in
            let timestamp = index == snapshotCount - 1 ? end : start.addingTimeInterval(Double(index) * interval)
            let markers = selectedDrivers.compactMap { driver -> ReplayMarker? in
                guard let points = locationData[driver.driverNumber],
                      let location = interpolatedLocation(in: points, at: timestamp),
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
                lapNumber: currentLap(at: timestamp, timeline: lapTimeline),
                markers: markers,
                standings: Array(standings.prefix(10)),
                headline: headline(for: markers, standings: standings, selectedDrivers: selectedDrivers)
            )
        }

        guard !snapshots.isEmpty else {
            return ReplayTimeline(snapshots: [], lapAnchors: [], raceStartSnapshotIndex: 0)
        }

        let lapAnchors = makeLapAnchors(snapshots: snapshots, lapTimeline: lapTimeline)
        let raceStartDistances = snapshots.enumerated().map { index, snapshot in
            (index, abs(snapshot.timestamp.timeIntervalSince(raceStart)))
        }
        let raceStartSnapshotIndex = raceStartDistances.min(by: { $0.1 < $1.1 })?.0 ?? 0

        return ReplayTimeline(snapshots: snapshots, lapAnchors: lapAnchors, raceStartSnapshotIndex: raceStartSnapshotIndex)
    }

    private func inferredRaceStart(from positionData: [Int: [PositionPoint]], lapTimeline: [LapBoundary]) -> Date? {
        // Primary: use remapped lap 1 start (accounts for formation lap offset)
        if let lap1 = lapTimeline.first(where: { $0.lapNumber == 1 }) {
            return lap1.start
        }
        // Fallback: earliest position feed timestamp
        return positionData.values.compactMap { $0.first?.date }.min()
    }

    private func makeLapTimeline(from lapData: [Int: [LapPoint]]) -> [LapBoundary] {
        var grouped: [Int: [Date]] = [:]
        for points in lapData.values {
            for point in points where point.lapNumber > 0 {
                grouped[point.lapNumber, default: []].append(point.date)
            }
        }

        return grouped.keys.sorted().compactMap { lap in
            guard let dates = grouped[lap], !dates.isEmpty else { return nil }
            let sorted = dates.sorted()
            let anchor = sorted[min(sorted.count / 3, sorted.count - 1)]
            return LapBoundary(lapNumber: lap, start: anchor)
        }
    }

    /// Remap raw OpenF1 lap numbers using the official total lap count.
    /// OpenF1 often reports lap 1 as the formation/grid lap, so the real racing
    /// lap 1 is actually data-lap 2. We use the official total and work backwards
    /// from the last observed lap to compute the offset.
    private func remapLapTimeline(_ raw: [LapBoundary], officialTotalLaps: Int?) -> [LapBoundary] {
        guard let officialTotal = officialTotalLaps,
              officialTotal > 0,
              let maxObserved = raw.last?.lapNumber,
              maxObserved > officialTotal
        else {
            return raw
        }

        let offset = maxObserved - officialTotal
        return raw.compactMap { boundary in
            let remapped = boundary.lapNumber - offset
            guard remapped >= 1 else { return nil }
            return LapBoundary(lapNumber: remapped, start: boundary.start)
        }
    }

    private func currentLap(at time: Date, timeline: [LapBoundary]) -> Int? {
        guard !timeline.isEmpty else { return nil }
        let candidates = timeline.filter { $0.start <= time }
        return candidates.last?.lapNumber ?? timeline.first?.lapNumber
    }

    private func makeLapAnchors(snapshots: [ReplaySnapshot], lapTimeline: [LapBoundary]) -> [ReplayLapAnchor] {
        guard !snapshots.isEmpty else { return [] }
        return lapTimeline.compactMap { lap in
            guard let best = snapshots.enumerated().min(by: {
                abs($0.element.timestamp.timeIntervalSince(lap.start)) < abs($1.element.timestamp.timeIntervalSince(lap.start))
            }) else { return nil }
            return ReplayLapAnchor(lapNumber: lap.lapNumber, snapshotIndex: best.offset, elapsedTime: best.element.elapsedTime)
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

    /// Interpolate between the two telemetry samples bracketing the target time.
    /// Falls back to nearest-point if the gap is too large, and returns nil if
    /// no sample is within the freshness window.
    private func interpolatedLocation(in points: [ReplayLocationPoint], at time: Date) -> ReplayLocationPoint? {
        guard !points.isEmpty else { return nil }

        // Binary search for first point >= time
        var low = 0, high = points.count
        while low < high {
            let mid = (low + high) / 2
            if points[mid].date < time { low = mid + 1 } else { high = mid }
        }

        // Exact or near-exact match
        if low < points.count && abs(points[low].date.timeIntervalSince(time)) < 0.05 {
            return points[low]
        }

        let hasBefore = low > 0
        let hasAfter = low < points.count

        // Only after-point available
        if !hasBefore {
            guard hasAfter, points[low].date.timeIntervalSince(time) <= freshnessWindow else { return nil }
            return points[low]
        }

        // Only before-point available
        if !hasAfter {
            let last = points[points.count - 1]
            return time.timeIntervalSince(last.date) <= freshnessWindow ? last : nil
        }

        let before = points[low - 1]
        let after = points[low]
        let gap = after.date.timeIntervalSince(before.date)

        // If the gap between samples is small enough, interpolate
        if gap > 0 && gap <= freshnessWindow * 2 {
            let t = time.timeIntervalSince(before.date) / gap
            return ReplayLocationPoint(
                date: time,
                x: before.x + (after.x - before.x) * t,
                y: before.y + (after.y - before.y) * t,
                z: before.z + (after.z - before.z) * t
            )
        }

        // Gap too large — use nearest within freshness
        let dBefore = time.timeIntervalSince(before.date)
        let dAfter = after.date.timeIntervalSince(time)
        if dBefore <= dAfter && dBefore <= freshnessWindow { return before }
        if dAfter <= freshnessWindow { return after }
        return nil
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

        // Subsample source for scoring — evenly spaced, up to 300 points
        let sourceSubsample = evenlySubsampled(sourceVectors, maxCount: 300)
        let targetSubsample = evenlySubsampled(targetVectors, maxCount: 300)

        let options: [(swap: Bool, flip1: Bool, flip2: Bool)] = [
            (false, false, false), (false, false, true), (false, true, false), (false, true, true),
            (true, false, false), (true, false, true), (true, true, false), (true, true, true)
        ]

        let best = options.min { lhs, rhs in
            alignmentScore(option: lhs, source: sourceSubsample, sourceBasis: sourceBasis, target: targetSubsample, targetBasis: targetBasis)
                < alignmentScore(option: rhs, source: sourceSubsample, sourceBasis: sourceBasis, target: targetSubsample, targetBasis: targetBasis)
        } ?? (false, false, false)

        // ICP refinement: iteratively improve alignment using Procrustes
        let correction = computeICPCorrection(
            source: sourceSubsample, option: best,
            sourceBasis: sourceBasis, targetBasis: targetBasis,
            target: targetSubsample, iterations: 4
        )

        return { point in
            let vector = SIMD2<Double>(point.x, point.y)
            guard let projected = self.project(vector: vector, option: best, sourceBasis: sourceBasis, targetBasis: targetBasis) else {
                return nil
            }
            let pv = SIMD2<Double>(projected.x, projected.y)
            let refined = correction.apply(pv)
            let clamped = TrackMapPoint(min(max(refined.x, 0), 100), min(max(refined.y, 0), 100))
            return self.snapToTrack(clamped, track: target)
        }
    }

    private func evenlySubsampled(_ points: [SIMD2<Double>], maxCount: Int) -> [SIMD2<Double>] {
        guard points.count > maxCount else { return points }
        let step = Double(points.count) / Double(maxCount)
        return (0..<maxCount).map { i in points[min(Int(Double(i) * step), points.count - 1)] }
    }

    private func computeICPCorrection(
        source: [SIMD2<Double>],
        option: (swap: Bool, flip1: Bool, flip2: Bool),
        sourceBasis: AxisBasis,
        targetBasis: AxisBasis,
        target: [SIMD2<Double>],
        iterations: Int
    ) -> AffineTransform2D {
        var projected = source.compactMap { v -> SIMD2<Double>? in
            guard let p = project(vector: v, option: option, sourceBasis: sourceBasis, targetBasis: targetBasis) else { return nil }
            return SIMD2<Double>(p.x, p.y)
        }
        guard projected.count >= 3 else { return .identity }

        var cumulative = AffineTransform2D.identity

        for _ in 0..<iterations {
            // Find correspondences: each projected → nearest target
            let pairs: [(SIMD2<Double>, SIMD2<Double>)] = projected.compactMap { p in
                guard let nearest = target.min(by: { simd_distance_squared($0, p) < simd_distance_squared($1, p) }) else { return nil }
                return (p, nearest)
            }
            guard pairs.count >= 3 else { break }

            // Centroids
            let meanP = pairs.reduce(SIMD2<Double>(0, 0)) { $0 + $1.0 } / Double(pairs.count)
            let meanT = pairs.reduce(SIMD2<Double>(0, 0)) { $0 + $1.1 } / Double(pairs.count)

            // Cross-covariance for 2D Procrustes
            var h00 = 0.0, h01 = 0.0, h10 = 0.0, h11 = 0.0
            var srcVar = 0.0
            for (p, t) in pairs {
                let dp = p - meanP
                let dt = t - meanT
                h00 += dp.x * dt.x; h01 += dp.x * dt.y
                h10 += dp.y * dt.x; h11 += dp.y * dt.y
                srcVar += simd_length_squared(dp)
            }

            // Optimal rotation angle
            let angle = atan2(h01 - h10, h00 + h11)
            let cosA = cos(angle), sinA = sin(angle)

            // Scale (clamped to avoid wild corrections)
            let tgtVar = pairs.reduce(0.0) { $0 + simd_length_squared($1.1 - meanT) }
            let rawScale = srcVar > 0 ? sqrt(tgtVar / srcVar) : 1.0
            let scale = min(max(rawScale, 0.85), 1.15)

            // Build this iteration's correction
            let tx = meanT.x - scale * (cosA * meanP.x - sinA * meanP.y)
            let ty = meanT.y - scale * (sinA * meanP.x + cosA * meanP.y)
            let step = AffineTransform2D(
                a: scale * cosA, b: -scale * sinA,
                c: scale * sinA, d: scale * cosA,
                tx: tx, ty: ty
            )

            // Apply to projected points
            projected = projected.map { step.apply($0) }
            cumulative = step.compose(with: cumulative)
        }

        return cumulative
    }

    private func snapToTrack(_ point: TrackMapPoint, track: [TrackMapPoint]) -> TrackMapPoint {
        guard track.count >= 2 else { return point }
        let vector = SIMD2<Double>(point.x, point.y)
        var best = vector
        var bestDistance = Double.greatestFiniteMagnitude

        for index in track.indices {
            let start = SIMD2<Double>(track[index].x, track[index].y)
            let end = SIMD2<Double>(track[(index + 1) % track.count].x, track[(index + 1) % track.count].y)
            let candidate = closestPointOnSegment(point: vector, start: start, end: end)
            let distance = simd_distance(candidate, vector)
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
        }

        return TrackMapPoint(best.x, best.y)
    }

    private func closestPointOnSegment(point: SIMD2<Double>, start: SIMD2<Double>, end: SIMD2<Double>) -> SIMD2<Double> {
        let segment = end - start
        let lengthSquared = simd_length_squared(segment)
        guard lengthSquared > 0.000001 else { return start }
        let t = max(0, min(1, simd_dot(point - start, segment) / lengthSquared))
        return start + segment * t
    }

    /// Bidirectional alignment score: measures how well projected source covers
    /// target AND how well target covers projected source. Prevents degenerate
    /// alignments where points collapse to a small region.
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

        // Forward: each target point → nearest projected
        let forward = target.reduce(0.0) { partial, point in
            partial + (projectedVectors.map { simd_distance_squared($0, point) }.min() ?? 1e6)
        }

        // Reverse: each projected point → nearest target
        let reverse = projectedVectors.reduce(0.0) { partial, point in
            partial + (target.map { simd_distance_squared($0, point) }.min() ?? 1e6)
        }

        // Normalize by count so neither direction dominates
        let n1 = max(Double(target.count), 1)
        let n2 = max(Double(projectedVectors.count), 1)
        return forward / n1 + reverse / n2
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

private struct ReplayTimeline {
    let snapshots: [ReplaySnapshot]
    let lapAnchors: [ReplayLapAnchor]
    let raceStartSnapshotIndex: Int
}

private struct LapBoundary {
    let lapNumber: Int
    let start: Date
}

private struct PositionPoint {
    let date: Date
    let position: Int
}

private struct LapPoint {
    let date: Date
    let lapNumber: Int
}
