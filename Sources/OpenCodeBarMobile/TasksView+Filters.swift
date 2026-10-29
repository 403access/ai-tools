import SwiftUI

extension TasksView {
    var groupingToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                groupedByTime.toggle()
            }
        } label: {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(groupedByTime ? Theme.accent : Color.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(
                        groupedByTime
                            ? Theme.accent.opacity(0.14)
                            : Color.primary.opacity(0.07)
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Group tasks by date")
        .accessibilityValue(groupedByTime ? "On" : "Off")
        .accessibilityAddTraits(groupedByTime ? .isSelected : [])
    }

    var activeProjectID: String? {
        guard let selectedProjectID, store.projects[selectedProjectID] != nil else {
            return nil
        }
        return selectedProjectID
    }

    /// The board after the project, date, and outcome filters have been applied.
    /// Task-status filters narrow this further in the view.
    var filteredTasks: [Session] {
        let filtered = SessionFiltering.apply(
            to: store.tasks,
            projectID: activeProjectID,
            time: timeFilter,
            status: statusFilter,
            projects: store.projects
        )
        guard statusFilter == .finished else { return filtered }
        // The shared filter treats a session without a failure as finished.
        // Tasks that have not run yet are still "open" on the board.
        return filtered.filter {
            $0.taskStatus != .working && $0.taskStatus != .queued
        }
    }

    /// Projects that have tasks, so the menu stays relevant.
    var filterProjects: [Project] {
        let tasks = store.tasks
        return store.orderedProjects.filter { project in
            tasks.contains {
                SessionFiltering.matchesProject(
                    $0,
                    projectID: project.id,
                    projects: store.projects
                )
            }
        }
    }

    var selectedProjectName: String {
        guard let activeProjectID else { return "All projects" }
        return store.projects[activeProjectID]?.displayName
            ?? filterProjects.first { $0.id == activeProjectID }?.displayName
            ?? "All projects"
    }

    var projectFilterMenu: some View {
        Menu {
            Button {
                selectedProjectID = nil
            } label: {
                if activeProjectID == nil {
                    Label("All projects", systemImage: "checkmark")
                } else {
                    Text("All projects")
                }
            }

            if !filterProjects.isEmpty {
                Divider()
            }

            ForEach(filterProjects) { project in
                Button {
                    selectedProjectID = project.id
                } label: {
                    if activeProjectID == project.id {
                        Label(project.displayName, systemImage: "checkmark")
                    } else {
                        Text(project.displayName)
                    }
                }
            }
        } label: {
            filterChip(icon: "folder", title: selectedProjectName)
        }
        .accessibilityLabel("Filter by project")
        .accessibilityValue(selectedProjectName)
    }

    var timeFilterMenu: some View {
        Menu {
            ForEach(SessionTimeFilter.allCases) { option in
                Button {
                    timeFilter = option
                } label: {
                    if option == timeFilter {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            filterChip(icon: "calendar", title: timeFilter.shortTitle)
        }
        .accessibilityLabel("Filter by date")
        .accessibilityValue(timeFilter.title)
    }

    var statusFilterMenu: some View {
        Menu {
            ForEach(SessionStatusFilter.allCases) { option in
                Button {
                    statusFilter = option
                } label: {
                    if option == statusFilter {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            filterChip(icon: "flag", title: statusFilter.shortTitle)
        }
        .accessibilityLabel("Filter by status")
        .accessibilityValue(statusFilter.title)
    }

    func filterChip(icon: String, title: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
        .contentShape(Capsule())
    }
}
