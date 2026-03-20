import Foundation
import SwiftUI

struct PositionPoint {
    let date: Date
    let position: Int
}

struct ReplayDriver: Identifiable, Hashable {
    let driverNumber: Int
    let fullName: String
    let nameAcronym: String
    let teamName: String
    let teamColour: String

    var id: Int { driverNumber }

    var color: Color {
        Color(hex: teamColour)
    }
}

struct ReplayStandingEntry: Identifiable, Hashable {
    let driver: ReplayDriver
    let position: Int
    let delta: Int

    var id: Int { driver.driverNumber }
}

struct ReplaySnapshot: Identifiable, Hashable {
    let index: Int
    let timestamp: Date
    let elapsedTime: TimeInterval
    let standings: [ReplayStandingEntry]
    let headline: String

    var id: Int { index }
}

struct RaceReplayPayload {
    let drivers: [ReplayDriver]
    let snapshots: [ReplaySnapshot]
    let totalDuration: TimeInterval
}
