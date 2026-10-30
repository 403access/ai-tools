import AppKit
import SwiftUI

/// GitHub Actions pipeline for one project: the selected run's summary, its
/// stages and jobs, the selected job's steps, and the commit's check runs.
/// Loaded on demand by the project's Flows tab.
struct ProjectFlowsView: View {
    let flows: GitHubFlows
    let isLoading: Bool
    let onSelectRun: (GitHubFlowRun) -> Void
    let onRefresh: () -> Void

    @State private var selectedJobID: Int?

    private var detail: GitHubFlowRunDetail? { flows.run }
    private var run: GitHubFlowRun? { detail?.run }
    private var selectedJob: GitHubFlowJob? {
        guard let detail else { return nil }
        return detail.jobs.first { $0.id == selectedJobID } ?? detail.jobs.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            runHeader

            if let detail, !detail.stages.isEmpty {
                stagesCard(detail)
                jobAndChecks(detail)
            } else if detail != nil {
                EmptyState(
                    icon: "hammer",
                    title: "No jobs reported",
                    subtitle: "This run has not reported workflow jobs yet."
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: run?.id) { _, _ in
            selectedJobID = nil
        }
    }

    // MARK: - Run header

    private var runHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let run {
                    FlowsStatusIcon(status: run.status, size: 12)
                    Text(run.workflowName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Chip(text: "#\(run.runNumber)", tint: run.status.flowTint)
                    if !run.branch.isEmpty {
                        Chip(
                            text: run.branch,
                            systemImage: "arrow.triangle.branch",
                            tint: Theme.reasoning
                        )
                    }
                } else {
                    Text("GitHub Actions")
                        .font(.system(size: 12, weight: .semibold))
                }

                Spacer(minLength: 4)

                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }

                runMenu

                iconButton("arrow.clockwise", help: "Refresh flows", action: onRefresh)

                if let run, let url = URL(string: run.htmlURL) {
                    iconButton("arrow.up.right.square", help: "Open run on GitHub") {
                        NSWorkspace.shared.open(url)
                    }
                } else if let url = URL(string: flows.repository.url) {
                    iconButton("arrow.up.right.square", help: "Open repository on GitHub") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            if let run {
                VStack(alignment: .leading, spacing: 4) {
                    Text(run.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(run.shortSHA)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if let actor = run.actor {
                            Text(actor.login)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Text(run.event.replacingOccurrences(of: "_", with: " "))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(Fmt.relative(from: run.createdDate))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text(Fmt.duration(milliseconds: run.durationMs))
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if let commit = flows.commit {
                    HStack(spacing: 7) {
                        Chip(
                            text: "+\(Fmt.grouped(commit.additions))",
                            tint: Theme.accent
                        )
                        Chip(
                            text: "−\(Fmt.grouped(commit.deletions))",
                            tint: Theme.danger
                        )
                        Chip(
                            text: "\(commit.changedFiles) files",
                            systemImage: "doc.text",
                            tint: .secondary
                        )
                        Spacer(minLength: 0)
                        if let url = URL(string: commit.url) {
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                Text(commit.shortSHA)
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Theme.accent)
                            }
                            .buttonStyle(.plain)
                            .help("Open commit on GitHub")
                        }
                    }
                }

                stageProgress(detail?.stages ?? [])
            } else {
                Text("No workflow runs yet for this repository.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
    }

    private var runMenu: some View {
        Menu {
            if flows.runs.isEmpty {
                Text("No recent runs")
            } else {
                ForEach(flows.runs) { candidate in
                    Button {
                        onSelectRun(candidate)
                    } label: {
                        Label(
                            "#\(candidate.runNumber) · \(candidate.workflowName)",
                            systemImage: candidate.status.flowSymbol
                        )
                    }
                }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("Choose a recent run")
    }

    private func iconButton(
        _ icon: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }

    private func stageProgress(_ stages: [GitHubFlowStage]) -> some View {
        HStack(spacing: 5) {
            ForEach(stages) { stage in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(stage.status.flowTint)
                            .frame(width: 5, height: 5)
                        Text(stage.name)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(stage.index == selectedStageIndex ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.07))
                            Capsule()
                                .fill(stage.status.flowTint.opacity(stage.status.isPending ? 0.35 : 0.9))
                                .frame(width: geometry.size.width * stageProgressFraction(stage))
                        }
                    }
                    .frame(height: 3)
                }
            }
        }
    }

    private var selectedStageIndex: Int? { selectedJob?.stage }

    private func stageProgressFraction(_ stage: GitHubFlowStage) -> CGFloat {
        switch stage.status {
        case .success, .failure, .cancelled, .skipped, .neutral: return 1
        case .running: return 0.55
        case .queued, .waiting: return 0.16
        case .unknown: return 0
        }
    }

    // MARK: - Stages

    private func stagesCard(_ detail: GitHubFlowRunDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Stages") {
                Text("\(detail.stages.count) stages · \(detail.jobs.count) jobs")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(detail.stages) { stage in
                        stageColumn(stage)
                        if stage.id != detail.stages.last?.id {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 22)
                                .padding(.top, 54)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card(padding: 10)
    }

    private func stageColumn(_ stage: GitHubFlowStage) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                FlowsStatusIcon(status: stage.status, size: 10)
                Text(stage.name)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("\(stage.jobs.count)")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 5) {
                ForEach(stage.jobs) { job in
                    Button {
                        selectedJobID = job.id
                    } label: {
                        jobNode(job)
                    }
                    .buttonStyle(.plain)
                    .help("Show \(job.name) steps")
                }
            }
        }
        .frame(width: 158, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(selectedStageIndex == stage.index ? 0.045 : 0.022))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    selectedStageIndex == stage.index ? Theme.accent.opacity(0.35) : Color.clear,
                    lineWidth: 1
                )
        )
    }

    private func jobNode(_ job: GitHubFlowJob) -> some View {
        HStack(alignment: .top, spacing: 6) {
            FlowsStatusIcon(status: job.status, size: 10)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.name)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 5) {
                    if job.durationMs > 0 {
                        Text(Fmt.duration(milliseconds: job.durationMs))
                    }
                    if !job.steps.isEmpty {
                        Text("\(job.steps.count) steps")
                    }
                }
                .font(.system(size: 8.5))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(selectedJob?.id == job.id ? 0.07 : 0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    selectedJob?.id == job.id ? Theme.accent.opacity(0.45) : Color.primary.opacity(0.05),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
    }

    // MARK: - Job + checks

    private func jobAndChecks(_ detail: GitHubFlowRunDetail) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260), spacing: 10)],
            alignment: .leading,
            spacing: 10
        ) {
            jobCard(detail)
            checksCard(detail)
        }
    }

    private func jobCard(_ detail: GitHubFlowRunDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let job = selectedJob {
                    FlowsStatusIcon(status: job.status, size: 11)
                    Text(job.name)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Text(job.status.label)
                        .font(.system(size: 9))
                        .foregroundStyle(job.status.flowTint)
                    Spacer(minLength: 4)
                    if job.durationMs > 0 {
                        Text(Fmt.duration(milliseconds: job.durationMs))
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if let url = URL(string: job.htmlURL) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Open job on GitHub")
                    }
                } else {
                    Text("Job")
                        .font(.system(size: 11, weight: .semibold))
                }
            }

            if let job = selectedJob {
                if !job.labels.isEmpty {
                    Text(job.labels.joined(separator: " · "))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let runner = job.runnerName, !runner.isEmpty {
                    Text(runner)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Divider().opacity(0.35)

                if job.steps.isEmpty {
                    Text("No step output reported for this job.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 0) {
                        ForEach(job.steps) { step in
                            stepRow(step)
                            if step.id != job.steps.last?.id {
                                Divider().opacity(0.22)
                            }
                        }
                    }
                }

                let annotations = annotations(for: job, checks: detail.checks)
                if !annotations.isEmpty {
                    Divider().opacity(0.35)
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.bubble")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.warn)
                        Text("\(annotations.count) annotations")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(annotations.prefix(6)) { annotation in
                        annotationRow(annotation)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
    }

    private func stepRow(_ step: GitHubFlowStep) -> some View {
        HStack(spacing: 6) {
            FlowsStatusIcon(status: step.status, size: 9)
            Text("\(step.number).")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 18, alignment: .trailing)
            Text(step.name)
                .font(.system(size: 10))
                .lineLimit(1)
            Spacer(minLength: 4)
            if step.durationMs > 0 {
                Text(Fmt.duration(milliseconds: step.durationMs))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func annotationRow(_ annotation: GitHubCheckAnnotation) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: annotation.isFailure ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(annotation.isFailure ? Theme.danger : Theme.warn)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(annotation.title ?? annotation.message)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(2)
                Text("\(annotation.path):\(annotation.startLine)")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func checksCard(_ detail: GitHubFlowRunDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Checks")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(detail.checks.filter { $0.status == .success }.count) passed")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if detail.checks.contains(where: { $0.status == .running }) {
                    Text("\(detail.checks.filter { $0.status == .running }.count) running")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.running)
                }
            }

            if detail.checks.isEmpty {
                Text("No checks reported for this commit.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(detail.checks) { check in
                        checkRow(check)
                        if check.id != detail.checks.last?.id {
                            Divider().opacity(0.22)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
    }

    private func checkRow(_ check: GitHubCheck) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                FlowsStatusIcon(status: check.status, size: 9)
                Text(check.name)
                    .font(.system(size: 10))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let description = check.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 9))
                        .foregroundStyle(check.status.isFailure ? Theme.danger : .secondary)
                        .lineLimit(1)
                } else if check.durationMs > 0 {
                    Text(Fmt.duration(milliseconds: check.durationMs))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            if check.status.isRunning || check.status.isPending {
                ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
            } else if let summary = check.summary, !summary.isEmpty {
                Text(summary.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 8.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
    }

    private func annotations(
        for job: GitHubFlowJob,
        checks: [GitHubCheck]
    ) -> [GitHubCheckAnnotation] {
        let jobName = Self.normalizedName(job.name)
        return checks
            .filter { check in
                let checkName = Self.normalizedName(check.name)
                return checkName == jobName
                    || checkName.hasPrefix(jobName)
                    || jobName.hasPrefix(checkName)
            }
            .flatMap(\.annotations)
    }

    private static func normalizedName(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}

/// Placeholder for the Flows tab while the hub reads GitHub.
struct FlowsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChartCardSkeleton(height: 58)
            ChartCardSkeleton(height: 74)
            HStack(alignment: .top, spacing: 10) {
                ChartCardSkeleton(height: 86)
                ChartCardSkeleton(height: 86)
            }
        }
    }
}

// MARK: - Status styling

extension GitHubFlowStatus {
    var flowTint: Color {
        switch self {
        case .success: return Theme.accent
        case .failure: return Theme.danger
        case .running: return Theme.running
        case .queued, .waiting: return Theme.warn
        case .cancelled, .skipped, .neutral, .unknown: return .secondary
        }
    }

    var flowSymbol: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.octagon.fill"
        case .running: return "arrow.triangle.2.circlepath"
        case .queued, .waiting: return "clock.fill"
        case .cancelled: return "slash.circle.fill"
        case .skipped: return "minus.circle.fill"
        case .neutral: return "circle.dashed"
        case .unknown: return "questionmark.circle"
        }
    }
}

private struct FlowsStatusIcon: View {
    let status: GitHubFlowStatus
    var size: CGFloat = 10

    var body: some View {
        Image(systemName: status.flowSymbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(status.flowTint)
            .accessibilityLabel(status.label)
    }
}
