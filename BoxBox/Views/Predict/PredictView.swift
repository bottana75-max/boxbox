import SwiftUI

struct PredictView: View {
    @State private var viewModel = PredictViewModel()
    @State private var apiKeyInput = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let race = viewModel.nextRace {
                        nextRaceHeader(race)
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
        VStack(spacing: 8) {
            Text("UPCOMING RACE")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.f1Red)
            Text(race.raceName)
                .font(.title2)
                .fontWeight(.bold)
            Text(race.circuitName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(race.formattedDate)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var predictButton: some View {
        Button {
            Task { await viewModel.predict() }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(viewModel.isLoading ? "Analyzing..." : "Predict Next Race")
                    .fontWeight(.bold)
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
                // P2
                podiumPlace(position: 2, name: prediction.second, height: 80)
                // P1
                podiumPlace(position: 1, name: prediction.first, height: 110)
                // P3
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
