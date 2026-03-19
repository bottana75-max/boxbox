import SwiftUI

struct ScheduleView: View {
    @State private var viewModel = ScheduleViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    F1LoadingView(message: "Loading calendar")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.error {
                    ErrorCard(message: error) {
                        Task { await viewModel.loadData() }
                    }
                    .padding()
                } else {
                    List(viewModel.races) { race in
                        NavigationLink(value: race) {
                            raceRow(race)
                        }
                        .listRowBackground(Color.f1CardBackground)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
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

    private func raceRow(_ race: Race) -> some View {
        let isNext = race.round == viewModel.nextRaceRound

        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isNext ? Color.f1Red : race.isPast ? Color.f1Subtle.opacity(0.5) : Color.f1SecondaryBackground)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("R\(race.round)")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(isNext ? Color.f1Red : .secondary)

                    if isNext {
                        Text("NEXT")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.6)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.f1Red)
                            .clipShape(Capsule())
                    }
                }

                Text(race.raceName)
                    .font(.headline)
                    .foregroundStyle(race.isPast && !isNext ? .secondary : .primary)

                HStack(spacing: 16) {
                    Label(race.country, systemImage: "mappin")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label(race.formattedDate, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if race.isPast {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green.opacity(0.7))
            }
        }
        .padding(.vertical, 4)
        .opacity(race.isPast && !isNext ? 0.6 : 1.0)
    }
}

#Preview {
    ScheduleView()
        .preferredColorScheme(.dark)
}
