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
    var savedAPIKey: String { aiService.apiKey ?? "" }

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
        if storeKit.isUnlimited { return "Pro unlocked — unlimited predictions" }
        let remaining = max(0, storeKit.credits)
        if remaining == 0 { return "Free trial finished — unlock Pro to keep predicting" }
        return "\(remaining) free prediction\(remaining == 1 ? "" : "s") remaining"
    }

    var predictButtonTitle: String {
        if isLoading { return "Analyzing context..." }
        if nextRace == nil { return "No Race To Predict Yet" }
        if !hasAPIKey { return "Add OpenAI Key" }
        if !storeKit.canPredict { return "Unlock Pro to Predict" }
        return "Generate AI Podium"
    }

    var predictButtonSubtitle: String {
        if nextRace == nil { return "We’ll light this up as soon as the next grand prix is on the board." }
        if !hasAPIKey { return "Add your OpenAI key once to unlock the prediction engine." }
        if !storeKit.canPredict { return "You’ve used the 3 free predictions. Unlock Pro to keep predicting all season." }
        return "Uses standings, recent results, timing context and circuit profile."
    }

    func saveAPIKey(_ key: String) {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        aiService.apiKey = trimmedKey.isEmpty ? nil : trimmedKey
        error = nil
    }

    func loadNextRace(forceRefresh: Bool = false) async {
        if !forceRefresh {
            isLoading = true
        }

        error = nil
        await storeKit.restorePurchases()
        await storeKit.loadProducts()
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

        isLoading = false
    }

    func predict() async {
        guard let nextRace else {
            error = "The next grand prix is not available yet. Pull to refresh and try again shortly."
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

            if !storeKit.isUnlimited {
                storeKit.consumeCredit()
            }
        } catch {
            self.error = "Something went wrong generating your prediction. Check your API key, connection and try again."
        }

        isLoading = false
    }
}
