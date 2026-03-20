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
            VStack(spacing: F1Design.cardSpacing) {
                headerSection
                overviewCard
                standingsCard
                driversCard
                rivalCard
                recentResultsCard
            }
            .padding()
        }
        .background(Color.f1Background)
        .navigationTitle(viewModel.teamName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Driver.self) { driver in
            DriverDetailView(driver: driver)
        }
        .navigationDestination(for: Race.self) { race in
            RaceDetailView(race: race)
        }
        .task {
            await viewModel.loadData()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { _ in
                    Rectangle().fill(teamColor).frame(height: 4)
                }
                ForEach(0..<5, id: \.self) { _ in
                    Rectangle().fill(teamColor.opacity(0.35)).frame(height: 4)
                }
            }
            .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.teamName.uppercased())
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.black)
                    .foregroundStyle(.white)

                Text("CONSTRUCTOR PROFILE")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.1)
                    .foregroundStyle(teamColor)

                Text(viewModel.teamNarrative)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
        }
        .f1Card(gradient: true, accent: teamColor)
    }

    private var overviewCard: some View {
        VStack(spacing: 12) {
            F1SectionHeader(title: "TEAM SNAPSHOT", subtitle: "Form, depth and recent conversion")

            HStack(spacing: 10) {
                F1StatPill(title: "Driver pts", value: viewModel.totalDriverPoints.cleanNumber)
                F1StatPill(title: "Avg grid", value: viewModel.averageGridRank)
                F1StatPill(title: "Recent form", value: viewModel.formAverage)
            }

            HStack(spacing: 10) {
                F1MetricTile(title: "Momentum", value: viewModel.momentumHeadline)
                F1MetricTile(title: "Recent podiums", value: "\(viewModel.podiumCount) in last 10 finishes")
                F1MetricTile(title: "DNF pressure", value: viewModel.dnfCount == 0 ? "Clean run" : "\(viewModel.dnfCount) setbacks")
            }
        }
        .f1Card(accent: teamColor.opacity(0.75))
    }

    private var standingsCard: some View {
        VStack(spacing: 16) {
            F1SectionHeader(title: "CHAMPIONSHIP STANDING")

            if viewModel.isLoading {
                ProgressView()
                    .tint(Color.f1Red)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else if let standing = viewModel.standing {
                HStack(spacing: 12) {
                    statColumn(title: "Position", value: "P\(standing.position)", color: F1Design.positionColor(standing.position))
                    statColumn(title: "Points", value: standing.points.cleanNumber, color: .white)
                    statColumn(title: "Wins", value: "\(standing.wins)", color: teamColor)
                }
            } else if let error = viewModel.error {
                errorRow(error)
            } else {
                F1EmptyView(icon: "chart.bar", title: "No standings data")
            }
        }
        .f1Card()
    }

    private var driversCard: some View {
        VStack(spacing: 16) {
            F1SectionHeader(title: "TEAM DRIVERS")

            if viewModel.isLoading {
                ProgressView()
                    .tint(Color.f1Red)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else if viewModel.teamDrivers.isEmpty {
                F1EmptyView(icon: "person.2", title: "No driver data available")
            } else {
                ForEach(viewModel.teamDrivers) { driver in
                    NavigationLink(value: Driver.fallback(driverCode: driver.driverCode, driverName: driver.driverName, teamName: viewModel.teamName)) {
                        F1ListRow(accent: teamColor) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(driver.driverName)
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                    Text("P\(driver.position) in championship · \(Int(driver.points)) pts · \(driver.wins) wins")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(driver.driverCode)
                                    .font(.system(.title3, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundStyle(teamColor)

                                F1Chevron()
                            }
                        }
                        .f1InnerCard()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .f1Card()
    }

    private var rivalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            F1SectionHeader(title: "PRESSURE CHECK", subtitle: "Nearest rival and season context")

            if let rival = viewModel.nearestRival, let standing = viewModel.standing {
                HStack(spacing: 12) {
                    rivalTile(title: viewModel.teamName, subtitle: "Current", value: "\(standing.points.cleanNumber) pts", accent: teamColor)
                    rivalTile(title: rival.name, subtitle: "Closest benchmark", value: "\(rival.points.cleanNumber) pts", accent: F1Design.teamColor(for: rival.name))
                }
                Text(viewModel.pointsGapSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            } else if viewModel.isLoading {
                F1LoadingView(message: "Loading...")
                    .frame(minHeight: 80)
            } else {
                F1EmptyView(icon: "arrow.left.arrow.right", title: "Rival context not ready")
            }
        }
        .f1Card()
    }

    private var recentResultsCard: some View {
        VStack(spacing: 12) {
            F1SectionHeader(title: "RECENT RESULTS", subtitle: "Tap a race for the full circuit page")

            if viewModel.isLoading {
                F1LoadingView(message: "Loading...")
                    .frame(minHeight: 100)
            } else if let error = viewModel.error {
                errorRow(error)
            } else if viewModel.recentResults.isEmpty {
                F1EmptyView(icon: "flag.checkered", title: "No results available yet")
            } else {
                ForEach(viewModel.recentResults) { result in
                    NavigationLink(value: result.race) {
                        resultRow(result)
                            .f1InnerCard()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .f1Card()
    }

    private func statColumn(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title, design: .rounded))
                .fontWeight(.black)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.f1SecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: F1Design.innerCornerRadius, style: .continuous))
    }

    private func rivalTile(title: String, subtitle: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(subtitle.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.4)
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(value)
                .font(.subheadline)
                .fontWeight(.heavy)
                .foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.f1SecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: F1Design.innerCornerRadius + 2, style: .continuous))
    }

    private func resultRow(_ result: TeamRaceResult) -> some View {
        F1ListRow(accent: teamColor) {
            HStack(spacing: 12) {
                Text("P\(result.position)")
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.black)
                    .frame(width: 44)
                    .foregroundStyle(F1Design.positionColor(result.position, isDNF: result.isDNF))

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

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(result.points)) pts")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    F1Chevron()
                }
            }
        }
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
}

#Preview {
    NavigationStack {
        TeamDetailView(teamName: "McLaren", teamColour: "FF8000")
    }
    .preferredColorScheme(.dark)
}
