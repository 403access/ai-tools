import SwiftUI
import UIKit

/// The app mark and wordmark used in the Live navigation bar. It mirrors the
/// small gradient tile at the top of the Mac panel.
struct MobileBrandTitle: View {
    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.accent, Theme.accent.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.black.opacity(0.75))
            }
            .frame(width: 23, height: 23)

            Text("OpenCode")
                .font(.system(size: 15, weight: .semibold))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("OpenCode")
    }
}

/// A compact status/notice row used across the mobile tabs.
struct NoticeRow: View {
    let icon: String
    let message: String
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .card(padding: 12)
    }
}

/// Connection state + running count, shown in navigation bars and settings.
struct ConnectionPill: View {
    let connection: MobileStore.Connection
    let activeCount: Int

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibility)
    }

    private var label: String {
        switch connection {
        case .connected:
            return activeCount > 0 ? "\(activeCount) running" : "Connected"
        case .connecting:
            return "Connecting"
        case .offline:
            return "Offline"
        case .disabled:
            return "Not configured"
        }
    }

    private var accessibility: String {
        switch connection {
        case .connected(let version): return "Connected to hub, OpenCode \(version)"
        case .connecting: return "Connecting to hub"
        case .offline(let reason): return "Offline: \(reason)"
        case .disabled: return "Hub not configured"
        }
    }

    private var color: Color {
        switch connection {
        case .connected: return Theme.accent
        case .connecting: return Theme.warn
        case .offline: return Theme.danger
        case .disabled: return .secondary
        }
    }
}

/// Shown on the Live and Projects tabs when no hub has been paired yet.
struct SetupPrompt: View {
    var title: String = "Connect to your Mac"
    var message: String = "Run `make hub` on your Mac, then open Settings and paste the hub URL and token — or tap the pairing link the hub prints at startup."

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "desktopcomputer.and.iphone")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            NavigationLink {
                SettingsView()
            } label: {
                Label("Open Settings", systemImage: "gearshape")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 2)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .card(padding: 18)
    }
}

/// A labelled row with a monospaced value and a copy button, used for paths.
struct CopyableRow: View {
    let label: String
    let value: String
    var icon: String = "folder"

    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            Button {
                UIPasteboard.general.string = value
                copied = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(copied ? Theme.accent : .secondary)
            .accessibilityLabel(copied ? "Copied" : "Copy \(label)")
        }
    }
}

extension UIPasteboard {
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}

/// Rounded tile for a project's own app icon. Falls back to a folder glyph
/// when the hub cannot find artwork in the project folder.
struct ProjectIconTile: View {
    let image: UIImage?
    var running = false
    var isLoading = false
    var size: CGFloat = 34

    private var tint: Color { running ? Theme.running : Theme.accent }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(tint.opacity(image == nil ? 0.14 : 0.06))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.07)
            } else {
                Image(systemName: running ? "bolt.fill" : "folder.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if running, image != nil {
                Circle()
                    .fill(Theme.running)
                    .frame(width: size * 0.24, height: size * 0.24)
                    .padding(size * 0.03)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.55)
                    .padding(1)
                    .background(.ultraThinMaterial, in: Circle())
                    .offset(x: 1, y: -1)
            }
        }
        .accessibilityHidden(true)
    }
}
