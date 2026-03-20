import SwiftUI

struct TrackReplayView: View {
    @State private var viewModel = ReplayViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    F1LoadingView(message: "Loading race sessions")
                } else if let error = viewModel.error, viewModel.selectedSession == nil {
                    ErrorCard(message: error) {
                        Task { await viewModel.loadSessions() }
                    }
                } else if viewModel.selectedSession == nil {
                    sessionPicker
                } else {
                    replayContent
                }
            }
            .background(Color.f1Background)
            .navigationTitle("Race Replay")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task {
            await viewModel.loadSessions()
        }
    }

    // MARK: - Session Picker

    @ViewBuilder
    private var sessionPicker: some View {
        ScrollView {
            VStack(spacing: F1Design.cardSpacing) {
                VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
                    F1SectionHeader(title: "SELECT RACE")

                    if viewModel.availableSessions.isEmpty {
                        F1EmptyView(
                            icon: "flag.checkered",
                            title: "No completed races yet",
                            subtitle: "Race replays will appear here after each Grand Prix."
                        )
                        .frame(minHeight: 140)
                    } else {
                        ForEach(viewModel.availableSessions) { session in
                            Button {
                                Task { await viewModel.selectSession(session) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(Color.f1Red)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(session.raceName)
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                        Text(session.circuitName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Text(session.date.formatted(.dateTime.day().month(.abbreviated)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .f1InnerCard()
                            }
                        }
                    }
                }
                .f1Card()
            }
            .padding()
        }
    }

    // MARK: - Replay Content

    @ViewBuilder
    private var replayContent: some View {
        if viewModel.isLoadingTrack {
            VStack(spacing: 16) {
                F1LoadingView(message: "Downloading telemetry")
                Text("This may take a moment — loading position data for all drivers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        } else if let error = viewModel.error {
            ErrorCard(message: error) {
                if let session = viewModel.selectedSession {
                    Task { await viewModel.selectSession(session) }
                }
            }
        } else {
            ScrollView {
                VStack(spacing: F1Design.cardSpacing) {
                    raceHeader
                    driverSelector
                    trackMap
                    playbackControls
                    liveStandings
                }
                .padding()
            }
        }
    }

    // MARK: - Header

    private var raceHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.selectedSession?.raceName ?? "")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    Text(viewModel.selectedSession?.circuitName ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    viewModel.pause()
                    viewModel.selectedSession = nil
                    viewModel.locationData = [:]
                    viewModel.positionData = [:]
                    viewModel.drivers = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .f1Card()
    }

    // MARK: - Driver Selector

    private var driverSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                F1SectionHeader(title: "DRIVERS")
                Spacer()
                Button("All") { viewModel.setAllVisible(true) }
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.f1SecondaryBackground)
                    .clipShape(Capsule())
                Button("Top 5") { viewModel.setTopNVisible(5) }
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.f1SecondaryBackground)
                    .clipShape(Capsule())
                Button("None") { viewModel.setAllVisible(false) }
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.f1SecondaryBackground)
                    .clipShape(Capsule())
            }
            .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.drivers) { driver in
                        Button { viewModel.toggleDriver(driver) } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(driver.color)
                                    .frame(width: 10, height: 10)
                                Text(driver.nameAcronym)
                                    .font(.caption2.weight(.bold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(driver.isVisible ? driver.color.opacity(0.25) : Color.f1SecondaryBackground)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(driver.isVisible ? driver.color : Color.clear, lineWidth: 1)
                            )
                        }
                        .foregroundStyle(.white)
                    }
                }
            }
        }
        .f1Card()
    }

    // MARK: - Track Map

    private var trackMap: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height

            ZStack {
                RoundedRectangle(cornerRadius: F1Design.innerCornerRadius)
                    .fill(Color.f1SecondaryBackground)

                // Draw track path from location data (use first driver with data as outline)
                if let firstDriver = viewModel.visibleDrivers.first,
                   let points = viewModel.locationData[firstDriver.driverNumber], !points.isEmpty {
                    let trackPath = Path { path in
                        let step = max(1, points.count / 500)
                        var first = true
                        for i in stride(from: 0, to: points.count, by: step) {
                            let p = viewModel.normalizedPoint(x: points[i].x, y: points[i].y)
                            let screenPt = CGPoint(
                                x: (p.x / 100) * w * 0.85 + w * 0.075,
                                y: (p.y / 100) * h * 0.85 + h * 0.075
                            )
                            if first {
                                path.move(to: screenPt)
                                first = false
                            } else {
                                path.addLine(to: screenPt)
                            }
                        }
                        path.closeSubpath()
                    }

                    trackPath
                        .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }

                // Driver dots
                let positions = viewModel.currentDriverPositions
                ForEach(viewModel.visibleDrivers) { driver in
                    if let pos = positions[driver.driverNumber] {
                        let screenX = (pos.x / 100) * w * 0.85 + w * 0.075
                        let screenY = (pos.y / 100) * h * 0.85 + h * 0.075

                        ZStack {
                            Circle()
                                .fill(driver.color)
                                .frame(width: 14, height: 14)
                            Text(driver.nameAcronym)
                                .font(.system(size: 6, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .position(x: screenX, y: screenY)
                        .animation(.linear(duration: 0.016), value: pos.x)
                        .animation(.linear(duration: 0.016), value: pos.y)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: F1Design.cornerRadius))
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        VStack(spacing: 10) {
            // Scrubber
            HStack(spacing: 8) {
                Text(viewModel.elapsedTimeString)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)

                Slider(value: Binding(
                    get: { viewModel.progress },
                    set: { viewModel.progress = $0 }
                ), in: 0...1)
                .tint(Color.f1Red)

                Text(viewModel.totalTimeString)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .leading)
            }

            // Buttons
            HStack(spacing: 20) {
                // Rewind to start
                Button {
                    if let range = viewModel.timeRange {
                        viewModel.seek(to: range.lowerBound)
                    }
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.title3)
                }

                // Play / Pause
                Button { viewModel.togglePlayback() } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .frame(width: 44, height: 44)
                        .background(Color.f1Red)
                        .clipShape(Circle())
                }

                // Speed picker
                Menu {
                    ForEach([1.0, 2.0, 4.0, 8.0], id: \.self) { speed in
                        Button("\(Int(speed))x") {
                            viewModel.playbackSpeed = speed
                        }
                    }
                } label: {
                    Text("\(Int(viewModel.playbackSpeed))x")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.f1SecondaryBackground)
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(.white)
        }
        .f1Card()
    }

    // MARK: - Live Standings

    private var liveStandings: some View {
        VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
            F1SectionHeader(title: "LIVE STANDINGS")

            let sorted = viewModel.sortedDriversByRank
            let ranks = viewModel.currentDriverRanks

            ForEach(sorted.prefix(10)) { driver in
                HStack(spacing: 12) {
                    let rank = ranks[driver.driverNumber] ?? 0
                    F1PositionBadge(position: rank)
                        .frame(width: 34)

                    Circle()
                        .fill(driver.color)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(driver.fullName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(driver.teamName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(driver.nameAcronym)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .f1InnerCard()
            }
        }
        .f1Card()
    }
}

#Preview {
    TrackReplayView()
}
