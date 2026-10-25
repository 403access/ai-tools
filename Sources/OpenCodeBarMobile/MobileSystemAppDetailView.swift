import SwiftUI

/// Detail page for one installed application on the Mac running the hub.
/// Mirrors `SystemAppDetailView` on macOS with touch-sized controls, and adds
/// Xcode's simulator inventory plus its management actions.
struct MobileSystemAppDetailView: View {
    @EnvironmentObject private var store: MobileStore

    let app: SystemApp

    @State private var detail: SystemAppDetail?
    @State private var isLoading = false
    @State private var error: String?
    @State private var actionError: String?
    @State private var busyAction: String?
    @State private var showAllFrameworks = false
    @State private var showAllSDKs = false
    @State private var deleteDevice: SystemSimulatorDevice?
    @State private var deleteRuntime: SystemSimulatorRuntime?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let error {
                    NoticeRow(icon: "exclamationmark.triangle.fill", message: error, tint: Theme.warn)
                }
                if let actionError {
                    NoticeRow(icon: "exclamationmark.triangle.fill", message: actionError, tint: Theme.warn)
                }

                if isLoading && detail == nil {
                    LoadingState(message: "Reading application details…")
                        .card()
                } else if let detail {
                    basics(detail)
                    extensions(detail)
                    if let xcode = detail.xcode {
                        xcodeSection(xcode)
                    }
                } else if error == nil {
                    LoadingState(message: "Reading application details…")
                        .card()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .mobileScreenBackground()
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    MobileFileBrowserView(startPath: app.path)
                } label: {
                    Image(systemName: "folder")
                }
                .accessibilityLabel("Browse app bundle")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isLoading)
                .accessibilityLabel("Reload app details")
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .alert(
            "Delete simulator?",
            isPresented: Binding(
                get: { deleteDevice != nil },
                set: { if !$0 { deleteDevice = nil } }
            ),
            presenting: deleteDevice
        ) { device in
            Button("Delete \(device.name)", role: .destructive) {
                Task { await run("simulator.delete", target: device.udid) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { device in
            Text("\(device.name) and its data will be removed from the Mac. This cannot be undone.")
        }
        .alert(
            "Delete simulator runtime?",
            isPresented: Binding(
                get: { deleteRuntime != nil },
                set: { if !$0 { deleteRuntime = nil } }
            ),
            presenting: deleteRuntime
        ) { runtime in
            Button("Delete \(runtime.name)", role: .destructive) {
                Task { await run("runtime.delete", target: runtime.identifier) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { runtime in
            Text("\(runtime.name) and every device using it will be removed from the Mac.")
        }
    }

    // MARK: - Basics

    private func basics(_ detail: SystemAppDetail) -> some View {
        let info = detail.info
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Application") {
                if let version = info.version ?? detail.app.version {
                    Chip(text: version, systemImage: "shippingbox", tint: Theme.cacheRead)
                }
            }

            HStack(spacing: 12) {
                AppIconView(
                    api: store.api,
                    path: detail.app.path,
                    hasIcon: detail.app.hasIcon == true,
                    size: 48
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(info.displayName ?? detail.app.name)
                        .font(.headline)
                        .lineLimit(2)
                    if let bundleID = info.bundleID ?? detail.app.bundleID {
                        Text(bundleID)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let source = detail.app.source {
                        Text(sourceLabel(source))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 0)

            VStack(alignment: .leading, spacing: 9) {
                if let version = info.version ?? detail.app.version {
                    MobileAppDetailRow("Version", version)
                }
                if let build = info.build {
                    MobileAppDetailRow("Build", build, monospaced: true)
                }
                if let size = info.sizeBytes {
                    MobileAppDetailRow("Size", Fmt.bytes(size))
                }
                if let modified = detail.app.lastModified {
                    MobileAppDetailRow("Modified", modified)
                }
                if let architecture = detail.app.architecture {
                    MobileAppDetailRow("Architecture", architecture)
                }
                if let minimumOS = info.minimumOS {
                    MobileAppDetailRow("Minimum OS", minimumOS)
                }
                if let executable = info.executable {
                    MobileAppDetailRow("Executable", executable, monospaced: true)
                }
                if let signing = info.signing, signing.verified || signing.authority != nil {
                    Divider().opacity(0.5)
                    MobileAppDetailRow("Signed by", signing.authority ?? "Unknown identity")
                    if let team = signing.teamID {
                        MobileAppDetailRow("Team ID", team, monospaced: true)
                    }
                    MobileAppDetailRow(
                        "Signature",
                        signing.verified ? "Valid" : "Not verified",
                        tint: signing.verified ? Theme.accent : Theme.warn
                    )
                }
                if let schemes = info.urlSchemes, !schemes.isEmpty {
                    Divider().opacity(0.5)
                    MobileAppDetailRow("URL schemes", schemes.joined(separator: ", "), monospaced: true)
                }
                if let types = info.documentTypes, !types.isEmpty {
                    MobileAppDetailRow("Documents", types.prefix(8).joined(separator: ", "))
                }
                if let copyright = info.copyright {
                    Divider().opacity(0.5)
                    Text(copyright)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider().opacity(0.5)
                MobileAppDetailRow("Path", detail.app.path, monospaced: true)
            }
            .card()
        }
    }

    private func sourceLabel(_ source: String) -> String {
        switch source.lowercased() {
        case "apple": return "Apple"
        case "mac_app_store": return "Mac App Store"
        case "identified_developer": return "Identified developer"
        default: return source
        }
    }

    @ViewBuilder
    private func extensions(_ detail: SystemAppDetail) -> some View {
        if !detail.info.extensions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Extensions") {
                    Text("\(detail.info.extensions.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(detail.info.extensions) { item in
                        HStack(spacing: 9) {
                            Image(systemName: item.kind == "xpc" ? "gearshape.2" : "puzzlepiece.extension")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.reasoning)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Text(item.path)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 4)
                            Text(item.kindLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .card()
            }
        }
    }

    // MARK: - Xcode

    private func xcodeSection(_ xcode: SystemXcodeDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Xcode") {
                if xcode.bootedCount > 0 {
                    Chip(
                        text: "\(xcode.bootedCount) running",
                        systemImage: "play.fill",
                        tint: Theme.accent
                    )
                } else {
                    Chip(text: "Idle", systemImage: "moon.zzz", tint: .secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                if let version = xcode.version {
                    MobileAppDetailRow("Version", version)
                }
                if let developerDir = xcode.developerDir {
                    MobileAppDetailRow("Developer dir", developerDir, monospaced: true)
                }
                if let error = xcode.error {
                    NoticeRow(icon: "exclamationmark.triangle.fill", message: error, tint: Theme.warn)
                }
            }
            .card()

            simulatorSection(xcode)
            sdkSection(xcode)
            frameworkSection(xcode)
        }
    }

    private func simulatorSection(_ xcode: SystemXcodeDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("SIMULATORS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 4)
                Text("\(xcode.simulators.count) runtimes · \(xcode.devices.count) devices")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            if xcode.simulators.isEmpty {
                Text("No simulator runtimes are installed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                ForEach(xcode.simulators) { runtime in
                    simulatorRuntime(runtime)
                }
            }
        }
    }

    private func simulatorRuntime(_ runtime: SystemSimulatorRuntime) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: simulatorIcon(runtime.platform))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text(runtime.name)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                if !runtime.available {
                    Chip(text: "Unavailable", systemImage: "exclamationmark.triangle", tint: Theme.warn)
                } else if runtime.bootedCount > 0 {
                    Chip(text: "\(runtime.bootedCount) booted", systemImage: "play.fill", tint: Theme.accent)
                }
                Menu {
                    Button("Delete runtime…", role: .destructive) {
                        deleteRuntime = runtime
                    }
                    .disabled(busyAction != nil)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.bold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel("Runtime actions")
            }

            if let build = runtime.build {
                Text(build)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }

            if runtime.devices.isEmpty {
                Text("No devices created for this runtime.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(runtime.devices) { device in
                    simulatorDevice(device)
                    if device.id != runtime.devices.last?.id {
                        Divider().opacity(0.35)
                    }
                }
            }
        }
        .card()
    }

    private func simulatorDevice(_ device: SystemSimulatorDevice) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(device.isBooted ? Theme.accent : Color.secondary.opacity(0.4))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(device.state.capitalized)
                        .foregroundStyle(device.isBooted ? Theme.accent : .secondary)
                    if let size = device.dataSizeBytes, size > 0 {
                        Text("·")
                        Text(Fmt.bytes(size))
                    }
                    if let used = device.lastUsedAt, !device.isBooted {
                        Text("·")
                        Text("used \(relativeDate(used))")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            if busyAction == device.udid {
                ProgressView().controlSize(.small)
            } else if device.isBooted {
                Button("Shut Down") {
                    Task { await run("simulator.shutdown", target: device.udid) }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(Theme.warn)
                .disabled(busyAction != nil)

                Menu {
                    Button("Delete…", role: .destructive) {
                        deleteDevice = device
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.bold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(.secondary)
                .disabled(busyAction != nil)
                .accessibilityLabel("Simulator actions")
            } else {
                Button("Boot") {
                    Task { await run("simulator.boot", target: device.udid) }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(Theme.accent)
                .disabled(busyAction != nil)

                Menu {
                    Button("Erase…") {
                        Task { await run("simulator.erase", target: device.udid) }
                    }
                    Button("Delete…", role: .destructive) {
                        deleteDevice = device
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.bold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(.secondary)
                .disabled(busyAction != nil)
                .accessibilityLabel("Simulator actions")
            }
        }
        .contextMenu {
            if device.isBooted {
                Button("Shut Down") {
                    Task { await run("simulator.shutdown", target: device.udid) }
                }
            } else {
                Button("Boot") {
                    Task { await run("simulator.boot", target: device.udid) }
                }
                Button("Erase…") {
                    Task { await run("simulator.erase", target: device.udid) }
                }
            }
            Button("Delete…", role: .destructive) {
                deleteDevice = device
            }
        }
    }

    private func sdkSection(_ xcode: SystemXcodeDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("INSTALLED SDKS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 4)
                Text("\(xcode.sdks.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 10) {
                if xcode.sdks.isEmpty {
                    Text("No SDKs reported.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleSDKs(xcode.sdks)) { sdk in
                        HStack(spacing: 9) {
                            Image(systemName: "hammer")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.cacheRead)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sdk.name)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                if let path = sdk.path {
                                    Text(path)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            Spacer(minLength: 4)
                            if let platform = sdk.platform {
                                Text(platform)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    if xcode.sdks.count > 8 {
                        Button(showAllSDKs ? "Show fewer" : "Show all \(xcode.sdks.count) SDKs") {
                            showAllSDKs.toggle()
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                    }
                }
            }
            .card()
        }
    }

    private func visibleSDKs(_ sdks: [SystemXcodeSDK]) -> [SystemXcodeSDK] {
        showAllSDKs ? sdks : Array(sdks.prefix(8))
    }

    private func frameworkSection(_ xcode: SystemXcodeDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("FRAMEWORKS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 4)
                Text("\(xcode.frameworks.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 10) {
                if xcode.frameworks.isEmpty {
                    Text("No frameworks found in the developer directory.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleFrameworks(xcode.frameworks)) { framework in
                        HStack(spacing: 9) {
                            Image(systemName: "shippingbox")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.reasoning)
                                .frame(width: 16)
                            Text(framework.name)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(framework.platform)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    if xcode.frameworks.count > 12 {
                        Button(showAllFrameworks ? "Show fewer" : "Show all \(xcode.frameworks.count) frameworks") {
                            showAllFrameworks.toggle()
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                    }
                }
            }
            .card()
        }
    }

    private func visibleFrameworks(_ frameworks: [SystemXcodeFramework]) -> [SystemXcodeFramework] {
        showAllFrameworks ? frameworks : Array(frameworks.prefix(12))
    }

    private func simulatorIcon(_ platform: String) -> String {
        switch platform.lowercased() {
        case "ios": return "iphone"
        case "watchos": return "applewatch"
        case "tvos": return "appletv"
        case "xros", "visionos": return "visionpro"
        default: return "display"
        }
    }

    private func relativeDate(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        return date.map { Fmt.relative(from: $0) } ?? value
    }

    // MARK: - Data

    private func load() async {
        guard let api = store.api else {
            error = "Connect to a hub to read app details."
            return
        }
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            detail = try await api.systemAppDetail(path: app.path)
            actionError = nil
        } catch {
            if detail == nil {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func run(_ action: String, target: String?) async {
        guard let api = store.api, busyAction == nil else { return }
        busyAction = target ?? action
        actionError = nil
        defer { busyAction = nil }

        do {
            detail = try await api.systemAppAction(path: app.path, action: action, target: target)
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct MobileAppDetailRow: View {
    let label: String
    let value: String
    var monospaced = false
    var tint: Color = .secondary

    init(_ label: String, _ value: String, monospaced: Bool = false, tint: Color = .secondary) {
        self.label = label
        self.value = value
        self.monospaced = monospaced
        self.tint = tint
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .caption.weight(.medium))
                .foregroundStyle(tint == .secondary ? Color.primary : tint)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}
