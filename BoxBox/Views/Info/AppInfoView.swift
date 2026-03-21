import SwiftUI

struct AppInfoView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: F1Design.cardSpacing) {
                aboutCard
                legalCard
                privacyCard
                sourcesCard
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
            Text("BoxBox is a premium Formula 1 companion focused on race context, standings, replay and AI-powered race calls.")
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
            Text("All trademarks, team names and driver names belong to their respective owners.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text("Race Call predictions are provided for informational and entertainment purposes.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .f1Card()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            F1SectionHeader(title: "PRIVACY", subtitle: "What BoxBox stores")
            Text("BoxBox stores only lightweight local preferences needed for the app experience, such as your selected options and on-device settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("If you add an API key, it is kept locally on your device for your own use of Race Call.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .f1Card()
    }

    private var sourcesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            F1SectionHeader(title: "DATA SOURCES", subtitle: "Public racing data providers")
            VStack(alignment: .leading, spacing: 8) {
                sourceRow(name: "OpenF1", detail: "Session, telemetry, weather and race context")
                sourceRow(name: "Jolpica F1 API", detail: "Standings, qualifying and historical result context")
            }
        }
        .f1Card()
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
