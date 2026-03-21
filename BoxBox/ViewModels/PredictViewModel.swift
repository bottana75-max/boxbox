import Foundation

@MainActor
@Observable
class PredictViewModel {
    var raceCall: RaceCall?
    var nextRace: Race?
    var standings: [DriverStanding] = []
    var recentRaces: [(Race, [RaceResult])] = []
    var trends: [DriverTrend] = []
    var contenderProfiles: [ContenderProfile] = []
    var pressureProfile = CircuitPressureProfile.from(info: nil)
    var isLoading = false
    var error: String?
    var showPaywall = false

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var predictTask: Task<Void, Never>?
    private let service = OpenF1Service.shared
    private let aiService = AIService.shared
    let storeKit = StoreKitManager.shared

    // Keep old name working for compatibility
    var prediction: RaceCall? { raceCall }

    var favoriteDrivers: [DriverStanding] {
        Array(standings.prefix(3))
    }

    var weekendContext: WeekendContext? {
        nextRace?.weekendContext
    }

    var projectedStoryline: String {
        guard let race = nextRace else { return "No upcoming race found." }
        let circuit = race.circuitInfo
        let city = circuit?.city ?? race.country
        let quality = pressureProfile.qualifyingImportance.lowercased()
        let overtaking = pressureProfile.overtaking.lowercased()
        let weather = race.weekendContext.weatherHeadline.lowercased()
        return "\(race.raceWeekendTitle) drops into \(city). Expect \(quality) qualifying, \(pressureProfile.tyreStress.lowercased()) tyre stress, \(overtaking) overtaking pressure and \(weather) conditions."
    }

    // MARK: - Confidence & Chaos

    var confidenceLabel: String {
        guard !contenderProfiles.isEmpty else { return "Medium" }
        let topRating = contenderProfiles.first?.overallRating ?? 50
        let spread = (contenderProfiles.first?.overallRating ?? 50) - (contenderProfiles.dropFirst(2).first?.overallRating ?? 50)
        if topRating >= 75 && spread >= 15 { return "High" }
        if topRating <= 45 || spread <= 5 { return "Low" }
        return "Medium"
    }

    var chaosLabel: String {
        guard let race = nextRace else { return "Medium" }
        let weather = race.weekendContext
        var chaos = 0
        if weather.rainChance.contains("35") || weather.rainChance.contains("40") || weather.rainChance.contains("55") { chaos += 2 }
        if pressureProfile.reliabilityRisk == "Punishing" { chaos += 2 }
        if pressureProfile.overtaking == "Track position" { chaos += 1 }
        if pressureProfile.tyreStress == "High" { chaos += 1 }
        if weather.riskLabel.contains("swing") || weather.riskLabel.contains("Attrition") { chaos += 1 }
        switch chaos {
        case 0...1: return "Low"
        case 2...3: return "Medium"
        case 4...5: return "High"
        default: return "Extreme"
        }
    }

    // MARK: - Scoring

    func buildContenderProfiles() {
        let limit = min(10, standings.count)
        guard limit > 0 else { contenderProfiles = []; return }

        contenderProfiles = standings.prefix(limit).map { standing in
            let trend = trends.first(where: { $0.id == standing.id })
            let formScore = computeFormScore(trend: trend, standing: standing)
            let trackFit = computeTrackFitScore(standing: standing)
            let overall = (formScore * 6 + trackFit * 4) / 10

            return ContenderProfile(
                driverName: standing.driverName,
                driverCode: standing.driverCode,
                team: standing.constructorName,
                championshipPosition: standing.position,
                points: standing.points,
                wins: standing.wins,
                formScore: formScore,
                trackFitScore: trackFit,
                overallRating: overall,
                momentumLabel: trend?.momentumLabel ?? "Unknown",
                recentForm: trend?.recentSummary ?? "—",
                averageFinish: trend?.averageFinish ?? 10.0
            )
        }.sorted { $0.overallRating > $1.overallRating }
    }

    private func computeFormScore(trend: DriverTrend?, standing: DriverStanding) -> Int {
        guard let trend, !trend.recentResults.isEmpty else {
            // Fallback: use championship position as rough proxy
            return max(10, 70 - standing.position * 5)
        }
        // Normalize trend score (max ~36+wins for perfect recent form)
        let raw = trend.trendScore
        let normalized = min(100, Int(Double(raw) / 40.0 * 100.0))
        return max(5, normalized)
    }

    private func computeTrackFitScore(standing: DriverStanding) -> Int {
        // Heuristic: team strengths vs circuit type
        let team = standing.constructorName.lowercased()
        let speed = pressureProfile.overtaking
        let tyre = pressureProfile.tyreStress

        var score = 50 // baseline

        // Top teams get baseline advantage
        if team.contains("red bull") || team.contains("ferrari") || team.contains("mclaren") || team.contains("mercedes") {
            score += 15
        } else if team.contains("aston") || team.contains("alpine") {
            score += 5
        }

        // High overtaking circuits favor power teams
        if speed == "High" && (team.contains("red bull") || team.contains("mercedes")) {
            score += 10
        }

        // Track position circuits favor qualifying-strong teams
        if speed == "Track position" && (team.contains("ferrari") || team.contains("mclaren")) {
            score += 10
        }

        // High tyre stress penalizes less consistent teams
        if tyre == "High" && (team.contains("haas") || team.contains("sauber") || team.contains("williams")) {
            score -= 10
        }

        return min(100, max(5, score))
    }

    // MARK: - Build Structured Context for AI

    func buildRaceCallContext() -> RaceCallContext? {
        guard let race = nextRace else { return nil }
        let info = race.circuitInfo

        let circuitProfile = CircuitProfileContext(
            speedClass: info?.speedClass ?? "Unknown",
            laps: info?.laps ?? 0,
            lengthKm: info?.lengthKm ?? 0,
            turns: info?.turns ?? 0,
            drsZones: info?.drsZones ?? 0,
            overtaking: pressureProfile.overtaking,
            tyreStress: pressureProfile.tyreStress,
            qualifyingImportance: pressureProfile.qualifyingImportance,
            reliabilityRisk: pressureProfile.reliabilityRisk
        )

        let weather = race.weekendContext
        let weatherProfile = WeatherProfileContext(
            headline: weather.weatherHeadline,
            riskLabel: weather.riskLabel,
            ambientTemperature: weather.ambientTemperature,
            trackTemperature: weather.trackTemperature,
            rainChance: weather.rainChance
        )

        let recentContext = recentRaces.prefix(3).map { r, results in
            RecentRaceContext(
                raceName: r.raceWeekendTitle,
                podium: results.prefix(3).map { $0.driverCode }
            )
        }

        return RaceCallContext(
            raceName: race.raceName,
            circuitName: race.circuitName,
            country: race.country,
            date: race.formattedDate,
            round: race.round,
            circuitProfile: circuitProfile,
            weatherProfile: weatherProfile,
            contenders: contenderProfiles,
            recentRaces: recentContext,
            confidenceLabel: confidenceLabel,
            chaosLabel: chaosLabel
        )
    }

    // MARK: - UI Text

    var trialStatusText: String {
        if storeKit.isUnlimited { return "Pro unlocked — unlimited race calls" }
        let remaining = max(0, storeKit.credits)
        if remaining == 0 { return "Free trial finished — unlock Pro to keep calling races" }
        return "\(remaining) free race call\(remaining == 1 ? "" : "s") remaining"
    }

    var predictButtonTitle: String {
        if isLoading { return "Analyzing context..." }
        if nextRace == nil { return "No Race To Call Yet" }
        if !storeKit.canPredict { return "Get More Race Calls" }
        return "Make the Call"
    }

    var predictButtonSubtitle: String {
        if nextRace == nil { return "We'll light this up as soon as the next grand prix is on the board." }
        if !storeKit.canPredict { return "You've used all your race calls. Unlock more to keep going." }
        return "Podium · dark horse · risk · flip scenario"
    }

    // MARK: - Data Loading

    func loadNextRace(forceRefresh: Bool = false) async {
        loadTask?.cancel()

        if !forceRefresh {
            isLoading = true
        }

        error = nil

        let task = Task { [weak self] in
            guard let self else { return }
            await storeKit.restorePurchases()
            await storeKit.loadProducts()
            do {
                async let scheduleTask = service.fetchCurrentSchedule()
                async let standingsTask = service.fetchDriverStandings()
                async let recentTask = service.fetchRecentCompletedRaces(limit: 3)

                let (schedule, fetchedStandings, fetchedRecent) = try await (scheduleTask, standingsTask, recentTask)
                guard !Task.isCancelled else { return }

                let now = Date()
                nextRace = schedule.first { race in
                    guard let raceDate = race.raceDate else { return false }
                    return raceDate > now
                }
                standings = fetchedStandings
                recentRaces = fetchedRecent
                pressureProfile = CircuitPressureProfile.from(info: nextRace?.circuitInfo)
                trends = service.buildTrends(from: fetchedStandings, recentRaces: fetchedRecent, limit: 10)
                buildContenderProfiles()
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            isLoading = false
        }
        loadTask = task
        await task.value
    }

    nonisolated deinit {
        loadTask?.cancel()
        predictTask?.cancel()
    }

    func predict() async {
        guard let _ = nextRace else {
            error = "The next grand prix is not available yet. Pull to refresh and try again shortly."
            return
        }

        guard storeKit.canPredict else {
            showPaywall = true
            return
        }

        predictTask?.cancel()
        isLoading = true
        error = nil

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                // Use already-loaded data where available; only fetch if the view was somehow bypassed.
                let activeStandings = standings.isEmpty ? try await service.fetchDriverStandings() : standings
                let activeRecent = recentRaces.isEmpty ? try await service.fetchRecentCompletedRaces(limit: 3) : recentRaces
                guard !Task.isCancelled else { return }

                if trends.isEmpty {
                    trends = service.buildTrends(from: activeStandings, recentRaces: activeRecent, limit: 10)
                }
                if standings.isEmpty { standings = activeStandings }
                if recentRaces.isEmpty { recentRaces = activeRecent }
                if contenderProfiles.isEmpty { buildContenderProfiles() }

                guard let context = buildRaceCallContext() else {
                    self.error = "Could not build race context."
                    isLoading = false
                    return
                }

                let result = try await aiService.predictRace(context: context)
                guard !Task.isCancelled else { return }

                raceCall = result
                storeKit.consumeCredit()
            } catch {
                guard !Task.isCancelled else { return }
                self.error = "Something went wrong generating your race call. Check your connection and try again."
            }
            isLoading = false
        }
        predictTask = task
        await task.value
    }
}
