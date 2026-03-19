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
