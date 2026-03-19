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
                WidgetDriverStanding(position: 2, name: "Lando Norris", code: "NOR", team: "McLaren", points: 168),
                WidgetDriverStanding(position: 3, name: "Charles Leclerc", code: "LEC", team: "Ferrari", points: 142),
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

// MARK: - Widget View

struct StandingsMediumView: View {
    let entry: StandingsEntry

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

                    teamDot(driver.team)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(driver.lastName.uppercased())
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                        Text(driver.team)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

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

    private func teamDot(_ team: String) -> some View {
        let name = team.lowercased()
        let color: Color = {
            if name.contains("red bull") { return Color(red: 0.21, green: 0.44, blue: 0.78) }
            if name.contains("ferrari") { return widgetRed }
            if name.contains("mercedes") { return Color(red: 0.15, green: 0.96, blue: 0.82) }
            if name.contains("mclaren") { return .orange }
            if name.contains("aston") { return Color(red: 0.13, green: 0.6, blue: 0.44) }
            if name.contains("alpine") { return Color(red: 1.0, green: 0.53, blue: 0.74) }
            if name.contains("williams") { return Color(red: 0.39, green: 0.77, blue: 1.0) }
            if name.contains("rb") || name.contains("alpha") { return Color(red: 0.4, green: 0.57, blue: 1.0) }
            if name.contains("sauber") || name.contains("stake") { return Color(red: 0.32, green: 0.89, blue: 0.32) }
            if name.contains("haas") { return Color(white: 0.72) }
            return .gray
        }()
        return Circle().fill(color).frame(width: 6, height: 6)
    }
}

// MARK: - Widget Definition

struct StandingsWidget: Widget {
    let kind = "StandingsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StandingsProvider()) { entry in
            if #available(iOSApplicationExtension 17.0, *) {
                StandingsMediumView(entry: entry)
            }
        }
        .configurationDisplayName("Championship")
        .description("Top 3 drivers in the current championship standings.")
        .supportedFamilies([.systemMedium])
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

#Preview("Standings", as: .systemMedium) {
    StandingsWidget()
} timeline: {
    StandingsEntry.placeholder
}
