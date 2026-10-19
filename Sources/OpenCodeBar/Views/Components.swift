import SwiftUI

struct StatTile: View {
    let icon: String
    let tint: Color
    let label: String
    let value: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
    }
}

/// A dot with an expanding halo, used to mark sessions that are running.
struct PulsingDot: View {
    var color: Color = Theme.running
    var size: CGFloat = 8

    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: size, height: size)
                .scaleEffect(pulsing ? 2.4 : 1)
                .opacity(pulsing ? 0 : 1)
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .frame(width: size * 2, height: size * 2)
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(.tertiary)
            Text(title).font(.system(size: 12, weight: .medium))
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .card()
    }
}

struct LoadingState: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

struct TokenBreakdown: View {
    let tokens: TokenUsage

    private var parts: [(label: String, value: Double, color: Color)] {
        [
            ("Input", tokens.input, Theme.input),
            ("Output", tokens.output, Theme.output),
            ("Reasoning", tokens.reasoning, Theme.reasoning),
            ("Cache read", tokens.cache.read, Theme.cacheRead),
            ("Cache write", tokens.cache.write, Theme.cacheWrite),
        ]
    }

    var body: some View {
        let items = parts
        let total = max(items.reduce(0) { $0 + $1.value }, 1)
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                HStack(spacing: 1.5) {
                    ForEach(items.indices, id: \.self) { index in
                        let item = items[index]
                        Rectangle()
                            .fill(item.color)
                            .frame(width: item.value > 0 ? max(geo.size.width * CGFloat(item.value / total), 1.5) : 0)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 5
            ) {
                ForEach(items.indices, id: \.self) { index in
                    let item = items[index]
                    HStack(spacing: 6) {
                        Circle().fill(item.color).frame(width: 6, height: 6)
                        Text(item.label).font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Text(Fmt.compact(item.value)).font(.system(size: 10, weight: .medium)).monospacedDigit()
                    }
                }
            }
        }
        .card()
    }
}
