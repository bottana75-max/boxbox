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
    var showPaywall = false

    private let service = OpenF1Service.shared
    private let aiService = AIService.shared
    let storeKit = StoreKitManager.shared

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
        if storeKit.isUnlimited { return "Pro unlocked - unlimited predictions" }
        let remaining = max(0, storeKit.credits)
        if remaining == 0 { return "Free trial finished - unlock Pro to keep predicting" }
        return "\(remaining) free prediction\(remaining == 1 ? "" : "s") remaining"
    }

    var predictButtonTitle: String {
        if isLoading { return "Analyzing context..." }
        if nextRace == nil { return "No Race To Predict Yet" }
        if !storeKit.canPredict { return "Get More Predictions" }
        return "Generate AI Podium"
    }

    var predictButtonSubtitle: String {
        if nextRace == nil { return "We'll light this up as soon as the next grand prix is on the board." }
        if !storeKit.canPredict { return "You've used all your predictions. Unlock more to keep predicting." }
        return "Uses standings, recent results and circuit profile."
    }

    func loadNextRace(forceRefresh: Bool = false) async {
        // Always show the loading indicator on the initial load.
        // On pull-to-refresh (forceRefresh: true) the system spinner is enough.
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
            let fetchedStandings = try await standingsTask
            let fetchedRecent = try await recentTask
            let now = Date()
            nextRace = schedule.first { race in
                guard let raceDate = race.raceDate else { return false }
                return raceDate > now
            }
            standings = fetchedStandings
            recentRaces = fetchedRecent
            pressureProfile = CircuitPressureProfile.from(info: nextRace?.circuitInfo)
            trends = service.buildTrends(from: fetchedStandings, recentRaces: fetchedRecent, limit: 5)
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

        guard storeKit.canPredict else {
            showPaywall = true
            return
        }

        isLoading = true
        error = nil

        do {
            // Use already-loaded data where available; only fetch if the view was somehow bypassed.
            let activeStandings = standings.isEmpty ? try await service.fetchDriverStandings() : standings
            let activeRecent = recentRaces.isEmpty ? try await service.fetchRecentCompletedRaces(limit: 3) : recentRaces
            let activeTrends = trends.isEmpty
                ? service.buildTrends(from: activeStandings, recentRaces: activeRecent, limit: 5)
                : trends

            prediction = try await aiService.predictRace(
                nextRace: nextRace,
                driverStandings: activeStandings,
                recentRaces: activeRecent,
                trends: activeTrends,
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
