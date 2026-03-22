import Foundation
import SwiftUI

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

struct ReplayLocationPoint: Hashable {
    let date: Date
    let x: Double
    let y: Double
    let z: Double
}

struct ReplayMarker: Identifiable, Hashable {
    let driver: ReplayDriver
    let runningPosition: Int?
    let projectedPoint: TrackMapPoint
    let sourcePoint: ReplayLocationPoint

    var id: Int { driver.driverNumber }
}

struct ReplayStandingEntry: Identifiable, Hashable {
    let driver: ReplayDriver
    let position: Int
    let isSelected: Bool

    var id: Int { driver.driverNumber }
}

struct ReplaySnapshot: Identifiable, Hashable {
    let index: Int
    let timestamp: Date
    let elapsedTime: TimeInterval
    let lapNumber: Int?
    let phase: ReplayPhase
    let markers: [ReplayMarker]
    let standings: [ReplayStandingEntry]
    let headline: String

    var id: Int { index }
}

struct ReplayPhase: Hashable {
    enum Kind: Hashable {
        case preRace
        case racing
    }

    let kind: Kind
    let label: String
    let shortLabel: String
}

struct ReplayLapAnchor: Identifiable, Hashable {
    let lapNumber: Int
    let snapshotIndex: Int
    let elapsedTime: TimeInterval

    var id: Int { lapNumber }
}

struct ReplayProjectionMetadata: Hashable {
    let loadedDriverCount: Int
    let sampleCount: Int
    let usesProjectedTrackFit: Bool
    let freshnessWindow: TimeInterval
    let isCached: Bool
}

struct RaceReplayPayload {
    let availableDrivers: [ReplayDriver]
    let selectedDrivers: [ReplayDriver]
    let snapshots: [ReplaySnapshot]
    let lapAnchors: [ReplayLapAnchor]
    let raceStartSnapshotIndex: Int
    let totalDuration: TimeInterval
    let displayTrackPoints: [TrackMapPoint]
    let projection: ReplayProjectionMetadata
}
