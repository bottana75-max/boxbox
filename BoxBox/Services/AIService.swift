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
        You are a senior Formula 1 race strategist on the pit wall. This is a premium race call briefing for a paying audience that expects precision, not punditry.

        CONTEXT:
        \(contextString)

        \(phaseInstructions)

        ANALYSIS RULES:
        1. Weigh each contender's overallRating, formScore, trackFitScore, and weekendPaceScore. Cite specific numbers.
        2. Use sessionContext to understand how much real weekend running is available; do not pretend you have data the phase does not support.
        3. Use weekendPace.tyreStrategy heavily: reference expectedStints, degradationSeverity, likelyCompounds, undercutPotency, safetyCarLikelihood, and pitWindowNarrative in your analysis.
        4. If gridPosition is available, factor it heavily — especially when qualifyingImportance is "Massive" or circuit overtaking is "Track position". Cross-reference grid vs overallRating to identify over/under-performers.
        5. Factor circuit profile: overtaking difficulty, tyre stress, reliability risk. Connect these to specific contenders.
        6. Factor weather: use both the seasonal profile AND liveWeather if present. If rainfall is true, consider wet-weather specialists and tyre crossover windows.
        7. Confidence score is \(context.confidenceScore)/10 (\(context.confidenceLabel)), chaos score is \(context.chaosScore)/10 (\(context.chaosLabel)). High chaos = hedge more, flag safety car scenarios. High confidence = be more assertive.
        8. Pick a dark horse — someone outside the obvious top 3 who could surprise. Cite a SPECIFIC data signal (score, grid, trend, circuit fit).
        9. Identify the biggest risk — a contender who could underperform. Tie it to a concrete vulnerability (tyre deg weakness, poor grid, reliability history).
        10. Identify the key battle — two drivers likely to fight directly, based on proximity in ratings, grid, or pit window overlap.
        11. Strategy angle: one tactical insight referencing a specific stint, compound, undercut/overcut, or weather timing.
        12. Tyre call: one sentence on the tyre decision that will define the race outcome — which compound choice or stint length separates the winner from the rest.
        13. Pit wall note: one sentence of insider-level tactical nuance — the kind of thing a race engineer would radio to their driver. Think specific, actionable, and non-obvious.
        14. Write reasoning that reads like a pit wall debrief: assertive, data-driven, referencing specific scores, positions, and circuit factors. 4-5 sentences.
        15. Flip scenario: specific and plausible, referencing a concrete event (safety car at lap X, rain at stint 2, specific driver DNF).

        TONE RULES:
        - Write like a race engineer, not a commentator. Be direct and assertive.
        - Never say "could" when you mean "will likely". Never hedge with "might" or "perhaps".
        - Every claim must reference a data point: a score, a position, a circuit characteristic, or a weather condition.
        - No filler phrases. No "it will be interesting to see". No "anything can happen".

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
            "tyreCall": "One sentence on the defining tyre decision — compound choice or stint length",
            "pitWallNote": "One sentence of insider-level tactical nuance a race engineer would radio",
            "reasoning": "4-5 sentences of pit-wall-grade analysis referencing specific scores, grid positions, and data",
            "flipScenario": "One specific, plausible event referencing a concrete trigger"
        }
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "You are a senior F1 race strategist on the pit wall. Respond with valid JSON only. Use the driver data, scores, tyre strategy, and grid positions provided — never hallucinate stats. Reference specific numbers. Be assertive and precise like a race engineer, never hedging. Every output field must contain actionable, data-grounded content."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.6,
            "max_tokens": 900
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
            tyreCall: apiResponse.tyreCall,
            pitWallNote: apiResponse.pitWallNote,
            reasoning: apiResponse.reasoning,
            flipScenario: apiResponse.flipScenario,
            confidenceLabel: context.confidenceLabel,
            chaosLabel: context.chaosLabel,
            confidenceScore: context.confidenceScore,
            chaosScore: context.chaosScore,
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
