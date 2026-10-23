import SwiftUI

extension SessionDetailView {
    // MARK: - Pieces

    var loadEarlierButton: some View {
        VStack(spacing: 4) {
            Button {
                Task { await loadEarlier() }
            } label: {
                HStack(spacing: 5) {
                    if isLoadingEarlier {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.down")
                            .font(.caption.weight(.bold))
                    }
                    Text(isLoadingEarlier ? "Loading…" : "Load earlier")
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .disabled(isLoadingEarlier)

            if let earlierError {
                Text(earlierError)
                    .font(.caption2)
                    .foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // Reaching the end of the loaded window pages the next one in, so long
        // sessions scroll without a tap. The button stays for accessibility.
        .onAppear {
            Task { await loadEarlier() }
        }
    }

    func loading(_ message: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(message).font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    func errorState(_ message: String, title: String = "Couldn't load this session") -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(Theme.warn)
            Text(title).font(.subheadline.weight(.medium))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await loadLatest() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .card()
    }

    func scrollToTop(_ proxy: ScrollViewProxy, animated: Bool) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 40_000_000)
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(topAnchor, anchor: .top)
                }
            } else {
                proxy.scrollTo(topAnchor, anchor: .top)
            }
        }
    }
}
