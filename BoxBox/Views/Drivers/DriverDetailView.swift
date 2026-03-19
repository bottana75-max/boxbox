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

    // MARK: - Header

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

            Text("#\(viewModel.driver.driverNumber)")
                .font(.system(.largeTitle, design: .rounded))
                .fontWeight(.black)
                .foregroundStyle(viewModel.driver.teamColor)
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

    // MARK: - Info Card

    private var infoCard: some View {
        VStack(spacing: 16) {
            Text("DRIVER INFO")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.f1Red)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 24) {
                infoItem(label: "Acronym", value: viewModel.driver.nameAcronym)
                infoItem(label: "Number", value: "#\(viewModel.driver.driverNumber)")
                if !viewModel.driver.countryCode.isEmpty {
                    infoItem(label: "Country", value: viewModel.driver.countryCode)
                }
            }

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(viewModel.driver.teamColor)
                    .frame(width: 4, height: 20)
                Text(viewModel.driver.teamName)
                    .font(.headline)
                    .foregroundStyle(viewModel.driver.teamColor)
                Spacer()
            }
        }
        .padding()
        .background(Color.f1CardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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

    // MARK: - Recent Results Card

    private var recentResultsCard: some View {
        VStack(spacing: 12) {
            Text("RECENT RESULTS")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.f1Red)
                .frame(maxWidth: .infinity, alignment: .leading)

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
                ForEach(viewModel.recentResults) { result in
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
