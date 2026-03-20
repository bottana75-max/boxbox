import SwiftUI

struct TrackReplayView: View {
    @State private var viewModel: ReplayViewModel

    init(race: Race) {
        _viewModel = State(initialValue: ReplayViewModel(race: race))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: F1Design.cardSpacing) {
            replayHeader

            if viewModel.isLoading {
                F1LoadingView(message: "Loading replay timeline")
                    .frame(minHeight: 180)
                    .f1Card()
            } else if let error = viewModel.error {
                ErrorCard(message: error) {
                    Task { await viewModel.loadReplay() }
                }
            } else if let snapshot = viewModel.currentSnapshot {
                snapshotHero(snapshot)
                playbackControls
                standingsCard(snapshot)
            } else {
                F1EmptyView(
                    icon: "play.slash",
                    title: "Replay not available",
                    subtitle: "We only surface replay inside completed races from this season when position data is ready."
                )
                .f1Card()
            }
        }
        .task {
            await viewModel.loadReplay()
        }
    }

    private var replayHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            F1SectionHeader(title: "RACE REPLAY", subtitle: "Accurate position-based playback for this completed race")

            HStack(spacing: 10) {
                F1StatPill(title: "Scope", value: "Current season only", style: .subtle)
                F1StatPill(title: "Format", value: "Timeline", style: .subtle)
                F1StatPill(title: "Data", value: "Live positions", style: .subtle)
            }
        }
        .f1Card()
    }

    private func snapshotHero(_ snapshot: ReplaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(snapshot.elapsedTime.replayClock)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(snapshot.headline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if let leader = snapshot.standings.first {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("P1")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.f1Red)
                        Text(leader.driver.nameAcronym)
                            .font(.title3.weight(.black))
                            .foregroundStyle(leader.driver.color)
                        Text(leader.driver.teamName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            replayTimeline(snapshot)
        }
        .f1Card(gradient: true, accent: .f1Red)
    }

    private func replayTimeline(_ snapshot: ReplaySnapshot) -> some View {
        let topFive = Array(snapshot.standings.prefix(5))

        return VStack(alignment: .leading, spacing: 10) {
            Text("Front of the field")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(topFive) { entry in
                HStack(spacing: 10) {
                    F1PositionBadge(position: entry.position)
                        .frame(width: 28)

                    Circle()
                        .fill(entry.driver.color)
                        .frame(width: 8, height: 8)

                    Text(entry.driver.fullName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    if entry.delta != 0 {
                        Label(
                            entry.delta > 0 ? "+\(entry.delta)" : "\(entry.delta)",
                            systemImage: entry.delta > 0 ? "arrow.up" : "arrow.down"
                        )
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(entry.delta > 0 ? .green : .orange)
                    } else {
                        Text("=")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .f1InnerCard()
            }
        }
    }

    private var playbackControls: some View {
        VStack(spacing: 14) {
            Slider(value: Binding(
                get: { viewModel.progress },
                set: { viewModel.progress = $0 }
            ), in: 0...1)
            .tint(Color.f1Red)

            HStack(spacing: 18) {
                Button {
                    viewModel.step(by: -1)
                } label: {
                    Image(systemName: "backward.frame.fill")
                        .font(.title3)
                }

                Button {
                    viewModel.togglePlayback()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(Color.f1Red)
                        .clipShape(Circle())
                }

                Button {
                    viewModel.step(by: 1)
                } label: {
                    Image(systemName: "forward.frame.fill")
                        .font(.title3)
                }

                Spacer()

                Text(viewModel.currentSnapshot?.elapsedTime.replayClock ?? "--:--")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
        }
        .f1Card()
    }

    private func standingsCard(_ snapshot: ReplaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
            F1SectionHeader(title: "TOP 10 SNAPSHOT", subtitle: "Position changes between replay checkpoints")

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

                    Text(entry.driver.nameAcronym)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    if entry.delta != 0 {
                        Text(entry.delta > 0 ? "+\(entry.delta)" : "\(entry.delta)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(entry.delta > 0 ? .green : .orange)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
                .f1InnerCard()
            }
        }
        .f1Card()
    }
}

private extension TimeInterval {
    var replayClock: String {
        let totalSeconds = Int(self)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
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
