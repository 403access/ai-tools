import SwiftUI

/// Mobile counterpart of the Mac model picker: a dedicated screen pushed from
/// the retry sheet with search, provider filters, sorting, and inline variants.
/// Rows are plain buttons, so a background refresh can never dismiss a choice.
struct MobileModelPickerView: View {
    let models: [ModelInfo]
    let selection: ModelChoice?
    let variant: String?
    let onSelect: (ModelInfo, String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var providerFilter: String?
    @State private var sort: ModelSortOrder = .provider

    private var providers: [String] { models.providerIDs }

    private var visible: [ModelInfo] {
        models.filteringModels(query: query, providerID: providerFilter)
    }

    private var isFiltering: Bool {
        providerFilter != nil || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                providerChips
                sortRow

                if visible.isEmpty {
                    emptyState
                } else if sort == .provider {
                    ForEach(visible.groupedByProvider()) { group in
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

    private var sortRow: some View {
        Picker("Sort models", selection: $sort) {
            ForEach(ModelSortOrder.allCases) { option in
                Text(option.rawValue).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func providerHeader(_ provider: String, count: Int) -> some View {
        HStack(spacing: 6) {
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
                    Spacer(minLength: 6)
                    Text(model.providerID)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(model.displayName), \(model.providerID)")

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
            Text("Try a different search or provider.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if isFiltering {
                ChoiceChip(title: "Clear filters", isSelected: false, fontSize: 13) {
                    query = ""
                    providerFilter = nil
                }
                .fixedSize()
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func choose(_ model: ModelInfo, variant: String?) {
        onSelect(model, variant)
        dismiss()
    }
}
