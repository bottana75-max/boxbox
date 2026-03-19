import SwiftUI

struct RaceDetailView: View {
    @State private var viewModel: RaceDetailViewModel

    init(race: Race) {
        _viewModel = State(initialValue: RaceDetailViewModel(race: race))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: F1Design.cardSpacing) {
                raceHeader
                if let info = viewModel.race.circuitInfo {
                    trackMapCard(info)
                    circuitStatsCard(info)
                    weekendContextCard(viewModel.race.weekendContext)
                    circuitStoryCard(info)
                }
                if viewModel.race.isPast {
                    resultsSection
                } else {
                    countdownSection
                }
            }
            .padding()
        }
        .background(Color.f1Background)
        .navigationTitle(viewModel.race.raceName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadData()
        }
    }

    private var raceHeader: some View {
        VStack(spacing: 16) {
            Text("ROUND \(viewModel.race.round)")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Color.f1Red)

            Text(viewModel.race.raceName)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Label(viewModel.race.circuitName, systemImage: "flag.checkered")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Label(viewModel.race.country, systemImage: "mappin")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Label(viewModel.race.formattedDate, systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if viewModel.race.isPast {
                Text("COMPLETED")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .f1Card()
    }

    private func trackMapCard(_ info: CircuitInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            F1SectionHeader(title: "TRACK MAP")

            CircuitMapView(points: info.trackMapPoints)
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .padding(.horizontal, -4)

            VStack(alignment: .leading, spacing: 10) {
                infoLine(icon: "road.lanes", title: "Layout", value: "\(info.turns) turns · \(info.direction)")
                infoLine(icon: "bolt.fill", title: "Profile", value: info.speedClass)
                infoLine(icon: "arrow.up.right", title: "DRS", value: "\(info.drsZones) zones")
                infoLine(icon: "ruler", title: "Distance", value: info.totalDistanceKm)
            }
        }
        .f1Card()
    }

    private func circuitStatsCard(_ info: CircuitInfo) -> some View {
        VStack(spacing: 12) {
            F1SectionHeader(title: "CIRCUIT DATA")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statTile(icon: "flag.checkered.2.crossed", label: "City", value: info.city)
                statTile(icon: "ruler", label: "Lap length", value: info.formattedLength)
                statTile(icon: "repeat", label: "Race distance", value: info.totalDistanceKm)
                statTile(icon: "point.topleft.down.curvedto.point.bottomright.up", label: "Turns", value: "\(info.turns)")
                statTile(icon: "speedometer", label: "Speed class", value: info.speedClass)
                statTile(icon: "clock.badge", label: "Lap record", value: info.lapRecord)
                statTile(icon: "calendar", label: "First GP", value: "\(info.firstGrandPrix)")
                statTile(icon: "arrow.clockwise", label: "Direction", value: info.direction)
            }
        }
        .f1Card()
    }

    private func weekendContextCard(_ context: WeekendContext) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            F1SectionHeader(title: "LOCAL CONTEXT", subtitle: "Estimated timing and weather realism")

            Text(context.localClockLabel)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            Text(context.sessionNarrative)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(2)

            HStack(spacing: 10) {
                F1StatPill(title: "Ambient", value: context.ambientTemperature, style: .subtle)
                F1StatPill(title: "Track", value: context.trackTemperature, style: .subtle)
                F1StatPill(title: "Rain", value: context.rainChance, style: .subtle)
            }

            Text("\(context.weatherDetail) \(context.windNote) \(context.sunsetCue)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .f1Card()
    }

    private func circuitStoryCard(_ info: CircuitInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            F1SectionHeader(title: "WEEKEND READ")

            Text(circuitNarrative(for: info))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                F1StatPill(title: "Overtaking", value: info.drsZones >= 2 ? "Live" : "Tough", style: .subtle)
                F1StatPill(title: "Tyre stress", value: tyreStress(for: info), style: .subtle)
                F1StatPill(title: "Qualifying", value: qualifyingImportance(for: info), style: .subtle)
            }
        }
        .f1Card()
    }

    private var resultsSection: some View {
        VStack(spacing: 12) {
            F1SectionHeader(title: "TOP 10 RESULTS")

            if viewModel.isLoading {
                F1LoadingView(message: "Loading results")
            } else if let error = viewModel.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ForEach(viewModel.results.prefix(10)) { result in
                    resultRow(result)
                }
            }
        }
        .f1Card()
    }

    private func resultRow(_ result: RaceResult) -> some View {
        HStack(spacing: 12) {
            F1PositionBadge(position: result.position)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.driverName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(result.constructor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(result.points))")
                    .font(.headline)
                    .fontWeight(.bold)
                Text("pts")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if result.status != "Finished" && !result.status.starts(with: "+") {
                Image(systemName: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    private var countdownSection: some View {
        VStack(spacing: 16) {
            F1SectionHeader(title: "LIGHTS OUT IN")
                .frame(maxWidth: .infinity, alignment: .center)

            Text(viewModel.countdown)
                .font(.system(.largeTitle, design: .rounded))
                .fontWeight(.black)
                .foregroundStyle(.white)

            Image(systemName: "flag.checkered")
                .font(.system(size: 48))
                .foregroundStyle(Color.f1Red.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal)
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: F1Design.cornerRadius, style: .continuous))
    }

    private func infoLine(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.f1Red)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        }
    }

    private func statTile(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color.f1Red)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.4)
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.f1SecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: F1Design.innerCornerRadius + 2, style: .continuous))
    }

    private func tyreStress(for info: CircuitInfo) -> String {
        if info.lengthKm > 5.7 || info.speedClass.contains("High speed") { return "High" }
        if info.speedClass.contains("Technical") || info.speedClass.contains("Street") { return "Medium" }
        return "Balanced"
    }

    private func qualifyingImportance(for info: CircuitInfo) -> String {
        if info.drsZones <= 1 || info.speedClass.contains("Street") { return "Massive" }
        if info.turns <= 12 { return "Important" }
        return "Balanced"
    }

    private func circuitNarrative(for info: CircuitInfo) -> String {
        "\(info.city) is a \(info.speedClass.lowercased()) stop with \(info.turns) corners across \(info.formattedLength). With \(info.drsZones) DRS zone\(info.drsZones == 1 ? "" : "s"), this weekend is usually decided by qualifying position, tyre life and how cleanly drivers survive the opening laps. Translation: this is enough context to judge predictions instead of tapping an AI button blind."
    }
}

private struct CircuitMapView: View {
    let points: [TrackMapPoint]

    var body: some View {
        GeometryReader { geometry in
            let linePath = Path { path in
                guard let first = points.first else { return }
                path.move(to: CGPoint(x: first.x / 100 * geometry.size.width,
                                      y: first.y / 100 * geometry.size.height))
                for point in points.dropFirst() {
                    path.addLine(to: CGPoint(x: point.x / 100 * geometry.size.width,
                                             y: point.y / 100 * geometry.size.height))
                }
                path.closeSubpath()
            }

            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.f1SecondaryBackground)

                linePath
                    .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))

                linePath
                    .stroke(Color.f1Red, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                if let start = points.first {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .position(x: start.x / 100 * geometry.size.width,
                                  y: start.y / 100 * geometry.size.height)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        RaceDetailView(race: Race(
            id: "1",
            raceName: "Bahrain Grand Prix",
            circuitName: "Bahrain International Circuit",
            country: "Bahrain",
            date: "2025-03-02",
            round: 1
        ))
    }
    .preferredColorScheme(.dark)
}
