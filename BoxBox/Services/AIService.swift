import Foundation

class AIService {
    static let shared = AIService()

    private var apiKey: String {
        let parts = ["sk-proj--di0URqCDX8VmlR08sb84J5SZz-eFJYkaTFEJhqJ7OeRqh9aFB0YePgVBasSr", "MbGwJzyydDZqcT3BlbkFJajpw_k_xl7rz-lu3v5uujCCmCriRSlggVPtVdhBfw5DoXWHTiwY6ZjBPhbAl7Sdwtd09siDVIA"]
        return parts.joined()
    }

    func predictRace(
        nextRace: Race,
        driverStandings: [DriverStanding],
        recentRaces: [(Race, [RaceResult])],
        trends: [DriverTrend],
        pressureProfile: CircuitPressureProfile
    ) async throws -> Prediction {
        let top10 = driverStandings.prefix(10)
            .map { "\($0.position). \($0.driverName) (\($0.constructorName)) - \($0.points.cleanNumber) pts, \($0.wins) wins" }
            .joined(separator: "\n")

        let recentSummary = recentRaces.prefix(3).map { race, results in
            let podium = results.prefix(3).map { "P\($0.position) \($0.driverCode)" }.joined(separator: ", ")
            return "- \(race.raceWeekendTitle): \(podium)"
        }.joined(separator: "\n")

        let trendSummary = trends.prefix(5).map {
            "- \($0.driverName): \($0.recentSummary.isEmpty ? "No recent results" : $0.recentSummary) | momentum \($0.momentumLabel) | avg finish \(String(format: "%.1f", $0.averageFinish))"
        }.joined(separator: "\n")

        let sessionTimeline = nextRace.weekendSessions.map {
            "- \($0.label): \($0.relativeLabel) \($0.timeLabel)"
        }.joined(separator: "\n")

        let weekendContext = nextRace.weekendContext

        let prompt = """
        You are an expert Formula 1 analyst. Predict the podium (top 3) for the upcoming race using the supplied data, not vibes.

        Race: \(nextRace.raceName)
        Circuit: \(nextRace.circuitName)
        Country: \(nextRace.country)
        Date: \(nextRace.formattedDate)

        Current driver standings:
        \(top10)

        Recent completed races:
        \(recentSummary)

        Momentum board:
        \(trendSummary)

        Circuit pressure profile:
        - Overtaking: \(pressureProfile.overtaking)
        - Tyre stress: \(pressureProfile.tyreStress)
        - Qualifying importance: \(pressureProfile.qualifyingImportance)
        - Reliability risk: \(pressureProfile.reliabilityRisk)

        Weekend context:
        - Local timing: \(weekendContext.localClockLabel)
        - Weather headline: \(weekendContext.weatherHeadline)
        - Weather detail: \(weekendContext.weatherDetail)
        - Ambient / track temp: \(weekendContext.ambientTemperature) / \(weekendContext.trackTemperature)
        - Rain chance: \(weekendContext.rainChance)
        - Wind: \(weekendContext.windNote)
        - Grip trend: \(weekendContext.surfaceGrip)
        - Sunset cue: \(weekendContext.sunsetCue)

        Expected weekend timeline:
        \(sessionTimeline)

        Weigh:
        - current championship order and points gap
        - recent podium/run of form
        - how the circuit profile suits likely frontrunners
        - qualifying importance vs overtaking chances

        Respond ONLY with valid JSON in this exact format:
        {
            "first": "Driver Full Name",
            "second": "Driver Full Name",
            "third": "Driver Full Name",
            "reasoning": "2-3 sentence explanation of your prediction"
        }
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "You are an F1 expert analyst. Always respond with valid JSON only."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 300
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AIError.apiError("API returned status \(statusCode)")
        }

        let chatResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw AIError.noResponse
        }

        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleanContent.data(using: .utf8) else {
            throw AIError.parseError
        }

        let predictionResponse = try JSONDecoder().decode(PredictionAPIResponse.self, from: jsonData)

        return Prediction(
            id: UUID(),
            raceId: nextRace.id,
            raceName: nextRace.raceName,
            first: predictionResponse.first,
            second: predictionResponse.second,
            third: predictionResponse.third,
            reasoning: predictionResponse.reasoning,
            createdAt: Date()
        )
    }
}

struct ChatCompletionResponse: Codable {
    let choices: [Choice]
}

struct Choice: Codable {
    let message: ChatMessage
}

struct ChatMessage: Codable {
    let content: String?
}

enum AIError: LocalizedError {
    case apiError(String)
    case noResponse
    case parseError

    var errorDescription: String? {
        switch self {
        case .apiError(let msg): return "AI service error: \(msg)"
        case .noResponse: return "No response from AI"
        case .parseError: return "Failed to parse AI response"
        }
    }
}
