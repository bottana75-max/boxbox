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
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    func predictRace(context: RaceCallContext) async throws -> RaceCall {
        let contextJSON = try encoder.encode(context)
        let contextString = String(data: contextJSON, encoding: .utf8) ?? "{}"

        let prompt = """
        You are an elite Formula 1 race analyst. You receive structured race context and must produce a structured race call.

        CONTEXT:
        \(contextString)

        ANALYSIS INSTRUCTIONS:
        1. Weigh each contender's formScore (recent results), trackFitScore (circuit suitability), and overallRating.
        2. Factor in the circuit profile (overtaking difficulty, tyre stress, qualifying importance).
        3. Consider the weather profile and its impact on race strategy.
        4. Note the confidence level (\(context.confidenceLabel)) and chaos potential (\(context.chaosLabel)).
        5. Pick a dark horse — someone outside the obvious top 3 who could surprise.
        6. Identify the biggest risk — a contender who could underperform or DNF.
        7. Write a flip scenario — one realistic event that would completely change your podium prediction.

        Respond ONLY with valid JSON matching this exact structure:
        {
            "podium": {
                "first": "Driver Full Name",
                "second": "Driver Full Name",
                "third": "Driver Full Name"
            },
            "darkHorse": {
                "driver": "Driver Full Name",
                "why": "One sentence reason"
            },
            "biggestRisk": {
                "driver": "Driver Full Name",
                "why": "One sentence reason"
            },
            "reasoning": "2-3 sentences explaining your podium picks using the data provided",
            "flipScenario": "One sentence describing what event would flip this prediction"
        }
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "You are an F1 expert analyst. Always respond with valid JSON only. Use driver data and scores provided — do not hallucinate stats."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 500
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

        let apiResponse = try decoder.decode(RaceCallAPIResponse.self, from: jsonData)

        return RaceCall(
            id: UUID(),
            raceId: context.round.description,
            raceName: context.raceName,
            first: apiResponse.podium.first,
            second: apiResponse.podium.second,
            third: apiResponse.podium.third,
            darkHorse: apiResponse.darkHorse.driver,
            darkHorseWhy: apiResponse.darkHorse.why,
            biggestRisk: apiResponse.biggestRisk.driver,
            biggestRiskWhy: apiResponse.biggestRisk.why,
            reasoning: apiResponse.reasoning,
            flipScenario: apiResponse.flipScenario,
            confidenceLabel: context.confidenceLabel,
            chaosLabel: context.chaosLabel,
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
