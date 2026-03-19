import SwiftUI

// MARK: - Design Tokens

enum F1Design {
    static let cornerRadius: CGFloat = 16
    static let innerCornerRadius: CGFloat = 12
    static let cardSpacing: CGFloat = 20
    static let innerSpacing: CGFloat = 14
    static let contentPadding: CGFloat = 16

    // Podium / position colors
    static func positionColor(_ position: Int, isDNF: Bool = false) -> Color {
        if isDNF { return .red }
        switch position {
        case 1: return Color(red: 1.0, green: 0.84, blue: 0.0)   // gold
        case 2: return Color(white: 0.75)                          // silver
        case 3: return Color(red: 0.8, green: 0.5, blue: 0.2)     // bronze
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

    func body(content: Content) -> some View {
        content
            .padding(F1Design.contentPadding)
            .background(
                gradient
                    ? AnyShapeStyle(LinearGradient(
                        colors: [Color.f1CardBackground, Color.f1SecondaryBackground.opacity(0.7)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(Color.f1CardBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: F1Design.cornerRadius, style: .continuous))
    }
}

extension View {
    func f1Card(gradient: Bool = false) -> some View {
        modifier(F1CardModifier(gradient: gradient))
    }
}

// MARK: - Section Header

struct F1SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.f1Red)
                    .frame(width: 3, height: 12)
                Text(title)
                    .font(.caption)
                    .fontWeight(.heavy)
                    .foregroundStyle(Color.f1Red)
                    .tracking(0.8)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 9) // align with text after accent bar
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
                .foregroundStyle(Color.f1SecondaryBackground)
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }
}

// MARK: - Stat Pill (reusable compact metric)

struct F1StatPill: View {
    let title: String
    let value: String
    var style: PillStyle = .standard

    enum PillStyle {
        case standard, subtle
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.4)
            Text(value)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            style == .standard
                ? Color.black.opacity(0.18)
                : Color.f1SecondaryBackground
        )
        .clipShape(RoundedRectangle(cornerRadius: F1Design.innerCornerRadius, style: .continuous))
    }
}

// MARK: - Metric Tile (label on top, value below)

struct F1MetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.4)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.f1SecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: F1Design.innerCornerRadius, style: .continuous))
    }
}

// MARK: - Inner Row Card (used for sub-items within a card)

struct F1InnerCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(F1Design.contentPadding)
            .background(Color.f1SecondaryBackground)
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
