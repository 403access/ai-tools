import SwiftUI

/// Mobile create flow for a NixOS guest. Mirrors the Mac sheet: a small set of
/// declarative fields, with the host prerequisites shown inline.
struct MobileNewVirtualMachineSheet: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var model: VirtualMachinesStore
    let onCreated: (VirtualMachine) -> Void

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("The hub builds a raw EFI NixOS image, boots it with Virtualization.framework, and applies package changes over SSH.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    field("Name") {
                        TextField("NixOS development", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isWorking)
                    }

                    HStack(alignment: .top, spacing: 12) {
                        field("CPU") {
                            Stepper(value: $cpuCount, in: 1...max(1, capabilities?.maxCPU ?? 8)) {
                                Text("\(cpuCount) cores")
                                    .font(.footnote)
                                    .monospacedDigit()
                            }
                            .disabled(isWorking)
                        }
                        field("Memory") {
                            Stepper(
                                value: $memoryMB,
                                in: 1_024...max(1_024, capabilities?.maxMemoryMB ?? 8_192),
                                step: 1_024
                            ) {
                                Text("\(memoryMB / 1_024) GB")
                                    .font(.footnote)
                                    .monospacedDigit()
                            }
                            .disabled(isWorking)
                        }
                    }

                    field("Disk") {
                        Stepper(value: $diskGB, in: 8...256, step: 4) {
                            Text("\(diskGB) GB")
                                .font(.footnote)
                                .monospacedDigit()
                        }
                        .disabled(isWorking)
                    }

                    field("NixOS channel") {
                        TextField("nixos-26.05", text: $channel)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .disabled(isWorking)
                    }

                    field("Extra packages") {
                        TextField("nodejs, python3, ripgrep", text: $packagesText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .disabled(isWorking)
                        Text("Comma or space separated. Base: curl, git, htop, vim.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Start after the image is built", isOn: $autostart)
                        .font(.footnote)
                        .disabled(isWorking)

                    if let capabilities, !capabilities.ready {
                        VMSetupNotice(capabilities: capabilities)
                    }

                    if let errorMessage {
                        NoticeRow(
                            icon: "exclamationmark.triangle.fill",
                            message: errorMessage,
                            tint: Theme.warn
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .mobileScreenBackground()
            .navigationTitle("New NixOS VM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await create() }
                    } label: {
                        if isWorking {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Create")
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canCreate)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isWorking {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Creating the VM definition…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear(perform: loadDefaults)
    }

    private var canCreate: Bool {
        !trimmedName.isEmpty && !isWorking && (capabilities?.ready ?? false)
    }

    private func field<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
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
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let machine = try await model.create(
                api: store.api,
                name: trimmedName,
                cpuCount: cpuCount,
                memoryMB: memoryMB,
                diskGB: diskGB,
                channel: channel.trimmingCharacters(in: .whitespacesAndNewlines),
                packages: packages
            )
            onCreated(machine)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
