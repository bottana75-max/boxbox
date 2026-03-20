import SwiftUI

// MARK: - Design Tokens

enum F1Design {
    static let cornerRadius: CGFloat = 18
    static let innerCornerRadius: CGFloat = 14
    static let cardSpacing: CGFloat = 20
    static let innerSpacing: CGFloat = 14
    static let contentPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 24
    static let metricTileMinHeight: CGFloat = 82
    static let statPillMinHeight: CGFloat = 74
    static let listRowMinHeight: CGFloat = 72
    static let gridCardMinHeight: CGFloat = 188

    static let cardGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.05),
            Color.clear,
            Color.black.opacity(0.12)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroGradient = LinearGradient(
        colors: [
            Color.f1CardBackground,
            Color.f1SecondaryBackground.opacity(0.96),
            Color.black.opacity(0.82)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Podium / position colors
    static func positionColor(_ position: Int, isDNF: Bool = false) -> Color {
        if isDNF { return .red }
        switch position {
        case 1: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case 2: return Color(white: 0.75)
        case 3: return Color(red: 0.8, green: 0.5, blue: 0.2)
        default: return .white
        }
    }

    // Centralized team colour lookup by constructor name
    static func teamHex(for teamName: String) -> String {
        let name = teamName.lowercased()
        if name.contains("red bull") { return "3671C6" }
        if name.contains("ferrari") { return "E8002D" }
        if name.contains("mercedes") { return "27F4D2" }
        if name.contains("mclaren") { return "FF8000" }
        if name.contains("aston") { return "229971" }
        if name.contains("alpine") { return "FF87BC" }
        if name.contains("williams") { return "64C4FF" }
        if name.contains("rb") || name.contains("alpha") { return "6692FF" }
        if name.contains("sauber") || name.contains("stake") { return "52E252" }
        if name.contains("haas") { return "B6BABD" }
        return "8A8A8A"
    }

    static func teamColor(for teamName: String) -> Color {
        Color(hex: teamHex(for: teamName))
    }
}

// MARK: - Card Modifier

struct F1CardModifier: ViewModifier {
    var gradient: Bool = false
    var accent: Color? = nil

    func body(content: Content) -> some View {
        content
            .padding(F1Design.contentPadding)
            .background(
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: F1Design.cornerRadius, style: .continuous)
                        .fill(gradient ? AnyShapeStyle(F1Design.heroGradient) : AnyShapeStyle(Color.f1CardBackground))

                    RoundedRectangle(cornerRadius: F1Design.cornerRadius, style: .continuous)
                        .fill(F1Design.cardGradient)

                    if let accent {
                        LinearGradient(
                            colors: [accent.opacity(0.28), .clear],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                        .clipShape(RoundedRectangle(cornerRadius: F1Design.cornerRadius, style: .continuous))
                    }
                }
            )
            .overlay {
                RoundedRectangle(cornerRadius: F1Design.cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: F1Design.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 10)
    }
}

extension View {
    func f1Card(gradient: Bool = false, accent: Color? = nil) -> some View {
        modifier(F1CardModifier(gradient: gradient, accent: accent))
    }
}

// MARK: - Section Header

struct F1SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.f1Red)
                    .frame(width: 3, height: 14)
                Text(title)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color.f1Red)
                    .tracking(1)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 11)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Team Color Dot

struct F1TeamDot: View {
    let teamName: String
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(F1Design.teamColor(for: teamName))
            .frame(width: size, height: size)
    }
}

// MARK: - Loading View

struct F1LoadingView: View {
    var message: String = "Loading"

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)
                .tint(Color.f1Red)
            Text(message.uppercased())
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .tracking(1.2)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

// MARK: - Empty State View

struct F1EmptyView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.f1Subtle)
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }
}

// MARK: - Stat Pill

struct F1StatPill: View {
    let title: String
    let value: String
    var style: PillStyle = .standard

    enum PillStyle {
        case standard, subtle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: F1Design.statPillMinHeight, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(style == .standard ? Color.black.opacity(0.16) : Color.f1SecondaryBackground)
        .overlay {
            RoundedRectangle(cornerRadius: F1Design.innerCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: F1Design.innerCornerRadius, style: .continuous))
    }
}

// MARK: - Metric Tile

struct F1MetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: F1Design.metricTileMinHeight, maxHeight: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.f1SecondaryBackground)
        .overlay {
            RoundedRectangle(cornerRadius: F1Design.innerCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: F1Design.innerCornerRadius, style: .continuous))
    }
}

// MARK: - Inner Row Card

struct F1InnerCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(F1Design.contentPadding)
            .background(Color.f1SecondaryBackground)
            .overlay {
                RoundedRectangle(cornerRadius: F1Design.innerCornerRadius + 2, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: F1Design.innerCornerRadius + 2, style: .continuous))
    }
}

extension View {
    func f1InnerCard() -> some View {
        modifier(F1InnerCardModifier())
    }
}

// MARK: - Position Badge

struct F1PositionBadge: View {
    let position: Int
    var design: Font.Design = .rounded
    var size: Font.TextStyle = .title3

    var body: some View {
        Text("\(position)")
            .font(.system(size, design: design))
            .fontWeight(.black)
            .foregroundStyle(F1Design.positionColor(position))
    }
}

// MARK: - Helpers

struct F1Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
    }
}

struct F1ListRow<Content: View>: View {
    let accent: Color?
    @ViewBuilder var content: Content

    init(accent: Color? = nil, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            if let accent {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent)
                    .frame(width: 3)
            }
            content
        }
        .frame(maxWidth: .infinity, minHeight: F1Design.listRowMinHeight, alignment: .leading)
        .padding(.vertical, 4)
    }
}
