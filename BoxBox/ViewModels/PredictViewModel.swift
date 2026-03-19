import Foundation

@MainActor
@Observable
class PredictViewModel {
    var prediction: Prediction?
    var nextRace: Race?
    var standings: [DriverStanding] = []
    var recentRaces: [(Race, [RaceResult])] = []
    var trends: [DriverTrend] = []
    var pressureProfile = CircuitPressureProfile.from(info: nil)
    var isLoading = false
    var error: String?
    var showAPIKeySheet = false
    var showPaywall = false

    private let service = OpenF1Service.shared
    private let aiService = AIService.shared
    let storeKit = StoreKitManager.shared

    var hasAPIKey: Bool { aiService.hasAPIKey }

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
        return "\(race.raceWeekendTitle) drops into \(city). Expect \(quality) qualifying, \(pressureProfile.tyreStress.lowercased()) tyre stress, \(overtaking) overtaking pressure and \(weather) conditions. Context first, AI second."
    }

    var trialStatusText: String {
        if storeKit.isProUnlocked { return "Pro — Unlimited predictions" }
        let remaining = storeKit.remainingFreePredictions
        if remaining == 0 { return "Free trial used — Upgrade to Pro" }
        return "\(remaining) free prediction\(remaining == 1 ? "" : "s") remaining"
    }

    var predictButtonTitle: String {
        if isLoading { return "Analyzing context..." }
        if !hasAPIKey { return "Add OpenAI Key" }
        if !storeKit.canPredict { return "Unlock Pro to Predict" }
        return "Generate AI Podium"
    }

    var predictButtonSubtitle: String {
        if !hasAPIKey { return "Add your OpenAI key once to unlock the prediction engine." }
        if !storeKit.canPredict { return "You’ve used the 3 free predictions. Unlock Pro to keep predicting all season." }
        return "Uses standings, recent results, timing context and circuit profile."
    }

    func saveAPIKey(_ key: String) {
        aiService.apiKey = key
    }

    func loadNextRace() async {
        error = nil
        await storeKit.checkEntitlements()
        await storeKit.loadProduct()
        do {
            async let scheduleTask = service.fetchCurrentSchedule()
            async let standingsTask = service.fetchDriverStandings()
            async let recentTask = service.fetchRecentCompletedRaces(limit: 3)

            let schedule = try await scheduleTask
            let standings = try await standingsTask
            let recent = try await recentTask
            let now = Date()
            nextRace = schedule.first { race in
                guard let raceDate = race.raceDate else { return false }
                return raceDate > now
            }
            self.standings = standings
            recentRaces = recent
            pressureProfile = CircuitPressureProfile.from(info: nextRace?.circuitInfo)
            trends = await service.buildTrends(from: standings, recentRaces: recent, limit: 5)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func predict() async {
        guard let nextRace else {
            error = "No upcoming race found"
            return
        }

        guard aiService.hasAPIKey else {
            showAPIKeySheet = true
            return
        }

        guard storeKit.canPredict else {
            showPaywall = true
            return
        }

        isLoading = true
        error = nil

        do {
            let standings = self.standings.isEmpty ? try await service.fetchDriverStandings() : self.standings
            let recentPayload = recentRaces.isEmpty ? try await service.fetchRecentCompletedRaces(limit: 3) : recentRaces
            let trendPayload = trends.isEmpty ? await service.buildTrends(from: standings, recentRaces: recentPayload, limit: 5) : trends

            prediction = try await aiService.predictRace(
                nextRace: nextRace,
                driverStandings: standings,
                recentRaces: recentPayload,
                trends: trendPayload,
                pressureProfile: pressureProfile
            )

            if !storeKit.isProUnlocked {
                storeKit.incrementPredictionCount()
            }
        } catch {
            self.error = "Something went wrong generating your prediction. Please check your API key and try again."
        }

        isLoading = false
    }
}
