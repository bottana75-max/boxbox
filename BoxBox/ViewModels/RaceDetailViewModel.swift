import Foundation

@MainActor
@Observable
class RaceDetailViewModel {
    let race: Race
    var results: [RaceResult] = []
    var isLoading = false
    var error: String?
    var countdown: String = ""

    private var timer: Timer?

    init(race: Race) {
        self.race = race
    }

    func loadData() async {
        if race.isPast {
            isLoading = true
            error = nil
            do {
                results = try await OpenF1Service.shared.fetchRaceResults(round: race.round)
            } catch {
                self.error = "Results not available yet"
            }
            isLoading = false
        } else {
            updateCountdown()
            startCountdownTimer()
        }
    }

    func startCountdownTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCountdown()
            }
        }
    }

    private func updateCountdown() {
        guard let raceDate = race.raceDate else {
            countdown = "Date TBD"
            return
        }
        let now = Date()
        if raceDate <= now {
            countdown = "Race started!"
            timer?.invalidate()
            return
        }
        let components = Calendar.current.dateComponents([.day, .hour, .minute, .second], from: now, to: raceDate)
        let d = components.day ?? 0
        let h = components.hour ?? 0
        let m = components.minute ?? 0
        let s = components.second ?? 0
        countdown = "\(d)d \(h)h \(m)m \(s)s"
    }

    deinit {
        timer?.invalidate()
    }
}
