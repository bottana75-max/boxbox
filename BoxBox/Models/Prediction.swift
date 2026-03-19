import Foundation

struct Prediction: Identifiable, Codable {
    let id: UUID
    let raceId: String
    let raceName: String
    let first: String
    let second: String
    let third: String
    let reasoning: String
    let createdAt: Date
}

struct PredictionAPIResponse: Codable {
    let first: String
    let second: String
    let third: String
    let reasoning: String
}
