import Foundation

struct RaceWinner: Hashable {
    let driverName: String
    let driverCode: String
    let constructor: String
}

@MainActor
@Observable
class ScheduleViewModel {
    var races: [Race] = []
    var winnerByRound: [Int: RaceWinner] = [:]
    var isLoading = false
    var error: String?

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    private let service = OpenF1Service.shared

    var completedCount: Int {
        races.filter(\.isPast).count
    }

    var nextRace: Race? {
        let now = Date()
        return races.first { race in
            guard let raceDate = race.raceDate else { return false }
            return raceDate > now
        }
    }

    var nextRaceRound: Int? {
        nextRace?.round
    }

    func loadData() async {
        loadTask?.cancel()
        isLoading = true
        error = nil

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let fetched = try await service.fetchCurrentSchedule()
                guard !Task.isCancelled else { return }
                races = fetched
                winnerByRound = await loadWinners(for: fetched)
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            isLoading = false
        }
        loadTask = task
        await task.value
    }

    private func loadWinners(for races: [Race]) async -> [Int: RaceWinner] {
        let completedRaces = races.filter(\.isPast)
        guard !completedRaces.isEmpty else { return [:] }

        return await withTaskGroup(of: (Int, RaceWinner?).self) { group in
            for race in completedRaces {
                group.addTask { [service] in
                    do {
                        let results = try await service.fetchRaceResults(round: race.round)
                        guard let winner = results.first(where: { $0.position == 1 }) else {
                            return (race.round, nil)
                        }
                        return (
                            race.round,
                            RaceWinner(
                                driverName: winner.driverName,
                                driverCode: winner.driverCode,
                                constructor: winner.constructor
                            )
                        )
                    } catch {
                        return (race.round, nil)
                    }
                }
            }

            var payload: [Int: RaceWinner] = [:]
            for await (round, winner) in group {
                if let winner {
                    payload[round] = winner
                }
            }
            return payload
        }
    }

    nonisolated deinit {
        loadTask?.cancel()
    }
}
