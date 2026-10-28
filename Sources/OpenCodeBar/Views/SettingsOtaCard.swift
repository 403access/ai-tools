import AppKit
import SwiftUI

/// Settings → Deployments: build an over-the-air install on the hub host and
/// hand it to a phone as a QR code or link. No USB cable and no shared Wi-Fi.
///
/// iOS only installs when the device asks for it, so the hub can prepare and
/// publish the build but the final confirmation happens on the phone.
struct SettingsOtaCard: View {
    @EnvironmentObject private var state: AppState
    @State private var copiedLink = false
    /// Build selected in the published list; `nil` means the newest one.
    @State private var selectedID: String?

    private var latest: OtaArtifact? {
        if let selectedID, let match = state.otaBuilds.first(where: { $0.id == selectedID }) {
            return match
        }
        return state.otaLatest
    }

    private var pageURL: URL? {
        latest.flatMap { state.otaInstallPageURL(for: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Text("Archive, sign, and publish a development build from this Mac. If the phone is reachable over USB or the local network the hub installs it right away; otherwise scan the code from any network.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = state.otaError {
                NoticeRow(icon: "exclamationmark.triangle.fill", message: error, tint: Theme.danger)
            } else if let notice = state.otaNotice {
                NoticeRow(icon: "checkmark.circle.fill", message: notice, tint: Theme.accent)
            }

            if state.otaNeedsHTTPS, !state.isOtaBuilding, latest != nil {
                NoticeRow(
                    icon: "lock.trianglebadge.exclamationmark",
                    message: "iOS only installs over HTTPS. Run `make hub-tunnel` and keep it running, then reopen this page.",
                    tint: Theme.warn
                )
            }

            actionRow

            if let latest, let pageURL {
                Divider().opacity(0.5)
                latestBuild(latest, pageURL: pageURL)
            }

            if state.otaBuilds.count > 1 {
                Divider().opacity(0.5)
                publishedBuilds
            }
        }
        .card(padding: 12)
        .task { await state.refreshOta() }
        .onChange(of: state.otaLatest?.id) { _, _ in
            // A fresh publish should become the selected build again.
            selectedID = nil
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Over-the-air install")
                .font(.system(size: 11, weight: .semibold))
            Spacer(minLength: 4)
            if state.isOtaBuilding {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
            } else if let latest {
                Text(Fmt.relative(from: latest.createdAtDate))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .help("Published \(latest.createdAtDate.formatted(date: .abbreviated, time: .shortened))")
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                Task { await state.startOtaBuild() }
            } label: {
                Label(
                    state.isOtaBuilding ? "Building…" : "Build & install",
                    systemImage: state.isOtaBuilding ? "hammer.fill" : "arrow.up.circle.fill"
                )
                .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.isOtaBuilding || state.api == nil)
            .help("Build the app on this Mac, install it if the phone is reachable, and publish an install code")
            .accessibilityHint("Starts an archive and export on the hub host, then shows an install code")

            if state.isOtaBuilding {
                Text(state.otaBuild?.lastLogLine ?? "Starting the build…")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("The phone confirms the install; iOS does not allow a remote push.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// True when the last build run installed this exact artifact directly.
    private func installedDirectly(_ artifact: OtaArtifact) -> Bool {
        guard let build = state.otaBuild, build.installed == true else { return false }
        return build.artifact?.id == artifact.id
    }

    private var publishedBuilds: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("PUBLISHED BUILDS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Text("\(state.otaBuilds.count)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                Spacer(minLength: 0)
                Text("Newest first; the hub keeps five")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }

            ForEach(state.otaBuilds) { build in
                let selected = latest?.id == build.id
                Button {
                    selectedID = build.id
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 10, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Theme.accent : Color.secondary.opacity(0.5))
                        Text(build.buildLabel)
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                        if !build.shortCommit.isEmpty {
                            Text(build.shortCommit)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Text(Fmt.relative(from: build.createdAtDate))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selected ? Theme.accent.opacity(0.12) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show the install code for this build")
            }
        }
    }

    private func latestBuild(_ artifact: OtaArtifact, pageURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if let code = QRCode.image(for: pageURL.absoluteString) {
                    Image(nsImage: code)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 104, height: 104)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.08))
                        )
                        .accessibilityLabel("Over-the-air install QR code")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(artifact.buildLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                    if !artifact.shortCommit.isEmpty {
                        Text("\(artifact.shortCommit) on \(artifact.branch.isEmpty ? "detached" : artifact.branch)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if installedDirectly(artifact) {
                        Label(
                            state.otaBuild?.device.map { "Installed on \($0) during this build." }
                                ?? "Installed on the phone during this build.",
                            systemImage: "checkmark.seal.fill"
                        )
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    } else {
                        Text("Scan with the iPhone camera, then tap Install. The page also pairs the hub in one tap.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 6) {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(pageURL.absoluteString, forType: .string)
                            copiedLink = true
                            Task {
                                try? await Task.sleep(for: .seconds(1.5))
                                copiedLink = false
                            }
                        } label: {
                            Label(copiedLink ? "Copied" : "Copy link", systemImage: copiedLink ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .buttonStyle(.bordered)

                        Button {
                            NSWorkspace.shared.open(pageURL)
                        } label: {
                            Label("Open", systemImage: "safari")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .help("Open the install page in the default browser")
                    }
                    .padding(.top, 2)
                }
            }

            Text(pageURL.absoluteString)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}
