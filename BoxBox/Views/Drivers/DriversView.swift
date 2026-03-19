import SwiftUI

struct DriversView: View {
    @State private var viewModel = DriversViewModel()

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    F1LoadingView(message: "Loading drivers")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.error {
                    ErrorCard(message: error) {
                        Task { await viewModel.loadData() }
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(viewModel.drivers) { driver in
                                NavigationLink(value: driver) {
                                    driverCard(driver)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                    .navigationDestination(for: Driver.self) { driver in
                        DriverDetailView(driver: driver)
                    }
                }
            }
            .background(Color.f1Background)
            .navigationTitle("Drivers")
        }
        .task {
            await viewModel.loadData()
        }
    }

    private func driverCard(_ driver: Driver) -> some View {
        VStack(spacing: 12) {
            AsyncImage(url: driver.headshotUrl.flatMap { URL(string: $0) }) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(driver.teamColor.opacity(0.4), lineWidth: 2)
                        )
                case .failure:
                    driverPlaceholder(driver)
                default:
                    driverPlaceholder(driver)
                }
            }

            VStack(spacing: 4) {
                Text(driver.fullName)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(driver.teamName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack {
                Text("#\(driver.driverNumber)")
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.black)
                    .foregroundStyle(driver.teamColor)

                Spacer()

                Text(driver.countryCode)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: F1Design.cornerRadius, style: .continuous)
                .fill(Color.f1CardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: F1Design.cornerRadius, style: .continuous)
                        .strokeBorder(driver.teamColor.opacity(0.2), lineWidth: 1)
                )
        )
        .overlay(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 2)
                .fill(driver.teamColor)
                .frame(width: 3, height: 24)
                .padding(.top, 12)
                .padding(.trailing, 12)
        }
    }

    private func driverPlaceholder(_ driver: Driver) -> some View {
        Circle()
            .fill(driver.teamColor.opacity(0.15))
            .frame(width: 80, height: 80)
            .overlay(
                Text(driver.nameAcronym)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(driver.teamColor)
            )
            .overlay(
                Circle()
                    .strokeBorder(driver.teamColor.opacity(0.3), lineWidth: 2)
            )
    }
}

#Preview {
    DriversView()
        .preferredColorScheme(.dark)
}
