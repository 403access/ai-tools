import SwiftUI

/// A page in the project info drawer. The project page used to stack every
/// section into one long scroll; each drawer page now owns one kind of content
/// so nothing competes for the first screen.
enum ProjectInfoPage: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case stats = "Stats"
    case changes = "Changes"
    case files = "Files"
    case git = "Git"
    case sessions = "Sessions"

    var id: String { rawValue }

    var title: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "rectangle.grid.2x2"
        case .stats: return "chart.bar.xaxis"
        case .changes: return "plus.forwardslash.minus"
        case .files: return "doc.text"
        case .git: return "arrow.triangle.branch"
        case .sessions: return "bubble.left.and.bubble.right"
        }
    }
}

/// Resting heights for the project info drawer, measured against the height
/// available between the navigation bar and the tab bar.
enum ProjectInfoDrawerDetent: String, CaseIterable {
    case peek
    case medium
    case expanded

    func height(in available: CGFloat) -> CGFloat {
        let peek = min(84, max(68, available * 0.13))
        let expanded = max(peek + 80, available - 8)
        let medium = min(max(peek + 100, available * 0.52), expanded - 24)
        switch self {
        case .peek: return peek
        case .medium: return medium
        case .expanded: return expanded
        }
    }

    /// The detent closest to a dragged height, used when a drag ends.
    static func nearest(
        to height: CGFloat,
        in available: CGFloat
    ) -> ProjectInfoDrawerDetent {
        Self.allCases.min {
            abs($0.height(in: available) - height)
                < abs($1.height(in: available) - height)
        } ?? .peek
    }
}

extension ProjectDetailView {
    // MARK: - Drawer chrome

    /// One-line summary shown on the collapsed drawer, so the peek still says
    /// something useful before it is pulled up.
    var drawerGlance: String {
        if let stats = detail?.stats {
            return [
                "\(Fmt.grouped(stats.steps)) steps",
                Fmt.usd(stats.cost),
                "\(stats.sessions) sessions",
            ].joined(separator: " · ")
        }
        return "Stats, changes, files, Git, and sessions"
    }

    func drawer(available: CGFloat) -> some View {
        let peek = ProjectInfoDrawerDetent.peek.height(in: available)
        let height = min(available, drawerHeight ?? drawerDetent.height(in: available))
        let showsDetail = height > peek + 8

        return VStack(spacing: 0) {
            drawerHeader
                .contentShape(Rectangle())
                .gesture(drawerDragGesture(available: available))

            if showsDetail {
                drawerPagePicker
                Divider().opacity(0.35)
                drawerScroll
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(height: height, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(MobileTheme.bar)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 22,
                topTrailingRadius: 22,
                style: .continuous
            )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(MobileTheme.border)
                .frame(height: 0.5)
        }
        .shadow(color: Color.black.opacity(0.28), radius: 18, y: -6)
    }

    var drawerHeader: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            HStack(spacing: 9) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Project info")
                        .font(.subheadline.weight(.semibold))
                    Text(drawerGlance)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 8)

                Button {
                    toggleDrawer(expand: drawerDetent == .peek)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(drawerDetent == .peek ? 0 : 180))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    drawerDetent == .peek
                        ? "Expand project info"
                        : "Collapse project info"
                )
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 10)
    }

    var drawerPagePicker: some View {
        HStack(spacing: 4) {
            ForEach(ProjectInfoPage.allCases) { page in
                drawerPageButton(page)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func drawerPageButton(_ page: ProjectInfoPage) -> some View {
        let isSelected = infoPage == page

        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                infoPage = page
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: page.icon)
                    .font(.system(size: 8, weight: .bold))
                Text(page.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.caption2.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    isSelected
                        ? Theme.accent.opacity(0.16)
                        : Color.primary.opacity(0.06)
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? Theme.accent.opacity(0.4) : Color.clear,
                    lineWidth: 1
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(page.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    var drawerScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                drawerPage
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        // Re-creating the scroll view resets the offset when the page changes.
        .id(infoPage)
        .refreshable { await refreshProject() }
    }

    /// Shown on the page itself when no sessions are running, so the remaining
    /// room explains where the rest of the project information went.
    var drawerHint: some View {
        Button {
            setDrawer(.medium)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Project info")
                        .font(.footnote.weight(.semibold))
                    Text("Stats, changes, files, Git, and sessions")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.up")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.accent)
            }
            .contentShape(Rectangle())
            .card(padding: 12)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the project info drawer")
    }

    // MARK: - Pages

    @ViewBuilder
    var drawerPage: some View {
        switch infoPage {
        case .overview: overviewDrawerPage
        case .stats: statsDrawerPage
        case .changes: changesSection
        case .files: filesSection
        case .git: gitSection
        case .sessions: sessionsDrawerPage
        }
    }

    @ViewBuilder
    var overviewDrawerPage: some View {
        if let detail {
            if let error = detail.error, detail.stats == nil {
                NoticeRow(
                    icon: "exclamationmark.triangle.fill",
                    message: error,
                    tint: Theme.warn
                )
            } else if let stats = detail.stats {
                SectionHeader("At a glance")
                statsGrid(stats)
            } else if detail.isLoading {
                ProjectDetailSkeleton()
                    .shimmering()
            }
        } else {
            ProjectDetailSkeleton()
                .shimmering()
        }

        documentationSection

        if let detail, !detail.sessions.isEmpty {
            let recent = Array(detail.sessions.prefix(5))
            SectionHeader("Recent sessions") {
                Button {
                    openDrawerPage(.sessions)
                } label: {
                    Text("All \(detail.sessions.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            ForEach(recent) { session in
                NavigationLink(value: session) {
                    RecentSessionRow(session: session, project: project.displayName)
                }
                .buttonStyle(.plain)
                .transition(.recentInsertion)
            }
            .animateRecentInsertion(ids: recent.map(\.id))
        }
    }

    @ViewBuilder
    var statsDrawerPage: some View {
        if let detail {
            if let error = detail.error, detail.stats == nil {
                NoticeRow(
                    icon: "exclamationmark.triangle.fill",
                    message: error,
                    tint: Theme.warn
                )
            } else if let stats = detail.stats {
                SectionHeader("Trend")
                UsageTrendCard(stats: stats, sessions: detail.sessions)
                    .equatable()

                if let totals = stats.tools.totals {
                    SectionHeader("Tool calls") {
                        if let rate = totals.successRate {
                            Text("\(Int((rate * 100).rounded()))% success")
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(
                                    rate >= 0.98 ? Theme.accent
                                        : rate >= 0.90 ? Theme.warn : Theme.danger
                                )
                        }
                    }
                    ToolSummaryCard(totals: totals, mode: stats.tools.mode)
                        .equatable()

                    if let usage = stats.tools.usage, !usage.isEmpty {
                        SectionHeader("Tools") {
                            Text("\(usage.count)")
                                .font(.caption.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        ToolUsageBreakdown(usage: usage)
                            .equatable()
                    }
                }

                if !stats.models.isEmpty {
                    SectionHeader("Models")
                    ModelBreakdownCard(models: stats.models)
                        .equatable()
                }
            } else if detail.isLoading {
                ProjectDetailSkeleton()
                    .shimmering()
            }
        } else {
            ProjectDetailSkeleton()
                .shimmering()
        }
    }

    @ViewBuilder
    var sessionsDrawerPage: some View {
        if let detail {
            if !detail.sessions.isEmpty {
                let sessions = Array(detail.sessions.prefix(40))
                SectionHeader("Sessions") {
                    Text("\(detail.sessions.count)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ForEach(sessions) { session in
                    NavigationLink(value: session) {
                        RecentSessionRow(session: session, project: project.displayName)
                    }
                    .buttonStyle(.plain)
                    .transition(.recentInsertion)
                }
                .animateRecentInsertion(ids: sessions.map(\.id))
            } else if detail.isLoading {
                ProjectDetailSkeleton()
                    .shimmering()
            } else {
                EmptyState(
                    icon: "bubble.left.and.bubble.right",
                    title: "No sessions yet",
                    subtitle: "Sessions appear here after OpenCode runs in this project."
                )
            }
        } else {
            ProjectDetailSkeleton()
                .shimmering()
        }
    }

    // MARK: - Drawer state

    func openDrawerPage(_ page: ProjectInfoPage) {
        infoPage = page
        if drawerDetent == .peek {
            setDrawer(.medium)
        }
    }

    func setDrawer(_ target: ProjectInfoDrawerDetent) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            drawerDetent = target
            drawerHeight = target.height(in: drawerSpace)
        }
    }

    func toggleDrawer(expand: Bool? = nil) {
        let target: ProjectInfoDrawerDetent
        if let expand {
            target = expand ? .medium : .peek
        } else {
            target = drawerDetent == .peek ? .medium : .peek
        }
        setDrawer(target)
    }

    func drawerDragGesture(available: CGFloat) -> some Gesture {
        let peek = ProjectInfoDrawerDetent.peek.height(in: available)

        return DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                if dragStartHeight == nil {
                    dragStartHeight = drawerHeight
                        ?? drawerDetent.height(in: available)
                }
                let start = dragStartHeight
                    ?? drawerDetent.height(in: available)
                let proposed = start - value.translation.height
                drawerHeight = min(available, max(peek, proposed))
            }
            .onEnded { value in
                let start = dragStartHeight
                    ?? drawerHeight
                    ?? drawerDetent.height(in: available)
                let projected = start - value.predictedEndTranslation.height
                let target = ProjectInfoDrawerDetent.nearest(
                    to: projected,
                    in: available
                )
                dragStartHeight = nil
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    drawerDetent = target
                    drawerHeight = target.height(in: available)
                }
            }
    }
}
