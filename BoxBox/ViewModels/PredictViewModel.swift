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

    var contenderComparisonBoard: [ContenderComparisonContext] {
        let pairs = zip(contenderProfiles, contenderProfiles.dropFirst())
        return Array(pairs.prefix(3)).map { leader, challenger in
            let gap = leader.overallRating - challenger.overallRating
            let leaderStrengths = scoreEdges(for: leader)
            let challengerStrengths = scoreEdges(for: challenger)
            let leaderAdvantage = strongestAdvantage(leader: leader, challenger: challenger)
            let chasePath = strongestCounterPath(leader: leader, challenger: challenger)

            return ContenderComparisonContext(
                leader: leader.driverName,
                challenger: challenger.driverName,
                overallGap: gap,
                leaderEdge: "\(leader.driverCode) sits ahead by \(gap) on overall rating because \(leaderAdvantage).",
                challengerPath: "The route back for \(challenger.driverCode) is \(chasePath).",
                verdict: "Score mix: \(leader.driverCode) \(leaderStrengths); \(challenger.driverCode) \(challengerStrengths)."
            )
        }
    }

    var weekendScenarioContext: WeekendScenarioContext {
        let lead = contenderProfiles.first
        let runnerUp = contenderProfiles.dropFirst().first
        let leaderCode = lead?.driverCode ?? "P1 seed"
        let runnerCode = runnerUp?.driverCode ?? "next best car"
        let trackPositionMatters = pressureProfile.qualifyingImportance == "Massive" || pressureProfile.overtaking == "Track position"
        let undercut = tyreStrategyContext.undercutPotency.lowercased()
        let deg = tyreStrategyContext.degradationSeverity.lowercased()
        let rainLive = liveWeather?.rainfall == true
        let rainChance = nextRace?.weekendContext.rainChance ?? "unknown rain risk"
        let volatility = chaosLabel.lowercased()
        let pitWindow = tyreStrategyContext.pitWindowNarrative

        return WeekendScenarioContext(
            poleConversion: trackPositionMatters
                ? "If \(leaderCode) locks pole or starts front row, the race tilts heavily toward clean-air control because overtaking is \(pressureProfile.overtaking.lowercased()) and qualifying importance is \(pressureProfile.qualifyingImportance.lowercased())."
                : "Pole helps, but it does not close the door here; \(runnerCode) still stays live if long-run pace holds through the first stop.",
            frontRowMiss: trackPositionMatters
                ? "If \(leaderCode) misses the front row, win equity drops fast because passing the top cars on-track is expensive and teams will defend track position aggressively."
                : "A poor Saturday is survivable here; missing the front row matters less than arriving at lap one with stronger race pace and cleaner tyre usage.",
            tyreStressSwing: "This is a \(deg) tyre-stress weekend. If degradation runs hotter than expected, the advantage shifts toward cars that can protect the fronts and still extend to the main pit window.",
            weatherSwing: rainLive
                ? "Rain is already in play live, so crossover timing becomes the race. The order can flip instantly if a lead contender commits one lap too late to intermediates."
                : "Weather risk sits at \(rainChance). Any shower around stint two rewards drivers with grid position first, then punishes teams that burn tyre life before the crossover.",
            strategyVolatility: "Strategy volatility is \(volatility). With a \(undercut) undercut and \(pitWindow.lowercased()), anyone boxed in traffic after the first stop can lose the race without being slower.",
            safetyCarWindow: "Safety-car threat is \(tyreStrategyContext.safetyCarLikelihood.lowercased()). If neutralisation lands near the first key pit window, the race resets toward whoever has track position plus a free stop."
        )
    }

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
                gridPosition: gridPos,
                edgeNarrative: "" // placeholder, built after sort
            )
        }.sorted { $0.overallRating > $1.overallRating }

        // V2.3: Build edge narratives now that we have the sorted order
        contenderProfiles = contenderProfiles.enumerated().map { index, profile in
            let narrative = buildEdgeNarrative(for: profile, rank: index + 1)
            return ContenderProfile(
                driverName: profile.driverName,
                driverCode: profile.driverCode,
                team: profile.team,
                championshipPosition: profile.championshipPosition,
                points: profile.points,
                wins: profile.wins,
                formScore: profile.formScore,
                trackFitScore: profile.trackFitScore,
                weekendPaceScore: profile.weekendPaceScore,
                overallRating: profile.overallRating,
                momentumLabel: profile.momentumLabel,
                recentForm: profile.recentForm,
                averageFinish: profile.averageFinish,
                gridPosition: profile.gridPosition,
                edgeNarrative: narrative
            )
        }
    }

    private func scoreEdges(for contender: ContenderProfile) -> String {
        ["form \(contender.formScore)", "track \(contender.trackFitScore)", "weekend \(contender.weekendPaceScore)"]
            .joined(separator: " · ")
    }

    private func strongestAdvantage(leader: ContenderProfile, challenger: ContenderProfile) -> String {
        let deltas = [
            ("stronger recent form (\(leader.formScore) vs \(challenger.formScore))", leader.formScore - challenger.formScore),
            ("better track fit for this circuit (\(leader.trackFitScore) vs \(challenger.trackFitScore))", leader.trackFitScore - challenger.trackFitScore),
            ("more convincing weekend pace so far (\(leader.weekendPaceScore) vs \(challenger.weekendPaceScore))", leader.weekendPaceScore - challenger.weekendPaceScore)
        ].sorted { $0.1 > $1.1 }

        if let best = deltas.first, best.1 > 0 {
            return best.0
        }

        if let gridA = leader.gridPosition, let gridB = challenger.gridPosition, gridA < gridB {
            return "the better grid slot (P\(gridA) vs P\(gridB)) on a weekend where track position matters"
        }

        return "the cleaner overall mix of form, track fit and race pace"
    }

    private func strongestCounterPath(leader: ContenderProfile, challenger: ContenderProfile) -> String {
        if let gridA = leader.gridPosition, let gridB = challenger.gridPosition, gridB < gridA {
            return "using the better grid slot (P\(gridB)) to control stint one before \(leader.driverCode) gets clean air"
        }

        let deltas = [
            ("leaning on stronger form if Sunday execution matches the last three rounds", challenger.formScore - leader.formScore),
            ("turning a better circuit fit into lower tyre loss over the long run", challenger.trackFitScore - leader.trackFitScore),
            ("keeping pressure on through the first stop because current weekend pace is stronger", challenger.weekendPaceScore - leader.weekendPaceScore)
        ].sorted { $0.1 > $1.1 }

        if let best = deltas.first, best.1 > 0 {
            return best.0
        }

        return "forcing strategy offset — the undercut, overcut or a safety-car stop is the cleanest way past"
    }

    // V2.3: Explain why a contender is ranked where they are
    private func buildEdgeNarrative(for profile: ContenderProfile, rank: Int) -> String {
        let strongestFactor: String
        let scores = [(label: "form", value: profile.formScore),
                      (label: "track fit", value: profile.trackFitScore),
                      (label: "weekend pace", value: profile.weekendPaceScore)]
        let best = scores.max(by: { $0.value < $1.value })!
        let worst = scores.min(by: { $0.value < $1.value })!
        strongestFactor = best.label

        let tyreCtx = tyreStrategyContext
        let overtaking = pressureProfile.overtaking
        let qualImportance = pressureProfile.qualifyingImportance

        // Build a concrete, editorial narrative
        if rank == 1 {
            if let grid = profile.gridPosition, grid <= 2 && qualImportance == "Massive" {
                return "Starting P\(grid) on a track-position circuit with the highest \(strongestFactor) score (\(best.value)) — hardest to beat."
            }
            if best.value >= 80 {
                return "Leading on \(strongestFactor) (\(best.value)) and \(profile.momentumLabel.lowercased()) momentum. The benchmark this weekend."
            }
            return "Strongest combined profile — \(best.value) \(strongestFactor), \(profile.overallRating) overall. Clear frontrunner."
        }

        // Contenders 2-3: explain the gap to #1
        if rank <= 3 {
            if let grid = profile.gridPosition {
                let gridNote = grid <= 3 ? "grid advantage (P\(grid))" : "needs to make up ground from P\(grid)"
                if worst.value < 45 {
                    return "\(gridNote.capitalized), but \(worst.label) vulnerability (\(worst.value)) could cost positions in \(tyreCtx.degradationSeverity.lowercased()) deg."
                }
                return "\(gridNote.capitalized). \(strongestFactor.capitalized) (\(best.value)) keeps them in the podium fight."
            }
            if worst.value < 45 {
                return "\(strongestFactor.capitalized) strength (\(best.value)) offset by weaker \(worst.label) (\(worst.value)) — podium depends on strategy."
            }
            return "Balanced profile, \(profile.overallRating) overall. Podium upside if \(strongestFactor) holds under race stress."
        }

        // Mid-pack (4-6): focus on what could lift them
        if overtaking == "High" && profile.formScore >= 60 {
            return "\(strongestFactor.capitalized) (\(best.value)) and high-overtaking layout give a route into the top 3 from P\(profile.gridPosition.map { "\($0)" } ?? "mid-grid")."
        }
        if let grid = profile.gridPosition, grid <= 5 {
            return "P\(grid) grid start outperforms their \(profile.overallRating) rating — track position could hold if deg stays \(tyreCtx.degradationSeverity.lowercased())."
        }
        if worst.value < 35 {
            return "\(worst.label.capitalized) weakness (\(worst.value)) limits ceiling, but \(strongestFactor) (\(best.value)) could matter if chaos hits."
        }
        return "\(strongestFactor.capitalized) (\(best.value)) is the lever — needs a safety car or strategy split to break into the top 4."
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

        let comparisons = contenderComparisonBoard
        let scenarios = weekendScenarioContext

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
            comparisonBoard: comparisons,
            weekendScenarios: scenarios,
            recentRaces: recentContext,
            confidenceLabel: confidenceLabel,
            chaosLabel: chaosLabel,
            confidenceScore: confidenceRawScore,
            chaosScore: chaosRawScore
        )
    }

    // MARK: - V2.3 Comparison Board

    var contenderComparisonBoard: [ContenderComparisonContext] {
        guard contenderProfiles.count >= 2 else { return [] }
        let tyreCtx = tyreStrategyContext

        // Build pairwise comparisons: #1 vs #2, #1 vs #3, #2 vs #3
        var pairs: [(Int, Int)] = [(0, 1)]
        if contenderProfiles.count >= 3 { pairs.append(contentsOf: [(0, 2), (1, 2)]) }

        return pairs.map { i, j in
            let top = contenderProfiles[i]
            let challenger = contenderProfiles[j]
            let gap = top.overallRating - challenger.overallRating

            let formGap = top.formScore - challenger.formScore
            let trackGap = top.trackFitScore - challenger.trackFitScore
            let paceGap = top.weekendPaceScore - challenger.weekendPaceScore
            let edges = [(label: "form", gap: formGap), (label: "track fit", gap: trackGap), (label: "weekend pace", gap: paceGap)]
            let bestEdge = edges.max(by: { $0.gap < $1.gap })!

            let leaderEdge: String
            if bestEdge.gap > 0 {
                leaderEdge = "\(top.driverCode) leads on \(bestEdge.label) by \(bestEdge.gap) points — \(bestEdge.label == "track fit" ? "circuit suits their car" : bestEdge.label == "form" ? "recent results give them momentum" : "stronger weekend running")."
            } else {
                leaderEdge = "\(top.driverCode) has the higher combined rating despite no single dominant factor — consistency across form, track fit, and pace."
            }

            let challengerBest = edges.min(by: { $0.gap < $1.gap })!
            var path: String
            if let cGrid = challenger.gridPosition, let tGrid = top.gridPosition, cGrid < tGrid {
                path = "Grid advantage (P\(cGrid) vs P\(tGrid)) — if track position holds through stint 1, \(challenger.driverCode) can control the race."
            } else if tyreCtx.degradationSeverity == "High" || tyreCtx.degradationSeverity == "Extreme" {
                path = "\(tyreCtx.degradationSeverity) deg could close the gap — if \(challenger.driverCode) manages tyres better through \(tyreCtx.likelyCompounds), the \(gap)-point rating gap shrinks."
            } else if challengerBest.gap <= 0 {
                path = "\(challenger.driverCode) actually leads on \(challengerBest.label) — a strategy split or undercut could overturn the overall gap."
            } else {
                path = "\(challenger.driverCode) needs a safety car or weather change to close the \(gap)-point overall deficit."
            }

            let verdict: String
            if gap >= 15 {
                verdict = "\(top.driverCode) is the clear favourite — \(challenger.driverCode) needs disruption."
            } else if gap >= 8 {
                verdict = "\(top.driverCode) has the edge, but \(challenger.driverCode) is within striking distance through strategy."
            } else {
                verdict = "Razor-thin margins — this matchup will be decided by pit wall execution and lap-1 positioning."
            }

            return ContenderComparisonContext(
                leader: top.driverName,
                challenger: challenger.driverName,
                overallGap: gap,
                leaderEdge: leaderEdge,
                challengerPath: path,
                verdict: verdict
            )
        }
    }

    // MARK: - V2.3 Weekend Scenario Context

    var weekendScenarioContext: WeekendScenarioContext {
        let tyreCtx = tyreStrategyContext
        let overtaking = pressureProfile.overtaking
        let qualImportance = pressureProfile.qualifyingImportance
        let laps = nextRace?.circuitInfo?.laps ?? 55

        let poleConversion: String
        if qualImportance == "Massive" || overtaking == "Track position" {
            poleConversion = "Pole is near-decisive. Converting from P1 has historically been 70%+ at low-overtaking circuits — whoever qualifies ahead controls the race."
        } else if overtaking == "High" {
            poleConversion = "Pole matters less here. High overtaking and \(tyreCtx.expectedStints == 2 ? "two" : "one") stop\(tyreCtx.expectedStints == 2 ? "s" : "") mean race pace can override grid by lap \(laps / 3)."
        } else {
            poleConversion = "Pole is an advantage but not decisive. The undercut window around lap \(Int(Double(laps) * 0.28)) will determine whether P1 holds or gets jumped."
        }

        let frontRowMiss: String
        if qualImportance == "Massive" {
            frontRowMiss = "Missing the front row is costly — starting P3+ on a track-position circuit drops win probability by 40%+. Recovery depends entirely on the undercut."
        } else {
            frontRowMiss = "Starting outside the front row is recoverable. \(overtaking) overtaking and \(tyreCtx.undercutPotency.lowercased()) undercut potency mean P3-P5 starters can still win through strategy."
        }

        let tyreStressSwing: String
        switch tyreCtx.degradationSeverity {
        case "Extreme":
            tyreStressSwing = "Extreme deg reshuffles the field. Teams that overheat fronts in stints 1-2 will drop 3+ positions through the pit window. Tyre-saving drivers gain 8-12 seconds over stint pushers."
        case "High":
            tyreStressSwing = "High deg favours patience. Drivers who push in the first 10 laps of each stint will pay in the final third — expect 5-8 second swings between tyre managers and sprint-style runners."
        case "Medium":
            tyreStressSwing = "Medium deg keeps strategy honest. Enough degradation to reward good management, but not enough to force defensive driving — the pit wall has real choices."
        default:
            tyreStressSwing = "Low deg neutralises tyre strategy as a differentiator. Race pace and track position dominate — the tyre-whisperer advantage is minimal."
        }

        let weatherSwing: String
        if liveWeather?.rainfall == true {
            weatherSwing = "Rain is active. Crossover to inters/wets could happen any lap — teams that time the switch within a 2-lap window will gain 15+ seconds on those who gamble."
        } else if let race = nextRace {
            let rain = race.weekendContext.rainChance
            if rain.contains("60") || rain.contains("70") || rain.contains("80") || rain.contains("90") {
                weatherSwing = "High rain risk (\(rain)) makes strategy volatile. A mid-race shower would trigger a full-field scramble — teams on older tyres benefit from a free pit stop."
            } else if rain.contains("30") || rain.contains("40") || rain.contains("50") {
                weatherSwing = "Moderate rain risk (\(rain)) adds a wildcard. Teams may split strategy pre-emptively — one car short-fuelling for a rain gamble, the other running dry baseline."
            } else {
                weatherSwing = "Low rain risk — weather is unlikely to disrupt the baseline strategy. Track evolution follows the normal rubber-down pattern."
            }
        } else {
            weatherSwing = "Weather data unavailable — assume dry baseline."
        }

        let strategyVolatility: String
        if tyreCtx.undercutPotency == "Strong" && tyreCtx.expectedStints >= 2 {
            strategyVolatility = "Strategy is the primary battleground. Strong undercut + 2 stops = 4 potential position changes through pit sequencing alone."
        } else if tyreCtx.overcutViable {
            strategyVolatility = "Overcut is live alongside the undercut — teams have genuine optionality. Expect strategy divergence creating temporary on-track battles."
        } else {
            strategyVolatility = "Strategy convergence likely — most teams will follow a similar \(tyreCtx.expectedStints)-stop \(tyreCtx.likelyCompounds) plan. Differentiation comes from execution."
        }

        let earlyLap = Int(Double(laps) * 0.15)
        let midLap = Int(Double(laps) * 0.45)
        let scWindow: String
        switch tyreCtx.safetyCarLikelihood {
        case "High":
            scWindow = "High SC probability. An SC before lap \(earlyLap) helps leaders (free tyre change), around lap \(midLap) helps those who haven't pitted. Circuit geometry makes incidents likely."
        case "Medium":
            scWindow = "Medium SC risk. If it happens around lap \(midLap), it inverts strategy — teams committed to their first stop lose the tyre advantage, while those who delayed get a free pit."
        default:
            scWindow = "Low SC probability — plan for a green-flag race. Strategy should assume uninterrupted running."
        }

        return WeekendScenarioContext(
            poleConversion: poleConversion,
            frontRowMiss: frontRowMiss,
            tyreStressSwing: tyreStressSwing,
            weatherSwing: weatherSwing,
            strategyVolatility: strategyVolatility,
            safetyCarWindow: scWindow
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
