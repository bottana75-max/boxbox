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

    private struct TrackBounds {
        let minX: Double, maxX: Double
        let minY: Double, maxY: Double

        var scale: Double { max(maxX - minX, maxY - minY, 1) }

        func normalize(_ x: Double, _ y: Double) -> TrackMapPoint {
            let xNorm = (x - minX) / scale * 90 + 5
            let yNorm = (maxY - y) / scale * 90 + 5
            return TrackMapPoint(xNorm, yNorm)
        }

        init(minX: Double, maxX: Double, minY: Double, maxY: Double) {
            self.minX = minX; self.maxX = maxX; self.minY = minY; self.maxY = maxY
        }

        init?(points: [ReplayLocationPoint]) {
            guard !points.isEmpty else { return nil }
            let xs = points.map(\.x), ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { return nil }
            self.minX = minX; self.maxX = maxX; self.minY = minY; self.maxY = maxY
        }
    }

    private struct LapInfoResponse: Decodable {
        let driverNumber: Int
        let lapNumber: Int
        let dateStart: String?
        let lapDuration: Double?
        let isPitOutLap: Bool?

        enum CodingKeys: String, CodingKey {
            case driverNumber = "driver_number"
            case lapNumber = "lap_number"
            case dateStart = "date_start"
            case lapDuration = "lap_duration"
            case isPitOutLap = "is_pit_out_lap"
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

    nonisolated private func parseDate(_ string: String) -> Date? {
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
            displayTrackPoints: payload.displayTrackPoints,
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

        statusUpdate?("Fetching single-lap track shape")
        let referenceDriver = orderedDrivers.first ?? 1
        let singleLapData = try? await fetchSingleLapLocationData(sessionKey: sessionKey, driverNumber: referenceDriver)

        statusUpdate?("Building replay timeline")
        let timeline = buildSnapshots(
            race: race,
            selectedDrivers: selectedDrivers,
            allDrivers: drivers,
            locationData: locationData,
            positionData: positionData,
            lapData: lapData,
            singleLapData: singleLapData
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
            displayTrackPoints: timeline.displayTrackPoints,
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

    private func fetchSingleLapLocationData(sessionKey: Int, driverNumber: Int) async throws -> (points: [ReplayLocationPoint], bounds: TrackBounds)? {
        let lapsURL = URL(string: "\(baseURL)/laps?session_key=\(sessionKey)&driver_number=\(driverNumber)")!
        let lapsData = try await fetchData(from: lapsURL, label: "single-lap laps")
        let laps = try decoder.decode([LapInfoResponse].self, from: lapsData)

        let cleanLap = laps.first { lap in
            lap.lapNumber >= 8 && lap.lapNumber <= 12
                && lap.isPitOutLap != true
                && lap.lapDuration != nil
                && lap.dateStart != nil
        } ?? laps.first { lap in
            lap.lapDuration != nil && lap.dateStart != nil && lap.isPitOutLap != true
        }

        guard let lap = cleanLap,
              let startStr = lap.dateStart,
              let lapStart = parseDate(startStr),
              let duration = lap.lapDuration
        else { return nil }

        let lapEnd = lapStart.addingTimeInterval(duration)
        let startISO = Self.isoFormatter.string(from: lapStart)
        let endISO = Self.isoFormatter.string(from: lapEnd)

        let startEncoded = startISO.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? startISO
        let endEncoded = endISO.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? endISO
        let locURL = URL(string: "\(baseURL)/location?session_key=\(sessionKey)&driver_number=\(driverNumber)&date%3E=\(startEncoded)&date%3C=\(endEncoded)")!
        let locData = try await fetchData(from: locURL, label: "single-lap location")
        let responses = try decoder.decode([LocationResponse].self, from: locData)

        let points = responses.compactMap { r -> ReplayLocationPoint? in
            guard let date = parseDate(r.date), let x = r.x, let y = r.y else { return nil }
            return ReplayLocationPoint(date: date, x: x, y: y, z: r.z ?? 0)
        }.sorted { $0.date < $1.date }

        guard points.count >= 10, let bounds = TrackBounds(points: points) else { return nil }
        return (points, bounds)
    }

    private func buildSnapshots(
        race: Race,
        selectedDrivers: [ReplayDriver],
        allDrivers: [ReplayDriver],
        locationData: [Int: [ReplayLocationPoint]],
        positionData: [Int: [PositionPoint]],
        lapData: [Int: [LapPoint]],
        singleLapData: (points: [ReplayLocationPoint], bounds: TrackBounds)?
    ) -> ReplayTimeline {
        let selectedNumbers = Set(selectedDrivers.map(\.driverNumber))
        let sourcePoints = selectedNumbers
            .compactMap { locationData[$0] }
            .flatMap { $0 }

        guard !sourcePoints.isEmpty else {
            return ReplayTimeline(snapshots: [], lapAnchors: [], raceStartSnapshotIndex: 0, displayTrackPoints: [])
        }

        let allTimes = sourcePoints.map(\.date).sorted()
        guard let rawStart = allTimes.first, let end = allTimes.last else {
            return ReplayTimeline(snapshots: [], lapAnchors: [], raceStartSnapshotIndex: 0, displayTrackPoints: [])
        }

        // Compute bounds from single-lap data, fallback to all source points
        let bounds: TrackBounds
        if let singleLapData {
            bounds = singleLapData.bounds
        } else if let fallbackBounds = TrackBounds(points: sourcePoints) {
            bounds = fallbackBounds
        } else {
            return ReplayTimeline(snapshots: [], lapAnchors: [], raceStartSnapshotIndex: 0, displayTrackPoints: [])
        }

        // Build display track by normalizing single-lap points (subsample to ~80)
        let displayTrackPoints: [TrackMapPoint]
        if let singleLapData {
            let subsampled = evenlySubsampled(
                singleLapData.points.map { SIMD2<Double>($0.x, $0.y) },
                maxCount: 80
            )
            displayTrackPoints = subsampled.map { bounds.normalize($0.x, $0.y) }
        } else {
            let subsampled = evenlySubsampled(
                sourcePoints.map { SIMD2<Double>($0.x, $0.y) },
                maxCount: 80
            )
            displayTrackPoints = subsampled.map { bounds.normalize($0.x, $0.y) }
        }

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
                      let location = interpolatedLocation(in: points, at: timestamp)
                else { return nil }

                let projectedPoint = bounds.normalize(location.x, location.y)

                return ReplayMarker(
                    driver: driver,
                    runningPosition: latestPosition(in: positionData[driver.driverNumber] ?? [], at: timestamp),
                    projectedPoint: projectedPoint,
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

            let lapNumber = currentLap(at: timestamp, timeline: lapTimeline)
            return ReplaySnapshot(
                index: index,
                timestamp: timestamp,
                elapsedTime: timestamp.timeIntervalSince(start),
                lapNumber: lapNumber,
                phase: phase(at: timestamp, lapNumber: lapNumber, raceStart: raceStart, raceStartOffset: raceStart.timeIntervalSince(start), totalLaps: officialTotalLaps),
                markers: markers,
                standings: Array(standings.prefix(10)),
                headline: headline(for: markers, standings: standings, selectedDrivers: selectedDrivers)
            )
        }

        guard !snapshots.isEmpty else {
            return ReplayTimeline(snapshots: [], lapAnchors: [], raceStartSnapshotIndex: 0, displayTrackPoints: displayTrackPoints)
        }

        let lapAnchors = makeLapAnchors(snapshots: snapshots, lapTimeline: lapTimeline)
        let raceStartDistances = snapshots.enumerated().map { index, snapshot in
            (index, abs(snapshot.timestamp.timeIntervalSince(raceStart)))
        }
        let raceStartSnapshotIndex = raceStartDistances.min(by: { $0.1 < $1.1 })?.0 ?? 0

        return ReplayTimeline(snapshots: snapshots, lapAnchors: lapAnchors, raceStartSnapshotIndex: raceStartSnapshotIndex, displayTrackPoints: displayTrackPoints)
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
        return candidates.last?.lapNumber
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

    private func phase(at time: Date, lapNumber: Int?, raceStart: Date, raceStartOffset: TimeInterval, totalLaps: Int?) -> ReplayPhase {
        if time < raceStart {
            let label = raceStartOffset >= 180 ? "Warm-up / formation" : "Formation / pre-start"
            return ReplayPhase(kind: .preRace, label: label, shortLabel: "Formation")
        }

        guard let lapNumber else {
            return ReplayPhase(kind: .racing, label: "Race underway", shortLabel: "Race")
        }

        let label: String
        if let totalLaps, totalLaps > 0 {
            label = "Lap \(lapNumber) / \(totalLaps)"
        } else {
            label = "Lap \(lapNumber)"
        }
        return ReplayPhase(kind: .racing, label: label, shortLabel: "Lap \(lapNumber)")
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

    private func evenlySubsampled(_ points: [SIMD2<Double>], maxCount: Int) -> [SIMD2<Double>] {
        guard points.count > maxCount else { return points }
        let step = Double(points.count) / Double(maxCount)
        return (0..<maxCount).map { i in points[min(Int(Double(i) * step), points.count - 1)] }
    }
}

private struct ReplayTimeline {
    let snapshots: [ReplaySnapshot]
    let lapAnchors: [ReplayLapAnchor]
    let raceStartSnapshotIndex: Int
    let displayTrackPoints: [TrackMapPoint]
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
