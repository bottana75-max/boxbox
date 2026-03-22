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
                        .init(label: "Career stage", left: leftProfile?.careerStage ?? "—", right: rightProfile?.careerStage ?? "—"),
                        .init(label: "Debut", left: stat(leftProfile?.debutSeason), right: stat(rightProfile?.debutSeason)),
                        .init(label: "Junior CV", left: leftProfile?.juniorTitle ?? "—", right: rightProfile?.juniorTitle ?? "—"),
                        .init(label: "Birthplace", left: leftProfile?.placeOfBirth ?? "—", right: rightProfile?.placeOfBirth ?? "—")
                    ]
                )
                comparisonCard(
                    title: "PROFILE",
                    rows: [
                        .init(label: "Team", left: leftDriver.teamName, right: rightDriver.teamName),
                        .init(label: "Number", left: leftDriver.driverNumber > 0 ? "#\(leftDriver.driverNumber)" : "—", right: rightDriver.driverNumber > 0 ? "#\(rightDriver.driverNumber)" : "—"),
                        .init(label: "Country", left: leftProfile?.nationality ?? leftDriver.countryCode, right: rightProfile?.nationality ?? rightDriver.countryCode),
                        .init(label: "Career stage", left: leftProfile?.careerStage ?? "—", right: rightProfile?.careerStage ?? "—")
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
            AsyncImage(url: driver.headshotUrl.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 74, height: 74)
                        .clipShape(Circle())
                default:
                    Circle()
                        .fill(driver.teamColor.opacity(0.15))
                        .frame(width: 74, height: 74)
                        .overlay(
                            Text(driver.nameAcronym)
                                .font(.headline)
                                .fontWeight(.black)
                                .foregroundStyle(driver.teamColor)
                        )
                }
            }
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
        let leftDebut = leftProfile?.debutSeason ?? 9999
        let rightDebut = rightProfile?.debutSeason ?? 9999

        if leftDebut != rightDebut {
            return leftDebut < rightDebut
                ? "\(leftDriver.nameAcronym) carries the longer F1 track record. Experience should matter if this matchup comes down to tyre management, racecraft and adapting through a messy weekend."
                : "\(rightDriver.nameAcronym) brings the deeper F1 sample. If both cars land in the same performance window, that experience usually sharpens the race-day calls."
        }

        if leftDriver.teamName != rightDriver.teamName {
            return "This one is context-heavy: different cars, different operating windows, different pressure. The smarter read is who extracts more relative to the package each weekend, not who simply starts with the faster machinery."
        }

        return "This one is tight on paper. The real separator is execution: qualifying sharpness, tyre life and whether either driver can keep the weekend inside the car's best window."
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
