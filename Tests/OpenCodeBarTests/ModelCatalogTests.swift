import XCTest
@testable import OpenCodeBar

final class ModelCatalogTests: XCTestCase {
    private func model(
        _ id: String,
        provider: String,
        name: String? = nil,
        variants: [String] = []
    ) -> ModelInfo {
        ModelInfo(
            id: id,
            modelID: id,
            providerID: provider,
            name: name,
            enabled: true,
            status: "active",
            variants: variants.map { ModelInfo.Variant(id: $0, name: $0.capitalized) }
        )
    }

    private var catalog: [ModelInfo] {
        [
            model("zeta", provider: "opencode-go", name: "Zeta"),
            model("alpha", provider: "opencode-go", name: "Alpha"),
            model("gpt-5", provider: "openai", name: "GPT-5", variants: ["high", "low"]),
            model("claude", provider: "anthropic", name: "Claude"),
        ]
    }

    func testProviderIDsAreUniqueAndSorted() {
        let providers = (catalog + [model("alpha", provider: "opencode-go", name: "Alpha")]).providerIDs
        XCTAssertEqual(providers, ["anthropic", "openai", "opencode-go"])
    }

    func testBlankQueryKeepsEveryModel() {
        XCTAssertEqual(
            catalog.filteringModels(query: "   ", providerID: nil).count,
            catalog.count
        )
    }

    func testQueryMatchesNameIDAndProvider() {
        XCTAssertEqual(
            catalog.filteringModels(query: "gpt", providerID: nil).map(\.id),
            ["gpt-5"]
        )
        XCTAssertEqual(
            catalog.filteringModels(query: "CLAUDE", providerID: nil).map(\.id),
            ["claude"]
        )
        XCTAssertEqual(
            catalog.filteringModels(query: "opencode", providerID: nil).map(\.id).sorted(),
            ["alpha", "zeta"]
        )
    }

    func testProviderFilterCombinesWithQuery() {
        XCTAssertEqual(
            catalog.filteringModels(query: "", providerID: "opencode-go").map(\.id).sorted(),
            ["alpha", "zeta"]
        )
        XCTAssertTrue(
            catalog.filteringModels(query: "claude", providerID: "opencode-go").isEmpty
        )
    }

    func testGroupsAreSortedAndDropEmptyProviders() {
        let groups = catalog.groupedByProvider()
        XCTAssertEqual(groups.map(\.providerID), ["anthropic", "openai", "opencode-go"])
        XCTAssertEqual(groups.last?.models.map(\.displayName), ["Alpha", "Zeta"])
        XCTAssertTrue(
            catalog.filteringModels(query: "gpt", providerID: nil).groupedByProvider()
                .map(\.providerID) == ["openai"]
        )
    }

    func testFlatSortIgnoresProvider() {
        XCTAssertEqual(
            catalog.sortedByDisplayName().map(\.displayName),
            ["Alpha", "Claude", "GPT-5", "Zeta"]
        )
    }

    func testSelectableModelsDropUnavailableEntries() {
        var disabled = model("offline", provider: "opencode-go", name: "Offline")
        disabled.enabled = false
        var deprecated = model("legacy", provider: "openai", name: "Legacy")
        deprecated.status = "deprecated"

        let selectable = (catalog + [disabled, deprecated]).availableForSelection

        XCTAssertEqual(selectable.map(\.id), ["claude", "gpt-5", "alpha", "zeta"])
    }

    func testFreeModelsAndCapabilityLabels() {
        var free = model("free-model", provider: "opencode", name: "Free Model")
        free.cost = ModelInfo.Cost(input: 0, output: 0)
        free.limit = ModelInfo.Limit(context: 200_000, output: 32_000)

        var paid = model("paid-model", provider: "openai", name: "Paid Model")
        paid.cost = ModelInfo.Cost(input: 3, output: 15)

        XCTAssertTrue(free.isFree)
        XCTAssertEqual(free.contextLabel, "200K")
        XCTAssertFalse(paid.isFree)
        XCTAssertNil(paid.contextLabel)

        var million = model("million", provider: "openai", name: "Million")
        million.limit = ModelInfo.Limit(context: 1_000_000, output: 64_000)
        XCTAssertEqual(million.contextLabel, "1M")

        var beta = model("beta", provider: "openai", name: "Beta")
        beta.status = "beta"
        XCTAssertEqual(beta.statusBadge, "Beta")
        XCTAssertNil(model("active", provider: "openai").statusBadge)
    }

    func testDecodesCostTiersAndSingleCostObjects() throws {
        let tiered = try JSONDecoder().decode(
            ModelInfo.self,
            from: Data(#"""
            {
              "id": "tiered",
              "providerID": "opencode",
              "cost": [
                {"input": 0, "output": 0},
                {"tier": {"type": "context", "size": 200000}, "input": 3, "output": 4}
              ],
              "limit": {"context": 100000, "output": 32000}
            }
            """#.utf8)
        )
        XCTAssertFalse(tiered.isFree)
        XCTAssertEqual(tiered.cost?.tiers.count, 2)
        XCTAssertEqual(tiered.contextLabel, "100K")

        let single = try JSONDecoder().decode(
            ModelInfo.self,
            from: Data(#"""
            {"id": "single", "providerID": "local", "cost": {"input": 0, "output": 0}}
            """#.utf8)
        )
        XCTAssertTrue(single.isFree)
    }

    func testSearchTokensMatchAllFields() {
        XCTAssertEqual(
            catalog.filteringModels(query: "openai gpt", providerID: nil).map(\.id),
            ["gpt-5"]
        )
        XCTAssertEqual(
            catalog.filteringModels(query: "gpt 5", providerID: nil).map(\.id),
            ["gpt-5"]
        )
        XCTAssertEqual(
            catalog.filteringModels(query: "PROVIDER:opencode", providerID: nil).map(\.id).sorted(),
            ["alpha", "zeta"]
        )
    }

    func testSearchIgnoresAccentsAndMatchesVariants() {
        let accented = model("cafe", provider: "local", name: "Café")
        XCTAssertEqual(
            [accented].filteringModels(query: "cafe", providerID: nil).map(\.id),
            ["cafe"]
        )
        XCTAssertEqual(
            catalog.filteringModels(query: "high", providerID: nil).map(\.id),
            ["gpt-5"]
        )
    }

    func testFavoriteShortcutAndOrdering() {
        var free = model("free-model", provider: "opencode", name: "Free Model")
        free.cost = ModelInfo.Cost(input: 0, output: 0)
        let models = catalog + [free]
        let favoriteID = ModelChoice(providerID: "opencode-go", modelID: "zeta").id

        XCTAssertEqual(
            models.filteringModels(
                query: "favorite",
                providerID: nil,
                favorites: [favoriteID]
            ).map(\.id),
            ["zeta"]
        )
        XCTAssertEqual(
            models.filteringModels(
                query: "free",
                providerID: nil
            ).map(\.id),
            ["free-model"]
        )
        XCTAssertEqual(
            models.favoritesFirst(in: [favoriteID]).first?.id,
            "zeta"
        )
    }
}
