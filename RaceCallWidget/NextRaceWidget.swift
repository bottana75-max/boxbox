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

// MARK: - Widget Views

struct NextRaceSmallView: View {
    let entry: NextRaceEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                SmartCountdownView(raceDate: raceDate, large: false)
            }
        }
        .padding(14)
        .widgetURL(URL(string: "racecall://schedule"))
        .containerBackground(widgetBackground, for: .widget)
    }
}

struct NextRaceMediumView: View {
    let entry: NextRaceEntry

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
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
                    HStack(spacing: 8) {
                        let formatter: DateFormatter = {
                            let f = DateFormatter()
                            f.dateFormat = "MMM d"
                            return f
                        }()
                        Text(formatter.string(from: raceDate))
                            .font(.caption)
                            .foregroundStyle(.white)
                        if let raceTime = entry.raceTime {
                            Text("\(raceTime) UTC")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()

            if let raceDate = entry.raceDate {
                SmartCountdownView(raceDate: raceDate, large: false)
                    .frame(width: 90)
            }
        }
        .padding(16)
        .widgetURL(URL(string: "racecall://schedule"))
        .containerBackground(widgetBackground, for: .widget)
    }
}

struct NextRaceLargeView: View {
    let entry: NextRaceEntry

    private var circuitStats: (laps: Int, km: Double)? {
        WidgetCircuitStats.stats(for: entry.circuitId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // — Top bar —
            HStack(spacing: 8) {
                Text("RACE CALL")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(widgetRed)
                Spacer()
                Text("ROUND \(entry.round)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
            }
            .padding(.bottom, 12)

            // — Race name —
            Text(entry.raceName)
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text("\(entry.circuitName) · \(entry.country)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            // — Divider —
            Rectangle()
                .fill(widgetRed.opacity(0.3))
                .frame(height: 1)
                .padding(.vertical, 14)

            // — Date row —
            HStack(spacing: 16) {
                if let raceDate = entry.raceDate {
                    let formatter: DateFormatter = {
                        let f = DateFormatter()
                        f.dateFormat = "EEE, MMM d"
                        return f
                    }()
                    Label(formatter.string(from: raceDate), systemImage: "calendar")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                }
                if let raceTime = entry.raceTime {
                    Label("\(raceTime) UTC", systemImage: "clock")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // — Circuit stats —
            if let stats = circuitStats {
                HStack(spacing: 16) {
                    Label("\(stats.laps) laps", systemImage: "repeat")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Label(String(format: "%.3f km", stats.km), systemImage: "road.lanes")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }

            Spacer()

            // — Countdown —
            if let raceDate = entry.raceDate {
                HStack {
                    Spacer()
                    SmartCountdownView(raceDate: raceDate, large: true)
                    Spacer()
                }
            }
        }
        .padding(16)
        .widgetURL(URL(string: "racecall://schedule"))
        .containerBackground(widgetBackground, for: .widget)
    }
}

// MARK: - Circuit Stats

enum WidgetCircuitStats {
    static func stats(for circuitId: String) -> (laps: Int, km: Double)? {
        let data: [String: (Int, Double)] = [
            "albert_park": (58, 5.278), "bahrain": (57, 5.412), "jeddah": (50, 6.174),
            "shanghai": (56, 5.451), "suzuka": (53, 5.807), "sakhir": (57, 5.412),
            "miami": (57, 5.412), "imola": (63, 4.909), "monaco": (78, 3.337),
            "catalunya": (66, 4.657), "villeneuve": (70, 4.361), "red_bull_ring": (71, 4.318),
            "silverstone": (52, 5.891), "hungaroring": (70, 4.381), "spa": (44, 7.004),
            "zandvoort": (72, 4.259), "monza": (53, 5.793), "baku": (51, 6.003),
            "marina_bay": (62, 4.940), "americas": (56, 5.513), "rodriguez": (71, 4.304),
            "interlagos": (71, 4.309), "las_vegas": (50, 6.201), "losail": (57, 5.380),
            "yas_marina": (58, 5.281)
        ]
        guard let s = data[circuitId] else { return nil }
        return (s.0, s.1)
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct NextRaceWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: NextRaceEntry

    var body: some View {
        switch family {
        case .systemLarge:
            NextRaceLargeView(entry: entry)
        case .systemMedium:
            NextRaceMediumView(entry: entry)
        default:
            NextRaceSmallView(entry: entry)
        }
    }
}

// MARK: - Shared Colors

let widgetRed = Color(red: 232/255, green: 0/255, blue: 45/255)
let widgetBackground = Color(red: 17/255, green: 17/255, blue: 17/255) // #111111
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
    let time: String?
}

struct WidgetCircuit: Codable {
    let circuitId: String
    let circuitName: String
    let Location: WidgetLocation
}

struct WidgetLocation: Codable {
    let country: String
}

// MARK: - Track Map Data (self-contained fallback, ~10 points per circuit)

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
