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
                .padding(.vertical, 12)

                if viewModel.isLoading {
                    Spacer()
                    F1LoadingView(message: "Fetching standings")
                    Spacer()
                } else if let error = viewModel.error {
                    Spacer()
                    ErrorCard(message: error) {
                        Task { await viewModel.loadData() }
                    }
                    .padding()
                    Spacer()
                } else {
                    List {
                        if viewModel.selectedTab == 0 {
                            ForEach(viewModel.driverStandings) { standing in
                                NavigationLink(value: Driver.fallback(driverCode: standing.driverCode, driverName: standing.driverName, teamName: standing.constructorName)) {
                                    driverStandingRow(standing)
                                }
                                .listRowBackground(Color.f1CardBackground)
                            }
                        } else {
                            ForEach(viewModel.constructorStandings) { constructor in
                                constructorStandingRow(constructor)
                                    .listRowBackground(Color.f1CardBackground)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
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

    private func driverStandingRow(_ standing: DriverStanding) -> some View {
        HStack(spacing: 12) {
            Text("\(standing.position)")
                .font(.system(.title2, design: .rounded))
                .fontWeight(.black)
                .frame(width: 36)
                .foregroundStyle(standing.position <= 3 ? F1Design.positionColor(standing.position) : .white)

            F1TeamDot(teamName: standing.constructorName)

            VStack(alignment: .leading, spacing: 2) {
                Text(standing.driverName)
                    .font(.headline)
                Text(standing.constructorName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(standing.points))")
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                Text("pts")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func constructorStandingRow(_ constructor: Constructor) -> some View {
        HStack(spacing: 12) {
            Text("\(constructor.position)")
                .font(.system(.title2, design: .rounded))
                .fontWeight(.black)
                .frame(width: 36)
                .foregroundStyle(constructor.position <= 3 ? F1Design.positionColor(constructor.position) : .white)

            F1TeamDot(teamName: constructor.name)

            VStack(alignment: .leading, spacing: 2) {
                Text(constructor.name)
                    .font(.headline)
                Text("\(constructor.wins) wins")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(constructor.points))")
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                Text("pts")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    StandingsView()
        .preferredColorScheme(.dark)
}
