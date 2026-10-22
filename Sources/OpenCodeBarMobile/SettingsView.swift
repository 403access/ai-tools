import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: HubSettingsStore
    @EnvironmentObject private var store: MobileStore
    @EnvironmentObject private var appearance: AppearanceStore

    @State private var url = ""
    @State private var token = ""
    @State private var pairingLink = ""
    @State private var showScanner = false
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                appearanceSection
                statusSection
                connectionSection
                pairingSection
                howToSection
                removeSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .mobileScreenBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showScanner) {
            PairingScannerSheet { code in
                applyPairingLink(code)
            }
        }
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

    // MARK: - Appearance

    private var appearanceSection: some View {
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

    private var statusSection: some View {
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

    private var connectionSection: some View {
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

    // MARK: - Pairing

    private var pairingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Pairing")

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    showScanner = true
                } label: {
                    Label("Scan QR code", systemImage: "qrcode.viewfinder")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Text("Or paste a pairing link")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("opencodebar://pair?url=…&token=…", text: $pairingLink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.caption.monospaced())
                    .mobileField()

                Button {
                    applyPairingLink()
                } label: {
                    Label("Apply pairing link", systemImage: "link")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(pairingLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .card(padding: 12)

            sectionNote("Scan the QR code from the Mac app's Settings → Pairing, or paste the link printed by the hub. The token is stored only on this device.")
        }
    }

    // MARK: - Help

    private var howToSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("How to connect")

            VStack(alignment: .leading, spacing: 12) {
                helpRow("On your Mac, run `make hub` in the ai-tools folder.", icon: "terminal")
                helpRow("On the same Wi-Fi, use the Mac's LAN address. On cellular, run `make hub-tunnel` and use the printed HTTPS URL.", icon: "wifi")
                helpRow("If the connection fails, allow OpenCodeBar in System Settings → Network → Local Network.", icon: "hand.raised")
            }
            .card(padding: 12)
        }
    }

    // MARK: - Remove

    private var removeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(role: .destructive) {
                settings.clear()
                store.disconnect()
                url = ""
                token = ""
                testMessage = nil
                savedMessage = nil
            } label: {
                Label("Remove hub configuration", systemImage: "trash")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.danger)
            .card(padding: 10)

            sectionNote("Removing the configuration does not change anything on the Mac; run `make hub` again to reconnect.")
        }
    }

    // MARK: - Pieces

    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .font(.caption.monospaced())
                .lineLimit(1)
        }
    }

    private func helpRow(_ text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 17)
                .padding(.top, 1)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func sectionNote(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 2)
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

    private func applyPairingLink(_ link: String? = nil) {
        let value = link ?? pairingLink
        guard settings.applyPairingLink(value) else {
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

/// Recessed field background used by the settings cards.
private extension View {
    func mobileField() -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(MobileTheme.field)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(MobileTheme.border, lineWidth: 1)
            )
    }
}
