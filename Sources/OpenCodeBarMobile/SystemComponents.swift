import SwiftUI

/// Shared building blocks for the Host → System dashboard and its category
/// pages. Keeping them here lets the main screen and the drill-in pages use the
/// same cards, rows and bars without duplicating layout code.

struct MobileSystemTile: View {
    let icon: String
    let tint: Color
    let label: String
    let value: String
    var caption: String?
    var showsDisclosure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if showsDisclosure {
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .card(padding: 11)
        .accessibilityElement(children: .combine)
    }
}

/// A destination card in the System dashboard's "Explore" grid.
struct MobileSystemNavTile: View {
    let icon: String
    let tint: Color
    let title: String
    let caption: String
    var badge: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tint.opacity(0.16))
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 30, height: 30)

                Spacer(minLength: 2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let badge, !badge.isEmpty {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                }
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .contentShape(Rectangle())
        .card(padding: 11)
        .accessibilityElement(children: .combine)
    }
}

struct MobileSystemRow: View {
    let label: String
    let value: String
    var monospaced = false
    var tint: Color = .secondary

    init(_ label: String, _ value: String, monospaced: Bool = false, tint: Color = .secondary) {
        self.label = label
        self.value = value
        self.monospaced = monospaced
        self.tint = tint
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .caption.weight(.medium))
                .foregroundStyle(tint == .secondary ? Color.primary : tint)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

struct MobileSystemBar: View {
    let fraction: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, fraction)) * geometry.size.width)
            }
        }
        .frame(height: height)
    }
}

/// Presentation helpers shared by the dashboard and category pages.
enum MobileSystemFormat {
    static func osLabel(_ host: SystemHost) -> String {
        var parts = [host.osName ?? host.platformName]
        if let version = host.osVersion { parts.append(version) }
        if let build = host.osBuild { parts.append("(\(build))") }
        return parts.joined(separator: " ")
    }

    static func batteryColor(_ battery: SystemBattery) -> Color {
        guard let percent = battery.percent else { return .secondary }
        if battery.charging == true { return Theme.accent }
        if percent <= 10 { return Theme.danger }
        if percent <= 25 { return Theme.warn }
        return Theme.accent
    }

    static func thermalPressureColor(_ pressure: String?) -> Color {
        switch pressure?.lowercased() {
        case "critical": return Theme.danger
        case "serious": return Theme.warn
        case "fair": return Theme.cacheRead
        default: return Theme.accent
        }
    }
}
