import SwiftUI

struct PredictView: View {
    @State private var viewModel = PredictViewModel()
    @State private var apiKeyInput = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let race = viewModel.nextRace {
                        nextRaceHeader(race)
                        predictionBriefingCard(race)
                        contendersCard
                        weekendPlanCard(race)
                    }

                    predictButton

                    if let prediction = viewModel.prediction {
                        podiumCard(prediction)
                        reasoningCard(prediction)
                    }

                    if let error = viewModel.error {
                        ErrorCard(message: error) {
                            Task { await viewModel.predict() }
                        }
                    }
                }
                .padding()
            }
            .background(Color.f1Background)
            .navigationTitle("AI Predictor")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showAPIKeySheet = true
                    } label: {
                        Image(systemName: "key.fill")
                    }
                }
            }
            .sheet(isPresented: $viewModel.showAPIKeySheet) {
                apiKeySheet
            }
        }
        .task {
            await viewModel.loadNextRace()
        }
    }

    private func nextRaceHeader(_ race: Race) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("UPCOMING RACE")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.f1Red)
                Spacer()
                Text("Round \(race.round)")
                    .font(.caption)
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
                contextTile(title: "Date", value: race.formattedDate)
                contextTile(title: "Track", value: race.circuitInfo?.speedClass ?? "Unknown")
                contextTile(title: "Tyres", value: viewModel.pressureProfile.tyreStress)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func predictionBriefingCard(_ race: Race) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("RACE BRIEF", subtitle: "The predictor now explains the setup before asking for AI")

            Text(viewModel.projectedStoryline)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                insightPill(title: "Overtaking", value: viewModel.pressureProfile.overtaking)
                insightPill(title: "Qualifying", value: viewModel.pressureProfile.qualifyingImportance)
                insightPill(title: "Reliability", value: viewModel.pressureProfile.reliabilityRisk)
            }
        }
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var contendersCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("LEADING CONTENDERS", subtitle: "Standings + recent form, because black-box AI is lazy product")

            ForEach(Array(viewModel.favoriteDrivers.enumerated()), id: \.element.id) { index, driver in
                let trend = viewModel.trends.first(where: { $0.id == driver.id })
                HStack(spacing: 12) {
                    Text("P\(index + 1)")
                        .font(.caption)
                        .fontWeight(.bold)
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
                                .foregroundStyle(.secondary)
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
                .padding()
                .background(Color.f1SecondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func weekendPlanCard(_ race: Race) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("SESSION RADAR", subtitle: "Estimated weekend cadence so users can plan around the big moments")

            ForEach(race.weekendSessions) { session in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.label)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                        Text(session.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(session.relativeLabel.uppercased())
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(session.isUpcoming ? Color.f1Red : .secondary)
                        Text(session.timeLabel)
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
                }
                .padding()
                .background(Color.f1SecondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
                        Image(systemName: "sparkles")
                    }
                    Text(viewModel.isLoading ? "Analyzing context..." : "Generate AI Podium")
                        .fontWeight(.bold)
                }
                Text(viewModel.hasAPIKey ? "Uses standings, recent results and circuit profile." : "Add your OpenAI key once to unlock the prediction engine.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.f1Red)
        .disabled(viewModel.isLoading)
    }

    private func podiumCard(_ prediction: Prediction) -> some View {
        VStack(spacing: 16) {
            Text("PREDICTED PODIUM")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.f1Red)

            HStack(alignment: .bottom, spacing: 12) {
                podiumPlace(position: 2, name: prediction.second, height: 80)
                podiumPlace(position: 1, name: prediction.first, height: 110)
                podiumPlace(position: 3, name: prediction.third, height: 60)
            }
        }
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
            return LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
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
            Text("AI ANALYSIS")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.f1Red)

            Text(prediction.reasoning)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .transition(.opacity)
    }

    private func sectionHeader(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.f1Red)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func contextTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.f1SecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func insightPill(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.f1SecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var apiKeySheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "key.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.f1Red)

                Text("OpenAI API Key")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Enter your OpenAI API key to enable AI race predictions. Your key is stored locally on your device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                SecureField("sk-...", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button {
                    viewModel.saveAPIKey(apiKeyInput)
                    viewModel.showAPIKeySheet = false
                } label: {
                    Text("Save Key")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.f1Red)
                .disabled(apiKeyInput.isEmpty)

                Spacer()
            }
            .padding()
            .background(Color.f1Background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        viewModel.showAPIKeySheet = false
                    }
                }
            }
        }
    }
}

#Preview {
    PredictView()
        .preferredColorScheme(.dark)
}
