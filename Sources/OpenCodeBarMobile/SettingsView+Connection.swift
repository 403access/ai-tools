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

                Divider()

                Toggle(isOn: $showsProjectIcons) {
                    Text("Project icons in Tasks")
                        .font(.subheadline.weight(.medium))
                }
                .tint(Theme.accent)

                Text("Show each project's app icon in Tasks group headers. Projects without artwork keep the folder symbol.")
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

    // MARK: - Power

    /// The hub runs on the Mac, so its host sleep policy is the setting that
    /// decides whether the phone keeps its connection while the Mac is idle.
    var powerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Power")

            VStack(alignment: .leading, spacing: 10) {
                if let settings = store.serverSettings,
                   settings.preventSleepSupported == true {
                    Toggle(isOn: Binding(
                        get: { store.serverSettings?.preventSleep ?? false },
                        set: { value in
                            Task { await store.updatePreventSleep(value) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Keep Mac awake")
                                .font(.subheadline.weight(.medium))
                            Text(settings.preventSleep == true
                                 ? "Idle sleep is blocked while the hub runs, so this phone keeps its connection. The Mac's display can still turn off."
                                 : "The Mac can sleep normally. This phone loses its connection while the Mac is asleep.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(Theme.accent)
                    .disabled(store.isUpdatingSettings)
                } else if store.serverSettings?.preventSleepSupported == false {
                    Text("This hub is not running on macOS, so there is no host sleep to manage.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(store.isRefreshingSettings
                         ? "Loading the Mac's power settings…"
                         : "The Mac's power settings are unavailable. Make sure the hub is running the latest version.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error = store.settingsError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(Theme.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card(padding: 12)

            sectionNote("This controls the Mac running the hub. The display can still turn off; closing the lid still sleeps the Mac.")
        }
    }

    // MARK: - Agents

    /// Caps how many sessions the hub runs at once. Prompts that arrive while
    /// every slot is busy wait in the task board's Queued column.
    var agentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Agents")

            VStack(alignment: .leading, spacing: 10) {
                if let settings = store.serverSettings {
                    let minimum = settings.maxConcurrentAgentsMin ?? 0
                    let maximum = settings.maxConcurrentAgentsMax ?? 16
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Concurrent agents")
                                .font(.subheadline.weight(.medium))
                            Text(settings.maxConcurrentAgents == 0
                                 ? "No limit. Every prompt starts immediately."
                                 : "New prompts wait in Queued until a slot frees.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Stepper(
                            value: Binding(
                                get: { store.serverSettings?.maxConcurrentAgents ?? 0 },
                                set: { value in
                                    Task { await store.updateMaxConcurrentAgents(value) }
                                }
                            ),
                            in: minimum...maximum
                        ) {
                            Text((settings.maxConcurrentAgents ?? 0) == 0
                                 ? "Unlimited"
                                 : "\(settings.maxConcurrentAgents ?? 0)")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        .labelsHidden()
                        .disabled(store.isUpdatingSettings)
                    }

                    if let error = store.settingsError {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(Theme.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(store.isRefreshingSettings
                         ? "Loading agent settings…"
                         : "Agent settings are unavailable. Make sure the hub is running the latest version.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card(padding: 12)

            sectionNote("Applies to the Mac running the hub. Queued tasks start in order as slots free up.")
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
