import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if let error = viewModel.error {
                        ErrorCard(message: error) {
                            Task { await viewModel.loadData() }
                        }
                    } else {
                        nextRaceCard
                        lastRaceCard
                        championshipLeaderCard
                    }
                }
                .padding()
            }
            .background(Color.f1Background)
            .navigationTitle("BoxBox")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task {
            await viewModel.loadData()
        }
    }

    @ViewBuilder
    private var nextRaceCard: some View {
        if let race = viewModel.nextRace {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("NEXT RACE")
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

                Text(race.circuitName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(Color.f1Red)
                    Text(race.country)
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "calendar")
                        .foregroundStyle(Color.f1Red)
                    Text(race.formattedDate)
                        .font(.subheadline)
                }

                if !viewModel.countdown.isEmpty {
                    HStack {
                        Spacer()
                        Text(viewModel.countdown)
                            .font(.system(.title, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(Color.f1Red)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
            .padding()
            .background(Color.f1CardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private var lastRaceCard: some View {
        if let race = viewModel.lastRace, !viewModel.lastRaceResults.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("LAST RACE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.f1Red)
                    Spacer()
                    Text(race.raceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(viewModel.lastRaceResults) { result in
                    HStack(spacing: 12) {
                        Text("\(result.position)")
                            .font(.system(.title, design: .rounded))
                            .fontWeight(.black)
                            .foregroundStyle(podiumColor(for: result.position))
                            .frame(width: 40)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.driverName)
                                .font(.headline)
                            Text(result.constructor)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("\(Int(result.points)) pts")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
            .background(Color.f1CardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private var championshipLeaderCard: some View {
        if let leader = viewModel.championshipLeader {
            VStack(alignment: .leading, spacing: 12) {
                Text("CHAMPIONSHIP LEADER")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.f1Red)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(leader.driverName)
                            .font(.title3)
                            .fontWeight(.bold)
                        Text(leader.constructorName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(Int(leader.points))")
                            .font(.system(.largeTitle, design: .rounded))
                            .fontWeight(.black)
                            .foregroundStyle(Color.f1Red)
                        Text("points")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Label("\(leader.wins) wins", systemImage: "trophy.fill")
                        .font(.subheadline)
                        .foregroundStyle(.yellow)
                }
            }
            .padding()
            .background(Color.f1CardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func podiumColor(for position: Int) -> Color {
        switch position {
        case 1: return .yellow
        case 2: return Color(white: 0.75)
        case 3: return Color(red: 0.8, green: 0.5, blue: 0.2)
        default: return .white
        }
    }
}

struct ErrorCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.yellow)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(Color.f1Red)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    HomeView()
        .preferredColorScheme(.dark)
}
