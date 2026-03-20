import SwiftUI

struct TrackReplayView: View {
    @State private var viewModel: ReplayViewModel

    init(race: Race) {
        _viewModel = State(initialValue: ReplayViewModel(race: race))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: F1Design.cardSpacing) {
            introCard

            if viewModel.isLoadingDrivers {
                F1LoadingView(message: "Loading driver list")
                    .frame(minHeight: 140)
                    .f1Card()
            } else if let error = viewModel.error, viewModel.availableDrivers.isEmpty {
                ErrorCard(message: error) {
                    Task { await viewModel.prepare() }
                }
            } else {
                selectionCard

                if viewModel.isLoadingReplay {
                    F1LoadingView(message: "Downloading real race location data")
                        .frame(minHeight: 220)
                        .f1Card()
                } else if let snapshot = viewModel.currentSnapshot, !viewModel.snapshots.isEmpty {
                    mapCard(snapshot)
                    playbackControls
                    standingsCard(snapshot)
                } else if let error = viewModel.error {
                    ErrorCard(message: error) {
                        Task { await viewModel.loadReplay() }
                    }
                }
            }
        }
        .task {
            await viewModel.prepare()
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            F1SectionHeader(title: "RACE REPLAY", subtitle: "Only shown for completed races from this season")

            Text("This replay uses OpenF1 race positions plus per-driver location samples. We only draw cars where we have fresh telemetry, and we ask you to choose drivers before pulling the heavy location stream.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                F1StatPill(title: "Motion", value: "Real samples", style: .subtle)
                F1StatPill(title: "Limit", value: "5 drivers", style: .subtle)
                F1StatPill(title: "Coverage", value: "Full race", style: .subtle)
            }

            Text("Race-start jump skips the pre-start idle telemetry when OpenF1 publishes samples before lights out.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .f1Card()
    }

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    F1SectionHeader(title: "LOAD DRIVERS", subtitle: viewModel.selectionSummary)
                    Text("Pick the drivers you want on the moving map. The field ranking still comes from the full race position feed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await viewModel.loadReplay() }
                } label: {
                    Text(viewModel.snapshots.isEmpty ? "Load replay" : "Reload")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(viewModel.selectedDriverNumbers.isEmpty ? Color.gray.opacity(0.35) : Color.f1Red)
                        .clipShape(Capsule())
                }
                .disabled(viewModel.selectedDriverNumbers.isEmpty || viewModel.isLoadingReplay)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(viewModel.availableDrivers) { driver in
                    driverChip(driver)
                }
            }
        }
        .f1Card()
    }

    private func driverChip(_ driver: ReplayDriver) -> some View {
        let isSelected = viewModel.selectedDriverNumbers.contains(driver.driverNumber)

        return Button {
            viewModel.toggleDriver(driver)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(driver.color)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 3) {
                    Text(driver.nameAcronym)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(driver.fullName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.f1Red : .secondary)
            }
            .padding(12)
            .background(Color.f1SecondaryBackground)
            .overlay {
                RoundedRectangle(cornerRadius: F1Design.innerCornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? driver.color : Color.white.opacity(0.05), lineWidth: isSelected ? 1.2 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: F1Design.innerCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func mapCard(_ snapshot: ReplaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(snapshot.elapsedTime.replayClock)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(snapshot.headline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(viewModel.currentLapLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                    Text("\(viewModel.selectedDriverNumbers.count) drivers loaded")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            ReplayCircuitMapView(trackPoints: viewModel.race.circuitInfo?.trackMapPoints ?? [], markers: snapshot.markers)
                .frame(height: 250)

            Text("Markers update only when a fresh OpenF1 location sample exists (held for up to \(Int(viewModel.projection?.freshnessWindow ?? 4))s). Projected positions are snapped back to the circuit path to keep alignment steadier without inventing missing motion.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .f1Card(gradient: true, accent: .f1Red)
    }

    private var playbackControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                controlChip(title: viewModel.currentLapLabel, systemImage: "flag.checkered.2.crossed")
                Button {
                    viewModel.jumpToRaceStart()
                } label: {
                    controlChip(title: "Jump to start", systemImage: "bolt.fill")
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canJumpToRaceStart)
                .opacity(viewModel.canJumpToRaceStart ? 1 : 0.45)
            }

            Slider(value: Binding(
                get: { viewModel.progress },
                set: { viewModel.progress = $0 }
            ), in: 0...1)
            .tint(Color.f1Red)

            HStack(spacing: 12) {
                Button { viewModel.stepToLap(direction: -1) } label: {
                    Label("Prev lap", systemImage: "backward.end.fill")
                        .font(.caption.weight(.bold))
                }
                .disabled(!viewModel.canStepToPreviousLap)

                Button { viewModel.step(by: -15) } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title3)
                }

                Button { viewModel.togglePlayback() } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(Color.f1Red)
                        .clipShape(Circle())
                }

                Button { viewModel.step(by: 15) } label: {
                    Image(systemName: "goforward.15")
                        .font(.title3)
                }

                Button { viewModel.stepToLap(direction: 1) } label: {
                    Label("Next lap", systemImage: "forward.end.fill")
                        .font(.caption.weight(.bold))
                }
                .disabled(!viewModel.canStepToNextLap)

                Spacer()

                Text(viewModel.currentSnapshot?.elapsedTime.replayClock ?? "--:--")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
        }
        .f1Card()
    }

    private func controlChip(title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.f1SecondaryBackground)
        .clipShape(Capsule())
    }

    private func standingsCard(_ snapshot: ReplaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
            F1SectionHeader(title: "RACE ORDER", subtitle: "Top 10 from the official position feed at this replay moment")

            ForEach(snapshot.standings) { entry in
                HStack(spacing: 12) {
                    F1PositionBadge(position: entry.position)
                        .frame(width: 32)

                    Circle()
                        .fill(entry.driver.color)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.driver.fullName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(entry.driver.teamName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if entry.isSelected {
                        Text("ON MAP")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.f1Red)
                    } else {
                        Text(entry.driver.nameAcronym)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .f1InnerCard()
            }
        }
        .f1Card()
    }
}

private struct ReplayCircuitMapView: View {
    let trackPoints: [TrackMapPoint]
    let markers: [ReplayMarker]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.f1SecondaryBackground)

                trackPath(in: geometry.size)
                    .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))

                trackPath(in: geometry.size)
                    .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round))

                ForEach(markers) { marker in
                    VStack(spacing: 2) {
                        Text(marker.driver.nameAcronym)
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(marker.driver.color)
                            .clipShape(Capsule())

                        Circle()
                            .fill(marker.driver.color)
                            .frame(width: 10, height: 10)
                            .overlay {
                                Circle().stroke(Color.white, lineWidth: 2)
                            }
                    }
                    .position(position(for: marker.projectedPoint, in: geometry.size))
                }
            }
        }
    }

    private func trackPath(in size: CGSize) -> Path {
        let source = trackPoints.isEmpty ? [TrackMapPoint(20, 80), TrackMapPoint(80, 20)] : trackPoints
        return Path { path in
            guard let first = source.first else { return }
            path.move(to: position(for: first, in: size))
            for point in source.dropFirst() {
                path.addLine(to: position(for: point, in: size))
            }
            path.closeSubpath()
        }
    }

    private func position(for point: TrackMapPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x / 100 * size.width, y: point.y / 100 * size.height)
    }
}

private extension TimeInterval {
    var replayClock: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            TrackReplayView(race: Race(
                id: "1",
                raceName: "Bahrain Grand Prix",
                circuitName: "Bahrain International Circuit",
                country: "Bahrain",
                date: "2026-03-02",
                round: 1
            ))
            .padding()
        }
        .background(Color.f1Background)
    }
}
