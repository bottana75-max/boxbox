import SwiftUI

struct StandingsView: View {
    @State private var viewModel = StandingsViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Standings", selection: $viewModel.selectedTab) {
                    Text("Drivers").tag(0)
                    Text("Constructors").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 12)

                if viewModel.isLoading {
                    Spacer()
                    F1LoadingView(message: "Loading...")
                    Spacer()
                } else if let error = viewModel.error {
                    Spacer()
                    ErrorCard(message: error) {
                        Task { await viewModel.loadData() }
                    }
                    .padding()
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: F1Design.cardSpacing) {
                            summaryCard

                            VStack(spacing: 12) {
                                if viewModel.selectedTab == 0 {
                                    ForEach(viewModel.driverStandings) { standing in
                                        NavigationLink(value: Driver.fallback(driverCode: standing.driverCode, driverName: standing.driverName, teamName: standing.constructorName)) {
                                            driverStandingRow(standing)
                                                .f1Card(accent: standing.position <= 3 ? F1Design.positionColor(standing.position) : nil)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                } else {
                                    ForEach(viewModel.constructorStandings) { constructor in
                                        constructorStandingRow(constructor)
                                            .f1Card(accent: constructor.position <= 3 ? F1Design.positionColor(constructor.position) : F1Design.teamColor(for: constructor.name).opacity(0.8))
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .navigationDestination(for: Driver.self) { driver in
                        DriverDetailView(driver: driver)
                    }
                }
            }
            .background(Color.f1Background)
            .navigationTitle("Standings")
            .refreshable {
                await viewModel.loadData()
            }
        }
        .task {
            await viewModel.loadData()
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
            F1SectionHeader(
                title: viewModel.selectedTab == 0 ? "DRIVER TITLE RACE" : "CONSTRUCTOR BATTLE",
                subtitle: viewModel.selectedTab == 0 ? "Clean hierarchy for every points swing" : "Team momentum, wins and total points"
            )

            if viewModel.selectedTab == 0, let leader = viewModel.driverStandings.first {
                HStack(spacing: 10) {
                    F1MetricTile(title: "Leader", value: leader.driverCode)
                    F1MetricTile(title: "Points", value: leader.points.cleanNumber)
                    F1MetricTile(title: "Wins", value: "\(leader.wins)")
                }
            } else if let leader = viewModel.constructorStandings.first {
                HStack(spacing: 10) {
                    F1MetricTile(title: "Leader", value: leader.name)
                    F1MetricTile(title: "Points", value: leader.points.cleanNumber)
                    F1MetricTile(title: "Wins", value: "\(leader.wins)")
                }
            }
        }
        .f1Card(gradient: true, accent: .f1Red)
    }

    private func driverStandingRow(_ standing: DriverStanding) -> some View {
        F1ListRow(accent: standing.position <= 3 ? F1Design.positionColor(standing.position) : F1Design.teamColor(for: standing.constructorName).opacity(0.7)) {
            HStack(spacing: 12) {
                Text("\(standing.position)")
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.black)
                    .frame(width: 36)
                    .foregroundStyle(standing.position <= 3 ? F1Design.positionColor(standing.position) : .white)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(standing.driverName)
                            .font(.headline)
                            .foregroundStyle(.white)
                        F1TeamDot(teamName: standing.constructorName)
                    }
                    Text(standing.constructorName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(standing.points.cleanNumber)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    Text("pts · \(standing.wins) wins")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                F1Chevron()
            }
        }
    }

    private func constructorStandingRow(_ constructor: Constructor) -> some View {
        F1ListRow(accent: F1Design.teamColor(for: constructor.name)) {
            HStack(spacing: 12) {
                Text("\(constructor.position)")
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.black)
                    .frame(width: 36)
                    .foregroundStyle(constructor.position <= 3 ? F1Design.positionColor(constructor.position) : .white)

                VStack(alignment: .leading, spacing: 4) {
                    Text(constructor.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("\(constructor.wins) wins this season")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(constructor.points.cleanNumber)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    Text("pts")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    StandingsView()
        .preferredColorScheme(.dark)
}
