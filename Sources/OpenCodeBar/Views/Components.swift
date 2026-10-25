#if canImport(AppKit)
import AppKit
typealias AppIconImage = NSImage
#elseif canImport(UIKit)
import UIKit
typealias AppIconImage = UIImage
#endif
import SwiftUI

// MARK: - Motion

extension AnyTransition {
    /// New feed rows slide down from the top and fade in; removals fade out.
    static var recentInsertion: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        )
    }
}

extension Animation {
    /// Shared spring for content that arrives at the top of a list.
    static var recentInsertion: Animation {
        .spring(response: 0.38, dampingFraction: 0.82, blendDuration: 0.1)
    }
}

/// Animates feed changes after the list has populated, so the initial load does
/// not cascade in but later inserts still slide down from the top.
private struct RecentInsertionAnimation: ViewModifier {
    let ids: [String]
    @State private var hasSeenContent = false
    @State private var isReady = false

    func body(content: Content) -> some View {
        content
            .animation(isReady ? .recentInsertion : nil, value: ids)
            .onAppear {
                guard !ids.isEmpty else { return }
                hasSeenContent = true
                enableAfterSettling()
            }
            .onChange(of: ids) { _, newIDs in
                guard !newIDs.isEmpty else { return }
                if hasSeenContent {
                    isReady = true
                } else {
                    hasSeenContent = true
                    enableAfterSettling()
                }
            }
    }

    private func enableAfterSettling() {
        Task { @MainActor in
            // Let the first population lay out before enabling motion.
            try? await Task.sleep(nanoseconds: 200_000_000)
            isReady = true
        }
    }
}

extension View {
    func animateRecentInsertion(ids: [String]) -> some View {
        modifier(RecentInsertionAnimation(ids: ids))
    }
}

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

/// Rounded tile for a project's own app icon. Falls back to a folder glyph when
/// the hub cannot find artwork in the project folder.
#if canImport(AppKit)
struct ProjectIconView: View {
    let image: NSImage?
    var running = false
    var size: CGFloat = 30

    private var tint: Color { running ? Theme.running : Theme.accent }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(tint.opacity(image == nil ? 0.14 : 0.06))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.07)
            } else {
                Image(systemName: running ? "bolt.fill" : "folder.fill")
                    .font(.system(size: size * 0.4, weight: .semibold))
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
        .accessibilityHidden(true)
    }
}
#endif

/// Loads one installed app's icon from the hub, keyed by its bundle path. The
/// generic app glyph stays visible until the artwork arrives; hits and misses
/// are cached so scrolling the apps list does not refetch them.
struct AppIconView: View {
    let api: HubAPI?
    let path: String
    var hasIcon = false
    var size: CGFloat = 16

    @State private var image: AppIconImage?

    var body: some View {
        Group {
            if let image {
                #if canImport(AppKit)
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                #else
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                #endif
            } else {
                Image(systemName: "app")
                    .font(.system(size: size * 0.58, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(width: size, height: size)
        .task(id: taskID) { await load() }
        .accessibilityHidden(true)
    }

    private var taskID: String {
        "\(api?.baseURL.absoluteString ?? "")|\(path)|\(hasIcon)"
    }

    private func load() async {
        guard image == nil, hasIcon, !path.isEmpty, let api else { return }
        let key = "\(api.baseURL.absoluteString)|\(path)"

        if let cached = AppIconCache.images[key] {
            image = cached
            return
        }
        guard !AppIconCache.misses.contains(key) else { return }

        guard let data = await api.systemAppIcon(path: path),
              let loaded = AppIconImage(data: data)
        else {
            AppIconCache.misses.insert(key)
            return
        }
        AppIconCache.images[key] = loaded
        image = loaded
    }
}

@MainActor
private enum AppIconCache {
    static var images: [String: AppIconImage] = [:]
    static var misses: Set<String> = []
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

struct TokenBreakdown: View, Equatable {
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

// MARK: - Tool reliability

/// Per-tool call counts, failures and median duration. Shared by the session,
/// project and usage screens on both platforms.
struct ToolUsageBreakdown: View, Equatable {
    let usage: [Stats.ToolUsage]

    private var ordered: [Stats.ToolUsage] {
        usage.sorted {
            if $0.calls != $1.calls { return $0.calls > $1.calls }
            return $0.name < $1.name
        }
    }

    var body: some View {
        let tools = ordered
        let maxCalls = max(tools.map(\.calls).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(tools) { tool in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(tool.name)
                            .font(.system(size: 10.5, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        if tool.failed > 0 {
                            Text("\(tool.failed) failed")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.danger)
                        }
                        if let p50 = tool.durationP50 {
                            Text(Fmt.milliseconds(p50))
                                .font(.system(size: 9))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Text("\(Fmt.grouped(tool.calls))×")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    GeometryReader { geo in
                        let width = max(geo.size.width * CGFloat(tool.calls) / CGFloat(maxCalls), 3)
                        HStack(spacing: 1) {
                            Rectangle()
                                .fill(Theme.accent)
                                .frame(width: width * fraction(tool.succeeded, of: tool.calls))
                            Rectangle()
                                .fill(Theme.danger)
                                .frame(width: width * fraction(tool.failed, of: tool.calls))
                            Rectangle()
                                .fill(Theme.warn)
                                .frame(width: width * fraction(tool.unfinished, of: tool.calls))
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: 5)
                }
            }
        }
        .card()
    }

    private func fraction(_ value: Int, of total: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(value) / CGFloat(total)
    }
}

/// Recent failed tool calls with the error OpenCode recorded.
struct ToolFailureList: View {
    let failures: [SessionStats.ToolFailure]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(failures) { failure in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark.octagon.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.danger)
                        Text(failure.name)
                            .font(.system(size: 10, weight: .semibold))
                        Spacer(minLength: 4)
                        Text(Fmt.relative(from: failure.createdDate))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Text(failure.message)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                if failure.id != failures.last?.id {
                    Divider().opacity(0.3)
                }
            }
        }
        .card()
    }
}
