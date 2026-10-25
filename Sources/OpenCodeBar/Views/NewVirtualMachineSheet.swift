import SwiftUI

/// Creates a declarative NixOS guest with the full click-together builder.
/// The sheet only saves the definition; the VM detail page streams the build.
struct NewVirtualMachineSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var model: VirtualMachinesStore
    @StateObject private var builder: NixOSBuilderModel

    init(model: VirtualMachinesStore) {
        self.model = model
        _builder = StateObject(
            wrappedValue: NixOSBuilderModel(
                mode: .create,
                catalog: model.catalog,
                capabilities: model.capabilities
            )
        )
    }

    private var capabilities: VMCapabilities? { model.capabilities }

    private var canCreate: Bool {
        builder.canSave && capabilities?.ready == true
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            NixOSBuilderWorkspace(model: builder, store: model, api: state.api)
            Divider().opacity(0.4)
            footer
        }
        .frame(width: 940, height: 740)
        .task {
            await model.loadCatalog(api: state.api)
            if let catalog = model.catalog {
                builder.attach(catalog: catalog, capabilities: model.capabilities)
            }
        }
        .task(id: builder.previewSignature) {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await builder.refreshPreview(api: state.api, store: model)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.accent.opacity(0.14))
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("Build a NixOS machine")
                    .font(.system(size: 17, weight: .semibold))
                Text("Click together users, apps, and infrastructure. The hub renders configuration.nix, builds the image, and keeps it declarative.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let catalog = model.catalog {
                Chip(text: "\(catalog.options.count) options", systemImage: "square.grid.2x2.fill", tint: Theme.input)
                Chip(text: "\(catalog.presets.count) presets", systemImage: "wand.and.stars", tint: Theme.reasoning)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Cancel")
            .disabled(builder.isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let capabilities, !capabilities.ready {
                VMSetupNotice(capabilities: capabilities)
            }

            if let issue = builder.issueMessage ?? builder.saveError {
                NoticeRow(icon: "exclamationmark.triangle.fill", message: issue, tint: Theme.warn)
            }

            HStack(spacing: 10) {
                field("NAME") {
                    TextField("NixOS development", text: $builder.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .frame(width: 190)
                        .disabled(builder.isSaving)
                }

                field("CPU") {
                    Stepper(value: $builder.cpuCount, in: 1...max(1, capabilities?.maxCPU ?? 8)) {
                        Text("\(builder.cpuCount) cores")
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .frame(width: 52, alignment: .leading)
                    }
                    .disabled(builder.isSaving || !builder.canEditResources)
                }

                field("MEMORY") {
                    Stepper(
                        value: $builder.memoryMB,
                        in: 1_024...max(1_024, capabilities?.maxMemoryMB ?? 8_192),
                        step: 1_024
                    ) {
                        Text("\(builder.memoryMB / 1_024) GB")
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .frame(width: 42, alignment: .leading)
                    }
                    .disabled(builder.isSaving || !builder.canEditResources)
                }

                field("DISK") {
                    Stepper(value: $builder.diskGB, in: 8...256, step: 4) {
                        Text("\(builder.diskGB) GB")
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .frame(width: 46, alignment: .leading)
                    }
                    .disabled(builder.isSaving)
                }

                field("CHANNEL") {
                    TextField("nixos-26.05", text: $builder.channel)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 128)
                        .disabled(builder.isSaving)
                }

                Toggle("Start after build", isOn: $builder.autostart)
                    .font(.system(size: 10))
                    .toggleStyle(.checkbox)
                    .disabled(builder.isSaving)

                Spacer(minLength: 6)

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(builder.isSaving)

                Button {
                    Task {
                        if await builder.save(api: state.api, store: model) != nil {
                            dismiss()
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        if builder.isSaving {
                            ProgressView().controlSize(.small).scaleEffect(0.7)
                        }
                        Text(builder.isSaving ? "Creating…" : "Create VM")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func field<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            content()
        }
    }
}

/// Edit an existing VM's declarative configuration without rebuilding its disk.
/// A running guest applies the change with `nixos-rebuild switch` over SSH.
struct NixOSConfigSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    let machine: VirtualMachine
    @ObservedObject var model: VirtualMachinesStore
    @StateObject private var builder: NixOSBuilderModel

    init(machine: VirtualMachine, model: VirtualMachinesStore) {
        self.machine = machine
        self.model = model
        _builder = StateObject(
            wrappedValue: NixOSBuilderModel(
                mode: .edit,
                machine: machine,
                catalog: model.catalog,
                capabilities: model.capabilities
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            NixOSBuilderWorkspace(model: builder, store: model, api: state.api)
            Divider().opacity(0.4)
            footer
        }
        .frame(width: 940, height: 740)
        .task {
            await model.loadCatalog(api: state.api)
            if let catalog = model.catalog {
                builder.attach(catalog: catalog, capabilities: model.capabilities)
            }
        }
        .task(id: builder.previewSignature) {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await builder.refreshPreview(api: state.api, store: model)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.reasoning.opacity(0.14))
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.reasoning)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("Configure \(machine.name)")
                    .font(.system(size: 16, weight: .semibold))
                Text(
                    machine.isRunning
                        ? "Changes are applied over SSH with nixos-rebuild switch when you save."
                        : "Changes are written to configuration.nix and applied the next time the guest boots."
                )
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
            Chip(text: machine.status.label, tint: Theme.accent)
            if machine.isRunning {
                Chip(text: "Live apply", systemImage: "bolt.fill", tint: Theme.warn)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close")
            .disabled(builder.isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let issue = builder.issueMessage ?? builder.saveError {
                NoticeRow(icon: "exclamationmark.triangle.fill", message: issue, tint: Theme.warn)
            }

            HStack(spacing: 10) {
                field("NAME") {
                    TextField("NixOS", text: $builder.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .frame(width: 190)
                        .disabled(builder.isSaving)
                }

                field("CPU") {
                    Stepper(value: $builder.cpuCount, in: 1...max(1, model.capabilities?.maxCPU ?? 8)) {
                        Text("\(builder.cpuCount) cores")
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .frame(width: 52, alignment: .leading)
                    }
                    .disabled(builder.isSaving || !builder.canEditResources)
                }

                field("MEMORY") {
                    Stepper(
                        value: $builder.memoryMB,
                        in: 1_024...max(1_024, model.capabilities?.maxMemoryMB ?? 8_192),
                        step: 1_024
                    ) {
                        Text("\(builder.memoryMB / 1_024) GB")
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .frame(width: 42, alignment: .leading)
                    }
                    .disabled(builder.isSaving || !builder.canEditResources)
                }

                field("DISK") {
                    Text("\(machine.diskGB) GB")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .frame(width: 46, alignment: .leading)
                }

                field("CHANNEL") {
                    Text(machine.channel)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 128, alignment: .leading)
                }

                if !builder.canEditResources {
                    Text("Stop the VM to change CPU or memory.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 6)

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(builder.isSaving)

                Button {
                    Task {
                        if await builder.save(api: state.api, store: model) != nil {
                            dismiss()
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        if builder.isSaving {
                            ProgressView().controlSize(.small).scaleEffect(0.7)
                        }
                        Text(builder.isSaving ? "Saving…" : "Save configuration")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!builder.canSave)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func field<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            content()
        }
    }
}
