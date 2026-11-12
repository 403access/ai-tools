import SwiftUI

/// Mobile counterpart of the Mac model picker: a dedicated screen pushed from
/// new session, retry and composer flows with token search, provider and
/// attribute filters, favorite stars, capability badges, sorting, and inline
/// variants. Rows are plain buttons, so a refresh cannot dismiss a choice.
struct MobileModelPickerView: View {
    let models: [ModelInfo]
    let selection: ModelChoice?
    let variant: String?
    let onSelect: (ModelInfo, String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var providerFilter: String?
    @State private var sort: ModelSortOrder = .provider
    @State private var favorites = ModelPreferences.favoriteIDs
    @State private var favoritesOnly = false
    @State private var freeOnly = false

    private var providers: [String] { models.providerIDs }

    private var visible: [ModelInfo] {
        models.filteringModels(
            query: query,
            providerID: providerFilter,
            favorites: favorites,
            favoritesOnly: favoritesOnly,
            freeOnly: freeOnly
        )
    }

    private var favoriteModels: [ModelInfo] {
        visible.favorites(in: favorites)
    }

    private var remainingModels: [ModelInfo] {
        visible.excludingFavorites(in: favorites)
    }

    private var searchScopedModels: [ModelInfo] {
        models.filteringModels(query: query, providerID: providerFilter)
    }

    private var isFiltering: Bool {
        providerFilter != nil
            || favoritesOnly
            || freeOnly
            || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                providerChips
                attributeChips
                sortRow

                if visible.isEmpty {
                    emptyState
                } else if sort == .provider {
                    if !favoriteModels.isEmpty {
                        providerHeader("Favorites", count: favoriteModels.count, icon: "star.fill")
                        ForEach(favoriteModels, id: \.choice) { model in
                            modelRow(model)
                        }
                    }
                    ForEach(remainingModels.groupedByProvider()) { group in
                        providerHeader(group.providerID, count: group.models.count)
                        ForEach(group.models, id: \.choice) { model in
                            modelRow(model)
                        }
                    }
                } else {
                    ForEach(visible.favoritesFirst(in: favorites), id: \.choice) { model in
                        modelRow(model)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .mobileScreenBackground()
        .navigationTitle("Model")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search models"
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(visible.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Filters

    private var providerChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ChoiceChip(
                    title: "All · \(models.count)",
                    isSelected: providerFilter == nil,
                    fontSize: 13
                ) {
                    providerFilter = nil
                }
                ForEach(providers, id: \.self) { provider in
                    ChoiceChip(
                        title: "\(provider) · \(models.filter { $0.providerID == provider }.count)",
                        isSelected: providerFilter == provider,
                        fontSize: 13
                    ) {
                        providerFilter = providerFilter == provider ? nil : provider
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var attributeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ChoiceChip(
                    title: "Favorites · \(searchScopedModels.filter { favorites.contains($0.choice.id) }.count)",
                    isSelected: favoritesOnly,
                    fontSize: 13
                ) {
                    favoritesOnly.toggle()
                }
                .fixedSize()

                ChoiceChip(
                    title: "Free · \(searchScopedModels.filter(\.isFree).count)",
                    isSelected: freeOnly,
                    fontSize: 13
                ) {
                    freeOnly.toggle()
                }
                .fixedSize()

                if isFiltering {
                    ChoiceChip(title: "Clear", isSelected: false, fontSize: 13) {
                        query = ""
                        providerFilter = nil
                        favoritesOnly = false
                        freeOnly = false
                    }
                    .fixedSize()
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var sortRow: some View {
        Picker("Sort models", selection: $sort) {
            ForEach(ModelSortOrder.allCases) { option in
                Text(option.rawValue).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func providerHeader(
        _ provider: String,
        count: Int,
        icon: String? = nil
    ) -> some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(Theme.warn)
            }
            Text(provider.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.top, 6)
    }

    // MARK: - Rows

    private func modelRow(_ model: ModelInfo) -> some View {
        let isSelected = selection == model.choice
        let variants = model.variants ?? []

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                Button {
                    choose(model, variant: nil)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(model.displayName)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(model.displayName), \(model.providerID)")

                Spacer(minLength: 6)
                Text(model.providerID)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                favoriteButton(model)
            }

            if model.isFree || model.contextLabel != nil
                || model.statusBadge != nil || !variants.isEmpty {
                HStack(spacing: 4) {
                    if model.isFree {
                        Chip(text: "Free", tint: Theme.accent)
                    }
                    if let context = model.contextLabel {
                        Chip(text: context, tint: Theme.running)
                    }
                    if let status = model.statusBadge {
                        Chip(text: status, tint: Theme.warn)
                    }
                    if !variants.isEmpty {
                        Chip(
                            text: "\(variants.count) variant\(variants.count == 1 ? "" : "s")",
                            tint: Theme.reasoning
                        )
                    }
                }
            }

            Text(model.id)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            if !variants.isEmpty {
                HStack(spacing: 6) {
                    ChoiceChip(
                        title: "Default",
                        isSelected: isSelected && variant == nil,
                        fontSize: 12
                    ) {
                        choose(model, variant: nil)
                    }
                    ForEach(variants, id: \.id) { option in
                        ChoiceChip(
                            title: option.name ?? option.id,
                            isSelected: isSelected && variant == option.id,
                            fontSize: 12
                        ) {
                            choose(model, variant: option.id)
                        }
                    }
                }
            }
        }
        .card(padding: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent.opacity(0.4) : Color.clear, lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
            Text("No models match")
                .font(.subheadline.weight(.medium))
            Text("Try a different search or filter.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if isFiltering {
                ChoiceChip(title: "Clear filters", isSelected: false, fontSize: 13) {
                    query = ""
                    providerFilter = nil
                    favoritesOnly = false
                    freeOnly = false
                }
                .fixedSize()
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func favoriteButton(_ model: ModelInfo) -> some View {
        let isFavorite = favorites.contains(model.choice.id)
        return Button {
            if ModelPreferences.toggleFavorite(model) {
                favorites.insert(model.choice.id)
            } else {
                favorites.remove(model.choice.id)
            }
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isFavorite ? Theme.warn : Color.secondary.opacity(0.65))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isFavorite
                ? "Remove \(model.displayName) from favorites"
                : "Add \(model.displayName) to favorites"
        )
    }

    private func choose(_ model: ModelInfo, variant: String?) {
        ModelPreferences.rememberSelection(model, variant: variant)
        onSelect(model, variant)
        dismiss()
    }
}
