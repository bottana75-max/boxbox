import Foundation

struct Race: Identifiable, Codable, Hashable {
    let id: String
    let raceName: String
    let circuitName: String
    let country: String
    let date: String
    let round: Int

    // Static formatters — DateFormatter allocation is expensive; reuse across calls.
    // These are only ever accessed from the main thread (SwiftUI rendering + @MainActor VMs).
    private static let parseDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    // Gregorian calendar shared across computed properties that need year/month/day extraction.
    private static let gregorianCalendar = Calendar(identifier: .gregorian)

    var raceDate: Date? {
        Race.parseDateFormatter.date(from: date)
    }

    var isPast: Bool {
        guard let raceDate else { return false }
        return raceDate < Date()
    }

    var seasonYear: Int {
        raceDate.map { Race.gregorianCalendar.component(.year, from: $0) }
            ?? Race.gregorianCalendar.component(.year, from: Date())
    }

    var isCurrentSeason: Bool {
        seasonYear == Race.gregorianCalendar.component(.year, from: Date())
    }

    var isReplayEligible: Bool {
        isPast && isCurrentSeason
    }

    var formattedDate: String {
        guard let raceDate else { return date }
        return Race.displayDateFormatter.string(from: raceDate)
    }

    var raceWeekendTitle: String {
        raceName.replacingOccurrences(of: " Grand Prix", with: "")
    }

    var month: Int {
        guard let raceDate else { return 1 }
        return Race.gregorianCalendar.component(.month, from: raceDate)
    }

    var weekendContext: WeekendContext {
        WeekendContext.build(for: self)
    }

    var daysUntilRace: Int? {
        guard let raceDate else { return nil }
        let cal = Race.gregorianCalendar
        return cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: raceDate)).day
    }

    var weekendSessions: [WeekendSession] {
        guard let raceDate else { return [] }
        let calendar = Race.gregorianCalendar
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

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var id: String {
        "\(label)-\(date.timeIntervalSince1970)"
    }

    var isUpcoming: Bool {
        date > Date()
    }

    var relativeLabel: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return WeekendSession.dayFormatter.string(from: date)
    }

    var timeLabel: String {
        WeekendSession.timeFormatter.string(from: date)
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

    // Track map points sourced from bacinger/f1-circuits GeoJSON (real coordinates)
    // Miami & Las Vegas use high-fidelity mock data (no GeoJSON available)
    private static let data: [(keywords: [String], info: CircuitInfo)] = [
        (["Albert Park", "Australia"], CircuitInfo(laps: 58, lengthKm: 5.278, city: "Melbourne", turns: 14, drsZones: 4, lapRecord: "1:19.813", firstGrandPrix: 1996, direction: "Clockwise", speedClass: "Balanced", trackMapPoints: [
            .init(42.3, 71.4), .init(31.1, 60.1), .init(30.5, 58.9), .init(31.3, 57.5),
            .init(31.6, 54.8), .init(30.7, 51.7), .init(27.5, 48.6), .init(22.1, 43.0),
            .init(16.9, 35.9), .init(13.3, 29.2), .init(14.1, 28.0), .init(19.7, 26.9),
            .init(20.4, 25.7), .init(20.2, 18.2), .init(20.9, 14.7), .init(27.8, 9.9),
            .init(36.9, 5.9), .init(39.3, 5.0), .init(41.1, 6.6), .init(44.9, 8.0),
            .init(49.0, 8.7), .init(52.5, 11.1), .init(54.7, 15.2), .init(56.4, 24.1),
            .init(56.0, 27.0), .init(54.2, 29.6), .init(53.2, 31.3), .init(51.3, 40.4),
            .init(51.1, 43.3), .init(51.8, 48.1), .init(53.5, 52.2), .init(56.6, 56.4),
            .init(62.7, 61.5), .init(65.2, 62.1), .init(68.4, 62.0), .init(70.7, 62.6),
            .init(77.2, 68.0), .init(80.8, 71.6), .init(82.3, 74.5), .init(86.3, 88.3),
            .init(86.7, 90.6), .init(80.9, 93.0), .init(75.2, 95.0), .init(73.0, 94.1),
            .init(69.3, 87.9), .init(67.1, 84.6), .init(66.2, 84.6), .init(62.3, 88.8),
            .init(60.7, 89.1), .init(58.9, 88.3)
        ])),
        (["Shanghai", "China"], CircuitInfo(laps: 56, lengthKm: 5.451, city: "Shanghai", turns: 16, drsZones: 2, lapRecord: "1:32.238", firstGrandPrix: 2004, direction: "Clockwise", speedClass: "Balanced", trackMapPoints: [
            .init(28.6, 81.3), .init(20.6, 83.1), .init(16.8, 82.3), .init(14.1, 79.9),
            .init(13.1, 76.7), .init(13.6, 73.5), .init(14.9, 72.0), .init(19.3, 71.7),
            .init(20.2, 73.7), .init(19.3, 77.3), .init(21.5, 79.3), .init(24.0, 77.8),
            .init(24.8, 75.9), .init(24.9, 72.4), .init(22.5, 68.7), .init(13.7, 58.6),
            .init(9.4, 52.6), .init(5.5, 41.2), .init(5.0, 37.4), .init(8.4, 38.2),
            .init(12.2, 42.0), .init(19.2, 53.9), .init(22.4, 57.8), .init(25.2, 59.1),
            .init(30.0, 59.1), .init(34.4, 56.5), .init(38.6, 48.6), .init(41.2, 46.0),
            .init(44.2, 45.2), .init(47.6, 46.4), .init(52.0, 53.7), .init(54.5, 54.6),
            .init(58.8, 49.4), .init(51.0, 35.2), .init(41.2, 19.1), .init(39.1, 19.6),
            .init(36.9, 21.9), .init(34.2, 21.2), .init(32.3, 18.2), .init(32.2, 15.7),
            .init(33.7, 12.1), .init(37.4, 10.5), .init(41.7, 10.9), .init(45.7, 13.6),
            .init(72.8, 54.6), .init(82.4, 69.3), .init(95.0, 88.3), .init(93.5, 89.5),
            .init(89.6, 87.1), .init(75.9, 70.1)
        ])),
        (["Suzuka", "Japan"], CircuitInfo(laps: 53, lengthKm: 5.807, city: "Suzuka", turns: 18, drsZones: 1, lapRecord: "1:30.983", firstGrandPrix: 1987, direction: "Figure-8", speedClass: "High speed", trackMapPoints: [
            .init(81.9, 51.6), .init(94.5, 67.1), .init(95.0, 69.6), .init(93.3, 73.6),
            .init(91.3, 74.0), .init(85.2, 66.1), .init(82.9, 65.2), .init(78.7, 63.7),
            .init(77.2, 58.8), .init(75.0, 57.2), .init(70.0, 56.4), .init(68.4, 54.2),
            .init(69.5, 48.9), .init(69.6, 46.9), .init(67.0, 44.3), .init(63.8, 43.0),
            .init(59.6, 43.1), .init(56.7, 44.5), .init(50.2, 51.7), .init(42.7, 52.7),
            .init(42.1, 51.5), .init(39.6, 38.4), .init(40.0, 36.2), .init(41.4, 32.5),
            .init(40.5, 31.9), .init(37.9, 35.2), .init(35.4, 38.9), .init(32.9, 40.7),
            .init(27.0, 41.2), .init(21.9, 39.7), .init(17.7, 36.9), .init(15.3, 33.6),
            .init(12.0, 26.5), .init(9.3, 26.0), .init(6.4, 26.7), .init(5.0, 29.7),
            .init(6.0, 31.7), .init(11.2, 36.0), .init(17.1, 39.5), .init(27.4, 43.6),
            .init(38.6, 47.3), .init(44.9, 48.8), .init(48.7, 47.3), .init(53.5, 43.4),
            .init(58.8, 38.8), .init(59.8, 38.7), .init(61.8, 39.8), .init(63.9, 38.2),
            .init(68.3, 38.0), .init(71.7, 39.7)
        ])),
        (["Bahrain", "Sakhir"], CircuitInfo(laps: 57, lengthKm: 5.412, city: "Sakhir", turns: 15, drsZones: 3, lapRecord: "1:31.447", firstGrandPrix: 2004, direction: "Clockwise", speedClass: "Traction", trackMapPoints: [
            .init(21.5, 47.6), .init(22.2, 22.3), .init(23.2, 5.0), .init(24.6, 5.1),
            .init(28.6, 8.9), .init(30.5, 9.2), .init(37.9, 7.1), .init(78.2, 14.8),
            .init(80.2, 15.9), .init(80.4, 16.8), .init(79.8, 18.8), .init(78.0, 20.6),
            .init(72.0, 25.1), .init(67.3, 30.0), .init(64.8, 35.1), .init(63.4, 36.5),
            .init(61.1, 37.2), .init(56.8, 36.4), .init(54.4, 36.7), .init(52.3, 38.3),
            .init(42.8, 50.1), .init(40.8, 49.7), .init(40.6, 46.7), .init(43.9, 26.4),
            .init(43.8, 23.5), .init(42.9, 21.4), .init(39.3, 18.3), .init(38.3, 18.2),
            .init(36.7, 28.4), .init(35.8, 46.3), .init(34.9, 69.3), .init(35.8, 72.2),
            .init(38.4, 73.1), .init(42.0, 72.6), .init(44.1, 71.6), .init(47.5, 68.7),
            .init(50.4, 62.0), .init(52.5, 58.7), .init(55.4, 56.6), .init(60.1, 56.0),
            .init(64.1, 57.5), .init(71.5, 61.5), .init(72.5, 62.5), .init(73.7, 64.6),
            .init(73.2, 66.6), .init(70.6, 68.8), .init(23.7, 95.0), .init(21.8, 94.5),
            .init(19.6, 88.4), .init(20.2, 67.3)
        ])),
        (["Jeddah", "Saudi Arabia"], CircuitInfo(laps: 50, lengthKm: 6.174, city: "Jeddah", turns: 27, drsZones: 3, lapRecord: "1:30.734", firstGrandPrix: 2021, direction: "Anti-clockwise", speedClass: "Street high speed", trackMapPoints: [
            .init(54.6, 74.2), .init(49.5, 60.5), .init(47.9, 60.6), .init(47.8, 59.0),
            .init(48.7, 55.5), .init(47.3, 46.3), .init(45.5, 45.1), .init(44.3, 43.1),
            .init(44.6, 40.8), .init(45.7, 38.4), .init(44.8, 35.0), .init(43.4, 34.0),
            .init(43.0, 29.8), .init(44.4, 27.9), .init(46.4, 26.5), .init(47.4, 22.4),
            .init(48.1, 18.7), .init(47.5, 6.2), .init(46.5, 5.0), .init(44.6, 5.1),
            .init(43.5, 7.2), .init(44.8, 10.8), .init(46.1, 13.9), .init(46.1, 16.9),
            .init(44.7, 20.0), .init(44.1, 23.7), .init(43.0, 24.8), .init(40.7, 26.4),
            .init(40.4, 29.1), .init(40.6, 31.8), .init(42.7, 36.8), .init(43.1, 40.7),
            .init(43.2, 43.5), .init(44.1, 46.4), .init(46.1, 49.7), .init(47.1, 53.7),
            .init(47.0, 57.5), .init(46.4, 60.1), .init(46.9, 61.5), .init(48.5, 63.0),
            .init(49.5, 67.1), .init(46.9, 72.5), .init(45.9, 75.8), .init(46.5, 80.3),
            .init(47.6, 83.9), .init(49.8, 88.0), .init(53.2, 91.7), .init(58.3, 95.0),
            .init(59.6, 94.0), .init(57.4, 83.0)
        ])),
        (["Miami"], CircuitInfo(laps: 57, lengthKm: 5.412, city: "Miami", turns: 19, drsZones: 3, lapRecord: "1:29.708", firstGrandPrix: 2022, direction: "Anti-clockwise", speedClass: "Street balanced", trackMapPoints: [
            .init(49.4, 72.6), .init(63.0, 50.9), .init(63.1, 47.9), .init(62.7, 45.9),
            .init(58.9, 37.9), .init(58.9, 28.7), .init(58.6, 22.9), .init(55.3, 13.8),
            .init(52.3, 11.2), .init(47.5, 9.9), .init(42.6, 13.9), .init(29.2, 34.3),
            .init(26.3, 37.7), .init(25.1, 37.9), .init(22.6, 36.4), .init(20.1, 32.1),
            .init(18.8, 30.0), .init(15.6, 29.6), .init(14.0, 31.6), .init(11.0, 38.6),
            .init(7.8, 41.4), .init(5.9, 40.6), .init(2.6, 37.3), .init(0.4, 30.5),
            .init(0.0, 26.0), .init(0.4, 19.8), .init(0.9, 18.1), .init(3.3, 16.5),
            .init(6.8, 17.4), .init(10.6, 15.4), .init(24.6, 12.4), .init(35.5, 13.5),
            .init(42.3, 7.7), .init(49.3, 1.8), .init(53.5, 0.0), .init(62.2, 1.7),
            .init(66.2, 5.3), .init(80.8, 19.0), .init(90.0, 30.9), .init(93.5, 36.6),
            .init(94.0, 41.1), .init(93.4, 42.7), .init(90.6, 47.3), .init(89.9, 53.8),
            .init(90.2, 57.8), .init(92.1, 61.1), .init(96.7, 61.1), .init(97.4, 62.2),
            .init(100.0, 72.0), .init(99.9, 73.6), .init(98.4, 75.7), .init(99.7, 88.7),
            .init(99.6, 90.5), .init(95.8, 92.4), .init(49.8, 96.5), .init(12.1, 100.0),
            .init(12.3, 95.2), .init(13.5, 92.3), .init(17.6, 85.6), .init(19.4, 84.5),
            .init(22.8, 86.6), .init(29.5, 93.4), .init(32.5, 94.0), .init(38.3, 90.0)
        ])),
        (["Imola", "Emilia Romagna"], CircuitInfo(laps: 63, lengthKm: 4.909, city: "Imola", turns: 19, drsZones: 1, lapRecord: "1:15.484", firstGrandPrix: 1980, direction: "Anti-clockwise", speedClass: "Old-school", trackMapPoints: [
            .init(62.1, 32.1), .init(60.5, 32.1), .init(47.0, 29.6), .init(34.5, 30.5),
            .init(29.4, 31.7), .init(28.4, 32.5), .init(28.0, 34.5), .init(27.7, 35.0),
            .init(22.4, 37.8), .init(14.1, 57.4), .init(14.0, 57.9), .init(14.8, 61.5),
            .init(14.5, 62.5), .init(14.2, 62.9), .init(5.0, 71.0), .init(5.0, 72.1),
            .init(5.4, 72.8), .init(6.3, 73.3), .init(21.5, 71.4), .init(23.2, 71.3),
            .init(27.4, 71.7), .init(32.2, 72.6), .init(33.5, 72.8), .init(34.9, 72.4),
            .init(36.5, 70.2), .init(38.0, 65.8), .init(38.1, 64.3), .init(36.1, 54.3),
            .init(36.4, 53.2), .init(37.4, 51.6), .init(39.1, 49.3), .init(40.0, 49.4),
            .init(42.0, 50.2), .init(63.5, 50.2), .init(64.1, 50.9), .init(64.2, 51.4),
            .init(64.9, 51.6), .init(74.3, 47.6), .init(77.8, 45.2), .init(81.7, 41.4),
            .init(87.3, 36.1), .init(88.4, 35.6), .init(95.0, 32.4), .init(94.9, 31.2),
            .init(93.1, 27.2), .init(92.2, 26.7), .init(91.0, 26.8), .init(82.7, 30.0),
            .init(78.2, 31.7), .init(75.8, 32.2)
        ])),
        (["Monaco"], CircuitInfo(laps: 78, lengthKm: 3.337, city: "Monte Carlo", turns: 19, drsZones: 1, lapRecord: "1:12.909", firstGrandPrix: 1950, direction: "Clockwise", speedClass: "Street precision", trackMapPoints: [
            .init(60.5, 22.4), .init(61.1, 19.5), .init(71.2, 5.7), .init(73.6, 5.0),
            .init(75.0, 7.5), .init(76.0, 10.5), .init(77.7, 13.6), .init(79.1, 14.0),
            .init(79.3, 12.4), .init(76.2, 8.6), .init(77.6, 6.5), .init(80.8, 5.5),
            .init(83.9, 5.3), .init(83.0, 18.8), .init(79.0, 29.0), .init(66.6, 39.3),
            .init(52.9, 44.1), .init(47.5, 45.5), .init(47.2, 46.9), .init(44.2, 46.7),
            .init(25.6, 49.2), .init(23.1, 50.1), .init(20.9, 55.2), .init(20.3, 62.0),
            .init(21.1, 64.1), .init(23.5, 67.6), .init(25.3, 76.9), .init(24.2, 78.5),
            .init(23.4, 80.4), .init(25.8, 86.2), .init(31.5, 91.2), .init(32.9, 93.1),
            .init(29.3, 94.9), .init(25.8, 95.0), .init(24.9, 93.4), .init(21.8, 88.1),
            .init(17.8, 76.7), .init(16.3, 68.2), .init(16.1, 57.9), .init(17.3, 52.1),
            .init(17.6, 48.3), .init(20.1, 47.1), .init(26.1, 46.5), .init(38.0, 43.4),
            .init(44.9, 42.1), .init(57.5, 37.9), .init(63.0, 35.9), .init(65.6, 31.8),
            .init(64.8, 27.6), .init(62.0, 24.4)
        ])),
        (["Catalunya", "Spain", "Barcelona"], CircuitInfo(laps: 66, lengthKm: 4.657, city: "Barcelona", turns: 14, drsZones: 2, lapRecord: "1:16.330", firstGrandPrix: 1991, direction: "Clockwise", speedClass: "Aero test", trackMapPoints: [
            .init(71.3, 45.2), .init(51.0, 77.4), .init(42.7, 90.5), .init(40.8, 91.3),
            .init(38.8, 90.8), .init(35.1, 89.0), .init(32.2, 89.7), .init(25.1, 94.5),
            .init(22.2, 95.0), .init(19.2, 94.5), .init(16.7, 92.9), .init(14.1, 89.1),
            .init(13.4, 85.1), .init(14.2, 79.9), .init(16.3, 75.3), .init(27.2, 59.1),
            .init(30.4, 59.1), .init(32.9, 61.1), .init(34.0, 65.6), .init(33.2, 69.1),
            .init(25.1, 82.4), .init(25.6, 84.4), .init(27.1, 85.4), .init(29.0, 85.2),
            .init(42.2, 78.5), .init(48.8, 69.4), .init(49.3, 66.7), .init(46.1, 63.9),
            .init(43.9, 61.6), .init(38.0, 47.8), .init(37.9, 44.5), .init(39.1, 41.8),
            .init(74.1, 23.0), .init(76.2, 21.1), .init(75.6, 18.9), .init(72.9, 17.1),
            .init(70.0, 16.7), .init(66.5, 17.8), .init(62.7, 20.6), .init(59.3, 20.9),
            .init(56.9, 18.9), .init(56.3, 16.4), .init(57.9, 13.3), .init(67.5, 5.5),
            .init(70.9, 5.0), .init(74.8, 6.8), .init(79.8, 10.1), .init(85.3, 13.8),
            .init(86.6, 16.5), .init(86.6, 20.5)
        ])),
        (["Montreal", "Canada", "Gilles Villeneuve"], CircuitInfo(laps: 70, lengthKm: 4.361, city: "Montreal", turns: 14, drsZones: 3, lapRecord: "1:13.078", firstGrandPrix: 1978, direction: "Clockwise", speedClass: "Stop-start", trackMapPoints: [
            .init(59.9, 70.1), .init(61.8, 79.1), .init(62.3, 84.2), .init(61.7, 91.2),
            .init(64.1, 92.4), .init(64.6, 93.2), .init(64.3, 94.3), .init(63.2, 95.0),
            .init(61.4, 94.8), .init(57.8, 93.7), .init(55.0, 92.0), .init(50.1, 87.7),
            .init(49.7, 86.7), .init(50.0, 85.2), .init(50.0, 84.1), .init(46.3, 79.4),
            .init(44.5, 78.0), .init(43.0, 76.4), .init(42.2, 74.2), .init(42.2, 66.5),
            .init(41.9, 65.5), .init(40.7, 65.0), .init(39.1, 65.3), .init(37.8, 64.7),
            .init(37.0, 63.8), .init(36.1, 61.2), .init(35.8, 58.6), .init(35.4, 50.7),
            .init(35.6, 45.9), .init(36.2, 42.5), .init(38.3, 34.5), .init(39.2, 34.1),
            .init(40.4, 33.9), .init(41.4, 33.0), .init(42.2, 31.4), .init(44.7, 20.2),
            .init(45.1, 14.5), .init(44.9, 12.6), .init(43.6, 5.7), .init(43.9, 5.0),
            .init(44.9, 5.0), .init(45.2, 5.6), .init(45.6, 9.2), .init(45.9, 10.8),
            .init(47.7, 14.5), .init(52.5, 26.9), .init(59.1, 58.5), .init(58.8, 59.2),
            .init(57.9, 59.7), .init(57.8, 60.6)
        ])),
        (["Spielberg", "Austria", "Red Bull Ring"], CircuitInfo(laps: 71, lengthKm: 4.318, city: "Spielberg", turns: 10, drsZones: 3, lapRecord: "1:05.619", firstGrandPrix: 1970, direction: "Clockwise", speedClass: "Power", trackMapPoints: [
            .init(65.0, 72.5), .init(58.8, 74.1), .init(42.4, 78.4), .init(41.7, 77.8),
            .init(36.7, 70.4), .init(29.4, 59.4), .init(26.5, 54.4), .init(20.4, 41.2),
            .init(18.4, 37.9), .init(10.1, 28.9), .init(5.0, 23.5), .init(5.0, 22.8),
            .init(6.8, 22.2), .init(14.7, 21.6), .init(18.7, 21.6), .init(27.0, 22.7),
            .init(40.7, 25.4), .init(60.4, 26.8), .init(62.2, 27.9), .init(62.4, 28.7),
            .init(62.0, 30.4), .init(59.6, 33.6), .init(57.6, 35.4), .init(52.9, 37.4),
            .init(50.0, 37.9), .init(35.6, 35.8), .init(32.8, 36.5), .init(31.7, 37.2),
            .init(30.2, 39.4), .init(29.8, 40.8), .init(30.0, 43.3), .init(35.9, 54.0),
            .init(36.8, 55.0), .init(40.0, 56.3), .init(43.4, 55.4), .init(44.4, 54.6),
            .init(46.5, 51.9), .init(47.6, 50.8), .init(50.5, 49.0), .init(54.9, 47.7),
            .init(72.7, 47.3), .init(87.8, 47.0), .init(90.4, 48.4), .init(91.3, 49.5),
            .init(94.8, 60.5), .init(95.0, 61.4), .init(94.5, 62.5), .init(92.0, 64.2),
            .init(90.1, 65.2), .init(85.5, 66.9)
        ])),
        (["Silverstone", "Britain", "British"], CircuitInfo(laps: 52, lengthKm: 5.891, city: "Silverstone", turns: 18, drsZones: 2, lapRecord: "1:27.097", firstGrandPrix: 1950, direction: "Clockwise", speedClass: "High speed", trackMapPoints: [
            .init(55.3, 5.7), .init(66.8, 5.0), .init(70.1, 7.2), .init(72.0, 13.3),
            .init(73.2, 19.4), .init(73.8, 30.4), .init(75.7, 35.7), .init(76.2, 37.8),
            .init(74.2, 45.0), .init(76.7, 49.6), .init(76.8, 53.1), .init(74.6, 55.2),
            .init(70.5, 58.0), .init(55.3, 85.8), .init(50.3, 93.4), .init(47.3, 95.0),
            .init(44.2, 94.3), .init(42.7, 92.5), .init(40.2, 87.8), .init(37.1, 83.9),
            .init(31.2, 77.3), .init(30.1, 77.5), .init(27.4, 79.1), .init(25.5, 77.6),
            .init(24.0, 75.2), .init(23.2, 71.9), .init(24.4, 69.6), .init(38.7, 50.9),
            .init(41.4, 49.3), .init(47.2, 49.9), .init(51.1, 49.9), .init(53.5, 49.0),
            .init(62.0, 42.4), .init(63.6, 42.9), .init(65.1, 47.8), .init(66.6, 48.8),
            .init(68.0, 47.4), .init(68.9, 44.7), .init(69.5, 41.1), .init(68.5, 38.5),
            .init(42.7, 15.4), .init(40.4, 15.4), .init(38.5, 17.3), .init(37.2, 22.8),
            .init(35.3, 23.4), .init(33.0, 22.0), .init(32.7, 19.7), .init(36.4, 12.1),
            .init(39.8, 8.7), .init(43.6, 6.9)
        ])),
        (["Budapest", "Hungary", "Hungaroring"], CircuitInfo(laps: 70, lengthKm: 4.381, city: "Budapest", turns: 14, drsZones: 1, lapRecord: "1:16.627", firstGrandPrix: 1986, direction: "Clockwise", speedClass: "Technical", trackMapPoints: [
            .init(30.0, 72.9), .init(10.7, 57.6), .init(10.2, 55.5), .init(11.5, 54.2),
            .init(16.9, 54.2), .init(23.5, 56.1), .init(26.4, 57.9), .init(40.3, 68.1),
            .init(42.6, 67.6), .init(44.0, 66.1), .init(44.4, 63.9), .init(40.4, 56.5),
            .init(40.0, 54.5), .init(40.8, 52.0), .init(52.6, 28.4), .init(56.2, 23.8),
            .init(56.4, 21.8), .init(53.2, 9.2), .init(53.9, 6.7), .init(56.1, 5.0),
            .init(59.0, 5.1), .init(62.5, 7.1), .init(66.3, 10.5), .init(73.0, 18.0),
            .init(72.7, 19.5), .init(71.6, 20.8), .init(74.1, 31.0), .init(75.3, 33.1),
            .init(76.4, 33.7), .init(83.3, 35.0), .init(84.9, 36.6), .init(85.3, 38.9),
            .init(83.9, 49.7), .init(84.6, 52.6), .init(89.8, 61.2), .init(89.8, 63.5),
            .init(88.8, 65.7), .init(71.1, 85.8), .init(69.4, 86.2), .init(68.5, 85.5),
            .init(59.1, 76.1), .init(56.9, 75.4), .init(54.8, 76.5), .init(54.1, 78.5),
            .init(54.9, 80.6), .init(63.7, 87.8), .init(64.5, 90.5), .init(63.7, 93.2),
            .init(60.9, 95.0), .init(57.5, 94.6)
        ])),
        (["Spa", "Belgium"], CircuitInfo(laps: 44, lengthKm: 7.004, city: "Stavelot", turns: 19, drsZones: 2, lapRecord: "1:46.286", firstGrandPrix: 1950, direction: "Clockwise", speedClass: "Forest high speed", trackMapPoints: [
            .init(39.0, 14.4), .init(34.2, 5.0), .init(36.8, 5.8), .init(44.7, 10.3),
            .init(55.4, 22.4), .init(58.5, 24.5), .init(60.2, 27.1), .init(60.8, 30.5),
            .init(65.2, 37.9), .init(68.7, 44.2), .init(76.8, 72.1), .init(77.8, 77.2),
            .init(76.2, 78.6), .init(75.3, 80.1), .init(76.2, 85.6), .init(75.0, 87.5),
            .init(63.2, 95.0), .init(61.4, 93.2), .init(61.9, 91.3), .init(67.5, 87.6),
            .init(67.8, 85.7), .init(64.0, 70.9), .init(62.9, 65.5), .init(61.1, 63.8),
            .init(56.7, 63.1), .init(53.7, 63.9), .init(51.4, 66.2), .init(45.9, 79.6),
            .init(44.0, 81.6), .init(41.7, 81.7), .init(39.3, 80.4), .init(36.8, 80.6),
            .init(35.2, 82.3), .init(30.1, 89.6), .init(25.3, 87.3), .init(22.7, 84.9),
            .init(22.2, 82.7), .init(23.0, 79.9), .init(25.7, 75.1), .init(31.7, 69.3),
            .init(41.2, 64.1), .init(43.8, 61.6), .init(46.3, 57.2), .init(48.5, 51.5),
            .init(47.3, 46.6), .init(44.5, 38.6), .init(43.8, 34.2), .init(43.7, 27.6),
            .init(45.3, 27.6), .init(46.1, 26.8)
        ])),
        (["Zandvoort", "Netherlands", "Dutch"], CircuitInfo(laps: 72, lengthKm: 4.259, city: "Zandvoort", turns: 14, drsZones: 2, lapRecord: "1:11.097", firstGrandPrix: 1952, direction: "Clockwise", speedClass: "Banked flow", trackMapPoints: [
            .init(16.0, 46.7), .init(30.0, 13.3), .init(32.0, 11.7), .init(35.6, 12.6),
            .init(36.8, 14.7), .init(35.7, 18.6), .init(31.1, 33.9), .init(31.0, 38.9),
            .init(26.9, 41.8), .init(21.0, 44.5), .init(20.6, 47.1), .init(23.2, 49.6),
            .init(33.5, 46.8), .init(40.9, 46.0), .init(48.8, 47.3), .init(55.3, 48.3),
            .init(63.3, 45.6), .init(69.5, 41.9), .init(74.8, 41.0), .init(89.1, 42.1),
            .init(92.7, 44.4), .init(94.5, 47.3), .init(95.0, 52.9), .init(93.3, 56.8),
            .init(83.4, 73.7), .init(79.4, 74.6), .init(74.8, 74.0), .init(66.7, 69.9),
            .init(64.7, 66.8), .init(67.5, 63.1), .init(73.5, 61.7), .init(80.5, 59.5),
            .init(83.1, 54.9), .init(81.0, 51.7), .init(72.4, 50.3), .init(51.0, 52.9),
            .init(42.5, 55.8), .init(33.5, 60.3), .init(31.7, 58.9), .init(29.6, 56.4),
            .init(25.6, 58.2), .init(25.6, 61.9), .init(29.2, 83.6), .init(27.6, 86.9),
            .init(24.5, 88.3), .init(14.4, 88.0), .init(10.7, 86.6), .init(7.0, 82.8),
            .init(5.0, 76.9), .init(5.8, 71.3)
        ])),
        (["Monza", "Italy", "Italian"], CircuitInfo(laps: 53, lengthKm: 5.793, city: "Monza", turns: 11, drsZones: 2, lapRecord: "1:21.046", firstGrandPrix: 1950, direction: "Clockwise", speedClass: "Low downforce", trackMapPoints: [
            .init(25.7, 62.2), .init(27.9, 36.9), .init(28.4, 36.4), .init(29.1, 36.4),
            .init(29.7, 36.1), .init(29.7, 35.6), .init(28.5, 29.5), .init(28.9, 23.1),
            .init(29.6, 20.5), .init(30.4, 18.7), .init(32.6, 15.9), .init(34.7, 14.2),
            .init(38.5, 12.4), .init(41.6, 11.7), .init(57.8, 10.5), .init(58.5, 10.4),
            .init(59.1, 9.0), .init(59.6, 8.7), .init(63.6, 7.7), .init(71.8, 5.0),
            .init(73.4, 5.3), .init(74.2, 5.8), .init(75.1, 7.2), .init(75.5, 11.3),
            .init(76.0, 18.3), .init(75.6, 18.9), .init(66.3, 24.1), .init(62.6, 26.1),
            .init(59.4, 28.6), .init(52.0, 35.1), .init(40.9, 44.8), .init(40.7, 45.5),
            .init(40.9, 47.4), .init(40.8, 48.5), .init(40.0, 50.2), .init(38.9, 51.3),
            .init(38.0, 52.3), .init(37.5, 56.3), .init(33.7, 92.3), .init(33.3, 93.4),
            .init(31.9, 94.6), .init(30.5, 95.0), .init(28.6, 94.6), .init(27.4, 93.9),
            .init(25.7, 92.1), .init(24.9, 90.6), .init(24.3, 87.9), .init(24.1, 85.5),
            .init(24.0, 80.0), .init(24.3, 75.0)
        ])),
        (["Baku", "Azerbaijan"], CircuitInfo(laps: 51, lengthKm: 6.003, city: "Baku", turns: 20, drsZones: 2, lapRecord: "1:43.009", firstGrandPrix: 2016, direction: "Anti-clockwise", speedClass: "Street speed trap", trackMapPoints: [
            .init(87.8, 34.0), .init(94.4, 31.2), .init(95.0, 30.5), .init(94.9, 29.5),
            .init(93.6, 26.1), .init(89.5, 17.4), .init(88.8, 17.2), .init(74.7, 22.7),
            .init(64.2, 27.4), .init(54.6, 32.2), .init(57.5, 40.7), .init(57.5, 41.3),
            .init(51.9, 44.3), .init(45.1, 48.4), .init(44.9, 49.2), .init(45.6, 50.6),
            .init(45.2, 51.4), .init(34.8, 59.6), .init(33.3, 61.0), .init(32.0, 61.4),
            .init(29.1, 53.8), .init(28.4, 53.5), .init(27.8, 53.5), .init(26.4, 52.8),
            .init(25.3, 52.9), .init(24.5, 52.2), .init(24.0, 50.5), .init(23.4, 50.0),
            .init(19.1, 51.3), .init(13.0, 54.2), .init(8.3, 57.3), .init(7.1, 59.3),
            .init(5.0, 66.8), .init(5.6, 76.0), .init(6.3, 77.1), .init(16.8, 82.4),
            .init(18.0, 82.8), .init(19.5, 82.8), .init(20.5, 82.0), .init(23.5, 76.4),
            .init(24.2, 75.6), .init(31.7, 68.4), .init(32.6, 63.4), .init(32.9, 62.6),
            .init(34.0, 61.2), .init(45.5, 52.5), .init(48.5, 51.0), .init(53.0, 49.1),
            .init(66.9, 43.0), .init(81.1, 36.8)
        ])),
        (["Marina Bay", "Singapore"], CircuitInfo(laps: 62, lengthKm: 4.940, city: "Singapore", turns: 19, drsZones: 3, lapRecord: "1:35.867", firstGrandPrix: 2008, direction: "Anti-clockwise", speedClass: "Street technical", trackMapPoints: [
            .init(93.0, 43.0), .init(95.0, 58.5), .init(94.3, 60.1), .init(91.7, 64.1),
            .init(89.6, 64.3), .init(75.3, 63.0), .init(73.5, 62.3), .init(72.4, 59.4),
            .init(72.2, 58.3), .init(69.8, 58.2), .init(43.2, 56.6), .init(40.1, 55.4),
            .init(31.0, 47.5), .init(29.1, 47.2), .init(28.1, 48.0), .init(26.3, 54.1),
            .init(21.4, 78.5), .init(20.8, 79.1), .init(19.6, 79.2), .init(17.9, 77.1),
            .init(16.7, 75.3), .init(12.6, 71.8), .init(10.6, 68.4), .init(10.9, 66.9),
            .init(11.1, 65.7), .init(9.1, 65.0), .init(5.6, 62.4), .init(5.0, 60.5),
            .init(6.0, 57.8), .init(16.8, 38.4), .init(18.1, 37.2), .init(20.5, 37.6),
            .init(28.2, 45.0), .init(29.0, 44.1), .init(34.4, 34.5), .init(36.4, 33.9),
            .init(53.2, 43.6), .init(57.7, 45.0), .init(82.7, 45.6), .init(84.2, 43.8),
            .init(84.2, 40.2), .init(81.0, 30.1), .init(80.5, 28.0), .init(80.8, 23.0),
            .init(82.9, 20.8), .init(84.1, 21.8), .init(84.9, 22.7), .init(88.2, 24.3),
            .init(90.5, 24.5), .init(91.1, 25.9)
        ])),
        (["Austin", "COTA", "Americas"], CircuitInfo(laps: 56, lengthKm: 5.513, city: "Austin", turns: 20, drsZones: 2, lapRecord: "1:36.169", firstGrandPrix: 2012, direction: "Anti-clockwise", speedClass: "Technical-power mix", trackMapPoints: [
            .init(23.0, 66.3), .init(35.1, 75.4), .init(36.3, 75.8), .init(36.8, 74.8),
            .init(34.1, 66.7), .init(34.5, 63.8), .init(35.9, 61.7), .init(42.1, 57.8),
            .init(45.2, 55.2), .init(46.1, 52.8), .init(47.9, 51.2), .init(50.4, 49.9),
            .init(51.2, 47.3), .init(51.7, 45.3), .init(52.8, 43.8), .init(55.5, 42.1),
            .init(57.2, 41.9), .init(63.5, 44.5), .init(65.9, 42.9), .init(68.1, 40.3),
            .init(70.3, 39.5), .init(72.1, 40.5), .init(73.1, 42.0), .init(82.3, 40.3),
            .init(88.3, 33.7), .init(95.0, 25.1), .init(94.8, 24.4), .init(93.5, 24.2),
            .init(71.4, 30.6), .init(39.1, 35.3), .init(37.2, 36.0), .init(41.6, 41.9),
            .init(43.0, 45.0), .init(42.1, 45.7), .init(38.4, 45.2), .init(37.5, 43.1),
            .init(34.9, 40.1), .init(32.6, 39.8), .init(31.9, 40.1), .init(36.5, 48.9),
            .init(36.5, 50.8), .init(35.1, 53.9), .init(31.3, 55.8), .init(28.3, 55.8),
            .init(25.5, 54.6), .init(21.5, 49.2), .init(17.9, 45.6), .init(16.2, 46.0),
            .init(5.0, 51.3), .init(5.2, 52.3)
        ])),
        (["Mexico", "Hermanos"], CircuitInfo(laps: 71, lengthKm: 4.304, city: "Mexico City", turns: 17, drsZones: 3, lapRecord: "1:17.774", firstGrandPrix: 1963, direction: "Clockwise", speedClass: "Altitude", trackMapPoints: [
            .init(21.4, 18.8), .init(51.0, 22.8), .init(62.3, 24.0), .init(88.3, 27.8),
            .init(92.3, 28.7), .init(92.8, 29.4), .init(92.2, 33.9), .init(92.5, 34.6),
            .init(94.7, 35.8), .init(95.0, 36.6), .init(94.1, 41.4), .init(92.3, 45.6),
            .init(75.6, 72.8), .init(74.9, 74.4), .init(75.3, 75.2), .init(78.3, 77.2),
            .init(78.2, 77.9), .init(72.6, 82.2), .init(71.7, 82.5), .init(70.4, 81.8),
            .init(70.2, 80.6), .init(72.5, 61.9), .init(71.9, 61.0), .init(68.7, 58.9),
            .init(67.1, 57.4), .init(65.9, 54.7), .init(64.6, 53.0), .init(62.8, 52.1),
            .init(53.5, 50.5), .init(52.6, 49.7), .init(51.3, 45.9), .init(50.4, 44.6),
            .init(42.9, 40.4), .init(38.5, 39.1), .init(17.3, 35.9), .init(16.9, 35.2),
            .init(16.5, 29.3), .init(15.9, 25.2), .init(15.2, 24.7), .init(14.1, 25.3),
            .init(12.9, 26.7), .init(11.8, 26.9), .init(10.4, 26.2), .init(6.1, 25.6),
            .init(5.3, 25.2), .init(5.0, 24.3), .init(5.7, 22.0), .init(7.4, 19.5),
            .init(9.9, 17.9), .init(12.5, 17.5)
        ])),
        (["Interlagos", "Brazil", "São Paulo"], CircuitInfo(laps: 71, lengthKm: 4.309, city: "São Paulo", turns: 15, drsZones: 2, lapRecord: "1:10.540", firstGrandPrix: 1973, direction: "Anti-clockwise", speedClass: "Old-school", trackMapPoints: [
            .init(44.5, 28.2), .init(64.2, 28.4), .init(69.0, 29.7), .init(71.9, 33.5),
            .init(72.5, 38.1), .init(70.5, 42.4), .init(67.0, 44.7), .init(55.0, 44.5),
            .init(53.2, 45.2), .init(51.2, 47.5), .init(50.8, 62.2), .init(52.1, 64.9),
            .init(54.9, 66.9), .init(58.4, 67.3), .init(62.0, 66.0), .init(74.5, 57.3),
            .init(80.7, 50.9), .init(80.8, 35.7), .init(83.3, 33.3), .init(88.5, 34.2),
            .init(92.3, 35.0), .init(95.0, 31.5), .init(94.9, 29.2), .init(92.0, 25.8),
            .init(76.1, 22.2), .init(12.0, 22.2), .init(7.7, 24.4), .init(5.5, 28.2),
            .init(5.0, 32.0), .init(5.2, 34.0), .init(6.4, 37.5), .init(9.1, 40.6),
            .init(13.5, 42.6), .init(19.5, 44.2), .init(21.4, 46.7), .init(21.4, 49.8),
            .init(19.1, 62.0), .init(19.1, 64.9), .init(20.0, 67.4), .init(21.7, 69.4),
            .init(33.3, 77.8), .init(36.2, 77.4), .init(38.9, 74.9), .init(39.3, 73.5),
            .init(39.1, 44.4), .init(36.8, 42.7), .init(12.6, 36.1), .init(11.5, 33.0),
            .init(12.8, 29.8), .init(16.1, 28.1)
        ])),
        (["Las Vegas"], CircuitInfo(laps: 50, lengthKm: 6.201, city: "Las Vegas", turns: 17, drsZones: 2, lapRecord: "1:35.490", firstGrandPrix: 2023, direction: "Clockwise", speedClass: "Street power", trackMapPoints: [
            .init(91.7, 11.2), .init(96.4, 14.4), .init(98.1, 15.8), .init(98.3, 16.6),
            .init(96.7, 17.9), .init(95.0, 18.3), .init(91.6, 18.4), .init(90.1, 18.1),
            .init(83.7, 15.1), .init(79.9, 14.3), .init(78.5, 14.3), .init(74.6, 15.3),
            .init(73.3, 15.9), .init(70.2, 19.2), .init(69.6, 63.1), .init(71.0, 64.1),
            .init(90.6, 63.9), .init(93.0, 64.2), .init(96.6, 66.3), .init(97.8, 67.3),
            .init(99.4, 69.4), .init(99.8, 70.6), .init(100.0, 73.0), .init(99.2, 73.3),
            .init(96.2, 73.7), .init(95.3, 75.3), .init(95.4, 76.0), .init(97.9, 78.8),
            .init(98.8, 79.8), .init(96.8, 81.5), .init(93.6, 81.7), .init(60.7, 82.9),
            .init(54.6, 85.7), .init(51.8, 89.0), .init(44.9, 96.7), .init(42.0, 97.9),
            .init(34.7, 99.4), .init(29.6, 100.0), .init(28.2, 99.6), .init(27.7, 98.5),
            .init(21.9, 91.6), .init(16.9, 86.1), .init(15.1, 84.3), .init(8.9, 76.9),
            .init(7.3, 73.7), .init(4.3, 67.3), .init(3.3, 64.7), .init(1.8, 58.1),
            .init(1.5, 53.1), .init(1.5, 45.7), .init(1.6, 38.3), .init(0.6, 21.7),
            .init(0.3, 8.8), .init(0.0, 3.7), .init(1.1, 3.1), .init(2.7, 3.2),
            .init(6.5, 1.3), .init(11.8, 0.2), .init(25.1, 0.0), .init(56.7, 0.1),
            .init(63.7, 0.1), .init(75.4, 1.3), .init(76.9, 1.7), .init(79.2, 2.8)
        ])),
        (["Lusail", "Qatar"], CircuitInfo(laps: 57, lengthKm: 5.380, city: "Lusail", turns: 16, drsZones: 1, lapRecord: "1:22.384", firstGrandPrix: 2021, direction: "Clockwise", speedClass: "Fast sweepers", trackMapPoints: [
            .init(25.2, 59.5), .init(12.0, 35.5), .init(12.0, 32.9), .init(13.2, 31.2),
            .init(15.6, 30.3), .init(26.3, 36.3), .init(28.3, 36.6), .init(30.8, 35.1),
            .init(31.4, 24.7), .init(31.8, 22.6), .init(33.0, 20.9), .init(47.1, 5.4),
            .init(49.4, 5.0), .init(51.4, 5.8), .init(55.8, 10.4), .init(55.7, 13.4),
            .init(46.4, 23.9), .init(46.0, 25.3), .init(46.6, 26.5), .init(48.1, 27.0),
            .init(49.5, 26.5), .init(65.7, 20.3), .init(68.8, 21.7), .init(69.5, 23.8),
            .init(69.2, 25.5), .init(68.0, 27.0), .init(65.5, 29.5), .init(63.5, 32.6),
            .init(62.4, 35.8), .init(60.9, 39.9), .init(59.2, 40.9), .init(49.8, 43.4),
            .init(48.9, 44.8), .init(48.9, 46.9), .init(51.5, 49.7), .init(56.6, 53.1),
            .init(64.4, 54.8), .init(80.2, 53.1), .init(82.8, 54.0), .init(84.8, 56.2),
            .init(88.0, 62.7), .init(87.9, 64.5), .init(82.6, 73.2), .init(80.3, 74.4),
            .init(64.2, 71.4), .init(62.1, 71.7), .init(60.5, 73.1), .init(49.3, 94.2),
            .init(47.0, 95.0), .init(45.0, 94.5)
        ])),
        (["Yas Marina", "Abu Dhabi"], CircuitInfo(laps: 58, lengthKm: 5.281, city: "Abu Dhabi", turns: 16, drsZones: 2, lapRecord: "1:26.103", firstGrandPrix: 2009, direction: "Anti-clockwise", speedClass: "Technical-power mix", trackMapPoints: [
            .init(49.5, 55.5), .init(62.7, 53.6), .init(63.6, 51.7), .init(61.4, 42.4),
            .init(59.8, 40.1), .init(54.5, 38.1), .init(52.8, 36.7), .init(51.2, 34.1),
            .init(51.2, 30.8), .init(52.5, 26.1), .init(52.7, 20.2), .init(50.9, 6.7),
            .init(50.4, 5.7), .init(48.9, 5.0), .init(47.7, 5.6), .init(47.3, 6.4),
            .init(39.5, 30.8), .init(34.6, 45.2), .init(31.3, 56.3), .init(28.9, 63.9),
            .init(29.7, 64.4), .init(32.2, 64.2), .init(33.9, 69.7), .init(36.7, 74.8),
            .init(40.3, 78.4), .init(52.3, 87.8), .init(58.9, 91.5), .init(65.4, 94.5),
            .init(68.9, 95.0), .init(70.6, 93.6), .init(71.1, 92.2), .init(70.9, 89.9),
            .init(69.6, 88.0), .init(68.1, 87.2), .init(56.9, 86.1), .init(51.1, 82.8),
            .init(50.3, 82.0), .init(48.9, 75.5), .init(53.5, 74.5), .init(54.3, 74.1),
            .init(55.0, 72.5), .init(54.4, 67.8), .init(53.1, 67.5), .init(50.7, 67.4),
            .init(40.7, 68.7), .init(39.2, 68.4), .init(36.1, 63.4), .init(34.4, 60.1),
            .init(34.4, 58.7), .init(35.2, 57.6)
        ])),
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
    let race: Race
    let driverCode: String
    let position: Int
    let points: Double
    let status: String

    var isDNF: Bool {
        status != "Finished" && !status.starts(with: "+")
    }

    var raceName: String { race.raceName }

    /// Short label for chart axes and compact lists (e.g. "Monaco").
    var shortName: String { race.raceWeekendTitle }
}

struct DriverRaceResult: Identifiable {
    let id: String
    let race: Race
    let position: Int
    let points: Double
    let status: String

    var isDNF: Bool {
        status != "Finished" && !status.starts(with: "+")
    }

    var raceName: String { race.raceName }

    /// Short label for chart axes and compact lists (e.g. "Monaco").
    var shortName: String { race.raceWeekendTitle }
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

// MARK: - Qualifying Models

struct JolpicaQualifyingResponse: Codable {
    let MRData: QualifyingMRData
}

struct QualifyingMRData: Codable {
    let RaceTable: QualifyingRaceTable
}

struct QualifyingRaceTable: Codable {
    let Races: [JolpicaQualifyingRace]
}

struct JolpicaQualifyingRace: Codable {
    let round: String
    let raceName: String
    let QualifyingResults: [JolpicaQualifyingResult]?
}

struct JolpicaQualifyingResult: Codable {
    let position: String
    let Driver: JolpicaDriver
    let Constructor: JolpicaConstructor
    let Q1: String?
    let Q2: String?
    let Q3: String?
}

struct QualifyingResult: Identifiable {
    let id: String
    let position: Int
    let driverName: String
    let driverCode: String
    let constructor: String
    let bestTime: String?

    var gridPosition: Int { position }
}
