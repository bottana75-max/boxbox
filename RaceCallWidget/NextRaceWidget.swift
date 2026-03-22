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

struct MiniTrackMapView: View {
    let circuitId: String

    var body: some View {
        let points = WidgetTrackData.points(for: circuitId)
        if points.isEmpty {
            EmptyView()
        } else {
            Canvas { context, size in
                guard points.count > 1 else { return }

                let xs = points.map(\.0)
                let ys = points.map(\.1)
                let minX = xs.min()!, maxX = xs.max()!
                let minY = ys.min()!, maxY = ys.max()!
                let rangeX = maxX - minX
                let rangeY = maxY - minY
                guard rangeX > 0 && rangeY > 0 else { return }

                let padding: CGFloat = 4
                let drawW = size.width - padding * 2
                let drawH = size.height - padding * 2
                let scale = min(drawW / rangeX, drawH / rangeY)
                let offsetX = padding + (drawW - rangeX * scale) / 2
                let offsetY = padding + (drawH - rangeY * scale) / 2

                var path = Path()
                for (i, p) in points.enumerated() {
                    let x = offsetX + (p.0 - minX) * scale
                    let y = offsetY + (rangeY - (p.1 - minY)) * scale
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                path.closeSubpath()

                context.stroke(path, with: .color(widgetRed.opacity(0.7)), lineWidth: 1.5)
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("R\(entry.round)")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(widgetRed)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(widgetRed.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(entry.raceName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()
            }

            // Circuit info
            HStack(spacing: 6) {
                Text(entry.circuitName)
                    .font(.caption)
                    .foregroundStyle(.white)
                Text("·")
                    .foregroundStyle(.secondary)
                Text(entry.country)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Date + local time
            HStack(spacing: 8) {
                if let raceDate = entry.raceDate {
                    let formatter: DateFormatter = {
                        let f = DateFormatter()
                        f.dateFormat = "EEEE, MMM d"
                        return f
                    }()
                    Text(formatter.string(from: raceDate))
                        .font(.caption)
                        .foregroundStyle(.white)
                }
                if let raceTime = entry.raceTime {
                    Text("\(raceTime) UTC")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Track map
            MiniTrackMapView(circuitId: entry.circuitId)
                .frame(maxWidth: .infinity)
                .frame(height: 100)

            Spacer()

            // Big countdown
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

enum WidgetTrackData {
    static func points(for circuitId: String) -> [(CGFloat, CGFloat)] {
        switch circuitId {
        // Albert Park, Melbourne
        case "albert_park":
            return [(42,71),(31,60),(31,57),(31,52),(27,49),(22,43),(17,36),(13,29),(14,28),(20,27),(20,18),(21,15),(28,10),(37,6),(41,7),(49,9),(53,11),(55,15),(56,24),(54,40),(52,50),(49,60),(42,71)]
        // Bahrain
        case "bahrain":
            return [(50,95),(50,75),(45,65),(40,55),(50,50),(55,45),(50,35),(40,25),(45,15),(55,10),(60,20),(60,40),(65,50),(60,60),(55,70),(60,80),(55,90),(50,95)]
        // Jeddah
        case "jeddah":
            return [(20,95),(20,80),(15,65),(20,50),(25,40),(30,30),(35,20),(45,10),(55,5),(65,10),(70,20),(65,35),(60,50),(55,65),(50,75),(45,80),(35,85),(25,90),(20,95)]
        // Shanghai
        case "shanghai":
            return [(60,90),(45,80),(35,70),(30,55),(35,40),(45,30),(55,25),(60,30),(55,40),(45,45),(40,50),(45,60),(55,65),(65,60),(70,50),(65,40),(60,35),(70,25),(75,35),(70,50),(65,70),(60,90)]
        // Suzuka
        case "suzuka":
            return [(25,50),(30,35),(40,25),(55,20),(65,25),(70,35),(65,45),(55,50),(45,55),(40,65),(45,75),(55,80),(65,75),(70,65),(65,55),(55,50),(45,45),(35,50),(25,50)]
        // Monaco
        case "monaco":
            return [(30,85),(20,70),(15,55),(20,40),(30,30),(45,25),(60,30),(70,40),(75,55),(70,65),(60,70),(50,65),(45,70),(50,80),(40,85),(30,85)]
        // Silverstone
        case "silverstone":
            return [(55,90),(40,80),(30,70),(25,55),(30,40),(40,30),(50,25),(60,20),(70,25),(75,35),(70,50),(65,60),(70,70),(65,80),(55,90)]
        // Spa
        case "spa":
            return [(30,90),(25,75),(20,60),(25,45),(35,35),(50,30),(60,20),(70,15),(75,25),(70,40),(60,50),(50,55),(40,60),(35,70),(40,80),(35,90),(30,90)]
        // Monza
        case "monza":
            return [(50,95),(40,80),(35,65),(30,50),(35,35),(45,25),(55,20),(65,25),(70,35),(65,50),(60,65),(55,75),(60,85),(55,95),(50,95)]
        // Red Bull Ring
        case "red_bull_ring":
            return [(40,90),(30,70),(25,50),(35,35),(50,25),(65,30),(70,45),(65,60),(55,70),(50,80),(45,90),(40,90)]
        // Interlagos
        case "interlagos":
            return [(45,90),(35,75),(25,60),(20,45),(25,30),(35,20),(50,15),(60,20),(70,30),(75,45),(70,60),(60,70),(55,80),(50,90),(45,90)]
        // Yas Marina
        case "yas_marina":
            return [(50,90),(40,80),(30,65),(25,50),(30,35),(40,25),(55,20),(65,25),(70,40),(65,55),(60,65),(65,75),(60,85),(50,90)]
        // Circuit of the Americas
        case "americas":
            return [(55,90),(45,80),(35,70),(25,55),(20,40),(25,25),(35,15),(50,10),(65,15),(75,25),(70,40),(60,50),(55,60),(60,70),(55,80),(55,90)]
        // Hungaroring
        case "hungaroring":
            return [(45,90),(35,75),(25,60),(20,45),(25,30),(40,20),(55,25),(65,35),(70,50),(65,65),(55,75),(50,85),(45,90)]
        // Singapore
        case "marina_bay":
            return [(40,90),(30,75),(20,60),(25,45),(35,30),(50,25),(60,30),(70,40),(65,55),(55,65),(45,70),(40,80),(40,90)]
        // Catalunya
        case "catalunya":
            return [(50,90),(35,80),(25,65),(20,50),(25,35),(40,25),(55,20),(70,25),(75,40),(70,55),(60,65),(55,75),(50,90)]
        // Las Vegas
        case "las_vegas":
            return [(30,90),(25,70),(20,50),(25,30),(40,15),(55,10),(70,15),(75,30),(70,50),(65,65),(55,75),(40,85),(30,90)]
        // Miami
        case "miami":
            return [(40,90),(30,75),(25,55),(30,35),(45,25),(60,20),(70,30),(75,45),(70,60),(60,70),(50,80),(40,90)]
        default:
            return []
        }
    }
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

#Preview("Large", as: .systemLarge) {
    NextRaceWidget()
} timeline: {
    NextRaceEntry.placeholder
}
