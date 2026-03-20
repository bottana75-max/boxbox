import SwiftUI

struct ScheduleView: View {
    @State private var viewModel = ScheduleViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    F1LoadingView(message: "Loading races")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.error {
                    ErrorCard(message: error) {
                        Task { await viewModel.loadData() }
                    }
                    .padding()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: F1Design.cardSpacing) {
                            headerCard

                            ForEach(viewModel.races) { race in
                                NavigationLink(value: race) {
                                    raceRow(race)
                                        .f1Card(accent: raceCardAccent(for: race))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                    .navigationDestination(for: Race.self) { race in
                        RaceDetailView(race: race)
                    }
                }
            }
            .background(Color.f1Background)
            .navigationTitle("Races")
            .refreshable {
                await viewModel.loadData()
            }
        }
        .task {
            await viewModel.loadData()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
            F1SectionHeader(title: "RACE BOARD", subtitle: "Every round in one premium season view, with the next lights-out and completed winners called out cleanly.")

            HStack(spacing: 10) {
                F1MetricTile(title: "Rounds", value: "\(viewModel.races.count)")
                F1MetricTile(title: "Completed", value: "\(viewModel.completedCount)")
                F1MetricTile(title: "Next", value: viewModel.nextRace?.raceWeekendTitle ?? "TBD")
            }
        }
        .f1Card(gradient: true, accent: .f1Red)
    }

    private func raceRow(_ race: Race) -> some View {
        let isNext = race.round == viewModel.nextRaceRound
        let winner = viewModel.winnerByRound[race.round]

        return HStack(spacing: 16) {
            // Round number column — fixed width for consistency
            VStack(spacing: 4) {
                Text("\(race.round)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(isNext ? Color.f1Red : .white)
                Text("RND")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44)

            // Divider
            Rectangle()
                .fill(isNext ? Color.f1Red : Color.white.opacity(0.08))
                .frame(width: 1)

            // Main content
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(race.raceWeekendTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    if isNext {
                        Text("NEXT")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.f1Red)
                            .clipShape(Capsule())
                    }
                }

                Text("\(race.country) · \(race.formattedDate)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let winner {
                    HStack(spacing: 6) {
                        Image(systemName: "trophy.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                        Text(winner.driverName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(winner.constructor)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !race.isPast {
                    Text(race.circuitName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }



    private func raceCardAccent(for race: Race) -> Color? {
        if race.round == viewModel.nextRaceRound { return .f1Red }
        if race.isPast { return nil }
        return nil
    }

    private func tag(_ title: String, color: Color, foreground: Color = .white) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .clipShape(Capsule())
    }
}



private struct CircuitOutlineView: View {
    let points: [TrackMapPoint]
    let stroke: Color

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                guard let first = points.first else { return }
                let mapped = points.map { CGPoint(x: ($0.x / 100) * proxy.size.width, y: ($0.y / 100) * proxy.size.height) }
                path.move(to: mapped[0])
                for point in mapped.dropFirst() {
                    path.addLine(to: point)
                }
                if shouldClose(points) {
                    path.addLine(to: CGPoint(x: (first.x / 100) * proxy.size.width, y: (first.y / 100) * proxy.size.height))
                }
            }
            .stroke(stroke, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            .shadow(color: stroke.opacity(0.35), radius: 6, x: 0, y: 0)
        }
        .padding(6)
        .opacity(0.9)
    }

    private func shouldClose(_ points: [TrackMapPoint]) -> Bool {
        guard points.count >= 3 else { return false }
        let segments = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        guard !segments.isEmpty else { return false }
        let median = segments.sorted()[segments.count / 2]
        let closureGap = hypot(points[0].x - points[points.count - 1].x, points[0].y - points[points.count - 1].y)
        return closureGap <= max(22, median * 6)
    }
}



#Preview {
    ScheduleView()
        .preferredColorScheme(.dark)
}
