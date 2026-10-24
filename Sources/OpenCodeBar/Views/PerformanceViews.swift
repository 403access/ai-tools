import SwiftUI

// Loading placeholders shared by the Mac panel and the iOS app. Screens show
// these instead of a bare spinner so the layout is stable while the hub's data
// arrives, and the first real content does not jump the panel around.

/// A single rounded placeholder block.
struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat
    var cornerRadius: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(0.09))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

struct SkeletonCircle: View {
    var size: CGFloat = 18

    var body: some View {
        Circle()
            .fill(Color.primary.opacity(0.09))
            .frame(width: size, height: size)
    }
}

/// A light sweep across a group of placeholders. Applied once to a container so
/// all of its blocks animate together, and disabled when Reduce Motion is on.
private struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.22), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: max(geo.size.width * 0.5, 90))
                        .offset(x: phase * (geo.size.width + 200) - 90)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    /// Animates a group of skeleton blocks with a single sweeping highlight.
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

/// Placeholder for a session row, matching the shape of `RecentRow` /
/// `RunningRow` closely enough that the list does not shift on load.
struct SessionRowSkeleton: View {
    var showsActivity: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SkeletonCircle(size: showsActivity ? 10 : 8)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 7) {
                SkeletonBlock(height: 11)
                SkeletonBlock(width: 150, height: 9)
                if showsActivity {
                    SkeletonBlock(width: 200, height: 9)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 6) {
                SkeletonBlock(width: 44, height: 9)
                SkeletonBlock(width: 32, height: 8)
            }
        }
        .card(padding: 10)
    }
}

/// A column of session-row placeholders.
struct SessionListSkeleton: View {
    var count: Int = 4
    var showsActivity: Bool = false

    var body: some View {
        VStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { _ in
                SessionRowSkeleton(showsActivity: showsActivity)
            }
        }
    }
}

/// Placeholder for one stat tile.
struct StatTileSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SkeletonBlock(width: 62, height: 8)
            SkeletonBlock(width: 84, height: 18, cornerRadius: 5)
            SkeletonBlock(width: 70, height: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
    }
}

/// Placeholder grid matching the two-column `LazyVGrid` of stat tiles.
struct StatGridSkeleton: View {
    var count: Int = 6

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            ForEach(0..<count, id: \.self) { _ in
                StatTileSkeleton()
            }
        }
    }
}

/// Placeholder for the compact two-row glance card on a project's Overview.
struct ProjectStatsSkeleton: View {
    var body: some View {
        VStack(spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                metric
                metric
                metric
            }
            Divider().opacity(0.35)
            HStack(alignment: .top, spacing: 8) {
                metric
                metric
                metric
            }
        }
        .card(padding: 10)
    }

    private var metric: some View {
        VStack(alignment: .leading, spacing: 5) {
            SkeletonBlock(width: 52, height: 8)
            SkeletonBlock(width: 62, height: 14, cornerRadius: 4)
            SkeletonBlock(width: 58, height: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Placeholder for a chart card: title row plus a plotting area.
struct ChartCardSkeleton: View {
    var height: CGFloat = 104

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                SkeletonBlock(width: 54, height: 9)
                SkeletonBlock(width: 40, height: 9)
                Spacer()
                SkeletonBlock(width: 34, height: 9)
            }
            SkeletonBlock(height: height, cornerRadius: 6)
        }
        .card()
    }
}

/// Placeholder conversation: alternating user and assistant cards.
struct ConversationSkeleton: View {
    var count: Int = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                if index % 3 == 0 {
                    userCard
                } else {
                    assistantCard
                }
            }
        }
    }

    private var userCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                SkeletonBlock(width: 54, height: 8)
                Spacer()
                SkeletonBlock(width: 40, height: 8)
            }
            SkeletonBlock(height: 10)
            SkeletonBlock(width: 220, height: 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
    }

    private var assistantCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                SkeletonBlock(width: 66, height: 8)
                Spacer()
                SkeletonBlock(width: 40, height: 8)
            }
            SkeletonBlock(height: 10)
            SkeletonBlock(height: 10)
            SkeletonBlock(width: 180, height: 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
    }
}

/// Placeholder for a session's Stats tab.
struct StatsDetailSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatGridSkeleton(count: 4)
            ChartCardSkeleton(height: 58)
            SessionListSkeleton(count: 2)
        }
    }
}

/// Placeholder for a Changes tab: summary bar plus a few patch cards.
struct ChangesSkeleton: View {
    var count: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonBlock(height: 12, cornerRadius: 6)
            ForEach(0..<count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 7) {
                    SkeletonBlock(width: 180, height: 10)
                    SkeletonBlock(height: 9)
                    SkeletonBlock(height: 9)
                    SkeletonBlock(width: 140, height: 9)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 10)
            }
        }
    }
}

/// Placeholder for a project's Overview tab: the at-a-glance grid and a few
/// session rows. The summary header is fixed by the detail page, so it is not
/// part of the skeleton.
struct ProjectDetailSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProjectStatsSkeleton()
            SessionListSkeleton(count: 3)
        }
    }
}

/// Placeholder for the Usage tab: plan limits, trend chart, tiles, heatmap and
/// breakdown cards.
struct UsageSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Plan limits")
            ChartCardSkeleton(height: 54)
            SectionHeader("Trend")
            ChartCardSkeleton()
            StatGridSkeleton()
            SectionHeader("Activity")
            ChartCardSkeleton(height: 82)
        }
        .shimmering()
    }
}
