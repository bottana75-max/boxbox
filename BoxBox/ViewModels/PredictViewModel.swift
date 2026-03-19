import Foundation

@MainActor
@Observable
class PredictViewModel {
    var prediction: Prediction?
    var nextRace: Race?
    var isLoading = false
    var error: String?
    var showAPIKeySheet = false

    private let service = OpenF1Service.shared
    private let aiService = AIService.shared

    var hasAPIKey: Bool { aiService.hasAPIKey }

    func saveAPIKey(_ key: String) {
        aiService.apiKey = key
    }

    func loadNextRace() async {
        do {
            let schedule = try await service.fetchCurrentSchedule()
            let now = Date()
            nextRace = schedule.first { race in
                guard let raceDate = race.raceDate else { return false }
                return raceDate > now
            }
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

        isLoading = true
        error = nil

        do {
            let standings = try await service.fetchDriverStandings()
            let (_, results) = try await service.fetchLastRaceResults()
            let recentWinners = results.prefix(3).map { $0.driverName }

            prediction = try await aiService.predictRace(
                nextRace: nextRace.raceName,
                circuitName: nextRace.circuitName,
                driverStandings: standings,
                lastRaceResults: recentWinners
            )
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
