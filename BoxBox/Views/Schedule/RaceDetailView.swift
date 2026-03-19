import SwiftUI

struct RaceDetailView: View {
    @State private var viewModel: RaceDetailViewModel

    init(race: Race) {
        _viewModel = State(initialValue: RaceDetailViewModel(race: race))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                raceHeader
                circuitInfoCard
                if viewModel.race.isPast {
                    resultsSection
                } else {
                    countdownSection
                }
            }
            .padding()
        }
        .background(Color.f1Background)
        .navigationTitle(viewModel.race.raceName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadData()
        }
    }

    // MARK: - Header

    private var raceHeader: some View {
        VStack(spacing: 16) {
            Text("ROUND \(viewModel.race.round)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.f1Red)

            Text(viewModel.race.raceName)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Label(viewModel.race.circuitName, systemImage: "flag.checkered")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Label(viewModel.race.country, systemImage: "mappin")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Label(viewModel.race.formattedDate, systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if viewModel.race.isPast {
                Text("COMPLETED")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Circuit Info

    @ViewBuilder
    private var circuitInfoCard: some View {
        if let info = viewModel.race.circuitInfo {
            VStack(spacing: 12) {
                Text("CIRCUIT INFO")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.f1Red)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 0) {
                    circuitStat(icon: "road.lanes", label: "Laps", value: "\(info.laps)")
                    Divider().frame(height: 40).overlay(Color.f1SecondaryBackground)
                    circuitStat(icon: "ruler", label: "Length", value: info.formattedLength)
                    Divider().frame(height: 40).overlay(Color.f1SecondaryBackground)
                    circuitStat(icon: "mappin.circle", label: "City", value: info.city)
                }
            }
            .padding()
            .background(Color.f1CardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func circuitStat(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.f1Red)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Results

    private var resultsSection: some View {
        VStack(spacing: 12) {
            Text("TOP 10 RESULTS")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.f1Red)
                .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if let error = viewModel.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ForEach(viewModel.results.prefix(10)) { result in
                    resultRow(result)
                }
            }
        }
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func resultRow(_ result: RaceResult) -> some View {
        HStack(spacing: 12) {
            Text("\(result.position)")
                .font(.system(.title3, design: .rounded))
                .fontWeight(.black)
                .frame(width: 32)
                .foregroundStyle(positionColor(result.position))

            VStack(alignment: .leading, spacing: 2) {
                Text(result.driverName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(result.constructor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(result.points))")
                    .font(.headline)
                    .fontWeight(.bold)
                Text("pts")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if result.status != "Finished" && !result.status.starts(with: "+") {
                Image(systemName: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Countdown

    private var countdownSection: some View {
        VStack(spacing: 16) {
            Text("LIGHTS OUT IN")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.f1Red)

            Text(viewModel.countdown)
                .font(.system(.largeTitle, design: .rounded))
                .fontWeight(.black)
                .foregroundStyle(.white)

            Image(systemName: "flag.checkered")
                .font(.system(size: 48))
                .foregroundStyle(Color.f1Red.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal)
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func positionColor(_ position: Int) -> Color {
        switch position {
        case 1: return .yellow
        case 2: return Color.white.opacity(0.75)
        case 3: return Color(red: 0.8, green: 0.5, blue: 0.2)
        default: return .white
        }
    }
}

#Preview {
    NavigationStack {
        RaceDetailView(race: Race(
            id: "1",
            raceName: "Bahrain Grand Prix",
            circuitName: "Bahrain International Circuit",
            country: "Bahrain",
            date: "2025-03-02",
            round: 1
        ))
    }
    .preferredColorScheme(.dark)
}
