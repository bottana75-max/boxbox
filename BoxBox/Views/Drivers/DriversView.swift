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
                    F1LoadingView(message: "Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.error {
                    ErrorCard(message: error) {
                        Task { await viewModel.loadData() }
                    }
                    .padding()
                } else {
                    ScrollView {
                        VStack(spacing: F1Design.cardSpacing) {
                            overviewCard

                            if viewModel.isCompareMode {
                                compareBanner
                            }

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(viewModel.drivers) { driver in
                                    if viewModel.isCompareMode {
                                        Button {
                                            viewModel.toggleSelection(for: driver)
                                        } label: {
                                            driverCard(driver)
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        NavigationLink(value: driver) {
                                            driverCard(driver)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
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
            .refreshable {
                await viewModel.loadData()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(viewModel.isCompareMode ? "Done" : "Compare") {
                        viewModel.isCompareMode.toggle()
                        if !viewModel.isCompareMode {
                            viewModel.selectedDriverIDs.removeAll()
                        }
                    }
                    .fontWeight(.bold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if viewModel.isCompareMode {
                    compareFooter
                }
            }
        }
        .task {
            await viewModel.loadData()
        }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: F1Design.innerSpacing) {
            F1SectionHeader(title: "GRID INDEX", subtitle: "Every driver in a cleaner, more comparable card system")

            HStack(spacing: 10) {
                F1MetricTile(title: "Drivers", value: "\(viewModel.drivers.count)")
                F1MetricTile(title: "Compare", value: viewModel.isCompareMode ? "Live" : "Off")
                F1MetricTile(title: "Selected", value: "\(viewModel.selectedDriverIDs.count)")
            }
        }
        .f1Card(gradient: true, accent: .f1Red)
    }

    private var compareBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            F1SectionHeader(title: "COMPARE MODE", subtitle: "Pick any two drivers for a quick side-by-side")
            Text(viewModel.selectedDriverIDs.isEmpty ? "Select two drivers to build the head-to-head." : "Selected: \(viewModel.selectedDrivers.map(\.nameAcronym).joined(separator: " vs "))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .f1Card(accent: .f1Red)
    }

    private var compareFooter: some View {
        VStack(spacing: 10) {
            if viewModel.selectedDriverIDs.count < 2 {
                Text("Select \(2 - viewModel.selectedDriverIDs.count) more driver\((2 - viewModel.selectedDriverIDs.count) == 1 ? "" : "s") to compare")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            NavigationLink {
                DriverComparisonView(
                    leftDriver: viewModel.selectedDrivers.first ?? Driver(id: "preview-left", driverNumber: 1, fullName: "Driver Left", nameAcronym: "LFT", teamName: "Team Left", teamColour: "E8002D", countryCode: "", headshotUrl: nil),
                    rightDriver: viewModel.selectedDrivers.dropFirst().first ?? Driver(id: "preview-right", driverNumber: 2, fullName: "Driver Right", nameAcronym: "RGT", teamName: "Team Right", teamColour: "3671C6", countryCode: "", headshotUrl: nil)
                )
            } label: {
                Text("Compare Drivers")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.f1Red)
            .disabled(!viewModel.canCompare)
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(.ultraThinMaterial)
        }
        .background(Color.clear)
    }

    private func driverCard(_ driver: Driver) -> some View {
        let isSelected = viewModel.selectedDriverIDs.contains(driver.id)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                AsyncImage(url: driver.headshotUrl.flatMap { URL(string: $0) }) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 76, height: 76)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(driver.teamColor.opacity(0.45), lineWidth: 2)
                            )
                    case .failure:
                        driverPlaceholder(driver)
                    default:
                        driverPlaceholder(driver)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text("#\(driver.driverNumber)")
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.black)
                        .foregroundStyle(driver.teamColor)

                    if viewModel.isCompareMode {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? Color.f1Red : .secondary)
                    } else {
                        Text(driver.countryCode)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(driver.fullName)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 6) {
                    F1TeamDot(teamName: driver.teamName)
                    Text(driver.teamName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: F1Design.gridCardMinHeight, maxHeight: .infinity, alignment: .topLeading)
        .f1Card(accent: isSelected ? .f1Red : driver.teamColor.opacity(0.8))
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
            .frame(width: 76, height: 76)
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
