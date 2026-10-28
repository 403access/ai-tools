import SwiftUI

/// In-app notice that the hub published a newer build. iOS cannot install
/// silently, so the button opens the hub's install page in Safari, where the
/// system confirmation takes over.
struct OtaUpdateBanner: View {
    let artifact: OtaArtifact
    let onInstall: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.16))
                    .frame(width: 32, height: 32)
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Update available")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(artifact.buildLabel) is ready to install")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button("Install", action: onInstall)
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityHint("Opens the install page in Safari")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss update")
        }
        .padding(10)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(MobileTheme.border)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }
}
