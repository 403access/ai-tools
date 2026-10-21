import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: HubSettingsStore
    @EnvironmentObject private var store: MobileStore

    @State private var url = ""
    @State private var token = ""
    @State private var pairingLink = ""
    @State private var showToken = false
    @State private var loaded = false
    @State private var testing = false
    @State private var testMessage: String?
    @State private var testSucceeded = false
    @State private var savedMessage: String?

    private var candidate: HubLocation? {
        HubSettings(url: url, token: token).location
    }

    var body: some View {
        Form {
            statusSection

            Section {
                TextField("http://192.168.1.10:8787", text: $url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.body.monospaced())

                HStack(spacing: 8) {
                    if showToken {
                        TextField("Hub token", text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                    } else {
                        SecureField("Hub token", text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                    }
                    Button {
                        showToken.toggle()
                    } label: {
                        Image(systemName: showToken ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showToken ? "Hide token" : "Show token")
                }

                Button {
                    saveAndConnect()
                } label: {
                    Label(store.connection.isConnected ? "Save & Reconnect" : "Save & Connect", systemImage: "link")
                }
                .disabled(candidate == nil)

                Button {
                    Task { await validate() }
                } label: {
                    HStack(spacing: 8) {
                        if testing { ProgressView().controlSize(.small) }
                        Text(testing ? "Testing…" : "Test connection")
                    }
                }
                .disabled(candidate == nil || testing)

                if let testMessage {
                    Label(testMessage, systemImage: testSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(testSucceeded ? Theme.accent : Theme.warn)
                }

                if let savedMessage {
                    Label(savedMessage, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
            } header: {
                Text("Hub connection")
            } footer: {
                Text("Use the Mac's LAN address — for example http://192.168.1.10:8787 — while the phone is on the same network. The hub prints the URL, token, and a pairing link when it starts.")
            }

            Section {
                TextField("opencodebar://pair?url=…&token=…", text: $pairingLink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.caption.monospaced())

                Button {
                    applyPairingLink()
                } label: {
                    Label("Apply pairing link", systemImage: "qrcode")
                }
                .disabled(pairingLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Pairing link")
            } footer: {
                Text("Paste the pairing link printed by the hub, or tap one from a message. The token is stored only on this device.")
            }

            Section("How to connect") {
                Label("On your Mac, run `make hub` in the ai-tools folder.", systemImage: "terminal")
                Label("Keep the Mac awake and on the same Wi-Fi network.", systemImage: "wifi")
                Label("If the connection fails, allow OpenCodeBar in System Settings → Network → Local Network.", systemImage: "hand.raised")
            }
            .font(.footnote)

            Section {
                Button(role: .destructive) {
                    settings.clear()
                    store.disconnect()
                    url = ""
                    token = ""
                    testMessage = nil
                    savedMessage = nil
                } label: {
                    Label("Remove hub configuration", systemImage: "trash")
                }
            } footer: {
                Text("Removing the configuration does not change anything on the Mac; run `make hub` again to reconnect.")
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            guard !loaded else { return }
            loaded = true
            url = settings.url
            token = settings.token
        }
        .task {
            await store.refreshHealth()
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        Section {
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
        } header: {
            Text("Status")
        } footer: {
            if !settings.isConfigured {
                Text("No hub configured yet. Start the hub on your Mac and add its URL and token below.")
            }
        }
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .font(.caption.monospaced())
                .lineLimit(1)
        }
    }

    private func duration(seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        return "\(seconds / 3_600)h \((seconds % 3_600) / 60)m"
    }

    // MARK: - Actions

    private func saveAndConnect() {
        guard candidate != nil else { return }
        settings.save(url: url, token: token)
        store.reconnect()
        savedMessage = "Saved — connecting…"
        testMessage = nil
        Task { await validate() }
    }

    private func applyPairingLink() {
        guard settings.applyPairingLink(pairingLink) else {
            testSucceeded = false
            testMessage = "That does not look like a valid pairing link."
            return
        }
        url = settings.url
        token = settings.token
        pairingLink = ""
        store.reconnect()
        savedMessage = "Paired — connecting…"
        Task { await validate() }
    }

    private func validate() async {
        guard let candidate else {
            testSucceeded = false
            testMessage = "Enter a valid http(s) URL and a token."
            return
        }
        testing = true
        defer { testing = false }
        testMessage = nil

        guard await HubAPI.ping(baseURL: candidate.url) else {
            testSucceeded = false
            testMessage = "No hub answered at \(candidate.url.absoluteString). Check the address and that `make hub` is running."
            return
        }

        do {
            let health = try await HubAPI(location: candidate).health()
            let opencode = health.opencode?.connected == true ? "connected" : "offline"
            testSucceeded = true
            testMessage = "Hub \(health.hub?.version ?? health.version ?? "?") · OpenCode \(opencode)"
        } catch {
            testSucceeded = false
            testMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
