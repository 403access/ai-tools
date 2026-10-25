import SwiftUI

/// Detail page for one installed application. It starts with the bundle's
/// metadata and adds app-specific inventory when the hub provides it — Xcode
/// gets simulator runtimes and devices, SDKs and shipped frameworks, with
/// boot/shutdown/erase/delete controls for simulators.
struct SystemAppDetailView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

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
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let error {
                        NoticeRow(icon: "exclamationmark.triangle.fill", message: error, tint: Theme.warn)
                    }
                    if let actionError {
                        NoticeRow(icon: "exclamationmark.triangle.fill", message: actionError, tint: Theme.warn)
                    }

                    if isLoading && detail == nil {
                        loading
                    } else if let detail {
                        basics(detail)
                        extensions(detail)
                        if let xcode = detail.xcode {
                            xcodeSection(xcode)
                        }
                    } else if error == nil {
                        loading
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 560, height: 660)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await load() }
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

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Back to System")

            AppIconView(
                api: state.api,
                path: app.path,
                hasIcon: app.hasIcon == true,
                size: 30
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(app.path)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            if isLoading {
                ProgressView().controlSize(.small).scaleEffect(0.65)
            }

            Button {
                Task { await load() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(isLoading)
            .help("Reload app details")

            Button {
                let path = app.path
                dismiss()
                state.openFileBrowser(at: path)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Browse the app bundle")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var loading: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Reading application details…")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
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
            VStack(alignment: .leading, spacing: 8) {
                if let displayName = info.displayName, displayName != detail.app.name {
                    AppDetailRow("Bundle name", displayName)
                }
                if let bundleID = info.bundleID ?? detail.app.bundleID {
                    AppDetailRow("Bundle ID", bundleID, monospaced: true)
                }
                if let version = info.version ?? detail.app.version {
                    AppDetailRow("Version", version)
                }
                if let build = info.build {
                    AppDetailRow("Build", build, monospaced: true)
                }
                if let size = info.sizeBytes {
                    AppDetailRow("Size", Fmt.bytes(size))
                }
                if let modified = detail.app.lastModified {
                    AppDetailRow("Modified", modified)
                }
                if let source = detail.app.source {
                    AppDetailRow("Source", sourceLabel(source))
                }
                if let architecture = detail.app.architecture {
                    AppDetailRow("Architecture", architecture)
                }
                if let minimumOS = info.minimumOS {
                    AppDetailRow("Minimum OS", minimumOS)
                }
                if let executable = info.executable {
                    AppDetailRow("Executable", executable, monospaced: true)
                }
                if let path = detail.info.signing, path.verified || path.authority != nil {
                    Divider().opacity(0.5)
                    AppDetailRow("Signed by", path.authority ?? "Unknown identity")
                    if let team = path.teamID {
                        AppDetailRow("Team ID", team, monospaced: true)
                    }
                    AppDetailRow(
                        "Signature",
                        path.verified ? "Valid" : "Not verified",
                        tint: path.verified ? Theme.accent : Theme.warn
                    )
                }
                if let schemes = info.urlSchemes, !schemes.isEmpty {
                    Divider().opacity(0.5)
                    AppDetailRow("URL schemes", schemes.joined(separator: ", "), monospaced: true)
                }
                if let types = info.documentTypes, !types.isEmpty {
                    AppDetailRow("Documents", types.prefix(8).joined(separator: ", "))
                }
                if let copyright = info.copyright {
                    Divider().opacity(0.5)
                    Text(copyright)
                        .font(.system(size: 8.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider().opacity(0.5)
                AppDetailRow("Path", detail.app.path, monospaced: true)
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
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(detail.info.extensions) { item in
                        HStack(spacing: 7) {
                            Image(systemName: item.kind == "xpc" ? "gearshape.2" : "puzzlepiece.extension")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.reasoning)
                                .frame(width: 14)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name)
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                Text(item.path)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 4)
                            Text(item.kindLabel)
                                .font(.system(size: 8))
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

            VStack(alignment: .leading, spacing: 9) {
                if let version = xcode.version {
                    AppDetailRow("Version", version)
                }
                if let developerDir = xcode.developerDir {
                    AppDetailRow("Developer dir", developerDir, monospaced: true)
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
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 4)
                Text("\(xcode.simulators.count) runtimes · \(xcode.devices.count) devices")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            if xcode.simulators.isEmpty {
                Text("No simulator runtimes are installed.")
                    .font(.system(size: 10))
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: simulatorIcon(runtime.platform))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(runtime.name)
                    .font(.system(size: 11, weight: .semibold))
                if let build = runtime.build {
                    Text(build)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
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
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 20, height: 18)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 20)
                .foregroundStyle(.secondary)
                .help("Runtime actions")
            }

            if runtime.devices.isEmpty {
                Text("No devices created for this runtime.")
                    .font(.system(size: 9))
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
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(device.isBooted ? Theme.accent : Color.secondary.opacity(0.4))
                .frame(width: 5, height: 5)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 10, weight: .medium))
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
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            if busyAction == device.udid {
                ProgressView().controlSize(.small).scaleEffect(0.55)
            } else if device.isBooted {
                Button("Shut Down") {
                    Task { await run("simulator.shutdown", target: device.udid) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(Theme.warn)
                .disabled(busyAction != nil)

                Menu {
                    Button("Delete…", role: .destructive) {
                        deleteDevice = device
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 18, height: 16)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 18)
                .foregroundStyle(.secondary)
                .disabled(busyAction != nil)
            } else {
                Button("Boot") {
                    Task { await run("simulator.boot", target: device.udid) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(Theme.accent)
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
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 18, height: 16)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 18)
                .foregroundStyle(.secondary)
                .disabled(busyAction != nil)
            }
        }
        .help(device.udid)
    }

    private func sdkSection(_ xcode: SystemXcodeDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("INSTALLED SDKS")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 4)
                Text("\(xcode.sdks.count)")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 7) {
                if xcode.sdks.isEmpty {
                    Text("No SDKs reported.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleSDKs(xcode.sdks)) { sdk in
                        HStack(spacing: 7) {
                            Image(systemName: "hammer")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.cacheRead)
                                .frame(width: 14)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(sdk.name)
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                if let path = sdk.path {
                                    Text(path)
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            Spacer(minLength: 4)
                            if let platform = sdk.platform {
                                Text(platform)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .help(sdk.canonicalName ?? sdk.name)
                    }
                    if xcode.sdks.count > 8 {
                        Button(showAllSDKs ? "Show fewer" : "Show all \(xcode.sdks.count) SDKs") {
                            showAllSDKs.toggle()
                        }
                        .font(.system(size: 9, weight: .semibold))
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
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 4)
                Text("\(xcode.frameworks.count)")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 7) {
                if xcode.frameworks.isEmpty {
                    Text("No frameworks found in the developer directory.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleFrameworks(xcode.frameworks)) { framework in
                        HStack(spacing: 7) {
                            Image(systemName: "shippingbox")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.reasoning)
                                .frame(width: 14)
                            Text(framework.name)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(framework.platform)
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        .help(framework.path)
                    }
                    if xcode.frameworks.count > 12 {
                        Button(showAllFrameworks ? "Show fewer" : "Show all \(xcode.frameworks.count) frameworks") {
                            showAllFrameworks.toggle()
                        }
                        .font(.system(size: 9, weight: .semibold))
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
        guard let api = state.api else {
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
        guard let api = state.api, busyAction == nil else { return }
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

private struct AppDetailRow: View {
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
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(monospaced ? .system(size: 9, design: .monospaced) : .system(size: 10, weight: .medium))
                .foregroundStyle(tint == .secondary ? Color.primary : tint)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}
