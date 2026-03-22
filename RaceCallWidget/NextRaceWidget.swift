import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct NextRaceEntry: TimelineEntry {
    let date: Date
    let raceName: String
    let circuitName: String
    let country: String
    let raceDate: Date?
    let raceTime: String? // e.g. "14:00"
    let round: Int
    let circuitId: String
    let isPlaceholder: Bool

    static var placeholder: NextRaceEntry {
        NextRaceEntry(
            date: .now,
            raceName: "Australian Grand Prix",
            circuitName: "Albert Park",
            country: "Australia",
            raceDate: Calendar.current.date(byAdding: .day, value: 5, to: .now),
            raceTime: "14:00",
            round: 1,
            circuitId: "albert_park",
            isPlaceholder: true
        )
    }
}

// MARK: - Timeline Provider

struct NextRaceProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextRaceEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (NextRaceEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        fetchNextRace { entry in
            completion(entry ?? .placeholder)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextRaceEntry>) -> Void) {
        fetchNextRace { entry in
            let resolved = entry ?? .placeholder

            // Dynamic refresh: every minute if < 60 min, else hourly
            let refreshDate: Date
            if let raceDate = resolved.raceDate {
                let remaining = raceDate.timeIntervalSince(.now)
                if remaining > 0 && remaining < 3600 {
                    refreshDate = Calendar.current.date(byAdding: .minute, value: 1, to: .now) ?? .now
                } else {
                    refreshDate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
                }
            } else {
                refreshDate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
            }

            let timeline = Timeline(entries: [resolved], policy: .after(refreshDate))
            completion(timeline)
        }
    }

    private func fetchNextRace(completion: @escaping (NextRaceEntry?) -> Void) {
        guard let url = URL(string: "https://api.jolpi.ca/ergast/f1/current.json") else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data, error == nil else {
                completion(nil)
                return
            }

            do {
                let response = try JSONDecoder().decode(WidgetRaceResponse.self, from: data)
                let now = Date()
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = TimeZone(secondsFromGMT: 0)

                let dateTimeFormatter = DateFormatter()
                dateTimeFormatter.dateFormat = "yyyy-MM-dd HH:mm:ssZ"
                dateTimeFormatter.timeZone = TimeZone(secondsFromGMT: 0)

                let nextRace = response.MRData.RaceTable.Races.first { race in
                    if let time = race.time {
                        let combined = "\(race.date) \(time.replacingOccurrences(of: "Z", with: "+0000"))"
                        if let dt = dateTimeFormatter.date(from: combined) {
                            return dt > now
                        }
                    }
                    guard let raceDate = formatter.date(from: race.date) else { return false }
                    // Add 1 day buffer so race day itself still shows
                    return Calendar.current.date(byAdding: .day, value: 1, to: raceDate)! > now
                }

                guard let race = nextRace else {
                    completion(nil)
                    return
                }

                var raceDate: Date?
                if let time = race.time {
                    let combined = "\(race.date) \(time.replacingOccurrences(of: "Z", with: "+0000"))"
                    raceDate = dateTimeFormatter.date(from: combined)
                }
                if raceDate == nil {
                    raceDate = formatter.date(from: race.date)
                }

                // Extract just HH:mm from time field
                var raceTimeStr: String?
                if let time = race.time {
                    let clean = time.replacingOccurrences(of: "Z", with: "")
                    let parts = clean.components(separatedBy: ":")
                    if parts.count >= 2 {
                        raceTimeStr = "\(parts[0]):\(parts[1])"
                    }
                }

                let entry = NextRaceEntry(
                    date: .now,
                    raceName: race.raceName,
                    circuitName: race.Circuit.circuitName,
                    country: race.Circuit.Location.country,
                    raceDate: raceDate,
                    raceTime: raceTimeStr,
                    round: Int(race.round) ?? 0,
                    circuitId: race.Circuit.circuitId,
                    isPlaceholder: false
                )
                completion(entry)
            } catch {
                completion(nil)
            }
        }.resume()
    }
}

// MARK: - Smart Countdown

struct SmartCountdownView: View {
    let raceDate: Date
    let large: Bool

    var body: some View {
        let now = Date()
        let remaining = raceDate.timeIntervalSince(now)

        if remaining <= 0 {
            countdownText("LIVE", sub: "NOW")
        } else if remaining < 3600 {
            let mins = Int(remaining) / 60
            let secs = Int(remaining) % 60
            countdownText("\(mins)m \(secs)s", sub: "TO LIGHTS OUT")
        } else if remaining < 86400 {
            let hours = Int(remaining) / 3600
            let mins = (Int(remaining) % 3600) / 60
            countdownText("\(hours)h \(mins)m", sub: "TO LIGHTS OUT")
        } else if remaining < 604800 {
            let days = Int(remaining) / 86400
            let hours = (Int(remaining) % 86400) / 3600
            countdownText("\(days)d \(hours)h", sub: days == 1 ? "TO RACE DAY" : "TO RACE DAY")
        } else {
            let days = Int(remaining) / 86400
            countdownText("\(days)d", sub: "TO RACE DAY")
        }
    }

    @ViewBuilder
    private func countdownText(_ value: String, sub: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: large ? 36 : 28, weight: .black, design: .rounded))
                .foregroundStyle(widgetRed)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(sub)
                .font(.system(size: large ? 9 : 8, weight: .heavy))
                .foregroundStyle(.secondary)
                .tracking(0.6)
        }
    }
}

// MARK: - Mini Track Map

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    NextRaceWidget()
} timeline: {
    NextRaceEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    NextRaceWidget()
} timeline: {
    NextRaceEntry.placeholder
}

#Preview("Large", as: .systemLarge) {
    NextRaceWidget()
} timeline: {
    NextRaceEntry.placeholder
}
