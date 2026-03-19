import SwiftUI

struct DriverComparisonView: View {
    let leftDriver: Driver
    let rightDriver: Driver

    private var leftProfile: DriverProfile? { leftDriver.profile }
    private var rightProfile: DriverProfile? { rightDriver.profile }

    var body: some View {
        ScrollView {
            VStack(spacing: F1Design.cardSpacing) {
                headerCard
                comparisonCard(
                    title: "CAREER SNAPSHOT",
                    rows: [
                        .init(label: "Titles", left: stat(leftProfile?.championships), right: stat(rightProfile?.championships)),
                        .init(label: "Wins", left: stat(leftProfile?.careerWins), right: stat(rightProfile?.careerWins)),
                        .init(label: "Podiums", left: stat(leftProfile?.careerPodiums), right: stat(rightProfile?.careerPodiums)),
                        .init(label: "Poles", left: stat(leftProfile?.careerPoles), right: stat(rightProfile?.careerPoles)),
                        .init(label: "Debut", left: stat(leftProfile?.debutSeason), right: stat(rightProfile?.debutSeason))
                    ]
                )
                comparisonCard(
                    title: "PROFILE",
                    rows: [
                        .init(label: "Team", left: leftDriver.teamName, right: rightDriver.teamName),
                        .init(label: "Number", left: "#\(leftDriver.driverNumber)", right: "#\(rightDriver.driverNumber)"),
                        .init(label: "Country", left: leftProfile?.nationality ?? leftDriver.countryCode, right: rightProfile?.nationality ?? rightDriver.countryCode),
                        .init(label: "Best result", left: leftProfile?.bestFinish ?? "—", right: rightProfile?.bestFinish ?? "—")
                    ]
                )
                scoutVerdictCard
            }
            .padding()
        }
        .background(Color.f1Background)
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        HStack(spacing: 12) {
            driverHero(leftDriver)
            VStack(spacing: 8) {
                Text("VS")
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.black)
                    .foregroundStyle(Color.f1Red)
                Text("Side-by-side talent check")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 80)
            driverHero(rightDriver)
        }
        .f1Card(gradient: true)
    }

    private func driverHero(_ driver: Driver) -> some View {
        VStack(spacing: 10) {
            Circle()
                .fill(driver.teamColor.opacity(0.15))
                .frame(width: 74, height: 74)
                .overlay(
                    Text(driver.nameAcronym)
                        .font(.headline)
                        .fontWeight(.black)
                        .foregroundStyle(driver.teamColor)
                )
                .overlay(Circle().strokeBorder(driver.teamColor.opacity(0.35), lineWidth: 2))

            Text(driver.fullName)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(driver.teamName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    private func comparisonCard(title: String, rows: [ComparisonRow]) -> some View {
        VStack(spacing: 12) {
            F1SectionHeader(title: title)
            ForEach(rows) { row in
                HStack(spacing: 12) {
                    comparisonValue(row.left, color: leftDriver.teamColor)
                    Text(row.label)
                        .font(.caption)
                        .fontWeight(.heavy)
                        .foregroundStyle(.secondary)
                        .frame(width: 92)
                    comparisonValue(row.right, color: rightDriver.teamColor)
                }
                .f1InnerCard()
            }
        }
        .f1Card()
    }

    private var scoutVerdictCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            F1SectionHeader(title: "SCOUT VERDICT")
            Text(verdictText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .f1Card()
    }

    private func comparisonValue(_ value: String, color: Color) -> some View {
        Text(value)
            .font(.subheadline)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: F1Design.innerCornerRadius, style: .continuous))
    }

    private func stat<T>(_ value: T?) -> String {
        value.map { "\($0)" } ?? "—"
    }

    private var verdictText: String {
        let leftTitles = leftProfile?.championships ?? 0
        let rightTitles = rightProfile?.championships ?? 0
        let leftWins = leftProfile?.careerWins ?? 0
        let rightWins = rightProfile?.careerWins ?? 0

        if leftTitles != rightTitles {
            return leftTitles > rightTitles
                ? "\(leftDriver.nameAcronym) brings the heavier title résumé, but the interesting bit is whether current-team trajectory lets that edge still matter every weekend."
                : "\(rightDriver.nameAcronym) owns the stronger championship résumé. If the current car is close, that experience usually decides the sharper weekends."
        }

        if leftWins != rightWins {
            return leftWins > rightWins
                ? "\(leftDriver.nameAcronym) has converted front-running chances more often. The gap is about proven Sunday execution, not just raw speed."
                : "\(rightDriver.nameAcronym) has the better win conversion profile. If both cars land in the same window, that usually travels well."
        }

        return "This one is close on paper. The real separator is context: qualifying sharpness, tyre life and whether either driver is being flattered or exposed by the current car."
    }
}

private struct ComparisonRow: Identifiable {
    let id = UUID()
    let label: String
    let left: String
    let right: String
}

#Preview {
    NavigationStack {
        DriverComparisonView(
            leftDriver: Driver(id: "1", driverNumber: 4, fullName: "Lando Norris", nameAcronym: "NOR", teamName: "McLaren", teamColour: "FF8000", countryCode: "GBR", headshotUrl: nil),
            rightDriver: Driver(id: "2", driverNumber: 16, fullName: "Charles Leclerc", nameAcronym: "LEC", teamName: "Ferrari", teamColour: "E8002D", countryCode: "MON", headshotUrl: nil)
        )
    }
    .preferredColorScheme(.dark)
}
