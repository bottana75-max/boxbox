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
    var openF1Sessions: [OpenF1Service.OpenF1Session] = []
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
        if !openF1Sessions.isEmpty {
            let names = openF1Sessions.compactMap { $0.session_name ?? $0.session_type }
            let normalized = names.map { $0.lowercased() }
            if normalized.contains(where: { $0.contains("race") }) {
                weekendPhase = .raceReady
                return
            }
            if normalized.contains(where: { $0.contains("qualifying") || $0 == "sprint shootout" }) || !qualifyingResults.isEmpty {
                weekendPhase = .postQualifying
                return
            }
            if normalized.contains(where: { $0.contains("practice") || $0 == "fp1" || $0 == "fp2" || $0 == "fp3" }) {
                weekendPhase = .postPractice
                return
            }
        }

        guard let race = nextRace, let raceDate = race.raceDate else {
            weekendPhase = .baseline
            return
        }
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let raceStart = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: raceDate) ?? raceDate

        if let preRaceWindow = calendar.date(byAdding: .hour, value: -4, to: raceStart), now >= preRaceWindow && now <= raceStart {
            weekendPhase = .raceReady
            return
        }

        let qualiDay = calendar.date(byAdding: .day, value: -1, to: raceDate) ?? raceDate
        let qualiEnd = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: qualiDay) ?? qualiDay
        if now > qualiEnd {
            weekendPhase = qualifyingResults.isEmpty ? .postPractice : .postQualifying
            return
        }

        let fp1Day = calendar.date(byAdding: .day, value: -2, to: raceDate) ?? raceDate
        let fp1Start = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: fp1Day) ?? fp1Day
        if now >= fp1Start {
            weekendPhase = .postPractice
            return
        }

        weekendPhase = .baseline
    }

    // MARK: - Confidence & Chaos (V2.2 — robust scoring with numeric granularity)

    var confidenceRawScore: Int {
        guard !contenderProfiles.isEmpty else { return 4 }
        let topRating = contenderProfiles.first?.overallRating ?? 50
        let second = contenderProfiles.dropFirst().first?.overallRating ?? 50
        let third = contenderProfiles.dropFirst(2).first?.overallRating ?? 50
        let spread = topRating - third
        let topGap = topRating - second

        var score = 0

        // Strong frontrunner (clear top dog raises confidence)
        if topRating >= 85 { score += 4 }
        else if topRating >= 75 { score += 3 }
        else if topRating >= 65 { score += 2 }
        else if topRating >= 55 { score += 1 }

        // Clear separation in top 3
        if spread >= 25 { score += 3 }
        else if spread >= 18 { score += 2 }
        else if spread >= 10 { score += 1 }

        // Dominant leader gap (1st vs 2nd)
        if topGap >= 15 { score += 2 }
        else if topGap >= 8 { score += 1 }

        // Phase bonus: more data = more confidence
        switch weekendPhase {
        case .raceReady: score += 3
        case .postQualifying: score += 2
        case .postPractice: score += 1
        case .baseline: break
        }

        // Grid data available and consistent with ratings
        if !qualifyingResults.isEmpty {
            score += 1
            // Grid-rating consistency: if pole sitter is also top rated, extra confidence
            if let poleCode = qualifyingResults.first(where: { $0.gridPosition == 1 })?.driverCode,
               contenderProfiles.first?.driverCode == poleCode {
                score += 1
            }
        }

        // Weather certainty
        if let race = nextRace {
            let rain = race.weekendContext.rainChance
            if rain.contains("<10") || rain.contains("0%") { score += 1 }
            else if rain.contains("40") || rain.contains("50") || rain.contains("60") { score -= 1 }
        }

        // Live weather corroboration
        if let live = liveWeather, live.rainfall == false, live.source == "OpenF1 live" { score += 1 }

        // Low circuit chaos circuits (low tyre stress + high overtaking = more predictable)
        if pressureProfile.tyreStress == "Balanced" && pressureProfile.overtaking == "High" { score += 1 }

        return max(0, min(10, score))
    }

    var confidenceLabel: String {
        switch confidenceRawScore {
        case 8...10: return "High"
        case 5...7: return "Medium"
        default: return "Low"
        }
    }

    var chaosRawScore: Int {
        guard let race = nextRace else { return 3 }
        let weather = race.weekendContext
        var chaos = 0

        // Rain risk (scaled with more granularity)
        let rainStr = weather.rainChance.lowercased()
        if rainStr.contains("70") || rainStr.contains("80") || rainStr.contains("90") { chaos += 4 }
        else if rainStr.contains("55") || rainStr.contains("60") { chaos += 3 }
        else if rainStr.contains("35") || rainStr.contains("40") || rainStr.contains("45") { chaos += 2 }
        else if rainStr.contains("25") || rainStr.contains("30") { chaos += 1 }

        // Live weather override: actual rainfall detected
        if liveWeather?.rainfall == true { chaos += 3 }

        // Track characteristics
        if pressureProfile.reliabilityRisk == "Punishing" { chaos += 2 }
        else if pressureProfile.reliabilityRisk == "Medium" { chaos += 1 }

        if pressureProfile.overtaking == "Track position" { chaos += 1 }
        if pressureProfile.tyreStress == "High" { chaos += 2 }
        else if pressureProfile.tyreStress == "Medium" { chaos += 1 }

        // Safety car likelihood from circuit profile
        let scLikelihood = tyreStrategyContext.safetyCarLikelihood
        if scLikelihood == "High" { chaos += 2 }
        else if scLikelihood == "Medium" { chaos += 1 }

        // Weather swing risk
        if weather.riskLabel.contains("swing") || weather.riskLabel.contains("Attrition") { chaos += 1 }

        // Field tightness: if top 5 are within 10 rating points, more chaos
        if contenderProfiles.count >= 5 {
            let top = contenderProfiles.first?.overallRating ?? 50
            let fifth = contenderProfiles[4].overallRating
            if top - fifth <= 8 { chaos += 2 }
            else if top - fifth <= 14 { chaos += 1 }
        }

        // DNF rates in recent races
        let recentDNFs = recentRaces.flatMap { $0.1 }.filter {
            $0.status != "Finished" && !$0.status.starts(with: "+")
        }.count
        if recentDNFs >= 8 { chaos += 2 }
        else if recentDNFs >= 5 { chaos += 1 }

        return max(0, min(10, chaos))
    }

    var chaosLabel: String {
        switch chaosRawScore {
        case 0...2: return "Low"
        case 3...4: return "Medium"
        case 5...7: return "High"
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
        if let qual = qualifyingResults.first(where: { $0.driverCode == standing.driverCode }) {
            let gridScore = max(5, 100 - (qual.gridPosition - 1) * 5)
            let amplifier: Double
            switch pressureProfile.qualifyingImportance {
            case "Massive": amplifier = 1.15
            case "Important": amplifier = 1.05
            default: amplifier = 1.0
            }
            // V2.2: factor tyre deg resistance for race pace — grid isn't everything
            let tyreCtx = tyreStrategyContext
            var raceAdj = 0
            if tyreCtx.degradationSeverity == "Extreme" || tyreCtx.degradationSeverity == "High" {
                let team = standing.constructorName.lowercased()
                // Teams historically good at tyre management get a race-pace bump
                if team.contains("mercedes") || team.contains("red bull") || team.contains("aston") {
                    raceAdj = 5
                }
                // Teams that struggle with deg get penalised
                if team.contains("haas") || team.contains("williams") || team.contains("sauber") || team.contains("kick") {
                    raceAdj = -5
                }
            }
            return min(100, Int(Double(gridScore) * amplifier) + raceAdj)
        }

        if weekendPhase == .postPractice {
            let trackFit = computeTrackFitScore(standing: standing)
            let form = computeFormScore(trend: trends.first(where: { $0.id == standing.id }), standing: standing)
            // V2.2: deg-aware practice score — high deg circuits reward consistency
            let tyreCtx = tyreStrategyContext
            let degBias: Int
            switch tyreCtx.degradationSeverity {
            case "Extreme": degBias = 12
            case "High": degBias = 8
            case "Medium": degBias = 5
            default: degBias = 3
            }
            return min(100, max(10, (trackFit + form) / 2 + degBias))
        }

        return max(10, 75 - standing.position * 4)
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

        let sessionNames = openF1Sessions.compactMap { $0.session_name ?? $0.session_type }
        let sessionContext = SessionContext(
            availableSessions: sessionNames,
            lastCompletedSession: sessionNames.last,
            sessionCount: sessionNames.count,
            source: sessionNames.isEmpty ? "Schedule estimate" : "OpenF1 sessions"
        )

        let weekendPace = WeekendPaceContext(
            headline: weekendPaceHeadline,
            longRunBias: longRunBias,
            firstStintShape: firstStintShape,
            gridPressure: gridPressureNarrative,
            tyreStrategy: tyreStrategyContext
        )

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
            sessionContext: sessionContext,
            weekendPace: weekendPace,
            contenders: contenderProfiles,
            recentRaces: recentContext,
            confidenceLabel: confidenceLabel,
            chaosLabel: chaosLabel,
            confidenceScore: confidenceRawScore,
            chaosScore: chaosRawScore
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
        return "Podium · battle · tyres · pit wall · strategy\(extras)"
    }

    // MARK: - Tyre Strategy Intelligence (V2.2)

    var tyreStrategyContext: TyreStrategyContext {
        let info = nextRace?.circuitInfo
        let laps = info?.laps ?? 55
        let tyreStress = pressureProfile.tyreStress
        let overtaking = pressureProfile.overtaking
        let speedClass = (info?.speedClass ?? "balanced").lowercased()
        let turns = info?.turns ?? 15
        let isStreet = speedClass.contains("street")
        let lengthKm = info?.lengthKm ?? 5.0

        // Expected stints based on tyre stress + lap count
        let expectedStints: Int
        if tyreStress == "High" && laps >= 55 { expectedStints = 2 }
        else if tyreStress == "High" || laps >= 65 { expectedStints = 2 }
        else if isStreet && laps <= 55 { expectedStints = 1 }
        else { expectedStints = laps >= 57 ? 2 : 1 }

        // Degradation severity
        let degradation: String
        if tyreStress == "High" && (speedClass.contains("high") || lengthKm > 5.5) { degradation = "Extreme" }
        else if tyreStress == "High" { degradation = "High" }
        else if tyreStress == "Medium" || turns >= 18 { degradation = "Medium" }
        else { degradation = "Low" }

        // Likely compounds
        let compounds: String
        if expectedStints >= 2 {
            if degradation == "Extreme" || degradation == "High" {
                compounds = "Medium \u{2192} Hard or Soft \u{2192} Hard"
            } else {
                compounds = "Soft \u{2192} Medium \u{2192} Hard"
            }
        } else {
            compounds = isStreet ? "Medium \u{2192} Hard" : "Soft \u{2192} Medium"
        }

        // Undercut potency
        let undercut: String
        if overtaking == "Track position" { undercut = "Strong" }
        else if overtaking == "Medium" || tyreStress == "High" { undercut = "Moderate" }
        else { undercut = "Weak" }

        // Overcut viability
        let overcutViable = tyreStress == "Balanced" && overtaking != "Track position"

        // Safety car likelihood from circuit geometry
        let scLikelihood: String
        if isStreet || turns >= 20 { scLikelihood = "High" }
        else if turns >= 15 || lengthKm > 5.8 { scLikelihood = "Medium" }
        else { scLikelihood = "Low" }

        // Pit window narrative
        let pitNarrative: String
        if expectedStints == 1 {
            let windowStart = Int(Double(laps) * 0.4)
            let windowEnd = Int(Double(laps) * 0.6)
            pitNarrative = "Single-stop window opens around lap \(windowStart)-\(windowEnd). Teams running hard compounds can push later."
        } else {
            let firstStop = Int(Double(laps) * 0.28)
            let secondStop = Int(Double(laps) * 0.62)
            pitNarrative = "Two-stop baseline: first window ~lap \(firstStop), second ~lap \(secondStop). Deg could force early first stops."
        }

        return TyreStrategyContext(
            expectedStints: expectedStints,
            degradationSeverity: degradation,
            likelyCompounds: compounds,
            undercutPotency: undercut,
            overcutViable: overcutViable,
            safetyCarLikelihood: scLikelihood,
            pitWindowNarrative: pitNarrative
        )
    }

    var weekendPaceHeadline: String {
        let tyreCtx = tyreStrategyContext
        switch weekendPhase {
        case .baseline:
            return "No live running yet — \(tyreCtx.expectedStints == 1 ? "one-stop baseline" : "two-stop territory") shapes the early read."
        case .postPractice:
            return "Practice data shifts the call toward long-run stability — \(tyreCtx.degradationSeverity.lowercased()) deg expected."
        case .postQualifying:
            return "Grid is live — \(tyreCtx.undercutPotency.lowercased()) undercut potency means \(tyreCtx.undercutPotency == "Strong" ? "pit timing is decisive" : "race pace can still override grid")."
        case .raceReady:
            return "Full picture: \(tyreCtx.likelyCompounds) is the base call, \(tyreCtx.safetyCarLikelihood.lowercased()) safety car risk."
        }
    }

    var longRunBias: String {
        let deg = tyreStrategyContext.degradationSeverity
        if deg == "Extreme" { return "Severe degradation — any driver who pushes hard early will crater in the second half of stints. Tyre management is the race." }
        if deg == "High" { return "High deg will punish anyone who leans on the fronts in stint one. Expect the tyre-whisperers to gain 5+ seconds by the pit window." }
        if pressureProfile.overtaking == "Track position" { return "Clean air matters more than raw deg, so expect teams to defend track position early and manage from the front." }
        return "Balanced degradation: usable long-run pace should keep the undercut live without forcing panic stops."
    }

    var firstStintShape: String {
        if liveWeather?.rainfall == true { return "Opening stint is fragile: crossover timing can wreck the first pit window. Teams will split between immediate inters and staying out." }
        let deg = tyreStrategyContext.degradationSeverity
        if deg == "Extreme" || deg == "High" { return "Expect the first stint to stretch around tyre protection, not all-out attack. Lap-one aggression will cost in the pit window." }
        if tyreStrategyContext.expectedStints >= 2 { return "Two-stop race shape means first stints stay short — teams can afford to push harder and pit early." }
        return "Opening stint should be stable enough for teams to split strategy on lap-time delta rather than survival."
    }

    var gridPressureNarrative: String {
        if qualifyingResults.isEmpty { return "Grid edge still estimated — qualifying will be the big swing factor." }
        let undercut = tyreStrategyContext.undercutPotency
        if pressureProfile.qualifyingImportance == "Massive" {
            return "Track position is king here (\(undercut.lowercased()) undercut), so any top-three start carries oversized win equity."
        }
        if undercut == "Strong" { return "Strong undercut potency means grid isn't final — a driver starting P4-P6 with better pace can jump through the pit window." }
        return "Grid matters, but pure race pace can still rewrite the order after the first stop cycle."
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

                // Phase-aware: qualify, sessions and live weather where available
                if let race = nextRace {
                    async let qualTask = service.fetchQualifyingResults(round: race.round)
                    async let weatherTask = service.fetchLiveWeather()
                    async let sessionsTask = service.fetchSessions(countryName: race.country, year: race.seasonYear)
                    let (qual, weather, sessions) = try await (qualTask, weatherTask, sessionsTask)
                    if !Task.isCancelled {
                        qualifyingResults = qual
                        liveWeather = weather
                        openF1Sessions = sessions.filter { session in
                            let name = (session.session_name ?? session.session_type ?? "").lowercased()
                            return name.contains("practice") || name.contains("qualifying") || name.contains("race") || name.contains("sprint")
                        }
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
