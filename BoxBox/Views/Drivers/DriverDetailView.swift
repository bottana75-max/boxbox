import SwiftUI

struct DriverDetailView: View {
    @State private var viewModel: DriverDetailViewModel

    init(driver: Driver) {
        _viewModel = State(initialValue: DriverDetailViewModel(driver: driver))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
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
                        .frame(width: 160, height: 160)
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
                    .frame(width: 166, height: 166)
            )

            VStack(spacing: 6) {
                Text("#\(viewModel.driver.driverNumber)")
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.black)
                    .foregroundStyle(viewModel.driver.teamColor)

                Text(viewModel.recentFormLabel.uppercased())
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(viewModel.driver.teamColor.opacity(0.22))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var driverPlaceholder: some View {
        Circle()
            .fill(viewModel.driver.teamColor.opacity(0.2))
            .frame(width: 160, height: 160)
            .overlay(
                Text(viewModel.driver.nameAcronym)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(viewModel.driver.teamColor)
            )
    }

    private var infoCard: some View {
        VStack(spacing: 16) {
            sectionHeader("DRIVER INFO")

            HStack(spacing: 24) {
                infoItem(label: "Acronym", value: viewModel.driver.nameAcronym)
                infoItem(label: "Number", value: "#\(viewModel.driver.driverNumber)")
                if !viewModel.driver.countryCode.isEmpty {
                    infoItem(label: "Country", value: viewModel.driver.countryCode)
                }
            }

            NavigationLink {
                TeamDetailView(teamName: viewModel.driver.teamName, teamColour: viewModel.driver.teamColour)
            } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(viewModel.driver.teamColor)
                        .frame(width: 4, height: 20)
                    Text(viewModel.driver.teamName)
                        .font(.headline)
                        .foregroundStyle(viewModel.driver.teamColor)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func careerSnapshotCard(_ profile: DriverProfile) -> some View {
        VStack(spacing: 12) {
            sectionHeader("CAREER SNAPSHOT")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statTile(label: "Debut", value: "\(profile.debutSeason)", accent: viewModel.driver.teamColor)
                statTile(label: "Titles", value: "\(profile.championships)", accent: viewModel.driver.teamColor)
                statTile(label: "Wins", value: "\(profile.careerWins)", accent: .yellow)
                statTile(label: "Podiums", value: "\(profile.careerPodiums)", accent: .white)
                statTile(label: "Poles", value: "\(profile.careerPoles)", accent: Color.f1Red)
                statTile(label: "Best result", value: profile.bestFinish, accent: viewModel.driver.teamColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                detailRow(title: "Nationality", value: profile.nationality)
                detailRow(title: "Born", value: "\(profile.dateOfBirth) · \(profile.placeOfBirth)")
                if let juniorTitle = profile.juniorTitle {
                    detailRow(title: "Junior CV", value: juniorTitle)
                }
            }
        }
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func driverStoryCard(_ profile: DriverProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("SCOUT NOTE")

            Text(profile.blurb)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var recentFormCard: some View {
        VStack(spacing: 12) {
            sectionHeader("RECENT FORM")

            HStack(spacing: 12) {
                formTile(label: "Avg finish", value: viewModel.averageFinishText)
                formTile(label: "Podiums", value: "\(viewModel.podiumFinishes)/5")
                formTile(label: "Points", value: "\(viewModel.pointsFinishes)/5")
            }
        }
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var recentResultsCard: some View {
        VStack(spacing: 12) {
            sectionHeader("LAST 5 RACES")

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 100)
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
                Text("No results available yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ForEach(viewModel.recentResults, id: \.id) { result in
                    resultRow(result)
                    if result.id != viewModel.recentResults.last?.id {
                        Divider().overlay(Color.f1SecondaryBackground)
                    }
                }
            }
        }
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(Color.f1Red)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoItem(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity)
    }

    private func statTile(label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
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
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func resultRow(_ result: DriverRaceResult) -> some View {
        HStack(spacing: 12) {
            Text("P\(result.position)")
                .font(.system(.title3, design: .rounded))
                .fontWeight(.black)
                .frame(width: 44)
                .foregroundStyle(positionColor(result.position, isDNF: result.isDNF))

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

            Text("\(Int(result.points)) pts")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func positionColor(_ position: Int, isDNF: Bool) -> Color {
        if isDNF { return .red }
        switch position {
        case 1: return .yellow
        case 2: return Color.white.opacity(0.75)
        case 3: return Color(red: 0.8, green: 0.5, blue: 0.2)
        default: return .white
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
