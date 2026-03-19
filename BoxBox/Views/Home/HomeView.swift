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
                        titleFightCard
                        formWatchCard
                        weekendTimelineCard
                        lastRaceCard
                    }
                }
                .padding()
            }
            .background(Color.f1Background)
            .navigationTitle("BoxBox")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: Race.self) { race in
                RaceDetailView(race: race)
            }
            .navigationDestination(for: DriverStanding.self) { standing in
                DriverStandingDetailView(standing: standing)
            }
        }
        .task {
            await viewModel.loadData()
        }
    }

    @ViewBuilder
    private var nextRaceCard: some View {
        if let race = viewModel.nextRace {
            NavigationLink(value: race) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("NEXT RACE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.f1Red)
                        Spacer()
                        if let days = race.daysUntilRace {
                            Text(days <= 0 ? "This week" : "T-\(days)d")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.f1Red.opacity(0.8))
                                .clipShape(Capsule())
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(race.raceName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)

                        Text("\(race.circuitName) · \(race.country)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if !viewModel.countdown.isEmpty {
                        Text(viewModel.countdown)
                            .font(.system(.largeTitle, design: .monospaced))
                            .fontWeight(.black)
                            .foregroundStyle(.white)
                    }

                    if let info = race.circuitInfo {
                        HStack(spacing: 10) {
                            compactMetric(title: "Track", value: info.speedClass)
                            compactMetric(title: "Turns", value: "\(info.turns)")
                            compactMetric(title: "DRS", value: "\(info.drsZones)")
                        }
                    }

                    HStack(spacing: 12) {
                        pressurePill(title: "Overtaking", value: viewModel.pressureProfile.overtaking)
                        pressurePill(title: "Tyres", value: viewModel.pressureProfile.tyreStress)
                        pressurePill(title: "Quali", value: viewModel.pressureProfile.qualifyingImportance)
                    }

                    HStack {
                        Label(race.formattedDate, systemImage: "calendar")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding()
                .background(
                    LinearGradient(colors: [Color.f1CardBackground, Color.f1SecondaryBackground], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var titleFightCard: some View {
        if let leader = viewModel.championshipLeader, !viewModel.titleChasers.isEmpty {
            NavigationLink(value: leader) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("TITLE FIGHT")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.f1Red)
                        Spacer()
                        Text(viewModel.titleFightGapText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(leader.driverName)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                            Text(leader.constructorName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(leader.points.cleanNumber)
                                .font(.system(.largeTitle, design: .rounded))
                                .fontWeight(.black)
                                .foregroundStyle(Color.f1Red)
                            Text("pts · \(leader.wins) wins")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(spacing: 10) {
                        ForEach(Array(viewModel.titleChasers.prefix(3).enumerated()), id: \.element.id) { _, standing in
                            HStack(spacing: 12) {
                                Text("P\(standing.position)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(standing.position == 1 ? Color.f1Red : .secondary)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(standing.driverName)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                    Text(standing.constructorName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(standing.points.cleanNumber) pts")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.f1CardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var formWatchCard: some View {
        if !viewModel.driverTrends.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("FORM WATCH", subtitle: "Recent podium pressure across the last 3 completed races")

                ForEach(viewModel.driverTrends.prefix(3)) { trend in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(trend.driverCode)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.f1Red)
                                Text(trend.driverName)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                            Text(trend.constructorName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(trend.recentSummary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 6) {
                            Label(trend.momentumLabel, systemImage: trend.trendIcon)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                            Text("Avg finish \(String(format: "%.1f", trend.averageFinish))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.f1SecondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding()
            .background(Color.f1CardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private var weekendTimelineCard: some View {
        if let race = viewModel.nextRace, !race.weekendSessions.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("WEEKEND FLOW", subtitle: "Estimated session cadence so the app feels useful before lights out")

                ForEach(race.weekendSessions) { session in
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.label)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                            Text(session.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(session.relativeLabel.uppercased())
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(session.isUpcoming ? Color.f1Red : .secondary)
                            Text(session.timeLabel)
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                    }
                    .padding()
                    .background(Color.f1SecondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
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
            NavigationLink(value: race) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("LAST RACE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.f1Red)
                        Spacer()
                        Text(race.raceWeekendTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(viewModel.lastRaceResults.prefix(5)) { result in
                        HStack(spacing: 12) {
                            Text("\(result.position)")
                                .font(.system(.title3, design: .rounded))
                                .fontWeight(.black)
                                .foregroundStyle(podiumColor(for: result.position))
                                .frame(width: 34)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.driverName)
                                    .font(.headline)
                                    .foregroundStyle(.white)
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
                    }
                }
                .padding()
                .background(Color.f1CardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionHeader(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.f1Red)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.black.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func pressurePill(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
