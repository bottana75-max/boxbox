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

    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    func predictRace(context: RaceCallContext) async throws -> RaceCall {
        let contextJSON = try encoder.encode(context)
        let contextString = String(data: contextJSON, encoding: .utf8) ?? "{}"

        let phaseInstructions: String
        switch context.weekendPhase {
        case "Baseline":
            phaseInstructions = """
            PHASE: Baseline (pre-weekend). You have championship form and historical circuit data only.
            Focus on season-long momentum, team/circuit matchups, and recent race trends.
            Confidence should reflect the inherent uncertainty of calling before practice data.
            """
        case "Post-Practice":
            phaseInstructions = """
            PHASE: Post-Practice. Practice pace indicators are available.
            Factor in weekendPaceScore which reflects observed practice form.
            Note any teams that looked unexpectedly strong or weak in sessions.
            """
        case "Post-Qualifying":
            phaseInstructions = """
            PHASE: Post-Qualifying. The grid is set — gridPosition data is available for each contender.
            Heavily weight grid positions against the circuit's overtaking difficulty.
            At low-overtaking circuits, grid position is near-decisive. At high-overtaking circuits, race pace matters more.
            Reference specific grid positions in your reasoning (e.g. "starting P3 on a track where...").
            """
        default:
            phaseInstructions = """
            PHASE: Race Ready. All weekend data is in — grid locked, final conditions known.
            Use all available signals: form, grid, weather, pace. This is your most informed call.
            If live weather data shows rainfall, factor wet-weather performance heavily.
            """
        }

        let prompt = """
        You are an elite Formula 1 race strategist producing a premium race call briefing.

        CONTEXT:
        \(contextString)

        \(phaseInstructions)

        ANALYSIS RULES:
        1. Weigh each contender's overallRating, formScore, trackFitScore, and weekendPaceScore.
        2. Use sessionContext to understand how much real weekend running is available; do not pretend you have data the phase does not support.
        3. Use weekendPace to discuss long-run bias, first-stint shape, and how grid pressure changes the likely race script.
        4. If gridPosition is available, factor it heavily — especially when qualifyingImportance is "Massive" or circuit overtaking is "Track position".
        5. Factor circuit profile: overtaking difficulty, tyre stress, reliability risk.
        6. Factor weather: use both the seasonal profile AND liveWeather if present. If rainfall is true, consider wet-weather specialists.
        7. Note confidence level (\(context.confidenceLabel)) and chaos potential (\(context.chaosLabel)) — let these guide your tone.
        8. Pick a dark horse — someone outside the obvious top 3 who could surprise, with a SPECIFIC reason tied to data.
        9. Identify the biggest risk — a contender who could underperform, with a concrete reason.
        10. Identify the key battle — two drivers likely to fight directly, based on proximity in ratings or grid positions.
        11. Provide a strategy angle — one tactical insight about tyres, undercuts, weather timing, or pit window that could decide the race.
        12. Write reasoning that references SPECIFIC scores, positions, or data points — never generic statements.
        13. Write a flip scenario that is specific and plausible, not generic.

        QUALITY RULES:
        - Never say "could" when you mean "will likely". Be assertive.
        - Reference actual driver names, scores, and positions.
        - The strategy angle must be actionable — mention a specific phase of the race, tyre compound, or weather window.
        - Dark horse reason must cite a specific data signal (form trend, track fit, grid position).
        - Reasoning should read like a pit wall brief, not a TV preview.

        Respond ONLY with valid JSON matching this exact structure:
        {
            "podium": {
                "first": "Driver Full Name",
                "second": "Driver Full Name",
                "third": "Driver Full Name"
            },
            "darkHorse": {
                "driver": "Driver Full Name",
                "why": "One sentence with specific data reference"
            },
            "biggestRisk": {
                "driver": "Driver Full Name",
                "why": "One sentence with specific data reference"
            },
            "keyBattle": {
                "drivers": ["Driver Full Name", "Driver Full Name"],
                "narrative": "One sentence about why these two will fight"
            },
            "strategyAngle": "One sentence tactical insight referencing a specific race phase or compound",
            "reasoning": "3-4 sentences referencing specific scores, grid positions, and data to justify your podium",
            "flipScenario": "One specific, plausible event that would change this prediction"
        }
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "You are an F1 expert race strategist. Always respond with valid JSON only. Use the driver data, scores, and grid positions provided — do not hallucinate stats. Reference specific numbers from the context. Be assertive and precise, not hedging."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.65,
            "max_tokens": 700
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
            keyBattleDrivers: apiResponse.keyBattle.drivers,
            keyBattleNarrative: apiResponse.keyBattle.narrative,
            strategyAngle: apiResponse.strategyAngle,
            reasoning: apiResponse.reasoning,
            flipScenario: apiResponse.flipScenario,
            confidenceLabel: context.confidenceLabel,
            chaosLabel: context.chaosLabel,
            weekendPhase: context.weekendPhase,
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
