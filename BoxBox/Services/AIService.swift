import Foundation

class AIService {
    static let shared = AIService()

    static let apiKeyKey = "openai_api_key"

    var apiKey: String? {
        get { UserDefaults.standard.string(forKey: Self.apiKeyKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.apiKeyKey) }
    }

    var hasAPIKey: Bool {
        guard let key = apiKey else { return false }
        return !key.isEmpty
    }

    func predictRace(
        nextRace: String,
        circuitName: String,
        driverStandings: [DriverStanding],
        lastRaceResults: [String]
    ) async throws -> Prediction {
        guard let apiKey, !apiKey.isEmpty else {
            throw AIError.noAPIKey
        }

        let top10 = driverStandings.prefix(10).map { "\($0.position). \($0.driverName) (\($0.constructorName)) - \($0.points) pts" }.joined(separator: "\n")
        let recentWinners = lastRaceResults.prefix(3).joined(separator: ", ")

        let prompt = """
        You are an expert Formula 1 analyst. Predict the podium (top 3) for the upcoming race.

        Race: \(nextRace)
        Circuit: \(circuitName)

        Current Driver Standings (Top 10):
        \(top10)

        Recent Race Winners: \(recentWinners)

        Consider:
        - Current form and momentum
        - Historical circuit performance
        - Team car performance characteristics
        - Weather and track conditions tendencies

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

        // Parse the JSON from the response
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
            raceId: nextRace,
            raceName: nextRace,
            first: predictionResponse.first,
            second: predictionResponse.second,
            third: predictionResponse.third,
            reasoning: predictionResponse.reasoning,
            createdAt: Date()
        )
    }
}

// MARK: - OpenAI Response Models

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
    case noAPIKey
    case apiError(String)
    case noResponse
    case parseError

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "Please set your OpenAI API key in Settings"
        case .apiError(let msg): return "AI service error: \(msg)"
        case .noResponse: return "No response from AI"
        case .parseError: return "Failed to parse AI response"
        }
    }
}
