import Foundation

struct Driver: Identifiable, Codable, Hashable {
    let id: String
    let driverNumber: Int
    let fullName: String
    let nameAcronym: String
    let teamName: String
    let teamColour: String
    let countryCode: String
    let headshotUrl: String?

    enum CodingKeys: String, CodingKey {
        case driverNumber = "driver_number"
        case fullName = "full_name"
        case nameAcronym = "name_acronym"
        case teamName = "team_name"
        case teamColour = "team_colour"
        case countryCode = "country_code"
        case headshotUrl = "headshot_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.driverNumber = try container.decode(Int.self, forKey: .driverNumber)
        self.fullName = try container.decode(String.self, forKey: .fullName)
        self.nameAcronym = try container.decode(String.self, forKey: .nameAcronym)
        self.teamName = try container.decode(String.self, forKey: .teamName)
        self.teamColour = try container.decodeIfPresent(String.self, forKey: .teamColour) ?? "FFFFFF"
        self.countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode) ?? ""
        self.headshotUrl = try container.decodeIfPresent(String.self, forKey: .headshotUrl)
        self.id = "\(self.driverNumber)-\(self.nameAcronym)"
    }

    init(id: String, driverNumber: Int, fullName: String, nameAcronym: String, teamName: String, teamColour: String, countryCode: String, headshotUrl: String?) {
        self.id = id
        self.driverNumber = driverNumber
        self.fullName = fullName
        self.nameAcronym = nameAcronym
        self.teamName = teamName
        self.teamColour = teamColour
        self.countryCode = countryCode
        self.headshotUrl = headshotUrl
    }
}

extension Driver {
    var teamColor: Color {
        Color(hex: teamColour)
    }

    var profile: DriverProfile? {
        DriverProfile.lookup(acronym: nameAcronym, fullName: fullName)
    }
}

struct DriverProfile {
    let nationality: String
    let dateOfBirth: String
    let placeOfBirth: String
    let debutSeason: Int
    let championships: Int
    let careerWins: Int
    let careerPodiums: Int
    let careerPoles: Int
    let bestFinish: String
    let juniorTitle: String?
    let blurb: String

    static func lookup(acronym: String, fullName: String) -> DriverProfile? {
        let key = acronym.uppercased()
        if let profile = data[key] { return profile }
        return data.first { fullName.uppercased().contains($0.key) }?.value
    }

    private static let data: [String: DriverProfile] = [
        "VER": DriverProfile(nationality: "Dutch", dateOfBirth: "30 Sep 1997", placeOfBirth: "Hasselt, Belgium", debutSeason: 2015, championships: 4, careerWins: 63, careerPodiums: 112, careerPoles: 40, bestFinish: "World Champion", juniorTitle: nil, blurb: "Aggressive benchmark of the ground-effect era. Elite race pace, tyre management and wet-weather control."),
        "NOR": DriverProfile(nationality: "British", dateOfBirth: "13 Nov 1999", placeOfBirth: "Bristol, England", debutSeason: 2019, championships: 0, careerWins: 4, careerPodiums: 26, careerPoles: 9, bestFinish: "Runner-up", juniorTitle: "2018 F2 runner-up", blurb: "Qualifying speed and confidence under pressure improved massively. Now expected to convert pace into titles."),
        "LEC": DriverProfile(nationality: "Monegasque", dateOfBirth: "16 Oct 1997", placeOfBirth: "Monte Carlo, Monaco", debutSeason: 2018, championships: 0, careerWins: 8, careerPodiums: 43, careerPoles: 26, bestFinish: "Runner-up", juniorTitle: "2017 F2 champion", blurb: "One-lap weapon with genuine star quality. Ferrari's ceiling rises or falls with his weekends."),
        "HAM": DriverProfile(nationality: "British", dateOfBirth: "7 Jan 1985", placeOfBirth: "Stevenage, England", debutSeason: 2007, championships: 7, careerWins: 105, careerPodiums: 202, careerPoles: 104, bestFinish: "World Champion", juniorTitle: "GP2 champion", blurb: "Historic reference point. Even late-career Hamilton still changes the perception of any project he joins."),
        "RUS": DriverProfile(nationality: "British", dateOfBirth: "15 Feb 1998", placeOfBirth: "King's Lynn, England", debutSeason: 2019, championships: 0, careerWins: 3, careerPodiums: 17, careerPoles: 5, bestFinish: "4th in championship", juniorTitle: "2018 F2 champion", blurb: "Structured, precise and often underrated. Strong over one lap and increasingly complete on Sundays."),
        "SAI": DriverProfile(nationality: "Spanish", dateOfBirth: "1 Sep 1994", placeOfBirth: "Madrid, Spain", debutSeason: 2015, championships: 0, careerWins: 4, careerPodiums: 27, careerPoles: 6, bestFinish: "5th in championship", juniorTitle: "Formula Renault 3.5 champion", blurb: "Methodical operator with strong race IQ. Rarely spectacular for the cameras, often excellent on the stopwatch."),
        "PIA": DriverProfile(nationality: "Australian", dateOfBirth: "6 Apr 2001", placeOfBirth: "Melbourne, Australia", debutSeason: 2023, championships: 0, careerWins: 2, careerPodiums: 10, careerPoles: 0, bestFinish: "4th in championship", juniorTitle: "F3 and F2 champion", blurb: "Cold-blooded and absurdly mature for his experience level. Massive upside if raw pace keeps climbing."),
        "ALO": DriverProfile(nationality: "Spanish", dateOfBirth: "29 Jul 1981", placeOfBirth: "Oviedo, Spain", debutSeason: 2001, championships: 2, careerWins: 32, careerPodiums: 106, careerPoles: 22, bestFinish: "World Champion", juniorTitle: nil, blurb: "One of the sharpest racers ever. Experience, starts and racecraft still mask machinery limits."),
        "STR": DriverProfile(nationality: "Canadian", dateOfBirth: "29 Oct 1998", placeOfBirth: "Montreal, Canada", debutSeason: 2017, championships: 0, careerWins: 0, careerPodiums: 3, careerPoles: 1, bestFinish: "10th in championship", juniorTitle: "2016 European F3 champion", blurb: "Can spike to a very high level in chaos, but consistency is the entire story with Stroll."),
        "PER": DriverProfile(nationality: "Mexican", dateOfBirth: "26 Jan 1990", placeOfBirth: "Guadalajara, Mexico", debutSeason: 2011, championships: 0, careerWins: 6, careerPodiums: 39, careerPoles: 3, bestFinish: "Runner-up", juniorTitle: "GP2 runner-up", blurb: "Tyre whisperer and street-circuit specialist. When confidence drops, the whole package collapses fast."),
        "GAS": DriverProfile(nationality: "French", dateOfBirth: "7 Feb 1996", placeOfBirth: "Rouen, France", debutSeason: 2017, championships: 0, careerWins: 1, careerPodiums: 5, careerPoles: 0, bestFinish: "10th in championship", juniorTitle: "2016 GP2 champion", blurb: "Fast enough to lead midfield fights, but needs a stable car window to look fully convincing."),
        "OCO": DriverProfile(nationality: "French", dateOfBirth: "17 Sep 1996", placeOfBirth: "Évreux, France", debutSeason: 2016, championships: 0, careerWins: 1, careerPodiums: 4, careerPoles: 0, bestFinish: "8th in championship", juniorTitle: "2014 European F3 champion", blurb: "Tough, disciplined and better wheel-to-wheel than people admit. Not flashy, usually useful."),
        "ALB": DriverProfile(nationality: "Thai", dateOfBirth: "23 Mar 1996", placeOfBirth: "London, England", debutSeason: 2019, championships: 0, careerWins: 0, careerPodiums: 2, careerPoles: 0, bestFinish: "7th in championship", juniorTitle: nil, blurb: "Calm under pressure and excellent at dragging limited machinery forward on race day."),
        "TSU": DriverProfile(nationality: "Japanese", dateOfBirth: "11 May 2000", placeOfBirth: "Sagamihara, Japan", debutSeason: 2021, championships: 0, careerWins: 0, careerPodiums: 0, careerPoles: 0, bestFinish: "12th in championship", juniorTitle: nil, blurb: "Raw speed has never been the issue. The challenge is packaging it over complete weekends."),
        "HUL": DriverProfile(nationality: "German", dateOfBirth: "19 Aug 1987", placeOfBirth: "Emmerich am Rhein, Germany", debutSeason: 2010, championships: 0, careerWins: 0, careerPodiums: 0, careerPoles: 1, bestFinish: "7th in championship", juniorTitle: "2009 GP2 champion", blurb: "Reliable benchmark for any midfield car. If a teammate beats him clearly, they're probably legit."),
        "BEA": DriverProfile(nationality: "British", dateOfBirth: "6 May 2005", placeOfBirth: "London, England", debutSeason: 2024, championships: 0, careerWins: 0, careerPodiums: 0, careerPoles: 0, bestFinish: "Rookie season", juniorTitle: "2023 F4 champion", blurb: "High-upside rookie profile: composure, racecraft and technical feedback matter more than headline results right now."),
        "COL": DriverProfile(nationality: "Argentine", dateOfBirth: "27 May 2003", placeOfBirth: "Pilar, Argentina", debutSeason: 2024, championships: 0, careerWins: 0, careerPodiums: 0, careerPoles: 0, bestFinish: "Rookie season", juniorTitle: "F3 race winner", blurb: "Exciting but still incomplete. Needs mileage and cleaner weekends before anyone should overhype him."),
        "BOT": DriverProfile(nationality: "Finnish", dateOfBirth: "28 Aug 1989", placeOfBirth: "Nastola, Finland", debutSeason: 2013, championships: 0, careerWins: 10, careerPodiums: 67, careerPoles: 20, bestFinish: "Runner-up", juniorTitle: "GP3 champion", blurb: "Still one of the cleaner qualifiers in the field. Ceiling depends heavily on machinery, not effort."),
        "ZHO": DriverProfile(nationality: "Chinese", dateOfBirth: "30 May 1999", placeOfBirth: "Shanghai, China", debutSeason: 2022, championships: 0, careerWins: 0, careerPodiums: 0, careerPoles: 0, bestFinish: "18th in championship", juniorTitle: nil, blurb: "Commercial spotlight aside, the real question is whether he can become a durable midfield-level scorer."),
        "MAG": DriverProfile(nationality: "Danish", dateOfBirth: "5 Oct 1992", placeOfBirth: "Roskilde, Denmark", debutSeason: 2014, championships: 0, careerWins: 0, careerPodiums: 1, careerPoles: 1, bestFinish: "11th in championship", juniorTitle: "Formula Renault 3.5 champion", blurb: "Old-school elbows-out racer. Valuable in messy fights, expensive when the red mist arrives."),
        "SAR": DriverProfile(nationality: "American", dateOfBirth: "31 Dec 2000", placeOfBirth: "Fort Lauderdale, USA", debutSeason: 2023, championships: 0, careerWins: 0, careerPodiums: 0, careerPoles: 0, bestFinish: "Rookie season", juniorTitle: nil, blurb: "The roadmap is simple: reduce errors, survive pressure, prove there is long-term F1 level underneath."),
        "LAW": DriverProfile(nationality: "New Zealander", dateOfBirth: "11 Feb 2002", placeOfBirth: "Hastings, New Zealand", debutSeason: 2023, championships: 0, careerWins: 0, careerPodiums: 0, careerPoles: 0, bestFinish: "Reserve/rookie phase", juniorTitle: "DTM runner-up", blurb: "Sharp, opportunistic and mentally ready. Needs a stable seat to show whether the ceiling is real."),
    ]
}

import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            r = 1; g = 1; b = 1
        }
        self.init(red: r, green: g, blue: b)
    }
}
