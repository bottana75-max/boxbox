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

    func matches(code: String, fullName: String) -> Bool {
        let normalizedSelf = self.fullName.lowercased()
        let normalizedName = fullName.lowercased()
        let familyName = normalizedName.split(separator: " ").last.map(String.init) ?? normalizedName

        return nameAcronym.uppercased() == code.uppercased()
            || normalizedSelf == normalizedName
            || normalizedSelf.contains(familyName)
    }

    static func fallback(driverCode: String, driverName: String, teamName: String) -> Driver {
        Driver(
            id: "\(driverCode)-\(driverName)",
            driverNumber: 0,
            fullName: driverName,
            nameAcronym: driverCode,
            teamName: teamName,
            teamColour: F1Design.teamHex(for: teamName),
            countryCode: "",
            headshotUrl: nil
        )
    }
}

struct DriverProfile {
    let nationality: String
    let dateOfBirth: String
    let placeOfBirth: String
    let debutSeason: Int
    let juniorTitle: String?
    let careerStage: String
    let blurb: String

    static func lookup(acronym: String, fullName: String) -> DriverProfile? {
        let key = acronym.uppercased()
        if let profile = data[key] { return profile }
        return data.first { fullName.uppercased().contains($0.key) }?.value
    }

    private static let data: [String: DriverProfile] = [
        "VER": DriverProfile(nationality: "Dutch", dateOfBirth: "30 Sep 1997", placeOfBirth: "Hasselt, Belgium", debutSeason: 2015, juniorTitle: nil, careerStage: "Multiple-time world champion", blurb: "Aggressive benchmark of the ground-effect era. Elite race pace, tyre management and wet-weather control."),
        "NOR": DriverProfile(nationality: "British", dateOfBirth: "13 Nov 1999", placeOfBirth: "Bristol, England", debutSeason: 2019, juniorTitle: "2018 F2 runner-up", careerStage: "Established front-runner", blurb: "Qualifying speed and confidence under pressure improved massively. Now expected to set the benchmark rather than chase it."),
        "LEC": DriverProfile(nationality: "Monegasque", dateOfBirth: "16 Oct 1997", placeOfBirth: "Monte Carlo, Monaco", debutSeason: 2018, juniorTitle: "2017 F2 champion", careerStage: "Ferrari lead driver", blurb: "One-lap weapon with genuine star quality. Ferrari's ceiling rises or falls with his weekends."),
        "HAM": DriverProfile(nationality: "British", dateOfBirth: "7 Jan 1985", placeOfBirth: "Stevenage, England", debutSeason: 2007, juniorTitle: "GP2 champion", careerStage: "Seven-time world champion", blurb: "Historic reference point. Even late-career Hamilton still changes the perception of any project he joins."),
        "RUS": DriverProfile(nationality: "British", dateOfBirth: "15 Feb 1998", placeOfBirth: "King's Lynn, England", debutSeason: 2019, juniorTitle: "2018 F2 champion", careerStage: "Mercedes race winner", blurb: "Structured, precise and often underrated. Strong over one lap and increasingly complete on Sundays."),
        "SAI": DriverProfile(nationality: "Spanish", dateOfBirth: "1 Sep 1994", placeOfBirth: "Madrid, Spain", debutSeason: 2015, juniorTitle: "Formula Renault 3.5 champion", careerStage: "Proven grand prix winner", blurb: "Methodical operator with strong race IQ. Rarely spectacular for the cameras, often excellent on the stopwatch."),
        "PIA": DriverProfile(nationality: "Australian", dateOfBirth: "6 Apr 2001", placeOfBirth: "Melbourne, Australia", debutSeason: 2023, juniorTitle: "F3 and F2 champion", careerStage: "Rapidly rising front-runner", blurb: "Cold-blooded and absurdly mature for his experience level. Massive upside if raw pace keeps climbing."),
        "ALO": DriverProfile(nationality: "Spanish", dateOfBirth: "29 Jul 1981", placeOfBirth: "Oviedo, Spain", debutSeason: 2001, juniorTitle: nil, careerStage: "Two-time world champion", blurb: "One of the sharpest racers ever. Experience, starts and racecraft still mask machinery limits."),
        "STR": DriverProfile(nationality: "Canadian", dateOfBirth: "29 Oct 1998", placeOfBirth: "Montreal, Canada", debutSeason: 2017, juniorTitle: "2016 European F3 champion", careerStage: "Experienced midfield runner", blurb: "Can spike to a very high level in chaos, but consistency is the entire story with Stroll."),
        "PER": DriverProfile(nationality: "Mexican", dateOfBirth: "26 Jan 1990", placeOfBirth: "Guadalajara, Mexico", debutSeason: 2011, juniorTitle: "GP2 runner-up", careerStage: "Established race winner", blurb: "Tyre whisperer and street-circuit specialist. When confidence drops, the whole package collapses fast."),
        "GAS": DriverProfile(nationality: "French", dateOfBirth: "7 Feb 1996", placeOfBirth: "Rouen, France", debutSeason: 2017, juniorTitle: "2016 GP2 champion", careerStage: "Grand prix winner", blurb: "Fast enough to lead midfield fights, but needs a stable car window to look fully convincing."),
        "OCO": DriverProfile(nationality: "French", dateOfBirth: "17 Sep 1996", placeOfBirth: "Évreux, France", debutSeason: 2016, juniorTitle: "2014 European F3 champion", careerStage: "Grand prix winner", blurb: "Tough, disciplined and better wheel-to-wheel than people admit. Not flashy, usually useful."),
        "ALB": DriverProfile(nationality: "Thai", dateOfBirth: "23 Mar 1996", placeOfBirth: "London, England", debutSeason: 2019, juniorTitle: nil, careerStage: "Established team leader", blurb: "Calm under pressure and excellent at dragging limited machinery forward on race day."),
        "TSU": DriverProfile(nationality: "Japanese", dateOfBirth: "11 May 2000", placeOfBirth: "Sagamihara, Japan", debutSeason: 2021, juniorTitle: nil, careerStage: "Established midfield racer", blurb: "Raw speed has never been the issue. The challenge is packaging it over complete weekends."),
        "HUL": DriverProfile(nationality: "German", dateOfBirth: "19 Aug 1987", placeOfBirth: "Emmerich am Rhein, Germany", debutSeason: 2010, juniorTitle: "2009 GP2 champion", careerStage: "Veteran benchmark", blurb: "Reliable benchmark for any midfield car. If a teammate beats him clearly, they're probably legit."),
        "BEA": DriverProfile(nationality: "British", dateOfBirth: "6 May 2005", placeOfBirth: "London, England", debutSeason: 2024, juniorTitle: "Junior single-seater standout", careerStage: "Early-career prospect", blurb: "High-upside rookie profile: composure, racecraft and technical feedback matter more than headline results right now."),
        "COL": DriverProfile(nationality: "Argentine", dateOfBirth: "27 May 2003", placeOfBirth: "Pilar, Argentina", debutSeason: 2024, juniorTitle: "Junior single-seater race winner", careerStage: "Early-career prospect", blurb: "Exciting but still incomplete. Needs mileage and cleaner weekends before anyone should overhype him."),
        "BOT": DriverProfile(nationality: "Finnish", dateOfBirth: "28 Aug 1989", placeOfBirth: "Nastola, Finland", debutSeason: 2013, juniorTitle: "GP3 champion", careerStage: "Multi-win veteran", blurb: "Still one of the cleaner qualifiers in the field. Ceiling depends heavily on machinery, not effort."),
        "ZHO": DriverProfile(nationality: "Chinese", dateOfBirth: "30 May 1999", placeOfBirth: "Shanghai, China", debutSeason: 2022, juniorTitle: nil, careerStage: "Midfield roster option", blurb: "Commercial spotlight aside, the real question is whether he can become a durable midfield-level scorer."),
        "MAG": DriverProfile(nationality: "Danish", dateOfBirth: "5 Oct 1992", placeOfBirth: "Roskilde, Denmark", debutSeason: 2014, juniorTitle: "Formula Renault 3.5 champion", careerStage: "Experienced midfield racer", blurb: "Old-school elbows-out racer. Valuable in messy fights, expensive when the red mist arrives."),
        "SAR": DriverProfile(nationality: "American", dateOfBirth: "31 Dec 2000", placeOfBirth: "Fort Lauderdale, USA", debutSeason: 2023, juniorTitle: nil, careerStage: "Developing F1 driver", blurb: "The roadmap is simple: reduce errors, survive pressure, prove there is long-term F1 level underneath."),
        "LAW": DriverProfile(nationality: "New Zealander", dateOfBirth: "11 Feb 2002", placeOfBirth: "Hastings, New Zealand", debutSeason: 2023, juniorTitle: "DTM runner-up", careerStage: "Seat-fighting prospect", blurb: "Sharp, opportunistic and mentally ready. Needs a stable seat to show whether the ceiling is real."),
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
