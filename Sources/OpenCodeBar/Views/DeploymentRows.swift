import SwiftUI

/// One physical device in Settings → Deployments, with the builds installed on
/// it right now. The row is presentational; the section wraps it in a button.
struct DeploymentDeviceRow: View {
    let device: DeploymentDevice

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: device.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(device.isReachable || device.connected ? Theme.accent : Color.secondary)
                .frame(width: 20)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(device.name)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)

                    if device.connected {
                        PulsingDot(size: 4)
                    }

                    Spacer(minLength: 4)

                    Text(device.stateLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(device.connected ? Theme.accent : .secondary)
                        .lineLimit(1)
                }

                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if device.current.isEmpty {
                    Text(device.lastSynced == nil ? "Not scanned yet" : "No OpenCodeBar build installed")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(device.current) { deployment in
                        HStack(spacing: 5) {
                            Chip(
                                text: deployment.variant.isEmpty ? "app" : deployment.variant,
                                tint: deployment.variant.isEmpty ? Theme.accent : Theme.running
                            )
                            Text(deployment.buildLabel)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                            if !deployment.shortCommit.isEmpty {
                                Text(deployment.shortCommit)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .card(padding: 10)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        [device.model, device.platform]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

/// One install row used by the recent list and the per-device history.
struct DeploymentInstallRow: View {
    let deployment: Deployment
    /// Shown in the cross-device recent list; hidden on a device's own page.
    var showsDevice = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(deployment.isCurrent ? Theme.accent : Color.secondary.opacity(0.35))
                .frame(width: 5, height: 5)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(deployment.displayName)
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)

                    if !deployment.variant.isEmpty {
                        Chip(text: deployment.variant, tint: Theme.running)
                    }

                    if let ended = deployment.endLabel {
                        Chip(text: ended, tint: .secondary)
                    } else {
                        Chip(text: "installed", tint: Theme.accent)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 6) {
                    Text(deployment.buildLabel)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if !deployment.shortCommit.isEmpty {
                        Text(deployment.shortCommit)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    if !deployment.branch.isEmpty {
                        Text(deployment.branch)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 4) {
                    if showsDevice {
                        Text(deployment.deviceName)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("·")
                            .font(.system(size: 9))
                            .foregroundStyle(.quaternary)
                    }
                    Text(installedLine)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var installedLine: String {
        let installed = Fmt.relative(from: deployment.installedAtDate)
        guard let ended = deployment.endedAtDate else { return "Installed \(installed)" }
        return "Installed \(installed) · ended \(Fmt.relative(from: ended))"
    }
}

/// Bundle id + worktree detail for the device page, in the Settings style.
struct DeploymentBuildCard: View {
    let deployment: Deployment

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(deployment.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                if !deployment.variant.isEmpty {
                    Chip(text: deployment.variant, tint: Theme.running)
                }
                Spacer(minLength: 0)
                Text(deployment.buildLabel)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            row("Bundle", deployment.bundleId, monospaced: true)
            if !deployment.shortCommit.isEmpty {
                row("Commit", deployment.shortCommit, monospaced: true)
            }
            if !deployment.branch.isEmpty {
                row("Branch", deployment.branch)
            }
            if !deployment.worktree.isEmpty {
                row("Worktree", deployment.worktree, monospaced: true)
            }
            row("Installed", Self.dateTime.string(from: deployment.installedAtDate))
            if let ended = deployment.endedAtDate {
                row("Ended", "\(Self.dateTime.string(from: ended)) · \(deployment.endLabel ?? "ended")")
            } else {
                row("Source", deployment.source == "sync" ? "Device scan" : "Install script")
            }
        }
        .card(padding: 10)
    }

    private func row(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(.system(size: 9, design: monospaced ? .monospaced : .default))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
