import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct NextRaceEntry: TimelineEntry {
    let date: Date
    let raceName: String
    let circuitName: String
    let country: String
    let raceDate: Date?
    let round: Int
    let isPlaceholder: Bool

    static var placeholder: NextRaceEntry {
        NextRaceEntry(
            date: .now,
            raceName: "Australian Grand Prix",
            circuitName: "Albert Park",
            country: "Australia",
            raceDate: Calendar.current.date(byAdding: .day, value: 5, to: .now),
            round: 1,
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
            let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
            let timeline = Timeline(entries: [entry ?? .placeholder], policy: .after(nextUpdate))
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

                let nextRace = response.MRData.RaceTable.Races.first { race in
                    guard let raceDate = formatter.date(from: race.date) else { return false }
                    return raceDate > now
                }

                guard let race = nextRace else {
                    completion(nil)
                    return
                }

                let entry = NextRaceEntry(
                    date: .now,
                    raceName: race.raceName,
                    circuitName: race.Circuit.circuitName,
                    country: race.Circuit.Location.country,
                    raceDate: formatter.date(from: race.date),
                    round: Int(race.round) ?? 0,
                    isPlaceholder: false
                )
                completion(entry)
            } catch {
                completion(nil)
            }
        }.resume()
    }
}

// MARK: - Widget Views

struct NextRaceSmallView: View {
    let entry: NextRaceEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NEXT RACE")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(widgetRed)
                    .tracking(0.6)
                Spacer()
                Text("R\(entry.round)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(entry.raceName.replacingOccurrences(of: " Grand Prix", with: ""))
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .lineLimit(2)

            Text(entry.circuitName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let raceDate = entry.raceDate {
                let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: raceDate)).day ?? 0
                HStack(spacing: 4) {
                    Text("\(days)")
                        .font(.title2)
                        .fontWeight(.black)
                        .foregroundStyle(widgetRed)
                    Text(days == 1 ? "day" : "days")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .containerBackground(widgetBackground, for: .widget)
    }
}

struct NextRaceMediumView: View {
    let entry: NextRaceEntry

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("NEXT RACE")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(widgetRed)
                        .tracking(0.6)
                    Spacer()
                }

                Text(entry.raceName.replacingOccurrences(of: " Grand Prix", with: ""))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text("\(entry.circuitName) · \(entry.country)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if let raceDate = entry.raceDate {
                    let formatter: DateFormatter = {
                        let f = DateFormatter()
                        f.dateFormat = "MMM d, yyyy"
                        return f
                    }()
                    Text(formatter.string(from: raceDate))
                        .font(.caption)
                        .foregroundStyle(.white)
                }
            }

            Spacer()

            if let raceDate = entry.raceDate {
                let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: raceDate)).day ?? 0
                VStack(spacing: 2) {
                    Text("\(days)")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(widgetRed)
                    Text(days == 1 ? "DAY" : "DAYS")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                }
                .frame(width: 80)
            }
        }
        .padding(16)
        .containerBackground(widgetBackground, for: .widget)
    }
}

// MARK: - Widget Definition

struct NextRaceWidget: Widget {
    let kind = "NextRaceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextRaceProvider()) { entry in
            if #available(iOSApplicationExtension 17.0, *) {
                NextRaceWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Next Race")
        .description("Countdown to the next Formula 1 Grand Prix.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NextRaceWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: NextRaceEntry

    var body: some View {
        switch family {
        case .systemMedium:
            NextRaceMediumView(entry: entry)
        default:
            NextRaceSmallView(entry: entry)
        }
    }
}

// MARK: - Shared Colors

let widgetRed = Color(red: 232/255, green: 0/255, blue: 45/255)
let widgetBackground = Color(red: 26/255, green: 26/255, blue: 26/255)
let widgetCardBackground = Color(red: 38/255, green: 38/255, blue: 38/255)

// MARK: - API Models (widget-local, no shared state)

struct WidgetRaceResponse: Codable {
    let MRData: WidgetMRData
}

struct WidgetMRData: Codable {
    let RaceTable: WidgetRaceTable
}

struct WidgetRaceTable: Codable {
    let Races: [WidgetRace]
}

struct WidgetRace: Codable {
    let round: String
    let raceName: String
    let Circuit: WidgetCircuit
    let date: String
}

struct WidgetCircuit: Codable {
    let circuitName: String
    let Location: WidgetLocation
}

struct WidgetLocation: Codable {
    let country: String
}

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
