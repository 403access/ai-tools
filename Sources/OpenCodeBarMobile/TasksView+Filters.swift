import SwiftUI

extension TasksView {
    var activeProjectID: String? {
        guard let selectedProjectID, store.projects[selectedProjectID] != nil else {
            return nil
        }
        return selectedProjectID
    }

    /// Number of project, date, and outcome filters narrowing the tasks.
    var activeFilterCount: Int {
        (activeProjectID != nil ? 1 : 0)
            + (timeFilter == .all ? 0 : 1)
            + (statusFilter == .all ? 0 : 1)
    }

    var grouping: MobileTaskGrouping {
        MobileTaskGrouping(rawValue: groupingRaw) ?? .none
    }

    var groupingBinding: Binding<MobileTaskGrouping> {
        Binding(
            get: { grouping },
            set: { groupingRaw = $0.rawValue }
        )
    }

    var dateInterval: MobileTaskDateInterval {
        MobileTaskDateInterval(rawValue: dateIntervalRaw) ?? .day
    }

    var dateIntervalBinding: Binding<MobileTaskDateInterval> {
        Binding(
            get: { dateInterval },
            set: { dateIntervalRaw = $0.rawValue }
        )
    }

    /// Date and project grouping is the default. Installs that stored another
    /// mode before this default shipped adopt it once; later choices are kept.
    func applyDefaultGroupingIfNeeded() {
        let defaults = UserDefaults.standard
        let key = "tasks.defaultGroupingApplied"
        guard !defaults.bool(forKey: key) else { return }
        groupingRaw = MobileTaskGrouping.dateAndProject.rawValue
        defaults.set(true, forKey: key)
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

    /// Projects that have tasks, so the filter drawer stays relevant.
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
}

/// Drawer opened from the Tasks header. Task states stay as chips in the list;
/// the project, date, and outcome filters plus the grouping options only need
/// attention occasionally, so they live here instead of taking a row of the
/// screen.
struct MobileTaskFiltersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedProjectID: String?
    @Binding var timeFilter: SessionTimeFilter
    @Binding var statusFilter: SessionStatusFilter
    @Binding var grouping: MobileTaskGrouping
    @Binding var dateInterval: MobileTaskDateInterval
    let projects: [Project]

    private var hasActiveFilters: Bool {
        selectedProjectID != nil || timeFilter != .all || statusFilter != .all
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Project", selection: $selectedProjectID) {
                        Text("All projects").tag(String?.none)
                        ForEach(projects) { project in
                            Text(project.displayName).tag(Optional(project.id))
                        }
                    }

                    Picker("Date", selection: $timeFilter) {
                        ForEach(SessionTimeFilter.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }

                    Picker("Outcome", selection: $statusFilter) {
                        ForEach(SessionStatusFilter.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } header: {
                    Text("Filter tasks")
                } footer: {
                    Text("Task states stay available as chips on the Tasks tab.")
                }

                Section {
                    Picker("Group by", selection: $grouping) {
                        ForEach(MobileTaskGrouping.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }

                    if grouping.usesDate {
                        Picker("Date interval", selection: $dateInterval) {
                            ForEach(MobileTaskDateInterval.allCases) { interval in
                                Text(interval.title).tag(interval)
                            }
                        }
                    }
                } header: {
                    Text("Grouping")
                } footer: {
                    Text("Grouping also applies to each status column in landscape.")
                }

                Section {
                    Button("Reset filters") {
                        selectedProjectID = nil
                        timeFilter = .all
                        statusFilter = .all
                    }
                    .disabled(!hasActiveFilters)
                }
            }
            .pickerStyle(.menu)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
