import SwiftUI

/// Creates a declarative NixOS guest. The first build can take a while, so the
/// sheet only confirms the definition; the VM's detail page streams the build.
struct NewVirtualMachineSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var model: VirtualMachinesStore

    @State private var name = "NixOS"
    @State private var cpuCount = 4
    @State private var memoryMB = 4_096
    @State private var diskGB = 20
    @State private var channel = "nixos-26.05"
    @State private var packagesText = ""
    @State private var autostart = true
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var didLoadDefaults = false

    private var capabilities: VMCapabilities? { model.capabilities }

    private var packages: [String] {
        packagesText
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        !trimmedName.isEmpty &&
            !isWorking &&
            (capabilities?.ready ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            field("NAME") {
                TextField("NixOS development", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .disabled(isWorking)
            }

            HStack(alignment: .top, spacing: 12) {
                field("CPU") {
                    Stepper(value: $cpuCount, in: 1...max(1, capabilities?.maxCPU ?? 8)) {
                        Text("\(cpuCount) cores")
                            .font(.system(size: 11))
                            .monospacedDigit()
                    }
                    .disabled(isWorking)
                }

                field("MEMORY") {
                    Stepper(
                        value: $memoryMB,
                        in: 1_024...max(1_024, capabilities?.maxMemoryMB ?? 8_192),
                        step: 1_024
                    ) {
                        Text("\(memoryMB / 1_024) GB")
                            .font(.system(size: 11))
                            .monospacedDigit()
                    }
                    .disabled(isWorking)
                }

                field("DISK") {
                    Stepper(value: $diskGB, in: 8...256, step: 4) {
                        Text("\(diskGB) GB")
                            .font(.system(size: 11))
                            .monospacedDigit()
                    }
                    .disabled(isWorking)
                }
            }

            field("NIXOS CHANNEL") {
                TextField("nixos-26.05", text: $channel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .disabled(isWorking)
                Text("The flake pins nixpkgs to this ref. The guest keeps its original stateVersion.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            field("EXTRA PACKAGES") {
                TextField("nodejs, python3, ripgrep", text: $packagesText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .disabled(isWorking)
                Text("Comma or space separated. Base: curl, git, htop, vim.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Toggle("Start after the image is built", isOn: $autostart)
                .font(.system(size: 11))
                .disabled(isWorking)

            if let capabilities, !capabilities.ready {
                VMSetupNotice(capabilities: capabilities)
            }

            if let errorMessage {
                NoticeRow(icon: "exclamationmark.triangle.fill", message: errorMessage, tint: Theme.warn)
            }

            HStack {
                Text("Built with \(capabilities?.nixVersion ?? "Nix") and Apple Virtualization.framework.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)
                Button {
                    Task { await create() }
                } label: {
                    HStack(spacing: 5) {
                        if isWorking { ProgressView().controlSize(.small).scaleEffect(0.7) }
                        Text(isWorking ? "Creating…" : "Create VM")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
            }
        }
        .padding(14)
        .frame(width: 420)
        .onAppear(perform: loadDefaults)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("New NixOS VM")
                    .font(.system(size: 15, weight: .semibold))
                Text("A declarative guest: packages are applied with nixos-rebuild.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Cancel")
            .disabled(isWorking)
        }
    }

    private func field<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func loadDefaults() {
        guard !didLoadDefaults else { return }
        didLoadDefaults = true
        guard let capabilities else { return }
        cpuCount = capabilities.defaultCPU
        memoryMB = capabilities.defaultMemoryMB
        channel = capabilities.defaultChannel
    }

    private func create() async {
        guard let api = state.api else {
            errorMessage = "Not connected to the hub"
            return
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            _ = try await model.create(
                api: api,
                name: trimmedName,
                cpuCount: cpuCount,
                memoryMB: memoryMB,
                diskGB: diskGB,
                channel: channel.trimmingCharacters(in: .whitespacesAndNewlines),
                packages: packages
            )
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
