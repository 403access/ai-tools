import SwiftUI

/// Mobile create flow for the full NixOS builder. The wide workspace becomes a
/// single scrolling column with the build plan behind a Review sheet.
struct MobileNewVirtualMachineSheet: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    @ObservedObject var model: VirtualMachinesStore
    let onCreated: (VirtualMachine) -> Void

    @StateObject private var builder: NixOSBuilderModel

    init(model: VirtualMachinesStore, onCreated: @escaping (VirtualMachine) -> Void) {
        self.model = model
        self.onCreated = onCreated
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
        NavigationStack {
            NixOSBuilderWorkspace(
                model: builder,
                store: model,
                api: store.api,
                compact: sizeClass == .compact
            )
            .mobileScreenBackground()
            .navigationTitle("New NixOS VM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(builder.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let machine = await builder.save(api: store.api, store: model) {
                                onCreated(machine)
                                dismiss()
                            }
                        }
                    } label: {
                        if builder.isSaving {
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
                VStack(spacing: 6) {
                    if let capabilities, !capabilities.ready {
                        VMSetupNotice(capabilities: capabilities)
                    }
                    if let issue = builder.issueMessage ?? builder.saveError {
                        NoticeRow(
                            icon: "exclamationmark.triangle.fill",
                            message: issue,
                            tint: Theme.warn
                        )
                    }
                    if builder.isSaving {
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
                .padding(.horizontal, 14)
            }
        }
        .presentationDragIndicator(.visible)
        .task {
            await model.loadCatalog(api: store.api)
            if let catalog = model.catalog {
                builder.attach(catalog: catalog, capabilities: model.capabilities)
            }
        }
        .task(id: builder.previewSignature) {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await builder.refreshPreview(api: store.api, store: model)
        }
    }
}

/// Edit an existing guest's builder configuration from the phone.
struct MobileNixOSConfigSheet: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

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
        NavigationStack {
            NixOSBuilderWorkspace(
                model: builder,
                store: model,
                api: store.api,
                compact: sizeClass == .compact
            )
            .mobileScreenBackground()
            .navigationTitle("Configure \(machine.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(builder.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if await builder.save(api: store.api, store: model) != nil {
                                dismiss()
                            }
                        }
                    } label: {
                        if builder.isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Save")
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!builder.canSave)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let issue = builder.issueMessage ?? builder.saveError {
                    NoticeRow(
                        icon: "exclamationmark.triangle.fill",
                        message: issue,
                        tint: Theme.warn
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .task {
            await model.loadCatalog(api: store.api)
            if let catalog = model.catalog {
                builder.attach(catalog: catalog, capabilities: model.capabilities)
            }
        }
        .task(id: builder.previewSignature) {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await builder.refreshPreview(api: store.api, store: model)
        }
    }
}
