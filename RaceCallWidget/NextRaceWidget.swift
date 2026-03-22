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
        // Albert Park — GeoJSON real coordinates
        case "albert_park":
            return [(42.3,71.4),(31.1,60.1),(30.5,58.9),(31.3,57.5),(31.6,54.8),(30.7,51.7),(27.5,48.6),(22.1,43.0),(16.9,35.9),(13.3,29.2),(14.1,28.0),(19.7,26.9),(20.2,18.8),(21.0,15.5),(28.0,10.4),(37.5,6.2),(41.3,7.3),(49.2,9.2),(53.1,11.6),(55.3,15.4),(56.2,24.1),(54.1,40.2),(52.0,50.1),(49.4,60.5),(42.3,71.4)]
        // Bahrain
        case "bahrain":
            return [(21.5,47.6),(22.2,22.3),(23.2,5.0),(28.6,8.9),(37.9,7.1),(78.2,14.8),(80.4,16.8),(79.8,18.8),(78.0,20.6),(72.0,25.1),(67.3,30.0),(63.4,36.5),(56.8,36.4),(52.3,38.3),(42.8,50.1),(40.6,46.7),(43.9,26.4),(38.3,18.2),(36.7,28.4),(35.8,46.3),(34.9,69.3),(38.4,73.1),(44.1,71.6),(50.4,62.0),(60.1,56.0)]
        // Jeddah
        case "jeddah":
            return [(54.6,74.2),(49.5,60.5),(47.8,59.0),(48.7,55.5),(47.3,46.3),(44.3,43.1),(44.6,40.8),(44.8,35.0),(43.0,29.8),(47.4,22.4),(48.1,18.7),(47.5,6.2),(43.5,7.2),(44.8,10.8),(44.1,23.7),(40.7,26.4),(40.6,31.8),(43.2,43.5),(46.1,49.7),(47.1,53.7),(46.9,61.5),(48.5,63.0),(54.6,74.2)]
        // Shanghai
        case "shanghai":
            return [(28.6,81.3),(20.6,83.1),(14.1,79.9),(13.1,76.7),(14.9,72.0),(19.3,71.7),(20.2,73.7),(21.5,79.3),(24.8,75.9),(22.5,68.7),(9.4,52.6),(5.0,37.4),(12.2,42.0),(25.2,59.1),(34.4,56.5),(41.2,46.0),(47.6,46.4),(54.5,54.6),(58.8,49.4),(51.0,35.2),(39.1,19.6),(32.2,15.7),(34.2,21.2),(39.4,21.1),(51.4,29.2),(61.2,30.9),(68.2,28.6),(73.2,18.3),(76.4,12.3),(82.7,12.7),(89.4,18.0),(93.5,26.6),(95.0,35.4),(93.0,44.8),(87.2,56.3),(78.4,64.2),(65.4,72.0),(55.4,75.4),(43.4,76.8),(28.6,81.3)]
        // Suzuka
        case "suzuka":
            return [(81.9,51.6),(94.5,67.1),(93.3,73.6),(85.2,66.1),(78.7,63.7),(75.0,57.2),(68.4,54.2),(69.5,48.9),(67.0,44.3),(59.6,43.1),(50.2,51.7),(42.1,51.5),(39.6,38.4),(37.9,35.2),(27.0,41.2),(15.3,33.6),(9.3,26.0),(11.2,36.0),(27.4,43.6),(38.4,45.0),(44.1,46.0),(47.0,49.5),(55.1,51.4),(63.8,55.0),(71.7,59.9),(79.8,60.9),(81.9,51.6)]
        // Monaco
        case "monaco":
            return [(60.5,22.4),(71.2,5.7),(75.0,7.5),(79.1,14.0),(83.9,5.3),(83.0,18.8),(79.0,29.0),(66.6,39.3),(47.5,45.5),(25.6,49.2),(20.3,62.0),(25.8,86.2),(31.5,91.2),(24.9,93.4),(17.8,76.7),(16.1,57.9),(17.3,52.1),(23.1,50.1),(44.2,46.7),(52.9,44.1),(60.5,22.4)]
        // Silverstone
        case "silverstone":
            return [(55.3,5.7),(70.1,7.2),(73.8,30.4),(76.7,49.6),(74.6,55.2),(55.3,85.8),(47.3,95.0),(37.1,83.9),(27.4,79.1),(24.0,75.2),(24.4,69.6),(38.7,50.9),(53.5,49.0),(68.5,38.5),(68.0,47.4),(62.0,42.4),(55.3,5.7)]
        // Spa
        case "spa":
            return [(39.0,14.4),(55.4,22.4),(65.2,37.9),(76.8,72.1),(75.0,87.5),(63.2,95.0),(67.5,87.6),(64.0,70.9),(56.7,63.1),(45.9,79.6),(39.3,80.4),(30.1,89.6),(22.7,84.9),(23.0,79.9),(31.7,69.3),(39.0,53.8),(34.2,5.0),(39.0,14.4)]
        // Monza
        case "monza":
            return [(25.7,62.2),(27.9,36.9),(28.5,29.5),(29.6,20.5),(38.5,12.4),(57.8,10.5),(71.8,5.0),(75.5,11.3),(76.0,18.3),(66.3,24.1),(52.0,35.1),(40.0,50.2),(37.5,56.3),(33.7,92.3),(25.7,62.2)]
        // Red Bull Ring
        case "red_bull_ring":
            return [(65.0,72.5),(42.4,78.4),(26.5,54.4),(10.1,28.9),(5.0,22.8),(18.7,21.6),(40.7,25.4),(62.4,28.7),(59.6,33.6),(50.0,37.9),(30.2,39.4),(35.9,54.0),(43.4,55.4),(54.9,47.7),(65.0,72.5)]
        // Interlagos
        case "interlagos":
            return [(44.5,28.2),(72.5,38.1),(67.0,44.7),(53.2,45.2),(50.8,62.2),(58.4,67.3),(74.5,57.3),(80.8,35.7),(95.0,31.5),(92.0,25.8),(44.5,22.2),(5.0,32.0),(9.1,40.6),(21.4,49.8),(19.1,62.0),(21.7,69.4),(36.0,74.2),(44.5,28.2)]
        // Yas Marina
        case "yas_marina":
            return [(49.5,55.5),(63.6,51.7),(61.4,42.4),(51.2,30.8),(52.7,20.2),(47.3,6.4),(34.6,45.2),(28.9,63.9),(33.9,69.7),(52.3,87.8),(65.4,94.5),(70.9,89.9),(68.1,87.2),(51.1,82.8),(48.9,75.5),(53.5,74.5),(54.3,74.1),(62.7,53.6),(49.5,55.5)]
        // Austin / COTA
        case "americas":
            return [(23.0,66.3),(42.1,57.8),(51.7,45.3),(63.5,44.5),(73.1,42.0),(88.3,33.7),(95.0,25.1),(71.4,30.6),(39.1,35.3),(43.0,45.0),(37.5,43.1),(31.9,40.1),(36.5,48.9),(46.1,52.8),(34.5,63.8),(36.8,74.8),(23.0,66.3)]
        // Hungaroring
        case "hungaroring":
            return [(30.0,72.9),(10.7,57.6),(16.9,54.2),(40.3,68.1),(44.4,63.9),(40.4,56.5),(52.6,28.4),(56.4,21.8),(53.2,9.2),(62.5,7.1),(73.0,18.0),(74.1,31.0),(83.3,35.0),(85.3,38.9),(83.9,49.7),(89.8,61.2),(88.8,65.7),(71.1,85.8),(68.5,85.5),(30.0,72.9)]
        // Singapore
        case "marina_bay":
            return [(93.0,43.0),(95.0,58.5),(91.7,64.1),(75.3,63.0),(72.4,59.4),(43.2,56.6),(31.0,47.5),(26.3,54.1),(21.4,78.5),(16.7,75.3),(10.6,68.4),(5.0,60.5),(6.0,57.8),(16.8,38.4),(20.5,37.6),(28.2,45.0),(34.4,34.5),(53.2,43.6),(82.7,45.6),(84.2,43.8),(93.0,43.0)]
        // Catalunya
        case "catalunya":
            return [(71.3,45.2),(51.0,77.4),(40.8,91.3),(25.1,94.5),(13.4,85.1),(16.3,75.3),(32.9,61.1),(34.0,65.6),(25.1,82.4),(29.0,85.2),(49.3,66.7),(43.9,61.6),(38.0,47.8),(74.1,23.0),(70.0,16.7),(59.3,20.9),(46.1,63.9),(71.3,45.2)]
        // Las Vegas
        case "las_vegas":
            return [(91.7,11.2),(98.3,16.6),(91.6,18.4),(78.5,14.3),(70.2,19.2),(69.6,63.1),(90.6,63.9),(99.8,70.6),(95.3,75.3),(97.9,78.8),(93.6,81.7),(54.6,85.7),(44.9,96.7),(29.6,100.0),(27.7,98.5),(21.0,85.0),(15.0,70.0),(12.0,55.0),(15.0,40.0),(20.0,25.0),(28.0,15.0),(55.0,11.5),(91.7,11.2)]
        // Miami
        case "miami":
            return [(49.4,72.6),(63.0,50.9),(58.9,37.9),(58.6,22.9),(52.3,11.2),(42.6,13.9),(26.3,37.7),(14.0,31.6),(5.9,40.6),(0.4,30.5),(0.0,26.0),(3.3,16.5),(10.6,15.4),(24.6,12.4),(42.3,7.7),(53.5,0.0),(66.2,5.3),(90.0,30.9),(93.5,36.6),(80.0,55.0),(65.0,65.0),(49.4,72.6)]
        // Baku
        case "baku":
            return [(87.8,34.0),(95.0,30.5),(89.5,17.4),(64.2,27.4),(57.5,40.7),(45.1,48.4),(45.6,50.6),(34.8,59.6),(29.1,53.8),(24.5,52.2),(19.1,51.3),(5.0,66.8),(6.3,77.1),(20.5,82.0),(23.5,76.4),(28.2,65.0),(35.0,58.0),(42.0,52.0),(45.0,50.5),(50.0,48.0),(57.0,45.0),(87.8,34.0)]
        // Zandvoort
        case "zandvoort":
            return [(16.0,46.7),(30.0,13.3),(36.8,14.7),(31.0,38.9),(21.0,44.5),(23.2,49.6),(40.9,46.0),(63.3,45.6),(74.8,41.0),(92.7,44.4),(95.0,52.9),(83.4,73.7),(66.7,69.9),(67.5,63.1),(80.5,59.5),(81.0,51.7),(51.0,52.9),(31.7,58.9),(29.6,56.4),(16.0,46.7)]
        // Imola
        case "imola":
            return [(62.1,32.1),(47.0,29.6),(28.0,34.5),(14.1,57.4),(14.8,61.5),(5.0,71.0),(6.3,73.3),(23.2,71.3),(34.9,72.4),(38.0,65.8),(36.1,54.3),(39.1,49.3),(63.5,50.2),(74.3,47.6),(81.7,41.4),(81.5,37.0),(62.1,32.1)]
        // Qatar / Lusail
        case "losail":
            return [(25.2,59.5),(12.0,35.5),(13.2,31.2),(15.6,30.3),(26.3,36.3),(30.8,35.1),(31.4,24.7),(33.0,20.9),(47.1,5.4),(51.4,5.8),(55.8,10.4),(46.4,23.9),(46.6,26.5),(49.5,26.5),(65.7,20.3),(69.5,23.8),(65.5,29.5),(62.4,35.8),(59.2,40.9),(49.8,43.4),(48.9,46.9),(51.5,49.7),(64.4,54.8),(82.8,54.0),(84.8,56.2),(25.2,59.5)]
        // Mexico City
        case "rodriguez":
            return [(21.4,18.8),(62.3,24.0),(92.8,29.4),(95.0,36.6),(92.3,45.6),(75.6,72.8),(78.3,77.2),(72.6,82.2),(72.5,61.9),(65.9,54.7),(53.5,50.5),(51.3,45.9),(38.5,39.1),(15.2,24.7),(21.4,18.8)]
        // Montreal / Villeneuve
        case "villeneuve":
            return [(59.9,70.1),(62.3,84.2),(64.6,93.2),(61.4,94.8),(55.0,92.0),(50.1,87.7),(46.3,79.4),(42.2,66.5),(37.0,63.8),(35.4,50.7),(38.3,34.5),(44.7,20.2),(43.6,5.7),(35.0,5.0),(28.0,12.0),(20.0,25.0),(15.0,45.0),(18.0,62.0),(28.0,72.0),(45.0,78.0),(59.9,70.1)]
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
