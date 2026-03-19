import SwiftUI

struct PredictView: View {
    @State private var viewModel = PredictViewModel()
    

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: F1Design.cardSpacing) {
                    if viewModel.isLoading && viewModel.nextRace == nil {
                        F1LoadingView(message: "Loading prediction desk")
                    } else if let race = viewModel.nextRace {
                        nextRaceHeader(race)
                        predictionBriefingCard(race)
                        if let context = viewModel.weekendContext {
                            weatherContextCard(context)
                        }
                        contendersCard
                        weekendPlanCard(race)
                    } else {
                        emptyStateCard
                    }

                    trialStatusBanner
                    predictButton

                    if let prediction = viewModel.prediction {
                        podiumCard(prediction)
                        reasoningCard(prediction)
                    }

                    if let error = viewModel.error {
                        ErrorCard(message: error) {
                            Task { await viewModel.loadNextRace(forceRefresh: true) }
                        }
                    }
                }
                .padding()
            }
            .background(Color.f1Background)
            .navigationTitle("AI Predictor")
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

    private func nextRaceHeader(_ race: Race) -> some View {
        VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
            HStack {
                F1SectionHeader(title: "UPCOMING RACE")
                Spacer()
                Text("Round \(race.round)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }

            Text(race.raceName)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Text("\(race.circuitName) · \(race.country)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                F1MetricTile(title: "Date", value: race.formattedDate)
                F1MetricTile(title: "Track", value: race.circuitInfo?.speedClass ?? "TBD")
                F1MetricTile(title: "Tyres", value: viewModel.pressureProfile.tyreStress)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .f1Card()
    }

    private func predictionBriefingCard(_ race: Race) -> some View {
        VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
            F1SectionHeader(title: "RACE BRIEF", subtitle: "Circuit context for the AI prediction engine")

            Text(viewModel.projectedStoryline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(2)

            HStack(spacing: 10) {
                F1StatPill(title: "Overtaking", value: viewModel.pressureProfile.overtaking, style: .subtle)
                F1StatPill(title: "Qualifying", value: viewModel.pressureProfile.qualifyingImportance, style: .subtle)
                F1StatPill(title: "Reliability", value: viewModel.pressureProfile.reliabilityRisk, style: .subtle)
            }
        }
        .f1Card()
    }

    private func weatherContextCard(_ context: WeekendContext) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            F1SectionHeader(title: "WEEKEND CONTEXT", subtitle: "Estimated local timing + realistic weather pressure")

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

            Text("\(context.weatherDetail) \(context.windNote)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .f1Card()
    }

    private var contendersCard: some View {
        VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
            F1SectionHeader(title: "LEADING CONTENDERS", subtitle: "Standings + recent form feed the prediction model")

            if viewModel.favoriteDrivers.isEmpty {
                F1EmptyView(icon: "person.3.fill", title: "Standings are still loading", subtitle: "Pull to refresh and we’ll rebuild the contender board.")
                    .f1InnerCard()
            } else {
                ForEach(Array(viewModel.favoriteDrivers.enumerated()), id: \.element.id) { index, driver in
                    let trend = viewModel.trends.first(where: { $0.id == driver.id })
                    HStack(spacing: 12) {
                        Text("P\(index + 1)")
                            .font(.caption)
                            .fontWeight(.heavy)
                            .foregroundStyle(Color.f1Red)
                            .frame(width: 30)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(driver.driverName)
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text(driver.constructorName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let trend {
                                Text("\(trend.recentSummary) · \(trend.momentumLabel)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(driver.points.cleanNumber)")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                            Text("pts")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .f1InnerCard()
                }
            }
        }
        .f1Card()
    }

    private func weekendPlanCard(_ race: Race) -> some View {
        VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
            F1SectionHeader(title: "SESSION RADAR", subtitle: "Weekend cadence and timing")

            if race.weekendSessions.isEmpty {
                F1EmptyView(icon: "calendar", title: "Session times not ready", subtitle: "We’ll populate the weekend plan when the next race timing lands.")
                    .f1InnerCard()
            } else {
                ForEach(race.weekendSessions) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.label)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                            Text(session.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(session.relativeLabel.uppercased())
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(0.4)
                                .foregroundStyle(session.isUpcoming ? Color.f1Red : .secondary)
                            Text(session.timeLabel)
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                    }
                    .f1InnerCard()
                }
            }
        }
        .f1Card()
    }

    private var predictButton: some View {
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
    }

    private var buttonIcon: String {
        if viewModel.nextRace == nil { return "calendar.badge.exclamationmark" }
        return viewModel.storeKit.canPredict ? "sparkles" : "lock.fill"
    }

    private func podiumCard(_ prediction: Prediction) -> some View {
        VStack(spacing: 16) {
            F1SectionHeader(title: "PREDICTED PODIUM")
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .bottom, spacing: 12) {
                podiumPlace(position: 2, name: prediction.second, height: 80)
                podiumPlace(position: 1, name: prediction.first, height: 110)
                podiumPlace(position: 3, name: prediction.third, height: 60)
            }
        }
        .f1Card()
        .transition(.scale.combined(with: .opacity))
    }

    private func podiumPlace(position: Int, name: String, height: CGFloat) -> some View {
        VStack(spacing: 8) {
            Text(name.components(separatedBy: " ").last ?? name)
                .font(.caption)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(podiumGradient(for: position))
                    .frame(height: height)

                Text("\(position)")
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.black)
                    .foregroundStyle(.white)
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

    private func reasoningCard(_ prediction: Prediction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            F1SectionHeader(title: "AI ANALYSIS")

            Text(prediction.reasoning)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .f1Card()
        .transition(.opacity)
    }

    private var trialStatusBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: viewModel.storeKit.isUnlimited ? "checkmark.seal.fill" : "sparkles")
                    .foregroundStyle(Color.f1Red)
                Text(viewModel.trialStatusText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                Spacer()
                if !viewModel.storeKit.isUnlimited && viewModel.storeKit.credits == 0 {
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
        if viewModel.storeKit.isUnlimited { return "Pro unlocked" }
        let used = max(0, 3 - viewModel.storeKit.credits)
        return "Free trial used: \(used)/3"
    }

    private var progressValue: CGFloat {
        if viewModel.storeKit.isUnlimited { return 1 }
        let used = max(0, min(3, 3 - viewModel.storeKit.credits))
        return CGFloat(Double(used) / 3.0)
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
            F1SectionHeader(title: "PREDICTION DESK", subtitle: "No race loaded yet")

            F1EmptyView(
                icon: "sparkles.rectangle.stack",
                title: "Waiting for the next grand prix",
                subtitle: "Pull to refresh once the next race weekend is available and BoxBox will rebuild the briefing automatically."
            )
            .frame(minHeight: 120)
        }
        .f1Card()
    }

}

#Preview {
    PredictView()
        .preferredColorScheme(.dark)
}
