import SwiftUI

/// Dedicated model browser for the retry flow. Rows are plain buttons instead
/// of an `NSMenu`-backed picker, so a background refresh can never dismiss an
/// open selection. The list can be searched, filtered by provider, sorted, and
/// a model's variants can be picked inline.
struct ModelPickerSheet: View {
    let models: [ModelInfo]
    let selection: ModelChoice?
    let variant: String?
    let onSelect: (ModelInfo, String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var providerFilter: String?
    @State private var sort: ModelSortOrder = .provider
    @State private var hovered: ModelChoice?
    @FocusState private var searchFocused: Bool

    private var providers: [String] { models.providerIDs }

    private var visible: [ModelInfo] {
        models.filteringModels(query: query, providerID: providerFilter)
    }

    private var isFiltering: Bool {
        providerFilter != nil || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            searchField
            filterControls
            Divider().opacity(0.4)
            results
            footer
        }
        .padding(14)
        .frame(width: 470, height: 540)
        .onAppear { searchFocused = true }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Choose a model")
                    .font(.system(size: 15, weight: .semibold))
                Text("Search by name, model id or provider. Variants are picked on the model itself.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
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
            .help("Close without changing the model")
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            TextField("Search models", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 10.5))
                .focused($searchFocused)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    searchFocused ? Theme.accent.opacity(0.4) : Color.clear,
                    lineWidth: 1
                )
        )
    }

    // MARK: - Filters

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("Provider") {
                Picker("Sort", selection: $sort) {
                    ForEach(ModelSortOrder.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 150)
                .help("Group models by provider, or show one A–Z list")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    providerChip("All", count: models.count, isSelected: providerFilter == nil) {
                        providerFilter = nil
                    }
                    ForEach(providers, id: \.self) { provider in
                        providerChip(
                            provider,
                            count: models.filter { $0.providerID == provider }.count,
                            isSelected: providerFilter == provider
                        ) {
                            providerFilter = providerFilter == provider ? nil : provider
                        }
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func providerChip(
        _ title: String,
        count: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Text("\(count)")
                    .foregroundStyle(isSelected ? Theme.accent.opacity(0.7) : Color.secondary.opacity(0.6))
            }
            .font(.system(size: 9.5, weight: isSelected ? .semibold : .regular))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
            .background(
                Capsule().fill(
                    isSelected ? Theme.accent.opacity(0.18) : Color.primary.opacity(0.05)
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? Theme.accent.opacity(0.45) : Color.clear,
                    lineWidth: 1
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if visible.isEmpty {
                    emptyState
                } else if sort == .provider {
                    ForEach(visible.groupedByProvider(), id: \.providerID) { group in
                        providerHeader(group.providerID, count: group.models.count)
                        ForEach(group.models, id: \.choice) { model in
                            modelRow(model)
                        }
                    }
                } else {
                    ForEach(visible.sortedByDisplayName(), id: \.choice) { model in
                        modelRow(model)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(.tertiary)
            Text("No models match")
                .font(.system(size: 12, weight: .medium))
            Text("Try a different search or provider.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            if isFiltering {
                ChoiceChip(title: "Clear filters", isSelected: false) {
                    query = ""
                    providerFilter = nil
                }
                .fixedSize()
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    private func providerHeader(_ provider: String, count: Int) -> some View {
        HStack(spacing: 5) {
            Text(provider.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 7)
        .padding(.bottom, 1)
    }

    private func modelRow(_ model: ModelInfo) -> some View {
        let isSelected = selection == model.choice
        let isHovered = hovered == model.choice
        let variants = model.variants ?? []

        return VStack(alignment: .leading, spacing: 3) {
            Button {
                choose(model, variant: nil)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.displayName)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Theme.accent)
                    }
                    Spacer(minLength: 6)
                    Text(model.providerID)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Use \(model.displayName) from \(model.providerID)")

            HStack(spacing: 4) {
                Text(model.id)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !variants.isEmpty {
                    Text("· \(variants.count) variant\(variants.count == 1 ? "" : "s")")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }

            if !variants.isEmpty {
                HStack(spacing: 4) {
                    variantChip("Default", isSelected: isSelected && variant == nil) {
                        choose(model, variant: nil)
                    }
                    ForEach(variants, id: \.id) { option in
                        variantChip(
                            option.name ?? option.id,
                            isSelected: isSelected && variant == option.id
                        ) {
                            choose(model, variant: option.id)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isSelected
                        ? Theme.accent.opacity(0.09)
                        : (isHovered ? Color.primary.opacity(0.05) : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isSelected ? Theme.accent.opacity(0.3) : Color.clear,
                    lineWidth: 1
                )
        )
        .onHover { inside in
            if inside {
                hovered = model.choice
            } else if hovered == model.choice {
                hovered = nil
            }
        }
    }

    private func variantChip(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 8.5, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
                .background(
                    Capsule().fill(
                        isSelected ? Theme.accent.opacity(0.18) : Color.primary.opacity(0.06)
                    )
                )
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Theme.accent.opacity(0.4) : Color.primary.opacity(0.07),
                        lineWidth: 1
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Use the \(title) variant")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text("\(visible.count) of \(models.count) models")
                .font(.system(size: 9.5))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if let providers = providerFilter {
                Text("· \(providers)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text("Click a model to use it")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    private func choose(_ model: ModelInfo, variant: String?) {
        onSelect(model, variant)
        dismiss()
    }
}
