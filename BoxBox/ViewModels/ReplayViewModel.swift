import Foundation
import SwiftUI

@MainActor
@Observable
class ReplayViewModel {
    // State
    var availableSessions: [ReplaySession] = []
    var selectedSession: ReplaySession?
    var drivers: [ReplayDriver] = []
    var locationData: [Int: [LocationPoint]] = [:]
    var positionData: [Int: [PositionPoint]] = [:]
    var currentTime: Date = .distantPast
    var isPlaying = false
    var playbackSpeed: Double = 1.0
    var isLoading = false
    var isLoadingTrack = false
    var error: String?

    // Computed
    var visibleDrivers: [ReplayDriver] {
        drivers.filter(\.isVisible)
    }

    var timeRange: ClosedRange<Date>? {
        let allDates = locationData.values.flatMap { $0.map(\.date) }
        guard let min = allDates.min(), let max = allDates.max() else { return nil }
        return min...max
    }

    var progress: Double {
        get {
            guard let range = timeRange else { return 0 }
            let total = range.upperBound.timeIntervalSince(range.lowerBound)
            guard total > 0 else { return 0 }
            return currentTime.timeIntervalSince(range.lowerBound) / total
        }
        set {
            guard let range = timeRange else { return }
            let total = range.upperBound.timeIntervalSince(range.lowerBound)
            currentTime = range.lowerBound.addingTimeInterval(newValue * total)
        }
    }

    var currentDriverPositions: [Int: CGPoint] {
        var result: [Int: CGPoint] = [:]
        for driver in visibleDrivers {
            guard let points = locationData[driver.driverNumber],
                  let pos = interpolatePosition(points: points, at: currentTime) else { continue }
            result[driver.driverNumber] = pos
        }
        return result
    }

    var currentDriverRanks: [Int: Int] {
        var result: [Int: Int] = [:]
        for (num, positions) in positionData {
            guard let pos = interpolateRank(positions: positions, at: currentTime) else { continue }
            result[num] = pos
        }
        return result
    }

    var sortedDriversByRank: [ReplayDriver] {
        let ranks = currentDriverRanks
        return drivers.sorted { a, b in
            (ranks[a.driverNumber] ?? 99) < (ranks[b.driverNumber] ?? 99)
        }
    }

    var elapsedTimeString: String {
        guard let range = timeRange else { return "--:--" }
        let elapsed = currentTime.timeIntervalSince(range.lowerBound)
        let mins = Int(elapsed) / 60
        let secs = Int(elapsed) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var totalTimeString: String {
        guard let range = timeRange else { return "--:--" }
        let total = range.upperBound.timeIntervalSince(range.lowerBound)
        let mins = Int(total) / 60
        let secs = Int(total) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // Normalization bounds (0-100 scale to match CircuitInfo trackMapPoints)
    private var minX: Double = 0
    private var maxX: Double = 1
    private var minY: Double = 0
    private var maxY: Double = 1

    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    private let service = ReplayService.shared

    // MARK: - Loading

    func loadSessions() async {
        isLoading = true
        error = nil
        do {
            availableSessions = try await service.fetchAvailableSessions()
        } catch {
            self.error = "Could not load race sessions"
        }
        isLoading = false
    }

    func selectSession(_ session: ReplaySession) async {
        selectedSession = session
        isLoadingTrack = true
        error = nil
        pause()

        do {
            let fetchedDrivers = try await service.fetchDrivers(sessionKey: session.sessionKey)
            drivers = fetchedDrivers

            let driverNumbers = fetchedDrivers.map(\.driverNumber)

            async let locationTask = service.fetchLocationData(sessionKey: session.sessionKey, driverNumbers: driverNumbers)
            async let positionTask = service.fetchPositionData(sessionKey: session.sessionKey)

            locationData = try await locationTask
            positionData = try await positionTask

            computeNormalizationBounds()

            if let range = timeRange {
                currentTime = range.lowerBound
            }
        } catch {
            self.error = "Could not load replay data"
        }
        isLoadingTrack = false
    }

    // MARK: - Playback

    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        playbackTask = Task { [weak self] in
            let frameInterval: UInt64 = 16_000_000 // ~16ms
            while !Task.isCancelled {
                guard let self else { return }
                guard let range = self.timeRange else { return }

                let step = self.playbackSpeed * 0.016
                let newTime = self.currentTime.addingTimeInterval(step)

                if newTime >= range.upperBound {
                    self.currentTime = range.upperBound
                    self.isPlaying = false
                    return
                }

                self.currentTime = newTime
                try? await Task.sleep(nanoseconds: frameInterval)
            }
        }
    }

    func pause() {
        isPlaying = false
        playbackTask?.cancel()
        playbackTask = nil
    }

    func togglePlayback() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to date: Date) {
        currentTime = date
    }

    func setAllVisible(_ visible: Bool) {
        for i in drivers.indices {
            drivers[i].isVisible = visible
        }
    }

    func setTopNVisible(_ n: Int) {
        let ranks = currentDriverRanks
        for i in drivers.indices {
            let rank = ranks[drivers[i].driverNumber] ?? 99
            drivers[i].isVisible = rank <= n
        }
    }

    func toggleDriver(_ driver: ReplayDriver) {
        guard let idx = drivers.firstIndex(where: { $0.driverNumber == driver.driverNumber }) else { return }
        drivers[idx].isVisible.toggle()
    }

    nonisolated deinit {
        playbackTask?.cancel()
    }

    // MARK: - Normalization

    private func computeNormalizationBounds() {
        let allPoints = locationData.values.flatMap { $0 }
        guard !allPoints.isEmpty else { return }

        minX = allPoints.map(\.x).min()!
        maxX = allPoints.map(\.x).max()!
        minY = allPoints.map(\.y).min()!
        maxY = allPoints.map(\.y).max()!

        // Preserve aspect ratio by expanding the smaller range
        let rangeX = maxX - minX
        let rangeY = maxY - minY
        if rangeX > rangeY {
            let diff = rangeX - rangeY
            minY -= diff / 2
            maxY += diff / 2
        } else {
            let diff = rangeY - rangeX
            minX -= diff / 2
            maxX += diff / 2
        }
    }

    /// Normalize a location coordinate to 0-100 scale (matching CircuitInfo trackMapPoints)
    func normalizedPoint(x: Double, y: Double) -> CGPoint {
        let rangeX = maxX - minX
        let rangeY = maxY - minY
        guard rangeX > 0, rangeY > 0 else { return CGPoint(x: 50, y: 50) }
        let nx = ((x - minX) / rangeX) * 100
        let ny = ((y - minY) / rangeY) * 100
        return CGPoint(x: nx, y: ny)
    }

    // MARK: - Interpolation

    private func interpolatePosition(points: [LocationPoint], at time: Date) -> CGPoint? {
        guard !points.isEmpty else { return nil }

        // Find the two nearest points
        var lo = 0
        var hi = points.count - 1

        if time <= points[lo].date {
            return normalizedPoint(x: points[lo].x, y: points[lo].y)
        }
        if time >= points[hi].date {
            return normalizedPoint(x: points[hi].x, y: points[hi].y)
        }

        // Binary search for bracket
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if points[mid].date <= time {
                lo = mid
            } else {
                hi = mid
            }
        }

        let t0 = points[lo]
        let t1 = points[hi]
        let interval = t1.date.timeIntervalSince(t0.date)
        guard interval > 0 else {
            return normalizedPoint(x: t0.x, y: t0.y)
        }

        let frac = time.timeIntervalSince(t0.date) / interval
        let ix = t0.x + (t1.x - t0.x) * frac
        let iy = t0.y + (t1.y - t0.y) * frac
        return normalizedPoint(x: ix, y: iy)
    }

    private func interpolateRank(positions: [PositionPoint], at time: Date) -> Int? {
        guard !positions.isEmpty else { return nil }
        // Find the latest position update at or before currentTime
        var best: PositionPoint?
        for p in positions {
            if p.date <= time {
                best = p
            } else {
                break
            }
        }
        return best?.position ?? positions.first?.position
    }
}
