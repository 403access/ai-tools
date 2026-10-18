import AppKit
import SwiftUI

struct HeaderView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            logo

            VStack(alignment: .leading, spacing: 1) {
                Text("OpenCode")
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(state.connection.label)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if state.isRefreshing {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            }

            Button {
                Task { await state.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Refresh now")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Quit OpenCodeBar")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var logo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.accent, Theme.accent.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.black.opacity(0.75))
        }
        .frame(width: 28, height: 28)
    }

    private var statusColor: Color {
        switch state.connection {
        case .connected: return Theme.accent
        case .connecting: return Theme.warn
        case .offline: return Theme.danger
        }
    }
}
