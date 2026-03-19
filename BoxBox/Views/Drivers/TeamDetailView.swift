import SwiftUI

struct TeamDetailView: View {
    @State private var viewModel: TeamDetailViewModel

    init(teamName: String, teamColour: String) {
        _viewModel = State(initialValue: TeamDetailViewModel(teamName: teamName, teamColour: teamColour))
    }

    private var teamColor: Color {
        Color(hex: viewModel.teamColour)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                standingsCard
                driversCard
                recentResultsCard
            }
            .padding()
        }
        .background(Color.f1Background)
        .navigationTitle(viewModel.teamName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadData()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<5) { _ in
                    Rectangle()
                        .fill(teamColor)
                        .frame(height: 4)
                }
                ForEach(0..<5) { _ in
                    Rectangle()
                        .fill(teamColor.opacity(0.4))
                        .frame(height: 4)
                }
            }

            VStack(spacing: 8) {
                Text(viewModel.teamName.uppercased())
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.black)
                    .foregroundStyle(teamColor)

                Text("CONSTRUCTOR")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Standings Card

    private var standingsCard: some View {
        VStack(spacing: 16) {
            Text("CHAMPIONSHIP STANDING")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.f1Red)
                .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else if let standing = viewModel.standing {
                HStack(spacing: 24) {
                    VStack(spacing: 4) {
                        Text("Position")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("P\(standing.position)")
                            .font(.system(.title, design: .rounded))
                            .fontWeight(.black)
                            .foregroundStyle(positionColor(standing.position))
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 4) {
                        Text("Points")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(Int(standing.points))")
                            .font(.system(.title, design: .rounded))
                            .fontWeight(.black)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 4) {
                        Text("Wins")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(standing.wins)")
                            .font(.system(.title, design: .rounded))
                            .fontWeight(.black)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else if let error = viewModel.error {
                errorRow(error)
            } else {
                Text("No standings data")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Drivers Card

    private var driversCard: some View {
        VStack(spacing: 16) {
            Text("TEAM DRIVERS")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.f1Red)
                .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else if viewModel.teamDrivers.isEmpty {
                Text("No driver data available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ForEach(viewModel.teamDrivers) { driver in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(teamColor)
                            .frame(width: 4, height: 40)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(driver.driverName)
                                .font(.headline)
                                .fontWeight(.bold)
                            Text("P\(driver.position) in championship · \(Int(driver.points)) pts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(driver.driverCode)
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(teamColor)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Recent Results Card

    private var recentResultsCard: some View {
        VStack(spacing: 12) {
            Text("RECENT RESULTS")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.f1Red)
                .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else if let error = viewModel.error {
                errorRow(error)
            } else if viewModel.recentResults.isEmpty {
                Text("No results available yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ForEach(viewModel.recentResults) { result in
                    resultRow(result)
                    if result.id != viewModel.recentResults.last?.id {
                        Divider().overlay(Color.f1SecondaryBackground)
                    }
                }
            }
        }
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func resultRow(_ result: TeamRaceResult) -> some View {
        HStack(spacing: 12) {
            Text("P\(result.position)")
                .font(.system(.title3, design: .rounded))
                .fontWeight(.black)
                .frame(width: 44)
                .foregroundStyle(positionColor(result.position, isDNF: result.isDNF))

            VStack(alignment: .leading, spacing: 2) {
                Text(result.shortName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                HStack(spacing: 4) {
                    Text(result.driverCode)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(teamColor)
                    if result.isDNF {
                        Text("· \(result.status)")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }

            Spacer()

            Text("\(Int(result.points)) pts")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
    }

    private func positionColor(_ position: Int, isDNF: Bool = false) -> Color {
        if isDNF { return .red }
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
        TeamDetailView(teamName: "McLaren", teamColour: "FF8000")
    }
    .preferredColorScheme(.dark)
}
