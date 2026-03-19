import Foundation

struct Race: Identifiable, Codable, Hashable {
    let id: String
    let raceName: String
    let circuitName: String
    let country: String
    let date: String
    let round: Int

    var raceDate: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: date)
    }

    var isPast: Bool {
        guard let raceDate else { return false }
        return raceDate < Date()
    }

    var formattedDate: String {
        guard let raceDate else { return date }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: raceDate)
    }

    var raceWeekendTitle: String {
        raceName.replacingOccurrences(of: " Grand Prix", with: "")
    }

    var month: Int {
        guard let raceDate else { return 1 }
        return Calendar(identifier: .gregorian).component(.month, from: raceDate)
    }

    var weekendContext: WeekendContext {
        WeekendContext.build(for: self)
    }

    var daysUntilRace: Int? {
        guard let raceDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: raceDate)).day
    }

    var weekendSessions: [WeekendSession] {
        guard let raceDate else { return [] }
        let calendar = Calendar(identifier: .gregorian)
        let raceStart = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: raceDate) ?? raceDate

        let offsets: [(String, String, Int, Int)] = [
            ("FP1", "Track goes green", -2, 11),
            ("FP2", "Long-run window", -2, 15),
            ("FP3", "Final setup check", -1, 11),
            ("Qualifying", "Grid-defining session", -1, 15),
            ("Race", "Lights out estimate", 0, 14)
        ]

        return offsets.compactMap { label, subtitle, dayOffset, hour in
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: raceStart),
                  let sessionDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
            else { return nil }
            return WeekendSession(label: label, subtitle: subtitle, date: sessionDate)
        }
    }

    /// Circuit info from hardcoded data (laps, length in km)
    var circuitInfo: CircuitInfo? {
        CircuitInfo.lookup(circuitName: circuitName, country: country)
    }
}

struct WeekendSession: Identifiable, Hashable {
    let label: String
    let subtitle: String
    let date: Date

    var id: String {
        "\(label)-\(date.timeIntervalSince1970)"
    }

    var isUpcoming: Bool {
        date > Date()
    }

    var relativeLabel: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    var timeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct DriverTrend: Identifiable, Hashable {
    let id: String
    let driverName: String
    let driverCode: String
    let constructorName: String
    let currentPosition: Int
    let currentPoints: Double
    let recentResults: [RaceResult]
    let trendScore: Int

    var averageFinish: Double {
        guard !recentResults.isEmpty else { return Double(currentPosition) }
        return recentResults.map(\.position).map(Double.init).reduce(0, +) / Double(recentResults.count)
    }

    var momentumLabel: String {
        switch trendScore {
        case 22...: return "White hot"
        case 16...: return "Charging"
        case 10...: return "Stable"
        default: return "Needs a reset"
        }
    }

    var trendIcon: String {
        switch trendScore {
        case 22...: return "arrow.up.right"
        case 16...: return "flame.fill"
        case 10...: return "equal"
        default: return "arrow.down.right"
        }
    }

    var recentSummary: String {
        recentResults.prefix(3).map { "P\($0.position)" }.joined(separator: " · ")
    }
}

struct CircuitPressureProfile: Hashable {
    let overtaking: String
    let tyreStress: String
    let qualifyingImportance: String
    let reliabilityRisk: String

    static func from(info: CircuitInfo?) -> CircuitPressureProfile {
        guard let info else {
            return CircuitPressureProfile(overtaking: "Unknown", tyreStress: "Unknown", qualifyingImportance: "Unknown", reliabilityRisk: "Unknown")
        }

        let overtaking = info.drsZones >= 3 ? "High" : (info.drsZones == 2 ? "Medium" : "Track position")
        let tyreStress = (info.lengthKm > 5.7 || info.speedClass.lowercased().contains("high")) ? "High" : (info.speedClass.lowercased().contains("street") ? "Medium" : "Balanced")
        let qualifyingImportance = (info.drsZones <= 1 || info.speedClass.lowercased().contains("street")) ? "Massive" : (info.turns <= 12 ? "Important" : "Balanced")
        let reliabilityRisk = info.turns >= 20 || info.speedClass.lowercased().contains("street") ? "Punishing" : (info.lengthKm > 5.6 ? "Medium" : "Contained")

        return CircuitPressureProfile(
            overtaking: overtaking,
            tyreStress: tyreStress,
            qualifyingImportance: qualifyingImportance,
            reliabilityRisk: reliabilityRisk
        )
    }
}

extension Double {
    var cleanNumber: String {
        if truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(self))
        }
        return String(format: "%.1f", self)
    }
}

struct CircuitInfo {
    let laps: Int
    let lengthKm: Double
    let city: String
    let turns: Int
    let drsZones: Int
    let lapRecord: String
    let firstGrandPrix: Int
    let direction: String
    let speedClass: String
    let trackMapPoints: [TrackMapPoint]

    var formattedLength: String {
        String(format: "%.3f km", lengthKm)
    }

    var totalDistanceKm: String {
        String(format: "%.1f km", lengthKm * Double(laps))
    }

    private static let data: [(keywords: [String], info: CircuitInfo)] = [
        (["Albert Park", "Australia"], CircuitInfo(laps: 58, lengthKm: 5.278, city: "Melbourne", turns: 14, drsZones: 4, lapRecord: "1:19.813", firstGrandPrix: 1996, direction: "Clockwise", speedClass: "Balanced", trackMapPoints: [.init(8, 60), .init(18, 22), .init(45, 12), .init(74, 18), .init(88, 34), .init(80, 56), .init(61, 62), .init(57, 78), .init(36, 86), .init(18, 76)])),
        (["Shanghai", "China"], CircuitInfo(laps: 56, lengthKm: 5.451, city: "Shanghai", turns: 16, drsZones: 2, lapRecord: "1:32.238", firstGrandPrix: 2004, direction: "Clockwise", speedClass: "Balanced", trackMapPoints: [.init(16, 28), .init(28, 10), .init(54, 14), .init(72, 30), .init(82, 56), .init(68, 78), .init(36, 80), .init(18, 66), .init(28, 46), .init(48, 50), .init(60, 36)])),
        (["Suzuka", "Japan"], CircuitInfo(laps: 53, lengthKm: 5.807, city: "Suzuka", turns: 18, drsZones: 1, lapRecord: "1:30.983", firstGrandPrix: 1987, direction: "Figure-8", speedClass: "High speed", trackMapPoints: [.init(12, 58), .init(22, 30), .init(46, 18), .init(66, 34), .init(55, 52), .init(34, 52), .init(44, 72), .init(72, 72), .init(86, 48), .init(74, 22)])),
        (["Bahrain", "Sakhir"], CircuitInfo(laps: 57, lengthKm: 5.412, city: "Sakhir", turns: 15, drsZones: 3, lapRecord: "1:31.447", firstGrandPrix: 2004, direction: "Clockwise", speedClass: "Traction", trackMapPoints: [.init(10, 58), .init(24, 18), .init(48, 12), .init(70, 20), .init(82, 40), .init(72, 58), .init(54, 56), .init(58, 78), .init(34, 84), .init(18, 72)])),
        (["Jeddah", "Saudi Arabia"], CircuitInfo(laps: 50, lengthKm: 6.174, city: "Jeddah", turns: 27, drsZones: 3, lapRecord: "1:30.734", firstGrandPrix: 2021, direction: "Anti-clockwise", speedClass: "Street high speed", trackMapPoints: [.init(10, 82), .init(18, 48), .init(30, 22), .init(54, 16), .init(76, 24), .init(88, 44), .init(82, 74), .init(58, 84), .init(40, 68), .init(24, 70)])),
        (["Miami"], CircuitInfo(laps: 57, lengthKm: 5.412, city: "Miami", turns: 19, drsZones: 3, lapRecord: "1:29.708", firstGrandPrix: 2022, direction: "Anti-clockwise", speedClass: "Street balanced", trackMapPoints: [.init(12, 52), .init(26, 18), .init(54, 16), .init(84, 30), .init(86, 58), .init(64, 74), .init(42, 70), .init(30, 84), .init(16, 72)])),
        (["Imola", "Emilia Romagna"], CircuitInfo(laps: 63, lengthKm: 4.909, city: "Imola", turns: 19, drsZones: 1, lapRecord: "1:15.484", firstGrandPrix: 1980, direction: "Anti-clockwise", speedClass: "Old-school", trackMapPoints: [.init(12, 58), .init(22, 24), .init(48, 14), .init(72, 22), .init(86, 46), .init(70, 64), .init(44, 70), .init(34, 86), .init(16, 78)])),
        (["Monaco"], CircuitInfo(laps: 78, lengthKm: 3.337, city: "Monte Carlo", turns: 19, drsZones: 1, lapRecord: "1:12.909", firstGrandPrix: 1950, direction: "Clockwise", speedClass: "Street precision", trackMapPoints: [.init(18, 62), .init(26, 34), .init(44, 24), .init(64, 32), .init(74, 48), .init(66, 62), .init(48, 60), .init(42, 78), .init(22, 82)])),
        (["Catalunya", "Spain", "Barcelona"], CircuitInfo(laps: 66, lengthKm: 4.657, city: "Barcelona", turns: 14, drsZones: 2, lapRecord: "1:16.330", firstGrandPrix: 1991, direction: "Clockwise", speedClass: "Aero test", trackMapPoints: [.init(10, 54), .init(22, 18), .init(50, 14), .init(78, 24), .init(84, 52), .init(68, 70), .init(40, 76), .init(24, 64)])),
        (["Montreal", "Canada", "Gilles Villeneuve"], CircuitInfo(laps: 70, lengthKm: 4.361, city: "Montreal", turns: 14, drsZones: 3, lapRecord: "1:13.078", firstGrandPrix: 1978, direction: "Clockwise", speedClass: "Stop-start", trackMapPoints: [.init(12, 44), .init(20, 20), .init(46, 12), .init(72, 24), .init(86, 48), .init(76, 70), .init(44, 78), .init(18, 64)])),
        (["Spielberg", "Austria", "Red Bull Ring"], CircuitInfo(laps: 71, lengthKm: 4.318, city: "Spielberg", turns: 10, drsZones: 3, lapRecord: "1:05.619", firstGrandPrix: 1970, direction: "Clockwise", speedClass: "Power", trackMapPoints: [.init(18, 70), .init(28, 20), .init(62, 14), .init(82, 34), .init(72, 62), .init(42, 78)])),
        (["Silverstone", "Britain", "British"], CircuitInfo(laps: 52, lengthKm: 5.891, city: "Silverstone", turns: 18, drsZones: 2, lapRecord: "1:27.097", firstGrandPrix: 1950, direction: "Clockwise", speedClass: "High speed", trackMapPoints: [.init(10, 54), .init(20, 22), .init(44, 12), .init(74, 18), .init(88, 38), .init(80, 64), .init(52, 76), .init(28, 68), .init(22, 46), .init(38, 42), .init(52, 54)])),
        (["Budapest", "Hungary", "Hungaroring"], CircuitInfo(laps: 70, lengthKm: 4.381, city: "Budapest", turns: 14, drsZones: 1, lapRecord: "1:16.627", firstGrandPrix: 1986, direction: "Clockwise", speedClass: "Technical", trackMapPoints: [.init(12, 60), .init(22, 24), .init(46, 16), .init(76, 26), .init(84, 50), .init(70, 70), .init(46, 80), .init(20, 72)])),
        (["Spa", "Belgium"], CircuitInfo(laps: 44, lengthKm: 7.004, city: "Stavelot", turns: 19, drsZones: 2, lapRecord: "1:46.286", firstGrandPrix: 1950, direction: "Clockwise", speedClass: "Forest high speed", trackMapPoints: [.init(12, 66), .init(24, 18), .init(54, 10), .init(82, 20), .init(88, 48), .init(76, 74), .init(42, 86), .init(18, 76)])),
        (["Zandvoort", "Netherlands", "Dutch"], CircuitInfo(laps: 72, lengthKm: 4.259, city: "Zandvoort", turns: 14, drsZones: 2, lapRecord: "1:11.097", firstGrandPrix: 1952, direction: "Clockwise", speedClass: "Banked flow", trackMapPoints: [.init(16, 58), .init(24, 26), .init(46, 12), .init(74, 22), .init(82, 48), .init(68, 74), .init(36, 80), .init(18, 70)])),
        (["Monza", "Italy", "Italian"], CircuitInfo(laps: 53, lengthKm: 5.793, city: "Monza", turns: 11, drsZones: 2, lapRecord: "1:21.046", firstGrandPrix: 1950, direction: "Clockwise", speedClass: "Low downforce", trackMapPoints: [.init(10, 44), .init(20, 18), .init(58, 16), .init(86, 24), .init(84, 50), .init(52, 56), .init(44, 80), .init(18, 74)])),
        (["Baku", "Azerbaijan"], CircuitInfo(laps: 51, lengthKm: 6.003, city: "Baku", turns: 20, drsZones: 2, lapRecord: "1:43.009", firstGrandPrix: 2016, direction: "Anti-clockwise", speedClass: "Street speed trap", trackMapPoints: [.init(10, 50), .init(16, 20), .init(38, 12), .init(68, 16), .init(86, 28), .init(88, 58), .init(64, 72), .init(42, 74), .init(32, 88), .init(16, 74)])),
        (["Marina Bay", "Singapore"], CircuitInfo(laps: 62, lengthKm: 4.940, city: "Singapore", turns: 19, drsZones: 3, lapRecord: "1:35.867", firstGrandPrix: 2008, direction: "Anti-clockwise", speedClass: "Street technical", trackMapPoints: [.init(12, 62), .init(22, 26), .init(52, 16), .init(78, 24), .init(86, 50), .init(70, 72), .init(46, 82), .init(22, 74)])),
        (["Austin", "COTA", "Americas"], CircuitInfo(laps: 56, lengthKm: 5.513, city: "Austin", turns: 20, drsZones: 2, lapRecord: "1:36.169", firstGrandPrix: 2012, direction: "Anti-clockwise", speedClass: "Technical-power mix", trackMapPoints: [.init(12, 66), .init(22, 18), .init(46, 10), .init(74, 22), .init(84, 48), .init(72, 72), .init(44, 84), .init(20, 76)])),
        (["Mexico", "Hermanos"], CircuitInfo(laps: 71, lengthKm: 4.304, city: "Mexico City", turns: 17, drsZones: 3, lapRecord: "1:17.774", firstGrandPrix: 1963, direction: "Clockwise", speedClass: "Altitude", trackMapPoints: [.init(10, 48), .init(20, 18), .init(50, 14), .init(82, 26), .init(88, 56), .init(72, 72), .init(40, 78), .init(18, 66)])),
        (["Interlagos", "Brazil", "São Paulo"], CircuitInfo(laps: 71, lengthKm: 4.309, city: "São Paulo", turns: 15, drsZones: 2, lapRecord: "1:10.540", firstGrandPrix: 1973, direction: "Anti-clockwise", speedClass: "Old-school", trackMapPoints: [.init(12, 64), .init(20, 22), .init(50, 12), .init(82, 22), .init(84, 56), .init(58, 70), .init(40, 86), .init(18, 76)])),
        (["Las Vegas"], CircuitInfo(laps: 50, lengthKm: 6.201, city: "Las Vegas", turns: 17, drsZones: 2, lapRecord: "1:35.490", firstGrandPrix: 2023, direction: "Clockwise", speedClass: "Street power", trackMapPoints: [.init(12, 40), .init(20, 16), .init(66, 16), .init(88, 34), .init(82, 66), .init(44, 76), .init(18, 64)])),
        (["Lusail", "Qatar"], CircuitInfo(laps: 57, lengthKm: 5.380, city: "Lusail", turns: 16, drsZones: 1, lapRecord: "1:22.384", firstGrandPrix: 2021, direction: "Clockwise", speedClass: "Fast sweepers", trackMapPoints: [.init(14, 56), .init(24, 22), .init(52, 12), .init(80, 22), .init(86, 52), .init(70, 74), .init(38, 82), .init(18, 70)])),
        (["Yas Marina", "Abu Dhabi"], CircuitInfo(laps: 58, lengthKm: 5.281, city: "Abu Dhabi", turns: 16, drsZones: 2, lapRecord: "1:26.103", firstGrandPrix: 2009, direction: "Anti-clockwise", speedClass: "Technical-power mix", trackMapPoints: [.init(10, 54), .init(22, 18), .init(54, 12), .init(82, 24), .init(88, 54), .init(68, 76), .init(42, 82), .init(20, 68)])),
    ]

    static func lookup(circuitName: String, country: String) -> CircuitInfo? {
        let search = "\(circuitName) \(country)".lowercased()
        for entry in data {
            if entry.keywords.contains(where: { search.contains($0.lowercased()) }) {
                return entry.info
            }
        }
        return nil
    }
}

struct TrackMapPoint: Hashable, Codable {
    let x: Double
    let y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

struct RaceResult: Identifiable, Codable, Hashable {
    let id: String
    let position: Int
    let driverName: String
    let driverCode: String
    let constructor: String
    let points: Double
    let status: String
}

struct TeamRaceResult: Identifiable {
    let id: String
    let raceName: String
    let driverCode: String
    let position: Int
    let points: Double
    let status: String

    var isDNF: Bool {
        status != "Finished" && !status.starts(with: "+")
    }

    var shortName: String {
        raceName.replacingOccurrences(of: " Grand Prix", with: "")
    }
}

struct DriverRaceResult: Identifiable {
    let id: String
    let raceName: String
    let position: Int
    let points: Double
    let status: String

    var isDNF: Bool {
        status != "Finished" && !status.starts(with: "+")
    }

    var shortName: String {
        raceName
            .replacingOccurrences(of: " Grand Prix", with: "")
    }
}

struct JolpicaRaceResponse: Codable {
    let MRData: MRData
}

struct MRData: Codable {
    let RaceTable: RaceTable
}

struct RaceTable: Codable {
    let Races: [JolpicaRace]
}

struct JolpicaRace: Codable {
    let round: String
    let raceName: String
    let Circuit: JolpicaCircuit
    let date: String
    let Results: [JolpicaResult]?
}

struct JolpicaCircuit: Codable {
    let circuitName: String
    let Location: JolpicaLocation
}

struct JolpicaLocation: Codable {
    let country: String
}

struct JolpicaResult: Codable {
    let position: String
    let Driver: JolpicaDriver
    let Constructor: JolpicaConstructor
    let points: String
    let status: String
}

struct JolpicaDriver: Codable {
    let driverId: String
    let code: String?
    let givenName: String
    let familyName: String
}

struct JolpicaConstructor: Codable {
    let name: String
}

struct StandingsResponse: Codable {
    let MRData: StandingsMRData
}

struct StandingsMRData: Codable {
    let StandingsTable: StandingsTable
}

struct StandingsTable: Codable {
    let StandingsLists: [StandingsList]
}

struct StandingsList: Codable {
    let DriverStandings: [JolpicaDriverStanding]?
    let ConstructorStandings: [JolpicaConstructorStanding]?
}

struct JolpicaDriverStanding: Codable {
    let position: String
    let points: String
    let wins: String
    let Driver: JolpicaDriver
    let Constructors: [JolpicaConstructor]
}

struct JolpicaConstructorStanding: Codable {
    let position: String
    let points: String
    let wins: String
    let Constructor: JolpicaConstructor
}
