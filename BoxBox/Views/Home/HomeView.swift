import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: F1Design.cardSpacing) {
                    if viewModel.isLoading {
                        F1LoadingView(message: "Fetching race data")
                    } else if let error = viewModel.error {
                        ErrorCard(message: error) {
                            Task { await viewModel.loadData() }
                        }
                    } else if viewModel.nextRace == nil && viewModel.lastRace == nil {
                        VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
                            F1SectionHeader(title: "PADDOCK STATUS", subtitle: "Nothing loaded yet")
                            F1EmptyView(
                                icon: "antenna.radiowaves.left.and.right.slash",
                                title: "Race data is not ready yet",
                                subtitle: "Pull to refresh and BoxBox will repopulate the home dashboard as soon as the schedule feed is back."
                            )
                            .frame(minHeight: 140)
                        }
                        .f1Card()
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
            .refreshable {
                await viewModel.loadData()
            }
            .navigationTitle("BoxBox")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: Race.self) { race in
                RaceDetailView(race: race)
            }
            .navigationDestination(for: Driver.self) { driver in
                DriverDetailView(driver: driver)
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
                VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
                    HStack {
                        F1SectionHeader(title: "NEXT RACE")
                        Spacer()
                        if let days = race.daysUntilRace {
                            Text(days <= 0 ? "THIS WEEK" : "T-\(days)d")
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(0.6)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.f1Red.opacity(0.85))
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
                            F1MetricTile(title: "Track", value: info.speedClass)
                            F1MetricTile(title: "Turns", value: "\(info.turns)")
                            F1MetricTile(title: "DRS", value: "\(info.drsZones)")
                        }
                    }

                    HStack(spacing: 12) {
                        F1StatPill(title: "Overtaking", value: viewModel.pressureProfile.overtaking)
                        F1StatPill(title: "Tyres", value: viewModel.pressureProfile.tyreStress)
                        F1StatPill(title: "Quali", value: viewModel.pressureProfile.qualifyingImportance)
                    }

                    HStack {
                        Label(race.formattedDate, systemImage: "calendar")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .f1Card(gradient: true)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var titleFightCard: some View {
        if let leader = viewModel.championshipLeader, !viewModel.titleChasers.isEmpty {
            VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
                HStack {
                    F1SectionHeader(title: "TITLE FIGHT")
                    Spacer()
                    Text(viewModel.titleFightGapText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                NavigationLink(value: Driver.fallback(driverCode: leader.driverCode, driverName: leader.driverName, teamName: leader.constructorName)) {
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
                    .f1InnerCard()
                }
                .buttonStyle(.plain)

                VStack(spacing: 8) {
                    ForEach(Array(viewModel.titleChasers.prefix(3).enumerated()), id: \.element.id) { _, standing in
                        NavigationLink(value: Driver.fallback(driverCode: standing.driverCode, driverName: standing.driverName, teamName: standing.constructorName)) {
                            HStack(spacing: 12) {
                                Text("P\(standing.position)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(standing.position == 1 ? Color.f1Red : .secondary)
                                    .frame(width: 30)
                                F1TeamDot(teamName: standing.constructorName)
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
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(standing.points.cleanNumber) pts")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
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
    }

    @ViewBuilder
    private var formWatchCard: some View {
        if !viewModel.driverTrends.isEmpty {
            VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
                F1SectionHeader(title: "FORM WATCH", subtitle: "Recent momentum across the last 3 completed races")

                ForEach(viewModel.driverTrends.prefix(3)) { trend in
                    NavigationLink(value: Driver.fallback(driverCode: trend.driverCode, driverName: trend.driverName, teamName: trend.constructorName)) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(trend.driverCode)
                                        .font(.caption)
                                        .fontWeight(.heavy)
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
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 6) {
                                Label(trend.momentumLabel, systemImage: trend.trendIcon)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                Text("Avg P\(String(format: "%.1f", trend.averageFinish))")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .f1InnerCard()
                    }
                    .buttonStyle(.plain)
                }
            }
            .f1Card()
        }
    }

    @ViewBuilder
    private var weekendTimelineCard: some View {
        if let race = viewModel.nextRace, !race.weekendSessions.isEmpty {
            NavigationLink(value: race) {
                VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
                    F1SectionHeader(title: "WEEKEND FLOW", subtitle: "Session cadence for the race weekend")

                    ForEach(race.weekendSessions) { session in
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.label)
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                Text(session.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(session.relativeLabel.uppercased())
                                    .font(.system(size: 9, weight: .heavy))
                                    .tracking(0.4)
                                    .foregroundStyle(session.isUpcoming ? Color.f1Red : .secondary)
                                Text(session.timeLabel)
                                    .font(.caption)
                                    .foregroundStyle(.white)
                            }
                        }
                        .f1InnerCard()
                    }
                }
                .f1Card()
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var lastRaceCard: some View {
        if let race = viewModel.lastRace, !viewModel.lastRaceResults.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink(value: race) {
                    HStack {
                        F1SectionHeader(title: "LAST RACE")
                        Spacer()
                        Text(race.raceWeekendTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                ForEach(viewModel.lastRaceResults.prefix(5)) { result in
                    NavigationLink(value: Driver.fallback(driverCode: result.driverCode, driverName: result.driverName, teamName: result.constructor)) {
                        HStack(spacing: 12) {
                            F1PositionBadge(position: result.position)
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

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(Int(result.points)) pts")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .f1InnerCard()
                    }
                    .buttonStyle(.plain)
                }
            }
            .f1Card()
        }
    }
}

struct ErrorCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.yellow)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.f1Red)
            .controlSize(.small)
        }
        .f1Card()
    }
}

#Preview {
    HomeView()
        .preferredColorScheme(.dark)
}
