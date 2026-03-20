import Foundation

class AIService {
    static let shared = AIService()

    // Key embedded — split to avoid trivial extraction
    private var embeddedKey: String {
        let a = "sk-proj--di0URqCDX8VmlR08sb84J5SZz-eFJYkaTFEJhqJ7OeRqh9aFB0YePgVBasSr"
        let b = "MbGwJzyydDZqcT3BlbkFJajpw_k_xl7rz-lu3v5uujCCmCriRSlggVPtVdhBfw5DoXWHTiwY6ZjBPhbAl7Sdwtd09siDVIA"
        return a + b
    }

    var hasAPIKey: Bool { true }

    // Reuse decoder — allocating JSONDecoder on every prediction call is wasteful.
    private let decoder = JSONDecoder()

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

        let weekendContext = nextRace.weekendContext

        let prompt = """
        You are an expert Formula 1 analyst. Predict the podium (top 3) for the upcoming race.

        Race: \(nextRace.raceName)
        Circuit: \(nextRace.circuitName), \(nextRace.country)
        Date: \(nextRace.formattedDate)

        Driver standings:
        \(top10)

        Recent races:
        \(recentSummary)

        Momentum:
        \(trendSummary)

        Circuit profile:
        - Overtaking: \(pressureProfile.overtaking)
        - Tyre stress: \(pressureProfile.tyreStress)
        - Qualifying importance: \(pressureProfile.qualifyingImportance)

        Respond ONLY with valid JSON:
        {
            "first": "Driver Full Name",
            "second": "Driver Full Name",
            "third": "Driver Full Name",
            "reasoning": "2-3 sentence explanation"
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
        request.timeoutInterval = 30
        request.setValue("Bearer \(embeddedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AIError.apiError("API returned status \(statusCode)")
        }

        let chatResponse = try decoder.decode(ChatCompletionResponse.self, from: data)
        guard let rawContent = chatResponse.choices.first?.message.content else {
            throw AIError.noResponse
        }

        // Strip optional markdown code fences the model sometimes wraps around JSON.
        let cleanContent = rawContent
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleanContent.data(using: .utf8) else {
            throw AIError.parseError
        }

        let predictionResponse = try decoder.decode(PredictionAPIResponse.self, from: jsonData)

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
