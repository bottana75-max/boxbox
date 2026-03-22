import SwiftUI

struct PredictView: View {
    @State private var viewModel = PredictViewModel()

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(spacing: F1Design.cardSpacing) {

                    if viewModel.isLoading && viewModel.nextRace == nil {
                        F1LoadingView(message: "Building your race brief")
                    } else if let race = viewModel.nextRace {
                        // 1. Hero
                        heroCard(race)
                        // 2. Track Profile
                        trackProfileCard(race)
                        // 3. Weekend Context
                        if let context = viewModel.weekendContext {
                            weatherContextCard(context)
                        }
                        // 4. Pace + Stints
                        paceAndStintsCard
                        // 4b. Tyre Strategy
                        tyreStrategyCard
                        // 5. Contenders
                        contendersCard
                        contenderComparisonCard
                        weekendScenarioMapCard
                        // 5. Confidence & Chaos
                        confidenceChaosCard
                    } else {
                        emptyStateCard
                    }

                    // Trial status
                    trialStatusBanner

                    // 7. CTA
                    raceCallButton

                    // 8. Structured Result
                    if let call = viewModel.raceCall {
                        resultLeadCard(call)
                        podiumCard(call)
                        resultSignalGrid(call)
                        weekendScenariosCard(call)
                        reasoningCard(call)
                        flipScenarioCard(call)
                    }

                    if let error = viewModel.error {
                        ErrorCard(message: error) {
                            Task { await viewModel.loadNextRace(forceRefresh: true) }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .background(Color.f1Background)
            .navigationTitle("Race Call")
            .sheet(isPresented: $viewModel.showPaywall) {
                PaywallView()
            }
            .refreshable {
                await viewModel.loadNextRace(forceRefresh: true)
            }
        }
        .task {
            await viewModel.loadNextRace()
        }
    }

    // MARK: - 1. Hero Card

    private func heroCard(_ race: Race) -> some View {
        VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
            HStack {
                F1SectionHeader(title: "RACE CALL")
                Spacer()
                phaseBadge
                Text("ROUND \(race.round)")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(race.raceName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("\(race.circuitName) · \(race.country)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(viewModel.projectedStoryline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(2)

            Text("Built from season form, circuit fit, weekend signals, and tyre shape — then sharpened into one decisive read.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineSpacing(2)

            HStack(spacing: 10) {
                F1MetricTile(title: "Date", value: race.formattedDate)
                F1MetricTile(title: "Track", value: race.circuitInfo?.speedClass ?? "TBD")
                F1MetricTile(title: "Tyres", value: viewModel.pressureProfile.tyreStress)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .f1Card(gradient: true, accent: .f1Red)
    }

    // MARK: - Phase Badge

    private var phaseBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: viewModel.weekendPhase.icon)
                .font(.system(size: 8))
            Text(viewModel.weekendPhase.shortLabel.uppercased())
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.5)
        }
        .foregroundStyle(phaseColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(phaseColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private var phaseColor: Color {
        switch viewModel.weekendPhase {
        case .baseline: return .secondary
        case .postPractice: return .yellow
        case .postQualifying: return .green
        case .raceReady: return Color.f1Red
        }
    }

    // MARK: - 2. Track Profile

    private func trackProfileCard(_ race: Race) -> some View {
        VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
            F1SectionHeader(title: "TRACK PROFILE", subtitle: "Circuit characteristics that shape the call")

            HStack(spacing: 10) {
                F1StatPill(title: "Overtaking", value: viewModel.pressureProfile.overtaking, style: .subtle)
                F1StatPill(title: "Qualifying", value: viewModel.pressureProfile.qualifyingImportance, style: .subtle)
                F1StatPill(title: "Reliability", value: viewModel.pressureProfile.reliabilityRisk, style: .subtle)
            }

            if let info = race.circuitInfo {
                HStack(spacing: 10) {
                    F1MetricTile(title: "Laps", value: "\(info.laps)")
                    F1MetricTile(title: "Length", value: String(format: "%.2f km", info.lengthKm))
                    F1MetricTile(title: "Turns", value: "\(info.turns)")
                }
            }
        }
        .f1Card()
    }

    // MARK: - 3. Weekend Context

    private func weatherContextCard(_ context: WeekendContext) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            F1SectionHeader(title: "WEEKEND CONTEXT", subtitle: "Estimated local timing and weather pressure")

            Text(context.localClockLabel)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            Text(context.sessionNarrative)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(2)

            HStack(spacing: 10) {
                F1StatPill(title: "Ambient", value: context.ambientTemperature)
                F1StatPill(title: "Track", value: context.trackTemperature)
                F1StatPill(title: "Rain", value: context.rainChance)
            }

            HStack(spacing: 10) {
                F1MetricTile(title: "Weather", value: context.weatherHeadline)
                F1MetricTile(title: "Risk", value: context.riskLabel)
                F1MetricTile(title: "Sunset", value: context.sunsetCue)
            }

            // Live weather overlay if available
            if let live = viewModel.liveWeather {
                liveWeatherRow(live)
            }

            Text("\(context.weatherDetail) \(context.windNote)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .f1Card()
    }

    private func liveWeatherRow(_ live: LiveWeatherContext) -> some View {
        HStack(spacing: 10) {
            if let airTemp = live.airTemp {
                F1MetricTile(title: "Live Air", value: String(format: "%.1f°C", airTemp))
            }
            if let trackTemp = live.trackTemp {
                F1MetricTile(title: "Live Track", value: String(format: "%.1f°C", trackTemp))
            }
            if let humidity = live.humidity {
                F1MetricTile(title: "Humidity", value: String(format: "%.0f%%", humidity))
            }
        }
    }

    // MARK: - 4. Pace + Stints

    private var paceAndStintsCard: some View {
        VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
            F1SectionHeader(title: "PACE & STINTS", subtitle: "Weekend read without overfitting the data")

            Text(viewModel.weekendPaceHeadline)
                .font(.subheadline)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 8) {
                insightRow(icon: "speedometer", title: "Long run bias", body: viewModel.longRunBias)
                insightRow(icon: "timer", title: "Opening stint", body: viewModel.firstStintShape)
                insightRow(icon: "square.grid.3x3.topleft.filled", title: "Grid pressure", body: viewModel.gridPressureNarrative)
            }
        }
        .f1Card()
    }

    private func insightRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.f1Red)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 5. Contenders with Scores

    private var contendersCard: some View {
        VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
            F1SectionHeader(title: "CONTENDERS", subtitle: contendersSubtitle)

            if viewModel.contenderProfiles.isEmpty {
                F1EmptyView(icon: "person.3.fill", title: "Standings are still loading", subtitle: "Pull to refresh and we'll rebuild the contender board.")
                    .f1InnerCard()
            } else {
                ForEach(Array(viewModel.contenderProfiles.prefix(5).enumerated()), id: \.element.driverCode) { index, contender in
                    HStack(spacing: 14) {
                        // Position
                        Text("\(index + 1)")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(index == 0 ? Color.f1Red : .secondary)
                            .frame(width: 28, alignment: .center)

                        // Team color bar
                        RoundedRectangle(cornerRadius: 2)
                            .fill(F1Design.teamColor(for: contender.team))
                            .frame(width: 3, height: 36)

                        // Driver info
                        VStack(alignment: .leading, spacing: 3) {
                            Text(contender.driverName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(contender.team)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        // Momentum badge only
                        Text(contender.momentumLabel)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(contender.momentumLabel.contains("↑") ? .green : contender.momentumLabel.contains("↓") ? .red : .secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.f1SecondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .f1Card()
    }

    private var contendersSubtitle: String {
        switch viewModel.weekendPhase {
        case .baseline: return "Ranked by form + track fit"
        case .postPractice: return "Ranked by form + track fit + practice pace"
        case .postQualifying, .raceReady: return "Ranked by form + track fit + weekend pace (grid set)"
        }
    }

    private var contenderComparisonCard: some View {
        VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
            F1SectionHeader(title: "WHY THE ORDER LOOKS LIKE THIS", subtitle: "Head-to-head gaps, not just ratings")

            ForEach(Array(viewModel.contenderComparisonBoard.enumerated()), id: \.offset) { _, comparison in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(comparison.leader) > \(comparison.challenger)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("+\(comparison.overallGap)")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.orange)
                    }

                    Text(comparison.leaderEdge)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(comparison.challengerPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(comparison.verdict)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .f1InnerCard()
            }
        }
        .f1Card()
    }

    private var weekendScenarioMapCard: some View {
        let scenarios = viewModel.weekendScenarioContext

        return VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
            F1SectionHeader(title: "SCENARIO MAP", subtitle: "How the weekend flips when one variable changes")

            scenarioInsightRow(icon: "flag.checkered", title: "If Saturday goes to plan", body: scenarios.poleConversion)
            scenarioInsightRow(icon: "arrow.down.right", title: "If the favourite misses the front row", body: scenarios.frontRowMiss)
            scenarioInsightRow(icon: "circle.lefthalf.filled", title: "If tyre stress spikes", body: scenarios.tyreStressSwing)
            scenarioInsightRow(icon: "cloud.rain", title: "If weather cuts across the race", body: scenarios.weatherSwing)
            scenarioInsightRow(icon: "shuffle", title: "If strategy gets messy", body: scenarios.strategyVolatility)
            scenarioInsightRow(icon: "car.rear.waves.up", title: "If a safety car lands in-window", body: scenarios.safetyCarWindow)
        }
        .f1Card()
    }

    private func scenarioInsightRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.f1Red)
                .frame(width: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .f1InnerCard()
    }

    private func scorePill(label: String, value: Int) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(scoreColor(value))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.f1SecondaryBackground)
        .clipShape(Capsule())
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 75...100: return .green
        case 50..<75: return .yellow
        case 25..<50: return .orange
        default: return .red
        }
    }

    // MARK: - 4b. Tyre Strategy

    private var tyreStrategyCard: some View {
        VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
            F1SectionHeader(title: "TYRE STRATEGY", subtitle: "Degradation, compounds, and pit windows")

            let ctx = viewModel.tyreStrategyContext

            HStack(spacing: 10) {
                F1StatPill(title: "Stints", value: "\(ctx.expectedStints)-stop", style: .subtle)
                F1StatPill(title: "Deg", value: ctx.degradationSeverity, style: .subtle)
                F1StatPill(title: "Undercut", value: ctx.undercutPotency, style: .subtle)
            }

            HStack(spacing: 10) {
                F1MetricTile(title: "Compounds", value: ctx.likelyCompounds)
                F1MetricTile(title: "Safety Car", value: ctx.safetyCarLikelihood)
            }

            insightRow(icon: "circle.circle", title: "Pit window", body: ctx.pitWindowNarrative)

            if ctx.overcutViable {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("Overcut is viable at this circuit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .f1Card()
    }

    // MARK: - 5. Confidence & Chaos

    private var confidenceChaosCard: some View {
        VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
            F1SectionHeader(title: "CALL CONFIDENCE", subtitle: "How predictable is this race?")

            HStack(spacing: 10) {
                VStack(spacing: 4) {
                    Text("\(viewModel.confidenceRawScore)")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(confidenceScoreColor)
                    Text("/ 10")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("Confidence")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color.f1SecondaryBackground)
                    .frame(width: 1, height: 50)

                VStack(spacing: 4) {
                    Text("\(viewModel.chaosRawScore)")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(chaosScoreColor)
                    Text("/ 10")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("Chaos")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 10) {
                F1StatPill(title: "Confidence", value: viewModel.confidenceLabel)
                F1StatPill(title: "Chaos Potential", value: viewModel.chaosLabel)
            }
        }
        .f1Card()
    }

    private var confidenceScoreColor: Color {
        switch viewModel.confidenceRawScore {
        case 8...10: return .green
        case 5...7: return .yellow
        default: return .orange
        }
    }

    private var chaosScoreColor: Color {
        switch viewModel.chaosRawScore {
        case 0...2: return .green
        case 3...4: return .yellow
        case 5...7: return .orange
        default: return .red
        }
    }

    // MARK: - 6. Session Radar

    private func weekendPlanCard(_ race: Race) -> some View {
        VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
            F1SectionHeader(title: "SESSION RADAR", subtitle: "Weekend cadence and timing")

            if race.weekendSessions.isEmpty {
                F1EmptyView(icon: "calendar", title: "Session times not ready", subtitle: "We'll populate the weekend plan when timing lands.")
                    .f1InnerCard()
            } else {
                ForEach(race.weekendSessions) { session in
                    F1WeekendSessionRow(session: session)
                }
            }
        }
        .f1Card()
    }

    // MARK: - 7. CTA Button

    private var raceCallButton: some View {
        VStack(alignment: .leading, spacing: 12) {
            F1SectionHeader(title: "GENERATE THE CALL", subtitle: "One premium race brief per tap. Credits and Pro unlock stay unchanged.")

            Button {
                Task { await viewModel.predict() }
            } label: {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: buttonIcon)
                        }
                        Text(viewModel.predictButtonTitle)
                            .fontWeight(.bold)
                    }
                    Text(viewModel.predictButtonSubtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.f1Red)
            .disabled(viewModel.isLoading)
            .controlSize(.large)
        }
        .f1Card(accent: .f1Red)
    }

    private var buttonIcon: String {
        if viewModel.nextRace == nil { return "calendar.badge.exclamationmark" }
        if viewModel.raceCallState?.source == .cacheExact { return "internaldrive" }
        return viewModel.storeKit.canPredict ? "flag.checkered" : "lock.fill"
    }

    private func cacheBadgeColor(for state: RaceCallPresentationState) -> Color {
        switch state.source {
        case .live: return .green
        case .cacheExact: return .blue
        case .cacheOutdated: return .yellow
        }
    }

    // MARK: - 8. Structured Result Cards

    private func resultLeadCard(_ call: RaceCall) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                F1SectionHeader(title: "THE RACE CALL", subtitle: "A finished race brief — tight, specific, and ready before lights out.")
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Text(call.weekendPhase.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Capsule())

                    if let state = viewModel.raceCallState {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(state.badgeTitle.uppercased())
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(0.6)
                                .foregroundStyle(cacheBadgeColor(for: state))
                            Text(state.subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }

            Text(call.winnerEdge)
                .font(.headline)
                .foregroundStyle(.white)
                .lineSpacing(3)

            HStack(spacing: 10) {
                F1StatPill(title: "Winner", value: call.first)
                F1StatPill(title: "Confidence", value: "\(call.confidenceScore)/10 · \(call.confidenceLabel)")
                F1StatPill(title: "Chaos", value: "\(call.chaosScore)/10 · \(call.chaosLabel)")
            }
        }
        .f1Card(gradient: true, accent: .f1Red)
        .transition(.opacity)
    }

    private func podiumCard(_ call: RaceCall) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            F1SectionHeader(title: "PROJECTED PODIUM", subtitle: "The headline order, stripped of noise.")

            HStack(alignment: .bottom, spacing: 12) {
                podiumPlace(position: 2, name: call.second, height: 84)
                podiumPlace(position: 1, name: call.first, height: 118)
                podiumPlace(position: 3, name: call.third, height: 68)
            }
        }
        .f1Card(accent: .f1Red)
        .transition(.scale.combined(with: .opacity))
    }

    private func podiumPlace(position: Int, name: String, height: CGFloat) -> some View {
        VStack(spacing: 10) {
            VStack(spacing: 3) {
                Text(name.components(separatedBy: " ").last ?? name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(positionLabel(position))
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(podiumGradient(for: position))
                    .frame(height: height)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    }

                Text("P\(position)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func podiumGradient(for position: Int) -> LinearGradient {
        switch position {
        case 1:
            return LinearGradient(colors: [Color(red: 1, green: 0.84, blue: 0), .orange], startPoint: .top, endPoint: .bottom)
        case 2:
            return LinearGradient(colors: [Color(white: 0.7), Color(white: 0.5)], startPoint: .top, endPoint: .bottom)
        case 3:
            return LinearGradient(colors: [Color(red: 0.8, green: 0.5, blue: 0.2), Color(red: 0.6, green: 0.3, blue: 0.1)], startPoint: .top, endPoint: .bottom)
        default:
            return LinearGradient(colors: [.gray], startPoint: .top, endPoint: .bottom)
        }
    }

    private func winnerEdgeCard(_ call: RaceCall) -> some View {
        editorialSignalCard(
            title: "Winner's Edge",
            subtitle: "The single lever that decides P1.",
            icon: "target",
            iconColor: .orange,
            accent: .orange,
            body: call.winnerEdge
        )
    }

    private func weekendScenariosCard(_ call: RaceCall) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            F1SectionHeader(title: "WEEKEND SCENARIOS", subtitle: "Three specific ways this race can break")

            ForEach(Array(call.weekendScenarios.enumerated()), id: \.offset) { index, scenario in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Scenario \(index + 1)")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(scenario.likelihood.uppercased())
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.5)
                            .foregroundStyle(.orange)
                    }
                    Text(scenario.trigger)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                    Text(scenario.outcome)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
                .f1InnerCard()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .f1Card()
        .transition(.opacity)
    }

    // MARK: - Key Battle (NEW V2.1)

    private func keyBattleCard(_ call: RaceCall) -> some View {
        editorialSignalCard(
            title: "Key Battle",
            subtitle: call.keyBattleDrivers.joined(separator: " vs "),
            icon: "bolt.fill",
            iconColor: .cyan,
            accent: .cyan,
            body: call.keyBattleNarrative
        )
    }

    // MARK: - Strategy Angle (NEW V2.1)

    private func strategyAngleCard(_ call: RaceCall) -> some View {
        editorialSignalCard(
            title: "Strategy Angle",
            subtitle: "The move that shapes the race from the pit wall.",
            icon: "gearshape.2.fill",
            iconColor: .mint,
            accent: .mint,
            body: call.strategyAngle
        )
    }

    // MARK: - Tyre Call (NEW V2.2)

    private func tyreCallCard(_ call: RaceCall) -> some View {
        editorialSignalCard(
            title: "Tyre Call",
            subtitle: "The compound decision with the biggest swing.",
            icon: "circle.circle.fill",
            iconColor: .red,
            accent: .red,
            body: call.tyreCall
        )
    }

    // MARK: - Pit Wall Note (NEW V2.2)

    private func pitWallNoteCard(_ call: RaceCall) -> some View {
        editorialSignalCard(
            title: "Pit Wall Note",
            subtitle: "The kind of detail you'd hear in the headset, not on the broadcast.",
            icon: "antenna.radiowaves.left.and.right",
            iconColor: .purple,
            accent: .purple,
            body: call.pitWallNote
        )
    }

    private func darkHorseCard(_ call: RaceCall) -> some View {
        editorialDriverCard(
            title: "Dark Horse",
            subtitle: "The outside bet with a real route into the fight.",
            icon: "eye.fill",
            iconColor: .yellow,
            accent: .yellow,
            driver: call.darkHorse,
            body: call.darkHorseWhy
        )
    }

    private func biggestRiskCard(_ call: RaceCall) -> some View {
        editorialDriverCard(
            title: "Biggest Risk",
            subtitle: "The pick most likely to slip off-script.",
            icon: "exclamationmark.triangle.fill",
            iconColor: .orange,
            accent: .orange,
            driver: call.biggestRisk,
            body: call.biggestRiskWhy
        )
    }

    private func reasoningCard(_ call: RaceCall) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            F1SectionHeader(title: "STRATEGIST'S READ", subtitle: "The full case behind the podium order.")

            Text(call.reasoning)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(5)

            HStack(spacing: 10) {
                F1StatPill(title: "Confidence", value: "\(call.confidenceLabel) (\(call.confidenceScore)/10)")
                F1StatPill(title: "Chaos", value: "\(call.chaosLabel) (\(call.chaosScore)/10)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .f1Card()
        .transition(.opacity)
    }

    private func flipScenarioCard(_ call: RaceCall) -> some View {
        editorialSignalCard(
            title: "Flip Scenario",
            subtitle: "The cleanest way the whole brief gets rewritten mid-race.",
            icon: "arrow.triangle.2.circlepath",
            iconColor: Color.f1Red,
            accent: Color.f1Red,
            body: call.flipScenario
        )
    }

    private func resultSignalGrid(_ call: RaceCall) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            F1SectionHeader(title: "KEY SIGNALS", subtitle: "Six sharp reads that make the brief feel complete.")

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                winnerEdgeCard(call)
                keyBattleCard(call)
                strategyAngleCard(call)
                tyreCallCard(call)
                pitWallNoteCard(call)
                darkHorseCard(call)
                biggestRiskCard(call)
            }
        }
    }

    private func editorialSignalCard(title: String, subtitle: String, icon: String, iconColor: Color, accent: Color, body: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 28, height: 28)
                    .background(iconColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.7)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .f1Card(accent: accent)
        .transition(.opacity)
    }

    private func editorialDriverCard(title: String, subtitle: String, icon: String, iconColor: Color, accent: Color, driver: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 28, height: 28)
                    .background(iconColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.7)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(driver)
                .font(.headline)
                .foregroundStyle(.white)

            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .f1Card(accent: accent)
        .transition(.opacity)
    }

    private func positionLabel(_ position: Int) -> String {
        switch position {
        case 1: return "Projected winner"
        case 2: return "Best shot at P2"
        case 3: return "Final podium slot"
        default: return "Projected finish"
        }
    }

    // MARK: - Trial Status

    private var trialStatusBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: viewModel.storeKit.canPredict ? "flag.checkered" : "lock.fill")
                    .foregroundStyle(Color.f1Red)
                Text(viewModel.trialStatusText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                Spacer()
                if viewModel.storeKit.credits == 0 {
                    Button("Upgrade") {
                        viewModel.showPaywall = true
                    }
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.f1Red)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(progressText.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.f1SecondaryBackground)
                        Capsule()
                            .fill(Color.f1Red)
                            .frame(width: geometry.size.width * progressValue)
                    }
                }
                .frame(height: 8)
            }
        }
        .f1Card()
    }

    private var progressText: String {
        let used = viewModel.storeKit.credits <= 0 ? 1 : 0
        return "Free trial used: \(used)/1"
    }

    private var progressValue: CGFloat {
        return viewModel.storeKit.credits <= 0 ? 1.0 : 0.0
    }

    // MARK: - Empty State

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
            F1SectionHeader(title: "RACE CALL", subtitle: "No race loaded yet")

            F1EmptyView(
                icon: "flag.checkered",
                title: "Waiting for the next grand prix",
                subtitle: "Pull to refresh once the next race weekend is available and RaceCall will rebuild the briefing automatically."
            )
            .frame(minHeight: 120)
        }
        .f1Card(gradient: true)
    }
}

#Preview {
    PredictView()
        .preferredColorScheme(.dark)
}
