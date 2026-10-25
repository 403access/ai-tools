import Foundation
import SwiftUI

/// Editable state for the NixOS configuration builder on both platforms.
///
/// The model owns dependency resolution, preset application, user editing, and
/// the live preview request. The views only render the catalog and call into it.
@MainActor
final class NixOSBuilderModel: ObservableObject {
    enum Mode {
        case create
        case edit

        var isCreate: Bool { self == .create }
    }

    @Published var config: NixOSBuilderConfig
    @Published var name: String
    @Published var cpuCount: Int
    @Published var memoryMB: Int
    @Published var diskGB: Int
    @Published var channel: String
    @Published var autostart: Bool

    @Published var search = ""
    @Published var selectedCategory = "system"
    @Published var catalog: VMConfigCatalog?
    @Published var preview: VMConfigPreview?
    @Published var isPreviewing = false
    @Published var previewError: String?
    @Published var notice: String?
    @Published var reviewVisible = false
    @Published var isSaving = false
    @Published var saveError: String?

    let mode: Mode
    let machine: VirtualMachine?
    private var didApplyRecommended = false
    private var maxCPU = 8
    private var maxMemoryMB = 8_192

    init(
        mode: Mode,
        machine: VirtualMachine? = nil,
        catalog: VMConfigCatalog? = nil,
        capabilities: VMCapabilities? = nil
    ) {
        self.mode = mode
        self.machine = machine
        self.catalog = catalog

        if let machine {
            config = machine.builder
            name = machine.name
            cpuCount = machine.cpuCount
            memoryMB = machine.memoryMB
            diskGB = machine.diskGB
            channel = machine.channel
            autostart = true
        } else {
            config = catalog?.defaults ?? .fresh()
            name = "NixOS"
            cpuCount = capabilities?.defaultCPU ?? 4
            memoryMB = capabilities?.defaultMemoryMB ?? 4_096
            diskGB = 20
            channel = capabilities?.defaultChannel ?? "nixos-26.05"
            autostart = true
        }

        if let capabilities {
            maxCPU = max(1, capabilities.maxCPU)
            maxMemoryMB = max(1_024, capabilities.maxMemoryMB)
            cpuCount = min(cpuCount, maxCPU)
            memoryMB = min(memoryMB, maxMemoryMB)
        }

        if let catalog {
            attach(catalog: catalog, capabilities: capabilities)
        }
    }

    /// Called when the hub's catalog arrives after the sheet is already open.
    func attach(catalog: VMConfigCatalog, capabilities: VMCapabilities? = nil) {
        self.catalog = catalog
        if let capabilities {
            maxCPU = max(1, capabilities.maxCPU)
            maxMemoryMB = max(1_024, capabilities.maxMemoryMB)
            if mode.isCreate {
                cpuCount = min(max(cpuCount, 1), maxCPU)
                memoryMB = min(max(memoryMB, 1_024), maxMemoryMB)
                if channel.isEmpty { channel = capabilities.defaultChannel }
            }
        }
        guard mode.isCreate, !didApplyRecommended else { return }
        guard config.enabled == catalog.defaults.enabled || config.enabled.isEmpty else { return }
        guard let preset = catalog.preset(catalog.recommendedPreset) else { return }
        didApplyRecommended = true
        applyPreset(preset, announce: false)
    }

    // MARK: - Derived catalog state

    var categories: [VMConfigCategory] {
        var result = catalog?.categories ?? []
        // Users is a first-class step even though it is not a catalog option.
        if !result.contains(where: { $0.id == "users" }) {
            let users = VMConfigCategory(
                id: "users",
                name: "Users",
                summary: "Logins, groups, keys, and sudo rules",
                icon: "person.2.fill",
                tint: "running"
            )
            if let index = result.firstIndex(where: { $0.id == "system" }) {
                result.insert(users, at: index + 1)
            } else {
                result.insert(users, at: 0)
            }
        }
        return result
    }

    var selectedCategoryName: String {
        categories.first { $0.id == selectedCategory }?.name ?? "Options"
    }

    var selectedCategorySummary: String {
        categories.first { $0.id == selectedCategory }?.summary ?? ""
    }

    var isSearching: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var visibleOptions: [VMConfigOption] {
        guard let catalog else { return [] }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            return catalog.options.filter { option in
                searchText(for: option).contains(query)
            }
        }
        return catalog.options.filter { $0.category == selectedCategory }
    }

    /// Options grouped for search results, otherwise one category.
    var optionGroups: [(category: VMConfigCategory?, options: [VMConfigOption])] {
        let options = visibleOptions
        guard isSearching else { return [(nil, options)] }
        var groups: [(VMConfigCategory?, [VMConfigOption])] = []
        for option in options {
            let category = catalog?.category(option.category)
            if let index = groups.firstIndex(where: { $0.0?.id == category?.id }) {
                groups[index].1.append(option)
            } else {
                groups.append((category, [option]))
            }
        }
        return groups
    }

    func categoryCount(_ id: String) -> Int {
        if id == "users" { return config.users.count }
        return config.enabled.filter { optionID in
            catalog?.option(optionID)?.category == id
        }.count
    }

    func option(_ id: String) -> VMConfigOption? {
        catalog?.option(id)
    }

    func isEnabled(_ option: VMConfigOption) -> Bool {
        option.locked || config.enabled.contains(option.id)
    }

    func selected(_ option: VMConfigOption) -> Bool {
        config.enabled.contains(option.id)
    }

    var selectedOptions: [VMConfigOption] {
        guard let catalog else { return [] }
        let enabled = Set(config.enabled)
        return catalog.options.filter { enabled.contains($0.id) && !$0.locked }
    }

    var customPreset: Bool {
        config.preset == nil && !config.enabled.isEmpty
    }

    var presetName: String {
        if let preset = catalog?.preset(config.preset) { return preset.name }
        return config.enabled.isEmpty ? "Blank" : "Custom"
    }

    private func searchText(for option: VMConfigOption) -> String {
        ([
            option.id,
            option.name,
            option.summary,
            option.description,
            option.badge ?? "",
            option.tags.joined(separator: " "),
            option.packages.joined(separator: " "),
            option.services.joined(separator: " "),
            option.category,
        ]).joined(separator: " ").lowercased()
    }

    // MARK: - Selecting options

    func toggle(_ option: VMConfigOption) {
        guard !option.locked else { return }
        var enabled = Set(config.enabled)
        var messages: [String] = []

        if enabled.contains(option.id) {
            var removed: Set<String> = [option.id]
            let dependents = dependents(of: option.id, in: enabled)
            removed.formUnion(dependents)
            enabled.subtract(removed)
            if !dependents.isEmpty {
                messages.append(
                    "Turned off \(names(dependents)) because \(option.name) is required."
                )
            }
        } else {
            enabled.insert(option.id)
            var added: Set<String> = []
            var queue = [option.id]
            while let current = queue.popLast() {
                guard let entry = catalog?.option(current) else { continue }
                for requirement in entry.requires where !enabled.contains(requirement) {
                    enabled.insert(requirement)
                    added.insert(requirement)
                    queue.append(requirement)
                }
            }

            var conflicts: Set<String> = []
            for id in enabled {
                guard let entry = catalog?.option(id) else { continue }
                for conflict in entry.conflicts where conflict != option.id && enabled.contains(conflict) {
                    conflicts.insert(conflict)
                }
            }
            if !conflicts.isEmpty {
                let withDependents = conflicts.union(
                    conflicts.flatMap { dependents(of: $0, in: enabled) }
                )
                enabled.subtract(withDependents)
                messages.append(
                    "Turned off \(names(withDependents)) because it conflicts with \(option.name)."
                )
            }
            if !added.isEmpty {
                messages.append("Added \(names(added)), required by \(option.name).")
            }
            applyResourceHints(for: [option.id])
        }

        config.enabled = ordered(enabled)
        config.preset = matchingPreset()
        notice = messages.isEmpty ? nil : messages.joined(separator: " ")
    }

    private func dependents(of id: String, in enabled: Set<String>) -> Set<String> {
        guard let catalog else { return [] }
        var removed: Set<String> = []
        var changed = true
        while changed {
            changed = false
            for entry in catalog.options where enabled.contains(entry.id) {
                if removed.contains(entry.id) { continue }
                if entry.requires.contains(id) || entry.requires.contains(where: { removed.contains($0) }) {
                    removed.insert(entry.id)
                    changed = true
                }
            }
        }
        return removed
    }

    private func ordered(_ ids: Set<String>) -> [String] {
        guard let catalog else { return ids.sorted() }
        return catalog.options.compactMap { ids.contains($0.id) ? $0.id : nil }
    }

    private func names(_ ids: Set<String>) -> String {
        let values = ids.compactMap { catalog?.option($0)?.name ?? $0 }.sorted()
        switch values.count {
        case 0: return ""
        case 1: return values[0]
        case 2: return "\(values[0]) and \(values[1])"
        default: return "\(values.dropLast().joined(separator: ", ")), and \(values.last ?? "")"
        }
    }

    private func matchingPreset() -> String? {
        guard let catalog else { return nil }
        let enabled = Set(config.enabled)
        return catalog.presets.first { Set($0.options) == enabled }?.id
    }

    func applyPreset(_ preset: VMConfigPreset, announce: Bool = true) {
        var enabled = Set(preset.options)
        var added: Set<String> = []
        var queue = Array(preset.options)
        while let current = queue.popLast() {
            guard let entry = catalog?.option(current) else { continue }
            for requirement in entry.requires where !enabled.contains(requirement) {
                enabled.insert(requirement)
                added.insert(requirement)
                queue.append(requirement)
            }
        }
        config.enabled = ordered(enabled)
        config.preset = preset.id
        applyResourceHints(for: preset.options)
        if announce {
            notice = added.isEmpty
                ? "Applied the \(preset.name) preset."
                : "Applied the \(preset.name) preset and added \(names(added))."
        }
    }

    /// Desktop and AI presets are not useful on a 2 GB / 20 GB guest.
    private func applyResourceHints(for optionIDs: [String]) {
        guard mode.isCreate else { return }
        let needsDesktop = optionIDs.contains { ["gnome", "kde", "xfce", "hyprland", "steam"].contains($0) }
        let needsSpace = optionIDs.contains { ["ollama", "jellyfin", "gitea", "jupyter", "media"].contains($0) }
        let needsMemory = optionIDs.contains {
            ["ollama", "jupyter", "home-assistant", "jellyfin", "open-webui"].contains($0)
        }
        if needsDesktop, memoryMB < 4_096 {
            memoryMB = min(4_096, maxMemoryMB)
        }
        if needsMemory, memoryMB < 8_192 {
            memoryMB = min(8_192, maxMemoryMB)
        }
        if needsDesktop, diskGB < 32 {
            diskGB = 32
        }
        if needsSpace, diskGB < 40 {
            diskGB = 40
        }
    }

    // MARK: - Users

    func addUser() {
        let limit = catalog?.limits.maxUsers ?? 16
        guard config.users.count < limit else {
            notice = "You can add up to \(limit) users."
            return
        }
        config.users.append(.fresh(existing: config.users))
        selectedCategory = "users"
    }

    func removeUser(at index: Int) {
        guard config.users.indices.contains(index) else { return }
        config.users.remove(at: index)
    }

    func toggleGroup(_ group: String, for index: Int) {
        guard config.users.indices.contains(index) else { return }
        if let position = config.users[index].groups.firstIndex(of: group) {
            config.users[index].groups.remove(at: position)
        } else {
            config.users[index].groups.append(group)
        }
        config.users[index].groups.sort()
    }

    func addSSHKey(to index: Int) {
        guard config.users.indices.contains(index) else { return }
        config.users[index].sshKeys.append("")
    }

    func removeSSHKey(_ keyIndex: Int, from index: Int) {
        guard config.users.indices.contains(index),
              config.users[index].sshKeys.indices.contains(keyIndex) else { return }
        config.users[index].sshKeys.remove(at: keyIndex)
    }

    // MARK: - Advanced fields

    func addPackages(_ text: String) {
        let incoming = text
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !incoming.isEmpty else { return }
        let limit = catalog?.limits.maxExtraPackages ?? 128
        var packages = config.extraPackages
        for name in incoming where !packages.contains(name) {
            if packages.count >= limit { break }
            packages.append(name)
        }
        config.extraPackages = packages
    }

    func removePackage(_ name: String) {
        config.extraPackages.removeAll { $0 == name }
    }

    func setPorts(tcp: [Int], udp: [Int]) {
        let limit = catalog?.limits.maxPorts ?? 32
        config.settings.extraTCPPorts = Array(Array(Set(tcp.filter { $0 > 0 && $0 <= 65_535 })).sorted().prefix(limit))
        config.settings.extraUDPPorts = Array(Array(Set(udp.filter { $0 > 0 && $0 <= 65_535 })).sorted().prefix(limit))
    }

    // MARK: - Live preview

    var previewSignature: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = (try? encoder.encode(config))?.base64EncodedString() ?? ""
        return "\(name)|\(cpuCount)|\(memoryMB)|\(diskGB)|\(channel)|\(encoded)"
    }

    func refreshPreview(api: HubAPI?, store: VirtualMachinesStore) async {
        guard let api else {
            previewError = "Not connected to the hub"
            return
        }
        isPreviewing = true
        defer { isPreviewing = false }
        do {
            let value: VMConfigPreview
            if let machine {
                value = try await store.preview(
                    api: api,
                    machine: machine,
                    config: config,
                    packages: machine.packages
                )
            } else {
                value = try await store.preview(
                    api: api,
                    config: config,
                    packages: [],
                    name: name,
                    diskGB: diskGB,
                    channel: channel
                )
            }
            preview = value
            previewError = nil
        } catch {
            preview = nil
            previewError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Validation and saving

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var maximumCPU: Int { maxCPU }
    var maximumMemoryMB: Int { maxMemoryMB }

    var canEditResources: Bool {
        guard let machine else { return true }
        return !machine.isRunning && !machine.isBusy
    }

    var issues: [String] {
        var result: [String] = []
        if trimmedName.isEmpty {
            result.append("Give the virtual machine a name.")
        }
        if let machine, mode == .edit, machine.status == .building {
            result.append("Wait for the image build to finish before editing.")
        }
        var seen = Set<String>()
        for user in config.users {
            let key = user.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if key.isEmpty {
                result.append("Every managed user needs a name.")
            } else if seen.contains(key) {
                result.append("The user \(key) is listed twice.")
            } else if key.range(of: "^[a-z_][a-z0-9_-]{0,31}$", options: .regularExpression) == nil {
                result.append("The user name \(key) must use lowercase letters, numbers, _ or -.")
            } else if ["root", "opencodebar", "nobody", "daemon"].contains(key) {
                result.append("The user name \(key) is reserved.")
            }
            seen.insert(key)
            for rawKey in user.sshKeys {
                let sshKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if sshKey.isEmpty { continue }
                let validPrefix = ["ssh-", "ecdsa-", "sk-ssh-", "sk-ecdsa-"].contains {
                    sshKey.hasPrefix($0)
                }
                if !validPrefix {
                    result.append("The key for \(key) does not look like an OpenSSH public key.")
                    break
                }
            }
        }
        for package in config.extraPackages {
            if package.range(of: "^[A-Za-z0-9][A-Za-z0-9._+-]*$", options: .regularExpression) == nil {
                result.append("“\(package)” is not a valid nixpkgs attribute.")
            }
        }
        if let machine, mode == .edit {
            if (cpuCount != machine.cpuCount || memoryMB != machine.memoryMB) && machine.isRunning {
                result.append("Stop the VM before changing CPU or memory.")
            }
        }
        return result
    }

    var canSave: Bool {
        issues.isEmpty && !isSaving
    }

    var issueMessage: String? {
        issues.first
    }

    /// Saves the definition. Returns the created or updated VM, or nil on error.
    func save(api: HubAPI?, store: VirtualMachinesStore) async -> VirtualMachine? {
        guard let api else {
            saveError = "Not connected to the hub"
            return nil
        }
        guard canSave else {
            saveError = issueMessage
            return nil
        }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            if let machine, mode == .edit {
                let resourcesChanged = cpuCount != machine.cpuCount || memoryMB != machine.memoryMB
                if resourcesChanged, !canEditResources {
                    saveError = "Stop the VM before changing CPU or memory."
                    return nil
                }
                store.clearError()
                await store.update(
                    api: api,
                    machine: machine,
                    name: trimmedName == machine.name ? nil : trimmedName,
                    cpuCount: resourcesChanged ? cpuCount : nil,
                    memoryMB: resourcesChanged ? memoryMB : nil,
                    config: config
                )
                if let error = store.error {
                    saveError = error
                    return nil
                }
                return store.machine(machine.id) ?? machine
            } else {
                return try await store.create(
                    api: api,
                    name: trimmedName,
                    cpuCount: cpuCount,
                    memoryMB: memoryMB,
                    diskGB: diskGB,
                    channel: channel,
                    packages: [],
                    config: config,
                    autostart: autostart
                )
            }
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    // MARK: - Summary helpers

    var summaryPackageCount: Int {
        if let preview { return preview.packages.count }
        var names = Set(["curl", "git", "htop", "vim"])
        names.formUnion(config.extraPackages)
        for option in selectedOptions { names.formUnion(option.packages) }
        return names.count
    }

    var summaryServiceCount: Int {
        preview?.services.count ?? Set(selectedOptions.flatMap(\.services)).count
    }

    var summaryPortCount: Int {
        preview?.ports.count ?? Set(selectedOptions.flatMap(\.ports)).count
    }

    var summaryUserCount: Int {
        config.users.count + 1
    }

    var summarySize: String {
        preview?.sizeLabel ?? "—"
    }

    var warnings: [String] {
        var result = preview?.warnings ?? []
        if let machine, mode == .edit, machine.isRunning, configChangedComparedToMachine {
            result.append("Changes will be applied over SSH with nixos-rebuild switch.")
        }
        if customPreset {
            result.append("This configuration no longer matches a preset.")
        }
        return result
    }

    private var configChangedComparedToMachine: Bool {
        guard let machine else { return false }
        return machine.builder != config
    }

    func clearNotice() {
        notice = nil
    }
}
