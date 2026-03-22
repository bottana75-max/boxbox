import SwiftUI

struct DriverStandingDetailView: View {
    @State private var viewModel: DriverStandingDetailViewModel

    init(standing: DriverStanding) {
        _viewModel = State(initialValue: DriverStandingDetailViewModel(standing: standing))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: F1Design.cardSpacing) {
                standingHeader
                pointsChart
                statsCard
            }
            .padding()
        }
        .background(Color.f1Background)
        .navigationTitle(viewModel.standing.driverName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var standingHeader: some View {
        VStack(spacing: 16) {
            Text("P\(viewModel.standing.position)")
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundStyle(F1Design.positionColor(viewModel.standing.position))

            Text(viewModel.standing.driverName)
                .font(.title2)
                .fontWeight(.bold)

            HStack(spacing: 8) {
                F1TeamDot(teamName: viewModel.standing.constructorName, size: 10)
                Text(viewModel.standing.constructorName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 32) {
                VStack(spacing: 4) {
                    Text("\(Int(viewModel.standing.points))")
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.black)
                    Text("Points")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 4) {
                    Text("\(viewModel.standing.wins)")
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.black)
                        .foregroundStyle(viewModel.standing.wins > 0 ? F1Design.positionColor(1) : .white)
                    Text("Wins")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 4) {
                    Text(viewModel.standing.driverCode)
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.black)
                    Text("Code")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .f1Card()
    }

    // MARK: - Points Chart

    private var pointsChart: some View {
        VStack(spacing: 12) {
            F1SectionHeader(title: "POINTS PER RACE", subtitle: "Estimated distribution")

            let maxPoints = viewModel.racePoints.map(\.points).max() ?? 26

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(viewModel.racePoints.enumerated()), id: \.offset) { _, racePoint in
                    VStack(spacing: 4) {
                        Text("\(Int(racePoint.points))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [Color.f1Red, Color.f1Red.opacity(0.4)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(
                                height: maxPoints > 0
                                    ? max(4, CGFloat(racePoint.points / maxPoints) * 120)
                                    : 4
                            )

                        Text(racePoint.race)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 160)
            .frame(maxWidth: .infinity)
        }
        .f1Card()
    }

    // MARK: - Stats

    private var statsCard: some View {
        VStack(spacing: 12) {
            F1SectionHeader(title: "SEASON STATS")

            statRow(label: "Championship Position", value: "P\(viewModel.standing.position)")
            Divider().overlay(Color.f1SecondaryBackground)
            statRow(label: "Total Points", value: "\(Int(viewModel.standing.points))")
            Divider().overlay(Color.f1SecondaryBackground)
            statRow(label: "Race Wins", value: "\(viewModel.standing.wins)")
            Divider().overlay(Color.f1SecondaryBackground)
            statRow(label: "Avg Points/Race", value: String(format: "%.1f", viewModel.standing.points / max(1, Double(viewModel.racePoints.count))))
        }
        .f1Card()
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
        }
    }
}

#Preview {
    NavigationStack {
        DriverStandingDetailView(standing: DriverStanding(
            id: "verstappen",
            position: 1,
            driverName: "Max Verstappen",
            driverCode: "VER",
            constructorName: "Red Bull",
            points: 395,
            wins: 15
        ))
    }
    .preferredColorScheme(.dark)
}
