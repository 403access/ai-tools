import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: HubSettingsStore
    @EnvironmentObject var store: MobileStore
    @EnvironmentObject var appearance: AppearanceStore

    @State var url = ""
    @State var token = ""
    @State var pairingLink = ""
    @State var showScanner = false
    @State var showToken = false
    @State var loaded = false
    @State var testing = false
    @State var testMessage: String?
    @State var testSucceeded = false
    @State var savedMessage: String?

    var candidate: HubLocation? {
        HubSettings(url: url, token: token).location
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                appearanceSection
                statusSection
                powerSection
                agentsSection
                connectionSection
                pairingSection
                howToSection
                developerSection
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
            await store.refreshSettings()
        }
    }

    // MARK: - Pairing

    var pairingSection: some View {
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

    var howToSection: some View {
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

    // MARK: - Developer

    var developerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Developer")

            NavigationLink {
                DeveloperView()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "ladybug")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Activity log")
                            .font(.subheadline.weight(.medium))
                        Text("API requests, syncs, events, and errors")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 6)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .card(padding: 12)

            sectionNote("Kept in memory on this device. Useful when the hub is slow or a request fails.")
        }
    }

    // MARK: - Remove

    var removeSection: some View {
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

    func statusRow(_ label: String, _ value: String) -> some View {
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

    func helpRow(_ text: String, icon: String) -> some View {
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

    func sectionNote(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 2)
    }

    func duration(seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        return "\(seconds / 3_600)h \((seconds % 3_600) / 60)m"
    }

    // MARK: - Actions

    func saveAndConnect() {
        guard candidate != nil else { return }
        settings.save(url: url, token: token)
        store.reconnect()
        savedMessage = "Saved — connecting…"
        testMessage = nil
        Task { await validate() }
    }

    func applyPairingLink(_ link: String? = nil) {
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

    func validate() async {
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
extension View {
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
