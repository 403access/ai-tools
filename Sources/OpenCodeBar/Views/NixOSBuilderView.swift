import SwiftUI

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - Palette helpers

enum VMBuilderTint {
    static func color(_ key: String) -> Color {
        switch key {
        case "input": return Theme.input
        case "output": return Theme.output
        case "reasoning": return Theme.reasoning
        case "warn": return Theme.warn
        case "danger": return Theme.danger
        case "running": return Theme.running
        case "cacheRead": return Theme.cacheRead
        case "cacheWrite": return Theme.cacheWrite
        default: return Theme.accent
        }
    }
}

private func vmBuilderCopy(_ text: String) {
    #if os(macOS)
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    #elseif canImport(UIKit)
    UIPasteboard.general.string = text
    #endif
}

private func parsePorts(_ text: String) -> [Int] {
    text
        .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
        .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        .filter { $0 > 0 && $0 <= 65_535 }
}

// MARK: - Workspace

/// The full click-together builder. A wide three-column layout is used on the
/// Mac and iPad; the phone passes `compact` and gets a single scroll with a
/// review sheet.
struct NixOSBuilderWorkspace: View {
    @ObservedObject var model: NixOSBuilderModel
    @ObservedObject var store: VirtualMachinesStore
    let api: HubAPI?
    var compact = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(0.4)
            if compact {
                compactContent
            } else {
                wideContent
            }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("Search apps, packages, services, tags…", text: $model.search)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    if model.isSearching {
                        Button {
                            model.search = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear the search")
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )

                if model.isPreviewing {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                        Text("Rendering")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                } else if let preview = model.preview {
                    Chip(
                        text: "\(preview.optionCount) selected · \(preview.packages.count) pkgs",
                        systemImage: "checkmark.seal.fill",
                        tint: Theme.accent
                    )
                }

                Spacer(minLength: 0)

                Menu {
                    if let catalog = model.catalog,
                       let preset = catalog.preset(catalog.recommendedPreset) {
                        Button("Start over with \(preset.name)") {
                            model.applyPreset(preset)
                        }
                    }
                    Button("Clear selected options", role: .destructive) {
                        model.config.enabled = []
                        model.config.preset = nil
                        model.notice = "Cleared every catalog option. Users and settings were kept."
                    }
                    .disabled(model.config.enabled.isEmpty)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Reset or clear the selection")

                if compact {
                    Button {
                        model.reviewVisible = true
                    } label: {
                        Label("Review", systemImage: "list.bullet.rectangle.portrait")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }
            }

            presetRail

            if compact, let notice = model.notice {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text(notice)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button {
                        model.clearNotice()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.accent.opacity(0.08))
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var presetRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(model.catalog?.presets ?? []) { preset in
                    NixOSPresetCard(
                        preset: preset,
                        selected: model.config.preset == preset.id,
                        compact: compact
                    ) {
                        model.applyPreset(preset)
                    }
                }
                if model.customPreset {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Custom")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text("Your own combination")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(width: compact ? 132 : 150, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Theme.accent.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1)
                    )
                }
            }
            .padding(.vertical, 1)
        }
    }

    // MARK: Layouts

    private var wideContent: some View {
        HStack(spacing: 0) {
            categoryRail
                .frame(width: 178)
            Divider().opacity(0.35)
            ScrollView {
                content
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().opacity(0.35)
            NixOSBuildSummary(model: model, api: api, compact: false)
                .frame(width: 326)
        }
    }

    private var compactContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NixOSMachineCard(model: model)
                categoryChips
                content
                Button {
                    model.reviewVisible = true
                } label: {
                    Label("Review build plan", systemImage: "checklist")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.accent.opacity(0.10))
                )
            }
            .padding(12)
        }
        .sheet(isPresented: $model.reviewVisible) {
            NixOSCompactReview(model: model, api: api)
        }
    }

    private var categoryRail: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(model.categories) { category in
                    Button {
                        model.selectedCategory = category.id
                        model.search = ""
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: category.icon)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(
                                    model.selectedCategory == category.id && !model.isSearching
                                        ? VMBuilderTint.color(category.tint)
                                        : .secondary
                                )
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(category.name)
                                    .font(.system(size: 11, weight: model.selectedCategory == category.id ? .semibold : .medium))
                                    .foregroundStyle(.primary)
                                Text(category.summary)
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 2)
                            let count = model.categoryCount(category.id)
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(VMBuilderTint.color(category.tint))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(VMBuilderTint.color(category.tint).opacity(0.14)))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    model.selectedCategory == category.id && !model.isSearching
                                        ? VMBuilderTint.color(category.tint).opacity(0.10)
                                        : Color.clear
                                )
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(7)
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.categories) { category in
                    let selected = model.selectedCategory == category.id && !model.isSearching
                    Button {
                        model.selectedCategory = category.id
                        model.search = ""
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: category.icon)
                                .font(.system(size: 9, weight: .semibold))
                            Text(category.name)
                                .font(.system(size: 10, weight: .semibold))
                            let count = model.categoryCount(category.id)
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(VMBuilderTint.color(category.tint).opacity(0.16)))
                            }
                        }
                        .foregroundStyle(selected ? VMBuilderTint.color(category.tint) : .secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    selected
                                        ? VMBuilderTint.color(category.tint).opacity(0.12)
                                        : Color.primary.opacity(0.05)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if model.isSearching {
            searchResults
        } else if model.selectedCategory == "users" {
            usersPane
        } else if model.selectedCategory == "advanced" {
            advancedPane
        } else if model.catalog == nil {
            EmptyState(
                icon: "square.grid.2x2",
                title: "Loading the catalog",
                subtitle: "The hub is sending the categories, presets, and NixOS options."
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if model.selectedCategory == "system" {
                    systemSettings
                }
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.selectedCategoryName)
                            .font(.system(size: 13, weight: .semibold))
                        Text(model.selectedCategorySummary)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Text("\(model.visibleOptions.filter { !$0.locked }.count) options")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                optionList(model.visibleOptions)
            }
        }
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Search results")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(model.visibleOptions.count) matches for “\(model.search)”")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear") { model.search = "" }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
            }
            if model.visibleOptions.isEmpty {
                EmptyState(
                    icon: "magnifyingglass",
                    title: "Nothing matched",
                    subtitle: "Try a package name, a service, or a tag such as “docker” or “media”."
                )
            } else {
                ForEach(Array(model.optionGroups.enumerated()), id: \.offset) { _, group in
                    if let category = group.category {
                        HStack(spacing: 5) {
                            Image(systemName: category.icon)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(VMBuilderTint.color(category.tint))
                            Text(category.name.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.6)
                                .foregroundStyle(.secondary)
                        }
                    }
                    optionList(group.options)
                }
            }
        }
    }

    private func optionList(_ options: [VMConfigOption]) -> some View {
        VStack(spacing: 6) {
            ForEach(options) { option in
                NixOSOptionCard(model: model, option: option)
            }
        }
    }

    private var systemSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("System settings")
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 16) {
                    NixOSPickerField(
                        title: "Time zone",
                        value: $model.config.settings.timezone,
                        choices: choices(model.catalog?.timezones ?? [], current: model.config.settings.timezone)
                    )
                    NixOSPickerField(
                        title: "Locale",
                        value: $model.config.settings.locale,
                        choices: choices(model.catalog?.locales ?? [], current: model.config.settings.locale)
                    )
                    NixOSPickerField(
                        title: "Keyboard",
                        value: $model.config.settings.keymap,
                        choices: choices(model.catalog?.keymaps ?? [], current: model.config.settings.keymap)
                    )
                }

                Divider().opacity(0.4)

                Toggle(isOn: $model.config.settings.firewall) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Firewall")
                            .font(.system(size: 11, weight: .medium))
                        Text("Block unsolicited inbound traffic except for the ports below.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $model.config.settings.passwordAuthentication) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Allow SSH passwords")
                            .font(.system(size: 11, weight: .medium))
                        Text("Off is safer. Managed users log in with keys; set a password from the console if you enable this.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)

                Divider().opacity(0.4)
                NixOSPortFields(model: model)
            }
            .card(padding: 11)
        }
    }

    private var usersPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Users")
                        .font(.system(size: 13, weight: .semibold))
                    Text("The admin is always present. Add teammates, service accounts, or shell-only logins.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button {
                    model.addUser()
                } label: {
                    Label("Add user", systemImage: "person.badge.plus")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .disabled(model.config.users.count >= (model.catalog?.limits.maxUsers ?? 16))
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.accent.opacity(0.14))
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text("opencodebar")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            Chip(text: "Admin", tint: Theme.accent)
                            Chip(text: "Generated key", tint: Theme.running)
                        }
                        Text("The hub connects as this passwordless-sudo wheel user. Its ed25519 key is created with the VM and cannot be removed here.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
            .card(padding: 10)

            if model.config.users.isEmpty {
                EmptyState(
                    icon: "person.2",
                    title: "No extra users",
                    subtitle: "The guest already has the opencodebar admin. Add another login when you want a separate human or service account."
                )
                .card(padding: 14)
            } else {
                ForEach(Array(model.config.users.enumerated()), id: \.offset) { index, _ in
                    NixOSManagedUserCard(model: model, index: index)
                }
            }

            NoticeRow(
                icon: "key.fill",
                message: "Managed users can log in with the SSH keys you paste here. Without a key they can still use the serial console. Add the wheel group to grant sudo; the hub never sets passwords for them.",
                tint: Theme.input
            )
        }
    }

    private var advancedPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Advanced")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Escape hatches for packages, ports, and raw Nix.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            NixOSExtraPackagesCard(model: model)
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Firewall ports")
                NixOSPortFields(model: model)
            }
            .card(padding: 11)
            NixOSCustomNixCard(model: model)

            NoticeRow(
                icon: "exclamationmark.triangle.fill",
                message: "Custom Nix is appended verbatim to configuration.nix. A typo can make the next build fail; the preview shows exactly what will be written.",
                tint: Theme.warn
            )
        }
    }

    private func choices(_ values: [String], current: String) -> [String] {
        var result = values
        if !current.isEmpty, !result.contains(current) {
            result.insert(current, at: 0)
        }
        return result
    }
}

// MARK: - Machine card (compact layouts)

private struct NixOSMachineCard: View {
    @ObservedObject var model: NixOSBuilderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Machine")
            VStack(alignment: .leading, spacing: 9) {
                TextField("Virtual machine name", text: $model.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, weight: .semibold))
                    .disabled(model.isSaving)

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CPU")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(.secondary)
                        Stepper(value: $model.cpuCount, in: 1...max(1, model.maximumCPU)) {
                            Text("\(model.cpuCount) cores")
                                .font(.system(size: 10))
                                .monospacedDigit()
                        }
                        .disabled(model.isSaving || !model.canEditResources)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("MEMORY")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(.secondary)
                        Stepper(
                            value: $model.memoryMB,
                            in: 1_024...max(1_024, model.maximumMemoryMB),
                            step: 1_024
                        ) {
                            Text("\(model.memoryMB / 1_024) GB")
                                .font(.system(size: 10))
                                .monospacedDigit()
                        }
                        .disabled(model.isSaving || !model.canEditResources)
                    }
                }

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("DISK")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(.secondary)
                        if model.mode.isCreate {
                            Stepper(value: $model.diskGB, in: 8...256, step: 4) {
                                Text("\(model.diskGB) GB")
                                    .font(.system(size: 10))
                                    .monospacedDigit()
                            }
                            .disabled(model.isSaving)
                        } else {
                            Text("\(model.diskGB) GB")
                                .font(.system(size: 10))
                                .monospacedDigit()
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("NIXOS CHANNEL")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(.secondary)
                        if model.mode.isCreate {
                            TextField("nixos-26.05", text: $model.channel)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 10, design: .monospaced))
                                .autocorrectionDisabled()
                                .disabled(model.isSaving)
                        } else {
                            Text(model.channel)
                                .font(.system(size: 10, design: .monospaced))
                        }
                    }
                }

                if model.mode.isCreate {
                    Toggle("Start after the image is built", isOn: $model.autostart)
                        .font(.system(size: 10))
                        .disabled(model.isSaving)
                }
            }
            .card(padding: 11)
        }
    }
}

// MARK: - Preset card

private struct NixOSPresetCard: View {
    let preset: VMConfigPreset
    let selected: Bool
    let compact: Bool
    let action: () -> Void

    var tint: Color { VMBuilderTint.color(preset.tint) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: preset.icon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(preset.name)
                        .font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 2)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
                Text(preset.summary)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    ForEach(preset.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 8, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(tint.opacity(0.12)))
                    }
                }
            }
            .foregroundStyle(selected ? tint : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: compact ? 132 : 150, height: 66, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? tint.opacity(0.10) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? tint.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(preset.summary)
    }
}

// MARK: - Option card

private struct NixOSOptionCard: View {
    @ObservedObject var model: NixOSBuilderModel
    let option: VMConfigOption
    @State private var hovering = false

    private var enabled: Bool { model.isEnabled(option) }
    private var tint: Color { VMBuilderTint.color(option.tint) }

    private var conflictingSelection: String? {
        guard !option.locked, !model.selected(option) else { return nil }
        return option.conflicts.first(where: { model.config.enabled.contains($0) })
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(enabled ? 0.18 : 0.10))
                Image(systemName: option.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(option.name)
                        .font(.system(size: 11, weight: .semibold))
                    if let badge = option.badge {
                        Chip(text: badge, tint: tint)
                    }
                    if option.locked {
                        Chip(text: "Always on", systemImage: "lock.fill", tint: .secondary)
                    }
                    if option.unfree {
                        Chip(text: "Unfree", tint: Theme.warn)
                    }
                    Spacer(minLength: 4)
                    Button {
                        model.toggle(option)
                    } label: {
                        Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(enabled ? tint : Color.secondary.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .disabled(option.locked)
                    .help(option.locked ? "Always enabled" : (enabled ? "Turn off \(option.name)" : "Add \(option.name)"))
                }

                Text(option.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    if !option.packages.isEmpty {
                        Chip(
                            text: option.packages.count == 1 ? option.packages[0] : "\(option.packages.count) packages",
                            systemImage: "shippingbox.fill",
                            tint: Theme.input
                        )
                    }
                    ForEach(option.services.prefix(2), id: \.self) { service in
                        Chip(text: service, systemImage: "server.rack", tint: Theme.output)
                    }
                    if !option.ports.isEmpty {
                        Chip(
                            text: option.ports.map(String.init).joined(separator: ", "),
                            systemImage: "network",
                            tint: Theme.running
                        )
                    }
                    if option.sizeMB > 0 {
                        Text("~\(option.sizeMB >= 1_024 ? String(format: "%.1f GB", Double(option.sizeMB) / 1_024) : "\(option.sizeMB) MB")")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                if let conflictingSelection,
                   let other = model.option(conflictingSelection) {
                    Text("Replaces \(other.name) when selected.")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.warn)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    enabled
                        ? tint.opacity(0.07)
                        : Color.primary.opacity(hovering ? 0.05 : 0.025)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    enabled ? tint.opacity(0.35) : Color.primary.opacity(0.05),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(option) }
        #if os(macOS)
        .onHover { hovering = $0 }
        #endif
    }
}

// MARK: - System field helpers

private struct NixOSPickerField: View {
    let title: String
    @Binding var value: String
    let choices: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Picker(title, selection: $value) {
                ForEach(choices, id: \.self) { choice in
                    Text(choice).tag(choice)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct NixOSPortFields: View {
    @ObservedObject var model: NixOSBuilderModel
    @State private var tcp = ""
    @State private var udp = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                field(
                    "Extra TCP ports",
                    placeholder: "8080, 443",
                    text: $tcp
                )
                field(
                    "Extra UDP ports",
                    placeholder: "41641",
                    text: $udp
                )
            }
            Text("Comma separated. Service options open their own ports automatically.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: sync)
        .onChange(of: tcp) { _, _ in apply() }
        .onChange(of: udp) { _, _ in apply() }
    }

    private func field(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))
                .autocorrectionDisabled()
        }
    }

    private func sync() {
        guard !loaded else { return }
        loaded = true
        tcp = model.config.settings.extraTCPPorts.map(String.init).joined(separator: ", ")
        udp = model.config.settings.extraUDPPorts.map(String.init).joined(separator: ", ")
    }

    private func apply() {
        guard loaded else { return }
        model.setPorts(tcp: parsePorts(tcp), udp: parsePorts(udp))
    }
}

// MARK: - Managed user editor

private struct NixOSManagedUserCard: View {
    @ObservedObject var model: NixOSBuilderModel
    let index: Int
    @State private var expanded = true

    private var user: Binding<NixOSManagedUser> {
        $model.config.users[index]
    }

    private var tint: Color { Theme.running }

    private var nameIssue: String? {
        let name = user.wrappedValue.name
        if name.isEmpty { return "A login name is required." }
        if name.range(of: "^[a-z_][a-z0-9_-]{0,31}$", options: .regularExpression) == nil {
            return "Use lowercase letters, numbers, _ or -, starting with a letter or _."
        }
        if ["root", "opencodebar", "nobody"].contains(name) {
            return "This login name is reserved."
        }
        let duplicates = model.config.users.filter {
            $0.name.trimmingCharacters(in: .whitespaces).lowercased() == name.lowercased()
        }
        if duplicates.count > 1 { return "This login is listed twice." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint.opacity(0.14))
                    Image(systemName: "person.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 28, height: 28)

                TextField("login", text: user.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif

                Button {
                    model.removeUser(at: index)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                }
                .buttonStyle(.plain)
                .help("Remove this user")

                Button {
                    expanded.toggle()
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            TextField("Display name", text: user.description)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))

            if let nameIssue {
                Text(nameIssue)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.warn)
            }

            if expanded {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SHELL")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                        Picker("Shell", selection: user.shell) {
                            ForEach(model.catalog?.shells ?? ["bash", "zsh", "fish"], id: \.self) { shell in
                                Text(shell).tag(shell)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                    }

                    Toggle(isOn: user.passwordlessSudo) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Passwordless sudo")
                                .font(.system(size: 10, weight: .medium))
                            Text("Adds a NOPASSWD rule for this login.")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    Toggle(isOn: user.createHome) {
                        Text("Create home")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .toggleStyle(.switch)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("GROUPS")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                    NixOSGroupChips(model: model, index: index)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("SSH KEYS")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            model.addSSHKey(to: index)
                        } label: {
                            Label("Add key", systemImage: "plus")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                    }

                    if user.wrappedValue.sshKeys.isEmpty {
                        Text("No keys. This login can use the serial console only.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(user.wrappedValue.sshKeys.enumerated()), id: \.offset) { keyIndex, _ in
                            HStack(spacing: 6) {
                                TextField(
                                    "ssh-ed25519 AAAAC3Nza… user@host",
                                    text: user.sshKeys[keyIndex]
                                )
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 9, design: .monospaced))
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                                Button {
                                    model.removeSSHKey(keyIndex, from: index)
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .card(padding: 10)
    }
}

private struct NixOSGroupChips: View {
    @ObservedObject var model: NixOSBuilderModel
    let index: Int
    @State private var draft = ""

    private var selected: [String] { model.config.users[index].groups }

    private var validDraft: String? {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty,
              value.range(of: "^[a-z_][a-z0-9_-]{0,31}$", options: .regularExpression) != nil,
              !selected.contains(value) else { return nil }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 52), spacing: 5)],
                alignment: .leading,
                spacing: 5
            ) {
                ForEach(model.catalog?.groups ?? [], id: \.self) { group in
                    let active = selected.contains(group)
                    Button {
                        model.toggleGroup(group, for: index)
                    } label: {
                        Text(group)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(active ? Theme.accent : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule().fill(
                                    active ? Theme.accent.opacity(0.14) : Color.primary.opacity(0.05)
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 5) {
                TextField("Custom group", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 9, design: .monospaced))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit {
                        if let validDraft {
                            model.toggleGroup(validDraft, for: index)
                            draft = ""
                        }
                    }
                Button("Add") {
                    if let validDraft {
                        model.toggleGroup(validDraft, for: index)
                        draft = ""
                    }
                }
                .font(.system(size: 9, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(validDraft == nil ? .secondary : Theme.accent)
                .disabled(validDraft == nil)
            }
        }
    }
}

// MARK: - Advanced cards

private struct NixOSExtraPackagesCard: View {
    @ObservedObject var model: NixOSBuilderModel
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Extra nixpkgs attributes") {
                Text("\(model.config.extraPackages.count)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    TextField("ripgrep, python3Packages.requests", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .monospaced))
                        .autocorrectionDisabled()
                        .onSubmit(add)
                    Button("Add", action: add)
                        .font(.system(size: 10, weight: .semibold))
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if model.config.extraPackages.isEmpty {
                    Text("Anything in nixpkgs can go here. Collections such as git-tools already cover the common apps.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.config.extraPackages, id: \.self) { name in
                        HStack(spacing: 7) {
                            Image(systemName: "shippingbox.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.accent)
                            Text(name)
                                .font(.system(size: 10, design: .monospaced))
                            Spacer()
                            Button {
                                model.removePackage(name)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .card(padding: 11)
        }
    }

    private func add() {
        model.addPackages(draft)
        draft = ""
    }
}

private struct NixOSCustomNixCard: View {
    @ObservedObject var model: NixOSBuilderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Custom Nix") {
                Text("\(model.config.extraConfig.count) chars")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 7) {
                TextEditor(text: $model.config.extraConfig)
                    .font(.system(size: 10, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 150)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.18))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                Text("Appended inside the module body, before environment.systemPackages. NixOS merges list options, so adding another list is safe.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card(padding: 11)
        }
    }
}

// MARK: - Summary

struct NixOSBuildSummary: View {
    @ObservedObject var model: NixOSBuilderModel
    let api: HubAPI?
    var compact = false

    enum Tab: String, CaseIterable, Identifiable {
        case plan = "Plan"
        case nix = "Nix"

        var id: String { rawValue }
    }

    @State private var tab: Tab = .plan
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Build plan")
                        .font(.system(size: 12, weight: .semibold))
                    Text(model.presetName)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if model.isPreviewing {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }
                Button {
                    vmBuilderCopy(previewText)
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(model.preview == nil)
                .help("Copy the generated configuration")

                Menu {
                    Button("Copy configuration.nix") {
                        vmBuilderCopy(model.preview?.configuration ?? "")
                    }
                    Button("Copy flake.nix") {
                        vmBuilderCopy(model.preview?.flake ?? "")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(model.preview == nil)
            }

            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            if tab == .plan {
                planTab
            } else {
                nixTab
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.015))
    }

    private var planTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                    spacing: 6
                ) {
                    summaryTile("Packages", "\(model.summaryPackageCount)", "shippingbox.fill", Theme.input)
                    summaryTile("Services", "\(model.summaryServiceCount)", "server.rack", Theme.output)
                    summaryTile("Ports", "\(model.summaryPortCount)", "network", Theme.running)
                    summaryTile("Users", "\(model.summaryUserCount)", "person.2.fill", Theme.reasoning)
                }

                VStack(alignment: .leading, spacing: 3) {
                    summaryRow("Name", model.trimmedName.isEmpty ? "—" : model.trimmedName)
                    summaryRow("Preset", model.presetName)
                    summaryRow("Resources", "\(model.cpuCount) vCPU · \(model.memoryMB / 1_024) GB · \(model.diskGB) GB")
                    summaryRow("Estimated", model.summarySize)
                    summaryRow("NixOS", model.channel)
                }
                .card(padding: 9)

                if let notice = model.notice {
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Text(notice)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button {
                            model.clearNotice()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.accent.opacity(0.08))
                    )
                }

                ForEach(model.warnings, id: \.self) { warning in
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.warn)
                        Text(warning)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }

                if let error = model.previewError {
                    NoticeRow(
                        icon: "exclamationmark.triangle.fill",
                        message: error,
                        tint: Theme.danger
                    )
                }

                if !model.selectedOptions.isEmpty {
                    summarySection("Included") {
                        FlowChips(
                            items: model.selectedOptions.map(\.name),
                            tint: Theme.accent,
                            columns: compact ? 2 : 1
                        )
                    }
                }

                summarySection("Users") {
                    FlowChips(
                        items: ["opencodebar"] + model.config.users.map(\.name),
                        tint: Theme.running,
                        columns: compact ? 2 : 1
                    )
                }

                if let preview = model.preview, !preview.services.isEmpty {
                    summarySection("Services") {
                        FlowChips(items: preview.services, tint: Theme.output, columns: compact ? 2 : 1)
                    }
                }

                if let preview = model.preview, !preview.ports.isEmpty {
                    summarySection("Open ports") {
                        FlowChips(
                            items: preview.ports.map(String.init),
                            tint: Theme.running,
                            columns: compact ? 4 : 3
                        )
                    }
                }

                if let preview = model.preview, !preview.packages.isEmpty {
                    summarySection("Packages") {
                        Text(preview.packages.joined(separator: "\n"))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let issue = model.issueMessage {
                    NoticeRow(icon: "exclamationmark.circle.fill", message: issue, tint: Theme.warn)
                }
            }
            .padding(.bottom, 8)
        }
    }

    private var nixTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let preview = model.preview {
                HStack {
                    Text("configuration.nix")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(preview.configuration.count) chars")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
                ScrollView {
                    Text(preview.configuration)
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.24))
                )
            } else if model.isPreviewing {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Rendering the NixOS module…")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyState(
                    icon: "chevron.left.forwardslash.chevron.right",
                    title: "No preview yet",
                    subtitle: model.previewError ?? "Change an option to render the module."
                )
            }
        }
    }

    private var previewText: String {
        model.preview?.configuration ?? ""
    }

    private func summaryTile(_ label: String, _ value: String, _ icon: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(tint)
                Text(label.uppercased())
                    .font(.system(size: 7, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func summarySection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            content()
        }
    }
}

/// Compact review sheet. The navigation chrome is only built for iOS; macOS
/// never uses the compact layout but the shared file still has to compile.
private struct NixOSCompactReview: View {
    @ObservedObject var model: NixOSBuilderModel
    let api: HubAPI?

    var body: some View {
        #if os(iOS)
        NavigationStack {
            NixOSBuildSummary(model: model, api: api, compact: true)
                .navigationTitle("Build plan")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Done") { model.reviewVisible = false }
                    }
                }
        }
        .presentationDetents([.large])
        #else
        NixOSBuildSummary(model: model, api: api, compact: true)
        #endif
    }
}
