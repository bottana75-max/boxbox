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
                .padding()

                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
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
                                driverStandingRow(standing)
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
                }
            }
            .background(Color.f1Background)
            .navigationTitle("Standings")
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
                .foregroundStyle(standing.position <= 3 ? Color.f1Red : .white)

            teamColorDot(for: standing.constructorName)

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
                .foregroundStyle(constructor.position <= 3 ? Color.f1Red : .white)

            teamColorDot(for: constructor.name)

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

    private func teamColorDot(for teamName: String) -> some View {
        Circle()
            .fill(teamColor(for: teamName))
            .frame(width: 8, height: 8)
    }

    private func teamColor(for teamName: String) -> Color {
        let name = teamName.lowercased()
        if name.contains("red bull") { return Color(hex: "3671C6") }
        if name.contains("ferrari") { return Color(hex: "E8002D") }
        if name.contains("mercedes") { return Color(hex: "27F4D2") }
        if name.contains("mclaren") { return Color(hex: "FF8000") }
        if name.contains("aston") { return Color(hex: "229971") }
        if name.contains("alpine") { return Color(hex: "FF87BC") }
        if name.contains("williams") { return Color(hex: "64C4FF") }
        if name.contains("rb") || name.contains("alpha") { return Color(hex: "6692FF") }
        if name.contains("sauber") || name.contains("stake") { return Color(hex: "52E252") }
        if name.contains("haas") { return Color(hex: "B6BABD") }
        return .gray
    }
}

#Preview {
    StandingsView()
        .preferredColorScheme(.dark)
}
