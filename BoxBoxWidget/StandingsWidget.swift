import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct StandingsEntry: TimelineEntry {
    let date: Date
    let drivers: [WidgetDriverStanding]
    let isPlaceholder: Bool

    static var placeholder: StandingsEntry {
        StandingsEntry(
            date: .now,
            drivers: [
                WidgetDriverStanding(position: 1, name: "Max Verstappen", code: "VER", team: "Red Bull", points: 195),
                WidgetDriverStanding(position: 2, name: "Lando Norris", code: "NOR", team: "McLaren", points: 183),
                WidgetDriverStanding(position: 3, name: "Charles Leclerc", code: "LEC", team: "Ferrari", points: 162),
            ],
            isPlaceholder: true
        )
    }
}

struct WidgetDriverStanding: Identifiable {
    let position: Int
    let name: String
    let code: String
    let team: String
    let points: Double

    var id: String { code }

    var lastName: String {
        name.components(separatedBy: " ").last ?? name
    }
}

// MARK: - Team Colors

enum WidgetTeamColor {
    static func color(for team: String) -> Color {
        let name = team.lowercased()
        if name.contains("mclaren") { return Color(hex: 0xFF8000) }
        if name.contains("ferrari") { return Color(hex: 0xE8002D) }
        if name.contains("red bull") && !name.contains("rb ") { return Color(hex: 0x3671C6) }
        if name.contains("mercedes") { return Color(hex: 0x27F4D2) }
        if name.contains("aston") { return Color(hex: 0x229971) }
        if name.contains("alpine") { return Color(hex: 0xFF87BC) }
        if name.contains("williams") { return Color(hex: 0x64C4FF) }
        if name.contains("haas") { return Color(hex: 0xB6BABD) }
        if name.contains("sauber") || name.contains("stake") || name.contains("kick") { return Color(hex: 0x52E252) }
        if name.contains("rb") || name.contains("alpha") || name.contains("vcarb") || name.contains("visa") { return Color(hex: 0x6692FF) }
        return .white
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Timeline Provider

struct StandingsProvider: TimelineProvider {
    func placeholder(in context: Context) -> StandingsEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (StandingsEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        fetchStandings { entry in
            completion(entry ?? .placeholder)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StandingsEntry>) -> Void) {
        fetchStandings { entry in
            let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
            let timeline = Timeline(entries: [entry ?? .placeholder], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    private func fetchStandings(completion: @escaping (StandingsEntry?) -> Void) {
        guard let url = URL(string: "https://api.jolpi.ca/ergast/f1/current/driverStandings.json") else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data, error == nil else {
                completion(nil)
                return
            }

            do {
                let response = try JSONDecoder().decode(WidgetStandingsResponse.self, from: data)
                guard let list = response.MRData.StandingsTable.StandingsLists.first,
                      let standings = list.DriverStandings else {
                    completion(nil)
                    return
                }

                let top3 = standings.prefix(3).map { s in
                    WidgetDriverStanding(
                        position: Int(s.position) ?? 0,
                        name: "\(s.Driver.givenName) \(s.Driver.familyName)",
                        code: s.Driver.code ?? String(s.Driver.familyName.prefix(3)).uppercased(),
                        team: s.Constructors.first?.name ?? "Unknown",
                        points: Double(s.points) ?? 0
                    )
                }

                completion(StandingsEntry(date: .now, drivers: top3, isPlaceholder: false))
            } catch {
                completion(nil)
            }
        }.resume()
    }
}

// MARK: - Small View (leader only)

struct StandingsSmallView: View {
    let entry: StandingsEntry

    var body: some View {
        if let leader = entry.drivers.first {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("LEADER")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(widgetRed)
                        .tracking(0.6)
                    Spacer()
                    Text("P1")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(WidgetTeamColor.color(for: leader.team))
                        .frame(width: 8, height: 8)
                    Text(leader.lastName.uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Text(leader.team)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Text("\(Int(leader.points))")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(widgetRed)
                    Text("PTS")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .widgetURL(URL(string: "boxbox://standings"))
            .containerBackground(widgetBackground, for: .widget)
        }
    }
}

// MARK: - Medium View (top 3 with gap)

struct StandingsMediumView: View {
    let entry: StandingsEntry

    private var leaderPoints: Double {
        entry.drivers.first?.points ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CHAMPIONSHIP")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(widgetRed)
                    .tracking(0.6)
                Spacer()
                Text("TOP 3")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            ForEach(entry.drivers) { driver in
                HStack(spacing: 10) {
                    Text("\(driver.position)")
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.black)
                        .foregroundStyle(positionColor(driver.position))
                        .frame(width: 24)

                    Circle()
                        .fill(WidgetTeamColor.color(for: driver.team))
                        .frame(width: 6, height: 6)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(driver.lastName.uppercased())
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                        Text(driver.team)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if driver.position > 1 {
                        let gap = Int(driver.points - leaderPoints)
                        Text("\(gap)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Text("\(Int(driver.points))")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("PTS")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .widgetURL(URL(string: "boxbox://standings"))
        .containerBackground(widgetBackground, for: .widget)
    }

    private func positionColor(_ position: Int) -> Color {
        switch position {
        case 1: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case 2: return Color(white: 0.75)
        case 3: return Color(red: 0.8, green: 0.5, blue: 0.2)
        default: return .white
        }
    }
}

// MARK: - Widget Definition

struct StandingsWidget: Widget {
    let kind = "StandingsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StandingsProvider()) { entry in
            if #available(iOSApplicationExtension 17.0, *) {
                StandingsWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Championship")
        .description("Driver championship standings.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StandingsWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: StandingsEntry

    var body: some View {
        switch family {
        case .systemSmall:
            StandingsSmallView(entry: entry)
        default:
            StandingsMediumView(entry: entry)
        }
    }
}

// MARK: - API Models (widget-local)

struct WidgetStandingsResponse: Codable {
    let MRData: WidgetStandingsMRData
}

struct WidgetStandingsMRData: Codable {
    let StandingsTable: WidgetStandingsTable
}

struct WidgetStandingsTable: Codable {
    let StandingsLists: [WidgetStandingsList]
}

struct WidgetStandingsList: Codable {
    let DriverStandings: [WidgetJolpicaDriverStanding]?
}

struct WidgetJolpicaDriverStanding: Codable {
    let position: String
    let points: String
    let wins: String
    let Driver: WidgetJolpicaDriver
    let Constructors: [WidgetJolpicaConstructor]
}

struct WidgetJolpicaDriver: Codable {
    let driverId: String
    let code: String?
    let givenName: String
    let familyName: String
}

struct WidgetJolpicaConstructor: Codable {
    let name: String
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    StandingsWidget()
} timeline: {
    StandingsEntry.placeholder
}

#Preview("Standings", as: .systemMedium) {
    StandingsWidget()
} timeline: {
    StandingsEntry.placeholder
}
