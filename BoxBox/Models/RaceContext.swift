import Foundation
import SwiftUI

struct WeekendContext: Hashable {
    let timezoneAbbreviation: String
    let localClockLabel: String
    let sessionNarrative: String
    let weatherHeadline: String
    let weatherDetail: String
    let riskLabel: String
    let ambientTemperature: String
    let trackTemperature: String
    let rainChance: String
    let windNote: String
    let surfaceGrip: String
    let sunsetCue: String

    static func build(for race: Race) -> WeekendContext {
        let info = race.circuitInfo
        let timezone = RaceLocalTime.lookup(country: race.country, city: info?.city)
        let localHour = RaceLocalTime.localHour(for: race, timezone: timezone)
        let season = SeasonalWeatherProfile.lookup(country: race.country, city: info?.city, month: race.month, localHour: localHour)
        let sessionNarrative = RaceLocalTime.sessionNarrative(localHour: localHour, weather: season)
        let localClock = RaceLocalTime.localClockLabel(for: race, timezone: timezone)

        return WeekendContext(
            timezoneAbbreviation: timezone.abbreviation,
            localClockLabel: localClock,
            sessionNarrative: sessionNarrative,
            weatherHeadline: season.headline,
            weatherDetail: season.detail,
            riskLabel: season.riskLabel,
            ambientTemperature: season.ambientTemperature,
            trackTemperature: season.trackTemperature,
            rainChance: season.rainChance,
            windNote: season.windNote,
            surfaceGrip: season.surfaceGrip,
            sunsetCue: season.sunsetCue
        )
    }
}

struct RaceLocalTime {
    let identifier: String
    let abbreviation: String

    // Cached formatter — DateFormatter allocation is expensive; reuse across calls.
    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM · HH:mm"
        return f
    }()

    static func lookup(country: String, city: String?) -> RaceLocalTime {
        let key = "\((city ?? "")) \(country)".lowercased()
        let mapping: [(String, RaceLocalTime)] = [
            ("melbourne australia", .init(identifier: "Australia/Melbourne", abbreviation: "AEDT")),
            ("shanghai china", .init(identifier: "Asia/Shanghai", abbreviation: "CST")),
            ("suzuka japan", .init(identifier: "Asia/Tokyo", abbreviation: "JST")),
            ("sakhir bahrain", .init(identifier: "Asia/Bahrain", abbreviation: "AST")),
            ("jeddah saudi arabia", .init(identifier: "Asia/Riyadh", abbreviation: "AST")),
            ("miami usa", .init(identifier: "America/New_York", abbreviation: "ET")),
            ("imola italy", .init(identifier: "Europe/Rome", abbreviation: "CET")),
            ("monte carlo monaco", .init(identifier: "Europe/Monaco", abbreviation: "CET")),
            ("barcelona spain", .init(identifier: "Europe/Madrid", abbreviation: "CET")),
            ("montreal canada", .init(identifier: "America/Toronto", abbreviation: "ET")),
            ("spielberg austria", .init(identifier: "Europe/Vienna", abbreviation: "CET")),
            ("silverstone britain", .init(identifier: "Europe/London", abbreviation: "GMT")),
            ("budapest hungary", .init(identifier: "Europe/Budapest", abbreviation: "CET")),
            ("stavelot belgium", .init(identifier: "Europe/Brussels", abbreviation: "CET")),
            ("zandvoort netherlands", .init(identifier: "Europe/Amsterdam", abbreviation: "CET")),
            ("monza italy", .init(identifier: "Europe/Rome", abbreviation: "CET")),
            ("baku azerbaijan", .init(identifier: "Asia/Baku", abbreviation: "AZT")),
            ("singapore singapore", .init(identifier: "Asia/Singapore", abbreviation: "SGT")),
            ("austin usa", .init(identifier: "America/Chicago", abbreviation: "CT")),
            ("mexico city mexico", .init(identifier: "America/Mexico_City", abbreviation: "CT")),
            ("são paulo brazil", .init(identifier: "America/Sao_Paulo", abbreviation: "BRT")),
            ("las vegas usa", .init(identifier: "America/Los_Angeles", abbreviation: "PT")),
            ("lusail qatar", .init(identifier: "Asia/Qatar", abbreviation: "AST")),
            ("abu dhabi united arab emirates", .init(identifier: "Asia/Dubai", abbreviation: "GST"))
        ]

        if let match = mapping.first(where: { key.contains($0.0) })?.1 {
            return match
        }
        return .init(identifier: "UTC", abbreviation: "UTC")
    }

    static func localHour(for race: Race, timezone: RaceLocalTime) -> Int {
        guard let date = race.raceDate else { return 14 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone.identifier) ?? .gmt
        let localDate = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: date) ?? date
        return calendar.component(.hour, from: localDate)
    }

    static func localClockLabel(for race: Race, timezone: RaceLocalTime) -> String {
        guard let date = race.raceDate else { return "Local time TBD" }
        let tz = TimeZone(identifier: timezone.identifier) ?? .gmt
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let localDate = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: date) ?? date
        clockFormatter.timeZone = tz
        return "Estimated local lights out: \(clockFormatter.string(from: localDate)) \(timezone.abbreviation)"
    }

    static func sessionNarrative(localHour: Int, weather: SeasonalWeatherProfile) -> String {
        switch localHour {
        case ..<13:
            return "Earlier local running means a greener surface at the start, then grip should ramp as support series rubber goes down. \(weather.surfaceGrip)"
        case 13..<18:
            return "Classic afternoon session. Expect peak track evolution, tyre overheating risk and strategy swings if the surface gets greasy. \(weather.surfaceGrip)"
        default:
            return "Later running pushes the track toward cooler asphalt and bigger balance swings into the final stints. \(weather.surfaceGrip)"
        }
    }
}

struct SeasonalWeatherProfile: Hashable {
    let headline: String
    let detail: String
    let riskLabel: String
    let ambientTemperature: String
    let trackTemperature: String
    let rainChance: String
    let windNote: String
    let surfaceGrip: String
    let sunsetCue: String

    static func lookup(country: String, city: String?, month: Int, localHour: Int) -> SeasonalWeatherProfile {
        let key = "\((city ?? "")) \(country)".lowercased()

        func desert(_ hot: Bool) -> SeasonalWeatherProfile {
            SeasonalWeatherProfile(
                headline: hot ? "Hot, dry and dusty" : "Warm desert evening",
                detail: hot ? "Low rain risk, big track-temp spikes and wind-blown sand can punish tyre prep." : "Cooling air helps race pace but dusty edges and gusts still punish anyone off-line.",
                riskLabel: hot ? "Thermal stress" : "Surface evolution",
                ambientTemperature: hot ? "29–36°C" : "24–31°C",
                trackTemperature: hot ? "41–49°C" : "31–39°C",
                rainChance: "<10%",
                windNote: "Crosswinds can knock confidence at braking turn-in.",
                surfaceGrip: "Grip rises sharply once rubber builds, but one wide moment brings the dust back.",
                sunsetCue: localHour >= 17 ? "Expect the last phase to cool quickly after sunset." : "Sun still active — tyre temps stay loaded."
            )
        }

        func temperate(rainy: Bool = false, cool: Bool = false) -> SeasonalWeatherProfile {
            SeasonalWeatherProfile(
                headline: rainy ? "Changeable sky" : (cool ? "Cool mixed conditions" : "Stable temperate running"),
                detail: rainy ? "Forecast logic points to scattered showers, shifting grip and a constant crossover headache." : (cool ? "Cooler air should help engine and tyre management, but warm-up can be awkward on out-laps." : "Balanced ambient conditions make setup execution and qualifying precision the bigger separator."),
                riskLabel: rainy ? "Weather swing" : (cool ? "Warm-up risk" : "Execution"),
                ambientTemperature: cool ? "14–21°C" : "18–27°C",
                trackTemperature: cool ? "19–29°C" : "27–38°C",
                rainChance: rainy ? "35–55%" : "10–25%",
                windNote: rainy ? "Wind direction matters if clouds roll through mid-session." : "Breeze is manageable unless gusts hit high-speed sections.",
                surfaceGrip: rainy ? "The line comes alive fast, but any drizzle resets confidence instantly." : "Expect predictable grip build unless track temps spike.",
                sunsetCue: localHour >= 17 ? "Long shadows can cool one side of the circuit late on." : "Full daylight should keep balance changes readable."
            )
        }

        func humidStreet() -> SeasonalWeatherProfile {
            SeasonalWeatherProfile(
                headline: "Humid street-circuit pressure",
                detail: "High humidity and long braking zones usually make brake temps, traction and driver fatigue part of the story.",
                riskLabel: "Attrition window",
                ambientTemperature: "28–33°C",
                trackTemperature: "34–43°C",
                rainChance: "25–40%",
                windNote: "Buildings can create sudden aero-dead gusts between sectors.",
                surfaceGrip: "Street tracks rubber in aggressively, but marbles punish offline moves.",
                sunsetCue: localHour >= 18 ? "Nightfall should calm track temps slightly, not the walls." : "Heat soak sticks around for most of the race distance."
            )
        }

        if key.contains("bahrain") || key.contains("jeddah") || key.contains("qatar") || key.contains("abu dhabi") {
            return desert(month <= 4 || month >= 10 ? false : true)
        }
        if key.contains("singapore") || key.contains("miami") || key.contains("las vegas") {
            return key.contains("las vegas")
                ? SeasonalWeatherProfile(headline: "Dry desert night", detail: "Cooler night air tends to drag tyre warm-up and front axle confidence into the spotlight.", riskLabel: "Warm-up phase", ambientTemperature: "14–22°C", trackTemperature: "17–28°C", rainChance: "<10%", windNote: "Straight-line gusts can upset braking references.", surfaceGrip: "Grip improves lap by lap but cold starts make the opening stint messy.", sunsetCue: "It gets quicker once fuel burns off and the surface finally wakes up.")
                : humidStreet()
        }
        if key.contains("silverstone") || key.contains("spa") || key.contains("zandvoort") || key.contains("suzuka") {
            return temperate(rainy: true, cool: month < 5 || month > 9)
        }
        if key.contains("monaco") || key.contains("montreal") || key.contains("baku") {
            return temperate(rainy: key.contains("montreal"), cool: false)
        }
        if month < 4 || month > 10 {
            return temperate(cool: true)
        }
        return temperate()
    }
}
