import SwiftUI

struct ScheduleView: View {
    @State private var viewModel = ScheduleViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    F1LoadingView(message: "Loading...")
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
                                        .f1Card(accent: race.round == viewModel.nextRaceRound ? .f1Red : nil)
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
            .navigationTitle("Schedule")
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
            F1SectionHeader(title: "SEASON FLOW", subtitle: "Every round in one clean race-weekend feed")

            HStack(spacing: 10) {
                F1MetricTile(title: "Rounds", value: "\(viewModel.races.count)")
                F1MetricTile(title: "Completed", value: "\(viewModel.races.filter(\.isPast).count)")
                F1MetricTile(title: "Next", value: viewModel.races.first(where: { $0.round == viewModel.nextRaceRound })?.raceName ?? "TBD")
            }
        }
        .f1Card(gradient: true, accent: .f1Red)
    }

    private func raceRow(_ race: Race) -> some View {
        let isNext = race.round == viewModel.nextRaceRound
        let accent = isNext ? Color.f1Red : (race.isPast ? Color.f1Subtle.opacity(0.7) : Color.f1SecondaryBackground)

        return F1ListRow(accent: accent) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("ROUND \(race.round)")
                                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                .tracking(0.8)
                                .foregroundStyle(isNext ? Color.f1Red : .secondary)

                            if isNext {
                                tag("Next", color: .f1Red)
                            } else if race.isPast {
                                tag("Done", color: .green.opacity(0.8))
                            }
                        }

                        Text(race.raceName)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)

                        Text(race.circuitName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)
                    F1Chevron()
                }

                HStack(spacing: 16) {
                    Label(race.country, systemImage: "mappin.and.ellipse")
                    Label(race.formattedDate, systemImage: "calendar")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .opacity(race.isPast && !isNext ? 0.72 : 1.0)
        }
    }

    private func tag(_ title: String, color: Color) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .clipShape(Capsule())
    }
}

#Preview {
    ScheduleView()
        .preferredColorScheme(.dark)
}
