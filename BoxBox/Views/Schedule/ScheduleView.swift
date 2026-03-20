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
            RaceCardBackdrop(treatment: treatment, isNext: isNext)
                .clipShape(RoundedRectangle(cornerRadius: F1Design.cornerRadius, style: .continuous))

            HStack(alignment: .top, spacing: 14) {
                RaceFlagPanel(race: race, treatment: treatment, isNext: isNext)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(isNext ? "UP NEXT" : "ROUND \(race.round)")
                                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                    .tracking(0.9)
                                    .foregroundStyle(isNext ? Color.white : .secondary)

                                if isNext {
                                    tag("Spotlight", color: .f1Red)
                                } else if race.isPast {
                                    tag("Final", color: treatment.primary.opacity(0.8))
                                } else {
                                    tag("Upcoming", color: .white.opacity(0.16), foreground: .white.opacity(0.86))
                                }
                            }

                            Text(race.raceWeekendTitle)
                                .font(isNext ? .title2 : .title3)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)

                            Text(race.circuitName)
                                .font(.subheadline)
                                .foregroundStyle(isNext ? .white.opacity(0.86) : .secondary)
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
                                            .strokeBorder(.white.opacity(isNext ? 0.10 : 0.05), lineWidth: 1)
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

                    if isNext {
                        nextRaceStrip(race, treatment: treatment)
                    } else if race.isPast, let winner {
                        winnerStrip(winner, treatment: treatment)
                    }
                }
            }
            .padding(F1Design.contentPadding)
        }
    }

    private func nextRaceStrip(_ race: Race, treatment: RaceVisualTreatment) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 34, height: 34)
                Image(systemName: "flag.checkered.2.crossed")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Next race")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(treatment.secondary.opacity(0.92))
                Text("\(race.formattedDate) • \(race.weekendContext.localClockLabel)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }

            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(treatment.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(treatment.secondary.opacity(0.32), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
    let isNext: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    treatment.primary.opacity(isNext ? 0.22 : 0.16),
                    Color.clear,
                    treatment.secondary.opacity(isNext ? 0.18 : 0.12)
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
                    colors: [.black.opacity(0.95), .black.opacity(0.2), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

            RadialGradient(
                colors: [treatment.primary.opacity(isNext ? 0.24 : 0.18), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 190
            )

            if isNext {
                RoundedRectangle(cornerRadius: F1Design.cornerRadius, style: .continuous)
                    .strokeBorder(treatment.secondary.opacity(0.28), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct RaceFlagPanel: View {
    let race: Race
    let treatment: RaceVisualTreatment
    let isNext: Bool

    var body: some View {
        let style = race.flagStripeStyle

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))

            FlagStripeFill(style: style, treatment: treatment)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(1)

            LinearGradient(
                colors: [.white.opacity(0.35), .clear, .black.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(1)

            VStack(alignment: .leading, spacing: 8) {
                Text("R\(race.round)")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))

                Spacer()

                Text(String(race.country.prefix(3)).uppercased())
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.95))
            }
            .padding(10)
        }
        .frame(width: 58)
        .overlay(alignment: .topTrailing) {
            if isNext {
                Circle()
                    .fill(Color.f1Red)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.white.opacity(0.75), lineWidth: 1.5))
                    .offset(x: 4, y: -4)
            }
        }
        .shadow(color: treatment.primary.opacity(isNext ? 0.22 : 0.12), radius: isNext ? 16 : 10, x: 0, y: 8)
    }
}

private struct FlagStripeFill: View {
    let style: FlagStripeStyle
    let treatment: RaceVisualTreatment

    var body: some View {
        switch style {
        case .vertical:
            HStack(spacing: 0) {
                treatment.primary
                treatment.secondary
                treatment.tertiary
            }
        case .horizontal:
            VStack(spacing: 0) {
                treatment.primary
                treatment.secondary
                treatment.tertiary
            }
        case .splitHorizontal:
            VStack(spacing: 0) {
                treatment.primary
                treatment.secondary
            }
        case .splitVertical:
            HStack(spacing: 0) {
                treatment.primary
                treatment.secondary
            }
        case .band:
            ZStack {
                treatment.tertiary
                VStack(spacing: 0) {
                    treatment.primary.frame(maxHeight: .infinity)
                    treatment.secondary.frame(height: 14)
                    treatment.tertiary.frame(maxHeight: .infinity)
                }
            }
        }
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

private struct RaceVisualTreatment {
    let primary: Color
    let secondary: Color
    let tertiary: Color
}

private enum FlagStripeStyle {
    case vertical
    case horizontal
    case splitHorizontal
    case splitVertical
    case band
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

    var flagStripeStyle: FlagStripeStyle {
        let normalized = country.lowercased()
        switch normalized {
        case let value where value.contains("italy") || value.contains("mexico") || value.contains("france") || value.contains("ireland"):
            return .vertical
        case let value where value.contains("monaco") || value.contains("indonesia") || value.contains("poland"):
            return .splitHorizontal
        case let value where value.contains("japan") || value.contains("canada") || value.contains("singapore") || value.contains("bahrain") || value.contains("qatar"):
            return .band
        case let value where value.contains("belgium"):
            return .vertical
        case let value where value.contains("china") || value.contains("hungary") || value.contains("netherlands") || value.contains("austria"):
            return .horizontal
        case let value where value.contains("usa") || value.contains("united states") || value.contains("great britain") || value.contains("britain"):
            return .band
        default:
            return .splitVertical
        }
    }
}

#Preview {
    ScheduleView()
        .preferredColorScheme(.dark)
}
