import Foundation
import SwiftUI

struct LocationPoint {
    let date: Date
    let x: Double
    let y: Double
}

struct PositionPoint {
    let date: Date
    let position: Int
}

struct ReplaySession: Identifiable, Hashable {
    let sessionKey: Int
    let raceName: String
    let circuitName: String
    let date: Date

    var id: Int { sessionKey }
}

struct ReplayDriver: Identifiable {
    let driverNumber: Int
    let fullName: String
    let nameAcronym: String
    let teamName: String
    let teamColour: String
    var isVisible: Bool = true

    var id: Int { driverNumber }

    var color: Color {
        Color(hex: teamColour)
    }
}
