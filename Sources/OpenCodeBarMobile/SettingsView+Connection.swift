import SwiftUI

extension SettingsView {
    // MARK: - Appearance

    var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Appearance")

            VStack(alignment: .leading, spacing: 8) {
                Picker("Appearance", selection: $appearance.appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Text("Dark mirrors the Mac menu bar panel.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .card(padding: 12)
        }
    }

    // MARK: - Status

    var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Status")

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ConnectionPill(connection: store.connection, activeCount: store.activeCount)
                    Spacer()
                    if store.isRefreshing {
                        ProgressView().controlSize(.small)
                    }
                }

                if let health = store.hubHealth {
                    statusRow("Hub", health.hub?.version.map { "v\($0)" } ?? "connected")
                    statusRow(
                        "OpenCode",
                        health.opencode?.connected == true
                            ? (health.opencode?.version.map { "v\($0)" } ?? "connected")
                            : "offline"
                    )
                    if let sessions = health.hub?.sessions {
                        statusRow("Cached", "\(Fmt.grouped(sessions)) sessions · \(Fmt.grouped(health.hub?.messages ?? 0)) messages")
                    }
                    if let uptime = health.hub?.uptime {
                        statusRow("Uptime", duration(seconds: uptime))
                    }
                    if let lastSync = health.opencode?.lastSync {
                        statusRow("Last sync", Fmt.relative(from: Date(timeIntervalSince1970: lastSync / 1000)))
                    }
                    if let error = health.opencode?.lastError, !error.isEmpty {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(Theme.warn)
                    }
                } else if case .offline(let reason) = store.connection {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .card(padding: 12)

            if !settings.isConfigured {
                sectionNote("No hub configured yet. Start the hub on your Mac and add its URL and token below.")
            }
        }
    }

    // MARK: - Hub connection

    var connectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Hub connection")

            VStack(alignment: .leading, spacing: 10) {
                TextField("http://192.168.1.10:8787", text: $url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.callout.monospaced())
                    .mobileField()

                HStack(spacing: 8) {
                    Group {
                        if showToken {
                            TextField("Hub token", text: $token)
                        } else {
                            SecureField("Hub token", text: $token)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.callout.monospaced())

                    Button {
                        showToken.toggle()
                    } label: {
                        Image(systemName: showToken ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showToken ? "Hide token" : "Show token")
                }
                .mobileField()

                Button {
                    saveAndConnect()
                } label: {
                    Label(store.connection.isConnected ? "Save & Reconnect" : "Save & Connect", systemImage: "link")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(candidate == nil)

                Button {
                    Task { await validate() }
                } label: {
                    HStack(spacing: 8) {
                        if testing { ProgressView().controlSize(.small) }
                        Text(testing ? "Testing…" : "Test connection")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(candidate == nil || testing)

                if let testMessage {
                    Label(testMessage, systemImage: testSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(testSucceeded ? Theme.accent : Theme.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let savedMessage {
                    Label(savedMessage, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
            }
            .card(padding: 12)

            sectionNote("Use the Mac's LAN address — for example http://192.168.1.10:8787 — while the phone is on the same network. On cellular, run `make hub-tunnel` on the Mac and enter the printed HTTPS URL. The hub prints the URL, token, and a pairing link when it starts.")
        }
    }
}
