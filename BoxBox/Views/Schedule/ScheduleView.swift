import SwiftUI

struct ScheduleView: View {
    @State private var viewModel = ScheduleViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.error {
                    ErrorCard(message: error) {
                        Task { await viewModel.loadData() }
                    }
                    .padding()
                } else {
                    List(viewModel.races) { race in
                        raceRow(race)
                            .listRowBackground(Color.f1CardBackground)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.f1Background)
            .navigationTitle("Schedule")
        }
        .task {
            await viewModel.loadData()
        }
    }

    private func raceRow(_ race: Race) -> some View {
        let isNext = race.round == viewModel.nextRaceRound

        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(isNext ? Color.f1Red : race.isPast ? Color.gray.opacity(0.3) : Color.f1SecondaryBackground)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("R\(race.round)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(isNext ? Color.f1Red : .secondary)

                    if isNext {
                        Text("NEXT")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
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
