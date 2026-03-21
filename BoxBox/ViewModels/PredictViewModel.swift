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
    var qualifyingResults: [QualifyingResult] = []
    var liveWeather: LiveWeatherContext?
    var pressureProfile = CircuitPressureProfile.from(info: nil)
    var weekendPhase: WeekendPhase = .baseline
    var isLoading = false
    var error: String?
    var showPaywall = false

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var predictTask: Task<Void, Never>?
    private let service = OpenF1Service.shared
    private let aiService = AIService.shared
    let storeKit = StoreKitManager.shared

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
        let phaseNote = weekendPhase == .baseline ? "" : " [\(weekendPhase.shortLabel)]"
        return "\(race.raceWeekendTitle) drops into \(city). Expect \(quality) qualifying, \(pressureProfile.tyreStress.lowercased()) tyre stress, \(overtaking) overtaking pressure and \(weather) conditions.\(phaseNote)"
    }

    // MARK: - Phase Detection

    func detectWeekendPhase() {
        guard let race = nextRace, let raceDate = race.raceDate else {
            weekendPhase = .baseline
            return
        }
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()

        // Race day: if within 4 hours before race start
        let raceStart = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: raceDate) ?? raceDate
        if now >= calendar.date(byAdding: .hour, value: -4, to: raceStart)! && now <= raceStart {
            weekendPhase = .raceReady
            return
        }

        // Qualifying day: Saturday (1 day before race)
        let qualiDay = calendar.date(byAdding: .day, value: -1, to: raceDate)!
        let qualiEnd = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: qualiDay) ?? qualiDay
        if now > qualiEnd {
            // After qualifying ended — check if we have qualifying data
            weekendPhase = qualifyingResults.isEmpty ? .postPractice : .postQualifying
            return
        }

        // Practice days: Friday (2 days before) through Saturday morning
        let fp1Day = calendar.date(byAdding: .day, value: -2, to: raceDate)!
        let fp1Start = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: fp1Day) ?? fp1Day
        if now >= fp1Start {
            weekendPhase = .postPractice
            return
        }

        weekendPhase = .baseline
    }

    // MARK: - Confidence & Chaos (V2.1 — stronger logic)

    var confidenceLabel: String {
        guard !contenderProfiles.isEmpty else { return "Medium" }
        let topRating = contenderProfiles.first?.overallRating ?? 50
        let second = contenderProfiles.dropFirst().first?.overallRating ?? 50
        let third = contenderProfiles.dropFirst(2).first?.overallRating ?? 50
        let spread = topRating - third
        let topGap = topRating - second

        var score = 0

        // Strong frontrunner
        if topRating >= 80 { score += 3 }
        else if topRating >= 70 { score += 2 }
        else if topRating >= 60 { score += 1 }

        // Clear separation
        if spread >= 20 { score += 2 }
        else if spread >= 12 { score += 1 }

        // Dominant leader gap
        if topGap >= 10 { score += 1 }

        // Phase bonus: more data = more confidence
        switch weekendPhase {
        case .postQualifying, .raceReady: score += 2
        case .postPractice: score += 1
        case .baseline: break
        }

        // Grid data available
        if !qualifyingResults.isEmpty { score += 1 }

        // Weather certainty (no rain = more predictable)
        if let race = nextRace {
            let rain = race.weekendContext.rainChance
            if rain.contains("<10") || rain.contains("0%") { score += 1 }
        }

        switch score {
        case 7...: return "High"
        case 4...6: return "Medium"
        default: return "Low"
        }
    }

    var chaosLabel: String {
        guard let race = nextRace else { return "Medium" }
        let weather = race.weekendContext
        var chaos = 0

        // Rain risk (scaled)
        let rainStr = weather.rainChance.lowercased()
        if rainStr.contains("55") || rainStr.contains("60") || rainStr.contains("70") { chaos += 3 }
        else if rainStr.contains("35") || rainStr.contains("40") || rainStr.contains("45") { chaos += 2 }
        else if rainStr.contains("25") || rainStr.contains("30") { chaos += 1 }

        // Live weather override: actual rainfall detected
        if liveWeather?.rainfall == true { chaos += 2 }

        // Track characteristics
        if pressureProfile.reliabilityRisk == "Punishing" { chaos += 2 }
        else if pressureProfile.reliabilityRisk == "Medium" { chaos += 1 }

        if pressureProfile.overtaking == "Track position" { chaos += 1 }
        if pressureProfile.tyreStress == "High" { chaos += 1 }

        // Weather swing risk
        if weather.riskLabel.contains("swing") || weather.riskLabel.contains("Attrition") { chaos += 1 }

        // Field tightness: if top 5 are within 10 rating points, more chaos
        if contenderProfiles.count >= 5 {
            let top = contenderProfiles.first?.overallRating ?? 50
            let fifth = contenderProfiles[4].overallRating
            if top - fifth <= 10 { chaos += 1 }
        }

        // DNF rates in recent races
        let recentDNFs = recentRaces.flatMap { $0.1 }.filter {
            $0.status != "Finished" && !$0.status.starts(with: "+")
        }.count
        if recentDNFs >= 6 { chaos += 1 }

        switch chaos {
        case 0...1: return "Low"
        case 2...3: return "Medium"
        case 4...5: return "High"
        default: return "Extreme"
        }
    }

    // MARK: - Scoring (V2.1)

    func buildContenderProfiles() {
        let limit = min(10, standings.count)
        guard limit > 0 else { contenderProfiles = []; return }

        contenderProfiles = standings.prefix(limit).map { standing in
            let trend = trends.first(where: { $0.id == standing.id })
            let formScore = computeFormScore(trend: trend, standing: standing)
            let trackFit = computeTrackFitScore(standing: standing)
            let weekendPace = computeWeekendPaceScore(standing: standing)
            let gridPos = qualifyingResults.first(where: { $0.driverCode == standing.driverCode })?.gridPosition

            // Weight shifts based on phase
            let overall: Int
            switch weekendPhase {
            case .baseline:
                overall = (formScore * 6 + trackFit * 4) / 10
            case .postPractice:
                overall = (formScore * 5 + trackFit * 3 + weekendPace * 2) / 10
            case .postQualifying, .raceReady:
                overall = (formScore * 4 + trackFit * 2 + weekendPace * 4) / 10
            }

            return ContenderProfile(
                driverName: standing.driverName,
                driverCode: standing.driverCode,
                team: standing.constructorName,
                championshipPosition: standing.position,
                points: standing.points,
                wins: standing.wins,
                formScore: formScore,
                trackFitScore: trackFit,
                weekendPaceScore: weekendPace,
                overallRating: overall,
                momentumLabel: trend?.momentumLabel ?? "Unknown",
                recentForm: trend?.recentSummary ?? "—",
                averageFinish: trend?.averageFinish ?? 10.0,
                gridPosition: gridPos
            )
        }.sorted { $0.overallRating > $1.overallRating }
    }

    private func computeFormScore(trend: DriverTrend?, standing: DriverStanding) -> Int {
        guard let trend, !trend.recentResults.isEmpty else {
            return max(10, 70 - standing.position * 5)
        }
        let raw = trend.trendScore
        let normalized = min(100, Int(Double(raw) / 40.0 * 100.0))
        return max(5, normalized)
    }

    private func computeTrackFitScore(standing: DriverStanding) -> Int {
        let team = standing.constructorName.lowercased()
        let speed = pressureProfile.overtaking
        let tyre = pressureProfile.tyreStress

        var score = 50

        // Team baseline tiers
        if team.contains("red bull") || team.contains("ferrari") || team.contains("mclaren") || team.contains("mercedes") {
            score += 15
        } else if team.contains("aston") || team.contains("alpine") {
            score += 5
        }

        // Circuit–team synergies
        if speed == "High" && (team.contains("red bull") || team.contains("mercedes")) {
            score += 10
        }
        if speed == "Track position" && (team.contains("ferrari") || team.contains("mclaren")) {
            score += 10
        }

        // Tyre stress penalty for less consistent teams
        if tyre == "High" && (team.contains("haas") || team.contains("sauber") || team.contains("williams") || team.contains("kick")) {
            score -= 10
        }

        return min(100, max(5, score))
    }

    private func computeWeekendPaceScore(standing: DriverStanding) -> Int {
        guard !qualifyingResults.isEmpty else {
            // No weekend data — use championship position as proxy
            return max(10, 75 - standing.position * 4)
        }

        // Grid-based scoring: P1=95, P2=90, ..., P20=5
        if let qual = qualifyingResults.first(where: { $0.driverCode == standing.driverCode }) {
            let gridScore = max(5, 100 - (qual.gridPosition - 1) * 5)

            // Grid advantage: circuits where qualifying matters more amplify the grid score
            let qualiImportance = pressureProfile.qualifyingImportance
            let amplifier: Double
            switch qualiImportance {
            case "Massive": amplifier = 1.15
            case "Important": amplifier = 1.05
            default: amplifier = 1.0
            }

            return min(100, Int(Double(gridScore) * amplifier))
        }

        // Driver not in qualifying results — fallback
        return max(5, 60 - standing.position * 3)
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
            weekendPhase: weekendPhase.rawValue,
            phaseDescription: weekendPhase.description,
            circuitProfile: circuitProfile,
            weatherProfile: weatherProfile,
            liveWeather: liveWeather,
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
        let extras = weekendPhase == .baseline ? "" : " · \(weekendPhase.shortLabel.lowercased()) data"
        return "Podium · dark horse · risk · key battle · strategy\(extras)"
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

                // Phase-aware: try to fetch qualifying and live weather
                if let race = nextRace {
                    async let qualTask = service.fetchQualifyingResults(round: race.round)
                    async let weatherTask = service.fetchLiveWeather()
                    let (qual, weather) = try await (qualTask, weatherTask)
                    if !Task.isCancelled {
                        qualifyingResults = qual
                        liveWeather = weather
                    }
                }

                detectWeekendPhase()
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
