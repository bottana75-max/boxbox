import SwiftUI

struct RaceDetailView: View {
    @State private var viewModel: RaceDetailViewModel

    init(race: Race) {
        _viewModel = State(initialValue: RaceDetailViewModel(race: race))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                raceHeader
                if let info = viewModel.race.circuitInfo {
                    trackMapCard(info)
                    circuitStatsCard(info)
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
                .font(.caption)
                .fontWeight(.bold)
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
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func trackMapCard(_ info: CircuitInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("TRACK MAP", subtitle: "Visual reference, not official artwork")

            HStack(spacing: 20) {
                CircuitMapView(points: info.trackMapPoints)
                    .frame(width: 150, height: 150)

                VStack(alignment: .leading, spacing: 12) {
                    infoLine(icon: "road.lanes", title: "Layout", value: "\(info.turns) turns · \(info.direction)")
                    infoLine(icon: "bolt.fill", title: "Profile", value: info.speedClass)
                    infoLine(icon: "arrow.up.right", title: "DRS", value: "\(info.drsZones) zones")
                    infoLine(icon: "ruler", title: "Distance", value: info.totalDistanceKm)
                }
            }
        }
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func circuitStatsCard(_ info: CircuitInfo) -> some View {
        VStack(spacing: 12) {
            sectionHeader("CIRCUIT DATA")

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
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func circuitStoryCard(_ info: CircuitInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("WEEKEND READ")

            Text(circuitNarrative(for: info))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                insightPill(title: "Overtaking", value: info.drsZones >= 2 ? "Live" : "Tough")
                insightPill(title: "Tyre stress", value: tyreStress(for: info))
                insightPill(title: "Qualifying", value: qualifyingImportance(for: info))
            }
        }
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var resultsSection: some View {
        VStack(spacing: 12) {
            sectionHeader("TOP 10 RESULTS")

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 200)
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
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func resultRow(_ result: RaceResult) -> some View {
        HStack(spacing: 12) {
            Text("\(result.position)")
                .font(.system(.title3, design: .rounded))
                .fontWeight(.black)
                .frame(width: 32)
                .foregroundStyle(positionColor(result.position))

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
            Text("LIGHTS OUT IN")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.f1Red)

            Text(viewModel.countdown)
                .font(.system(.largeTitle, design: .rounded))
                .fontWeight(.black)
                .foregroundStyle(.white)

            Image(systemName: "flag.checkered")
                .font(.system(size: 48))
                .foregroundStyle(Color.f1Red.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal)
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func sectionHeader(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.f1Red)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
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
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.f1SecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func insightPill(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.f1SecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

    private func positionColor(_ position: Int) -> Color {
        switch position {
        case 1: return .yellow
        case 2: return Color.white.opacity(0.75)
        case 3: return Color(red: 0.8, green: 0.5, blue: 0.2)
        default: return .white
        }
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
                    .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round))

                linePath
                    .stroke(Color.f1Red, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

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
