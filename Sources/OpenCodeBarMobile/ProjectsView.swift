import SwiftUI
import UIKit

struct ProjectsView: View {
    @EnvironmentObject private var settings: HubSettingsStore
    @EnvironmentObject private var store: MobileStore
    @State private var query = ""
    @State private var path = NavigationPath()

    private var projects: [Project] {
        let ordered = store.orderedProjects
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return ordered }
        let needle = query.lowercased()
        return ordered.filter {
            $0.displayName.lowercased().contains(needle)
                || $0.canonical.lowercased().contains(needle)
        }
    }

    var body: some View {
        let connection = store.connection
        let activeCount = store.activeCount

        return NavigationStack(path: $path) {
            Group {
                if !settings.isConfigured {
                    ScrollView {
                        SetupPrompt()
                            .padding(16)
                    }
                } else if projects.isEmpty {
                    ScrollView {
                        EmptyState(
                            icon: "folder",
                            title: store.orderedProjects.isEmpty ? "No projects yet" : "No matches",
                            subtitle: store.orderedProjects.isEmpty
                                ? "Projects appear after OpenCode has run in them."
                                : "Try a different name or path."
                        )
                        .padding(16)
                    }
                } else {
                    projectList
                }
            }
            .mobileScreenBackground()
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ConnectionPill(connection: connection, activeCount: activeCount)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search projects")
            .refreshable { await store.refreshLive() }
            .navigationDestination(for: Project.self) { project in
                ProjectDetailView(project: project)
            }
            .navigationDestination(for: Session.self) { session in
                SessionDetailView(sessionID: session.id, fallback: session)
            }
            .task(id: store.lastUpdated) {
                openRequestedProject()
            }
        }
    }

    #if DEBUG
    /// Opens a project on launch for screenshot tooling:
    /// `SIMCTL_CHILD_OPENCODEBAR_OPEN_PROJECT=<id-or-path>`.
    private func openRequestedProject() {
        guard path.isEmpty,
              let requested = ProcessInfo.processInfo.environment["OPENCODEBAR_OPEN_PROJECT"],
              let project = store.orderedProjects.first(where: {
                  $0.id == requested || $0.canonical == requested
              })
        else { return }
        path.append(project)
    }
    #else
    private func openRequestedProject() {}
    #endif

    private var projectList: some View {
        let ids = projects.map(\.id)

        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Projects") {
                    Text("\(projects.count)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                ForEach(projects) { project in
                    NavigationLink(value: project) {
                        ProjectRow(
                            project: project,
                            running: store.runningSessions(in: project).count,
                            lastActive: project.lastActiveDate
                        )
                    }
                    .buttonStyle(.plain)
                    .transition(.recentInsertion)
                }

                Text("\(store.orderedProjects.count) projects · running work first")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .animateRecentInsertion(ids: ids)
    }
}

struct ProjectRow: View {
    let project: Project
    let running: Int
    let lastActive: Date

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill((running > 0 ? Theme.running : Theme.accent).opacity(0.14))
                Image(systemName: running > 0 ? "bolt.fill" : "folder.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(running > 0 ? Theme.running : Theme.accent)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(project.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if running > 0 {
                        Text("\(running)")
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.running)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.running.opacity(0.14)))
                    }
                }
                Text(shortPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.relative(from: lastActive))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let vcs = project.vcs, !vcs.isEmpty {
                    Chip(text: vcs, tint: Theme.reasoning)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .card(padding: 12)
    }

    private var shortPath: String {
        (project.canonical as NSString).abbreviatingWithTildeInPath
    }
}
