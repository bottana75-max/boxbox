import SwiftUI

struct DriverDetailView: View {
    @State private var viewModel: DriverDetailViewModel

    init(driver: Driver) {
        _viewModel = State(initialValue: DriverDetailViewModel(driver: driver))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: F1Design.cardSpacing) {
                headerSection
                infoCard
                if let profile = viewModel.profile {
                    careerSnapshotCard(profile)
                    driverStoryCard(profile)
                }
                recentFormCard
                recentResultsCard
            }
            .padding()
        }
        .background(Color.f1Background)
        .navigationTitle(viewModel.driver.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Race.self) { race in
            RaceDetailView(race: race)
        }
        .task {
            await viewModel.loadResults()
        }
    }

    private var headerSection: some View {
        VStack(spacing: 16) {
            AsyncImage(url: viewModel.driver.headshotUrl.flatMap { URL(string: $0) }) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 148, height: 148)
                        .clipShape(Circle())
                case .failure:
                    driverPlaceholder
                default:
                    driverPlaceholder
                }
            }
            .overlay(
                Circle()
                    .strokeBorder(viewModel.driver.teamColor, lineWidth: 3)
                    .frame(width: 154, height: 154)
            )

            VStack(spacing: 6) {
                if viewModel.driver.driverNumber > 0 {
                    Text("#\(viewModel.driver.driverNumber)")
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.black)
                        .foregroundStyle(viewModel.driver.teamColor)
                }

                Text(viewModel.recentFormLabel.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(viewModel.driver.teamColor.opacity(0.22))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .f1Card(gradient: true, accent: viewModel.driver.teamColor)
    }

    private var driverPlaceholder: some View {
        Circle()
            .fill(viewModel.driver.teamColor.opacity(0.15))
            .frame(width: 148, height: 148)
            .overlay(
                Text(viewModel.driver.nameAcronym)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(viewModel.driver.teamColor)
            )
    }

    private var infoCard: some View {
        VStack(spacing: 16) {
            F1SectionHeader(title: "DRIVER INFO")

            HStack(spacing: 12) {
                infoItem(label: "Acronym", value: viewModel.driver.nameAcronym)
                if viewModel.driver.driverNumber > 0 {
                    infoItem(label: "Number", value: "#\(viewModel.driver.driverNumber)")
                }
                if !viewModel.driver.countryCode.isEmpty {
                    infoItem(label: "Country", value: viewModel.driver.countryCode)
                }
            }

            NavigationLink {
                TeamDetailView(teamName: viewModel.driver.teamName, teamColour: viewModel.driver.teamColour)
            } label: {
                F1ListRow(accent: viewModel.driver.teamColor) {
                    HStack(spacing: 8) {
                        Text(viewModel.driver.teamName)
                            .font(.headline)
                            .foregroundStyle(viewModel.driver.teamColor)
                        Spacer()
                        F1Chevron()
                    }
                }
                .f1InnerCard()
            }
            .buttonStyle(.plain)
        }
        .f1Card()
    }

    private func careerSnapshotCard(_ profile: DriverProfile) -> some View {
        VStack(spacing: 12) {
            F1SectionHeader(title: "CAREER SNAPSHOT", subtitle: "Stable bio details only")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statTile(label: "Debut", value: "\(profile.debutSeason)", accent: viewModel.driver.teamColor)
                statTile(label: "Career stage", value: profile.careerStage, accent: .white)
            }

            VStack(alignment: .leading, spacing: 8) {
                detailRow(title: "Nationality", value: profile.nationality)
                detailRow(title: "Born", value: "\(profile.dateOfBirth) · \(profile.placeOfBirth)")
                if let juniorTitle = profile.juniorTitle {
                    detailRow(title: "Junior CV", value: juniorTitle)
                }
            }
        }
        .f1Card()
    }

    private func driverStoryCard(_ profile: DriverProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            F1SectionHeader(title: "SCOUT NOTE")

            Text(profile.blurb)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .f1Card()
    }

    private var recentFormCard: some View {
        VStack(spacing: 12) {
            F1SectionHeader(title: "RECENT FORM")

            HStack(spacing: 12) {
                formTile(label: "Avg finish", value: viewModel.averageFinishText)
                formTile(label: "Podiums", value: "\(viewModel.podiumFinishes)/5")
                formTile(label: "Points", value: "\(viewModel.pointsFinishes)/5")
            }
        }
        .f1Card()
    }

    private var recentResultsCard: some View {
        VStack(spacing: 12) {
            F1SectionHeader(title: "LAST 5 RACES", subtitle: "Tap a race for the full weekend page")

            if viewModel.isLoading {
                F1LoadingView(message: "Loading results")
                    .frame(minHeight: 100)
            } else if let error = viewModel.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 60)
            } else if viewModel.recentResults.isEmpty {
                F1EmptyView(icon: "flag.checkered", title: "No results available yet")
            } else {
                ForEach(viewModel.recentResults, id: \.id) { result in
                    NavigationLink(value: result.race) {
                        resultRow(result)
                            .f1InnerCard()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .f1Card()
    }

    private func infoItem(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.f1SecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: F1Design.innerCornerRadius, style: .continuous))
    }

    private func statTile(label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.4)
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.75)
            Capsule()
                .fill(accent)
                .frame(width: 28, height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.f1SecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: F1Design.innerCornerRadius + 2, style: .continuous))
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.4)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formTile(label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(.title2, design: .rounded))
                .fontWeight(.black)
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.f1SecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: F1Design.innerCornerRadius, style: .continuous))
    }

    private func resultRow(_ result: DriverRaceResult) -> some View {
        F1ListRow(accent: viewModel.driver.teamColor) {
            HStack(spacing: 12) {
                Text("P\(result.position)")
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.black)
                    .frame(width: 44)
                    .foregroundStyle(F1Design.positionColor(result.position, isDNF: result.isDNF))

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.shortName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if result.isDNF {
                        Text(result.status)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(result.points)) pts")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    F1Chevron()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        DriverDetailView(driver: Driver(
            id: "1-VER",
            driverNumber: 1,
            fullName: "Max VERSTAPPEN",
            nameAcronym: "VER",
            teamName: "Red Bull Racing",
            teamColour: "3671C6",
            countryCode: "NED",
            headshotUrl: nil
        ))
    }
    .preferredColorScheme(.dark)
}
