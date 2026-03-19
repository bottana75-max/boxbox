import SwiftUI

struct DriverStandingDetailView: View {
    @State private var viewModel: DriverStandingDetailViewModel

    init(standing: DriverStanding) {
        _viewModel = State(initialValue: DriverStandingDetailViewModel(standing: standing))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
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
                .foregroundStyle(positionColor(viewModel.standing.position))

            Text(viewModel.standing.driverName)
                .font(.title2)
                .fontWeight(.bold)

            HStack(spacing: 8) {
                teamColorDot(for: viewModel.standing.constructorName)
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
                        .foregroundStyle(viewModel.standing.wins > 0 ? .yellow : .white)
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
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Points Chart

    private var pointsChart: some View {
        VStack(spacing: 12) {
            Text("POINTS PER RACE")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.f1Red)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Estimated distribution")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

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
                                    colors: [Color.f1Red, Color.f1Red.opacity(0.5)],
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
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Stats

    private var statsCard: some View {
        VStack(spacing: 12) {
            Text("SEASON STATS")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.f1Red)
                .frame(maxWidth: .infinity, alignment: .leading)

            statRow(label: "Championship Position", value: "P\(viewModel.standing.position)")
            Divider().overlay(Color.f1SecondaryBackground)
            statRow(label: "Total Points", value: "\(Int(viewModel.standing.points))")
            Divider().overlay(Color.f1SecondaryBackground)
            statRow(label: "Race Wins", value: "\(viewModel.standing.wins)")
            Divider().overlay(Color.f1SecondaryBackground)
            statRow(label: "Avg Points/Race", value: String(format: "%.1f", viewModel.standing.points / max(1, Double(viewModel.racePoints.count))))
        }
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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

    private func positionColor(_ position: Int) -> Color {
        switch position {
        case 1: return .yellow
        case 2: return Color.white.opacity(0.75)
        case 3: return Color(red: 0.8, green: 0.5, blue: 0.2)
        default: return .white
        }
    }

    private func teamColorDot(for teamName: String) -> some View {
        Circle()
            .fill(teamColor(for: teamName))
            .frame(width: 10, height: 10)
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
