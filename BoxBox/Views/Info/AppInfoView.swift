import SwiftUI

struct AppInfoView: View {
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let legalURL = URL(string: "https://bottana75-max.github.io/boxbox/")!
    private let supportEmail = "an.murru@gmail.com"

    var body: some View {
        ScrollView {
            VStack(spacing: F1Design.cardSpacing) {
                aboutCard
                legalCard
                privacyCard
                sourcesCard
                contactCard
                footerCard
            }
            .padding()
        }
        .background(Color.f1Background)
        .navigationTitle("Info")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            F1SectionHeader(title: "ABOUT", subtitle: "Independent F1 companion")
            Text("BoxBox is an independent Formula 1 companion app for race context, standings, replay and AI-powered Race Call briefings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Built to make a race weekend easier to read, not noisier.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .f1Card()
    }

    private var legalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            F1SectionHeader(title: "LEGAL", subtitle: "Independence and trademark notice")
            Text("BoxBox is an independent app and is not affiliated with, endorsed by, or sponsored by Formula 1, FIA, or any Formula 1 team.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("All trademarks, team names, driver names, and related marks belong to their respective owners.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text("Race Call outputs are provided for informational and entertainment purposes and do not constitute betting advice.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .f1Card()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            F1SectionHeader(title: "PRIVACY", subtitle: "What BoxBox stores")
            Text("BoxBox is designed to minimize personal data handling and stores lightweight local settings on your device to support the app experience.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("When you use Race Call, the app may send structured public motorsport context to OpenAI. No personal profile information is intentionally included.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Divider().background(Color.white.opacity(0.08))

            Link(destination: legalURL) {
                Label("Privacy Policy & Terms", systemImage: "lock.shield")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.f1Red)
            }
        }
        .f1Card()
    }

    private var sourcesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            F1SectionHeader(title: "DATA SOURCES", subtitle: "Public racing data providers")
            VStack(alignment: .leading, spacing: 8) {
                sourceRow(name: "OpenF1", detail: "Telemetry, positions, weather and session context")
                sourceRow(name: "Jolpica F1 API", detail: "Standings, results, qualifying and schedule")
                sourceRow(name: "OpenAI", detail: "Race Call generation")
                sourceRow(name: "Bacinger F1 Circuits", detail: "Track layout reference data where applicable")
            }
        }
        .f1Card()
    }

    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            F1SectionHeader(title: "SUPPORT", subtitle: "Get in touch")
            Link(destination: URL(string: "mailto:\(supportEmail)")!) {
                Label(supportEmail, systemImage: "envelope")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.f1Red)
            }
        }
        .f1Card()
    }

    private var footerCard: some View {
        VStack(spacing: 6) {
            Text("BoxBox v\(appVersion)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("© 2026 Andrea Murru · All rights reserved")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func sourceRow(name: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        AppInfoView()
            .preferredColorScheme(.dark)
    }
}
