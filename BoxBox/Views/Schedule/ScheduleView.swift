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
        let treatment = race.visualTreatment
        let winner = viewModel.winnerByRound[race.round]

        return ZStack(alignment: .topLeading) {
            RaceCardBackdrop(treatment: treatment)
                .clipShape(RoundedRectangle(cornerRadius: F1Design.cornerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("ROUND \(race.round)")
                                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                .tracking(0.8)
                                .foregroundStyle(isNext ? Color.f1Red : .secondary)

                            if isNext {
                                tag("Next", color: .f1Red)
                            } else if race.isPast {
                                tag("Final", color: treatment.primary.opacity(0.8))
                            } else {
                                tag("Upcoming", color: .white.opacity(0.16), foreground: .white.opacity(0.86))
                            }
                        }

                        Text(race.raceWeekendTitle)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)

                        Text(race.circuitName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Group {
                        if let info = race.circuitInfo {
                            CircuitOutlineView(points: info.trackMapPoints, stroke: treatment.secondary)
                                .frame(width: 64, height: 64)
                                .padding(10)
                                .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(.white.opacity(0.05), lineWidth: 1)
                                }
                        } else {
                            F1Chevron()
                        }
                    }
                }

                HStack(spacing: 10) {
                    schedulePill(systemImage: "flag.fill", title: race.country)
                    schedulePill(systemImage: "calendar", title: race.formattedDate)
                    schedulePill(systemImage: "clock", title: race.weekendContext.localClockLabel)
                }

                if race.isPast, let winner {
                    winnerStrip(winner, treatment: treatment)
                }
            }
            .padding(F1Design.contentPadding)
        }
    }

    private func winnerStrip(_ winner: RaceWinner, treatment: RaceVisualTreatment) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(treatment.primary.opacity(0.18))
                    .frame(width: 34, height: 34)
                Text("P1")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(treatment.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Winner")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(winner.driverName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    if !winner.driverCode.isEmpty {
                        Text(winner.driverCode)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(treatment.primary)
                    }
                }
            }

            Spacer()

            HStack(spacing: 6) {
                F1TeamDot(teamName: winner.constructor, size: 8)
                Text(winner.constructor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.18))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(treatment.secondary.opacity(0.26), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func schedulePill(systemImage: String, title: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.white.opacity(0.04), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.04), lineWidth: 1)
            }
    }

    private func raceCardAccent(for race: Race) -> Color? {
        if race.round == viewModel.nextRaceRound { return .f1Red }
        return race.visualTreatment.primary.opacity(race.isPast ? 0.28 : 0.18)
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

private struct RaceCardBackdrop: View {
    let treatment: RaceVisualTreatment

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    treatment.primary.opacity(0.16),
                    Color.clear,
                    treatment.secondary.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack(spacing: 0) {
                treatment.primary.opacity(0.18)
                treatment.secondary.opacity(0.14)
                treatment.tertiary.opacity(0.12)
            }
            .blendMode(.plusLighter)
            .mask(
                LinearGradient(
                    colors: [.black.opacity(0.9), .black.opacity(0.15), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

            RadialGradient(
                colors: [treatment.primary.opacity(0.18), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 180
            )
        }
        .allowsHitTesting(false)
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
                path.addLine(to: CGPoint(x: (first.x / 100) * proxy.size.width, y: (first.y / 100) * proxy.size.height))
            }
            .stroke(stroke, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            .shadow(color: stroke.opacity(0.35), radius: 6, x: 0, y: 0)
        }
        .padding(6)
        .opacity(0.9)
    }
}

private struct RaceVisualTreatment {
    let primary: Color
    let secondary: Color
    let tertiary: Color
}

private extension Race {
    var visualTreatment: RaceVisualTreatment {
        let normalized = country.lowercased()

        switch normalized {
        case let value where value.contains("italy"):
            return RaceVisualTreatment(primary: .green.opacity(0.95), secondary: .white.opacity(0.9), tertiary: .f1Red.opacity(0.92))
        case let value where value.contains("great britain") || value.contains("britain") || value.contains("united kingdom"):
            return RaceVisualTreatment(primary: .white.opacity(0.9), secondary: Color(red: 0.79, green: 0.04, blue: 0.18), tertiary: Color(red: 0.05, green: 0.18, blue: 0.52))
        case let value where value.contains("monaco"):
            return RaceVisualTreatment(primary: .white.opacity(0.92), secondary: .f1Red.opacity(0.95), tertiary: Color(red: 0.65, green: 0.65, blue: 0.68))
        case let value where value.contains("japan"):
            return RaceVisualTreatment(primary: .white.opacity(0.92), secondary: .f1Red.opacity(0.92), tertiary: Color(red: 0.72, green: 0.72, blue: 0.76))
        case let value where value.contains("netherlands"):
            return RaceVisualTreatment(primary: Color(red: 0.73, green: 0.26, blue: 0.05), secondary: .white.opacity(0.9), tertiary: Color(red: 0.10, green: 0.20, blue: 0.58))
        case let value where value.contains("belgium"):
            return RaceVisualTreatment(primary: .black.opacity(0.9), secondary: Color(red: 0.96, green: 0.84, blue: 0.18), tertiary: .f1Red.opacity(0.88))
        case let value where value.contains("austria"):
            return RaceVisualTreatment(primary: .f1Red.opacity(0.9), secondary: .white.opacity(0.92), tertiary: Color(red: 0.64, green: 0.64, blue: 0.68))
        case let value where value.contains("hungary"):
            return RaceVisualTreatment(primary: .f1Red.opacity(0.88), secondary: .white.opacity(0.9), tertiary: .green.opacity(0.82))
        case let value where value.contains("mexico"):
            return RaceVisualTreatment(primary: .green.opacity(0.84), secondary: .white.opacity(0.9), tertiary: .f1Red.opacity(0.9))
        case let value where value.contains("brazil"):
            return RaceVisualTreatment(primary: .green.opacity(0.86), secondary: Color(red: 0.95, green: 0.82, blue: 0.16), tertiary: Color(red: 0.10, green: 0.30, blue: 0.72))
        case let value where value.contains("usa") || value.contains("united states"):
            return RaceVisualTreatment(primary: Color(red: 0.72, green: 0.09, blue: 0.16), secondary: .white.opacity(0.92), tertiary: Color(red: 0.12, green: 0.22, blue: 0.56))
        case let value where value.contains("canada"):
            return RaceVisualTreatment(primary: .f1Red.opacity(0.9), secondary: .white.opacity(0.94), tertiary: Color(red: 0.70, green: 0.70, blue: 0.74))
        case let value where value.contains("singapore"):
            return RaceVisualTreatment(primary: .f1Red.opacity(0.92), secondary: .white.opacity(0.92), tertiary: Color(red: 0.20, green: 0.20, blue: 0.24))
        case let value where value.contains("china"):
            return RaceVisualTreatment(primary: .f1Red.opacity(0.92), secondary: Color(red: 0.95, green: 0.82, blue: 0.14), tertiary: Color(red: 0.35, green: 0.05, blue: 0.05))
        default:
            return RaceVisualTreatment(primary: .f1Red.opacity(0.86), secondary: .white.opacity(0.85), tertiary: Color.f1Subtle.opacity(0.92))
        }
    }
}

#Preview {
    ScheduleView()
        .preferredColorScheme(.dark)
}
